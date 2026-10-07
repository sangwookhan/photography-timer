// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// `.sheet(item:)` payload for the item editor: the Filter Set it
/// starts in, the item being edited (`nil` when creating), and — for a
/// new item — the notation the editing session remembers from the last
/// saved ND or GND item (FILTER-ITEM-007). A new item starts as ND
/// (FILTER-ITEM-003) without a Filter Set when Add Filter comes from
/// Shooting Filters, or in the Filter Set whose editor it comes from
/// (FILTER-ITEM-009).
struct FilterItemEditorContext: Identifiable {
    /// Every kind, ND first, for new and existing items alike: the type
    /// is chosen inside the editor, and an existing item may be
    /// corrected to any kind (FILTER-ITEM-003/008).
    let selectableKinds = FilterSetItemOrder.kinds

    /// The Set the editor opened from; `nil` for a general Add filter
    /// entry, which chooses its Set in the editor (FILTER-ITEM-009).
    let filterSetID: FilterSetID?
    let item: FilterItem?
    var initialUnit: FilterValueUnit = .stops
    /// The color a proposed New Filter Set gets when the inventory holds
    /// no Set yet (FILTER-SET-003).
    var proposedFilterSetColor: FilterSetColor = .blue

    init(filterSetID: FilterSetID?, item: FilterItem?, initialUnit: FilterValueUnit = .stops) {
        self.filterSetID = filterSetID
        self.item = item
        self.initialUnit = initialUnit
    }

    /// A general Add filter entry: no Set chosen yet (FILTER-FLOW-004).
    static func general(initialUnit: FilterValueUnit, proposedFilterSetColor: FilterSetColor) -> FilterItemEditorContext {
        var context = FilterItemEditorContext(filterSetID: nil, item: nil, initialUnit: initialUnit)
        context.proposedFilterSetColor = proposedFilterSetColor
        return context
    }

    var id: String {
        "\(filterSetID?.rawValue ?? "general")-\(item?.id.rawValue ?? "new")"
    }
}

/// Registers or edits one physical filter (FILTER-ITEM-002/003/004/009,
/// FILTER-CPL-001…004, FILTER-GND-001/003, FILTER-COLOR-001/002). A new
/// or existing filter chooses its Filter Set here, or creates one
/// inline and comes back with it selected and the entered values kept.
/// The kind is chosen explicitly; Fixed and GND take a decimal value in
/// Stops, OD, or ND factor and show the canonical conversion; a CPL
/// exposes its three exposure-loss fields on a decimal-capable numeric
/// keyboard; a Color filter records its optical color beside an
/// explicit loss in stops, and an Effect filter its explicit loss.
/// Saving is blocked with the affected cameras when any stack would
/// exceed 30 stops (FILTER-ITEM-005).
struct FilterItemEditorView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let context: FilterItemEditorContext
    let onDismiss: () -> Void
    /// Called with the saved item before dismissing, so the owning
    /// session can remember a new item's notation (FILTER-ITEM-007).
    var onSaved: (FilterItem) -> Void = { _ in }

    /// Where the filter is saved; an existing filter starts in the set
    /// that holds it, and a general entry starts with none.
    @State private var filterSetID: FilterSetID?
    /// The name of the New Filter Set proposed while the inventory holds
    /// no Set; it is created with the filter on Save (FILTER-ITEM-009).
    @State private var proposedFilterSetName = String(localized: "proposed-filter-set-name", defaultValue: "New Filter Set")
    /// Filter Set creation opened from the Filter Set field.
    @State private var creationDraft: FilterSetDraft?
    @State private var name: String
    @State private var kind: FilterItemKind
    @State private var valueText: String
    @State private var unit: FilterValueUnit
    @State private var cplFields: [String]
    /// Display color of a Color filter (FILTER-COLOR-001); kept even
    /// while another kind is selected so switching back restores it.
    @State private var opticalColor: FilterSetColor
    @State private var blockedSave: BlockedSave?

    private struct BlockedSave: Identifiable {
        let cameras: [String]
        let reason: FilterItemSaveBlockReason
        var id: String { cameras.joined(separator: ",") + "\(reason)" }
    }
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case value
        case cpl(Int)
    }

    init(
        viewModel: ExposureCalculatorViewModel,
        context: FilterItemEditorContext,
        onSaved: @escaping (FilterItem) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.context = context
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        let item = context.item
        _filterSetID = State(initialValue: item.flatMap { viewModel.filterInventory.item(withID: $0.id)?.filterSet.id } ?? context.filterSetID)
        _name = State(initialValue: item?.name ?? "")
        // The kind never inherits from the previous item: every new
        // item starts as ND (FILTER-ITEM-003/007).
        _kind = State(initialValue: item?.behavior.kind ?? FilterSetItemOrder.newItemKind)
        _opticalColor = State(initialValue: item?.behavior.opticalColor ?? .red)
        switch item?.behavior {
        case .fixed(let value), .gnd(let value):
            _valueText = State(initialValue: FilterWheelPresenter.trimmedNumber(value.value))
            _unit = State(initialValue: value.unit)
            _cplFields = State(initialValue: Self.fieldTexts(CPLExposureLossChoices.defaults))
        case .cpl(let choices):
            _valueText = State(initialValue: "")
            _unit = State(initialValue: .stops)
            _cplFields = State(initialValue: Self.fieldTexts(choices))
        case .color(let loss, _), .effect(let loss):
            // Color / Effect loss is always stops; the notation picker
            // is not shown for these kinds.
            _valueText = State(initialValue: FilterWheelPresenter.trimmedNumber(loss.stops))
            _unit = State(initialValue: .stops)
            _cplFields = State(initialValue: Self.fieldTexts(CPLExposureLossChoices.defaults))
        case nil:
            // A new item starts in the session's remembered notation
            // (Stops until a Fixed or GND item was saved in this
            // session).
            _valueText = State(initialValue: "")
            _unit = State(initialValue: context.initialUnit)
            _cplFields = State(initialValue: Self.fieldTexts(CPLExposureLossChoices.defaults))
        }
    }

    private static func fieldTexts(_ choices: CPLExposureLossChoices) -> [String] {
        choices.fields.map { $0.map(FilterWheelPresenter.trimmedNumber) ?? "" }
    }

    // MARK: Derived validation

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var registeredValue: FilterRegisteredValue? {
        guard let value = FilterDecimalInput.parseDecimal(valueText) else { return nil }
        let registered = FilterRegisteredValue(value: value, unit: unit)
        return registered.isValid ? registered : nil
    }

    /// Explicit loss of a Color or Effect item (FILTER-COLOR-001/002):
    /// stops as entered, zero allowed, at most 30.
    private var exposureLoss: FilterExposureLoss? {
        guard let value = FilterDecimalInput.parseDecimal(valueText) else { return nil }
        let loss = FilterExposureLoss(stops: value)
        return loss.isValid ? loss : nil
    }

    private var valueErrorText: String? {
        guard !valueText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch kind {
        case .fixed, .gnd:
            return registeredValue == nil ? String(localized: "Enter a value above 0 and at most 30 stops.") : nil
        case .color, .effect:
            return exposureLoss == nil ? String(localized: "Enter a value from 0 to 30 stops.") : nil
        case .cpl:
            return nil
        }
    }

    private var cplParses: [FilterDecimalInput.CPLFieldParse] {
        cplFields.map(FilterDecimalInput.parseCPLField)
    }

    private var cplChoices: CPLExposureLossChoices? {
        var fields: [Double?] = []
        for parse in cplParses {
            switch parse {
            case .empty: fields.append(nil)
            case .value(let value): fields.append(value)
            case .invalid: return nil
            }
        }
        let choices = CPLExposureLossChoices(fields: fields)
        return choices.isValid ? choices : nil
    }

    private var behavior: FilterItemBehavior? {
        switch kind {
        case .fixed:
            return registeredValue.map(FilterItemBehavior.fixed)
        case .gnd:
            return registeredValue.map(FilterItemBehavior.gnd)
        case .cpl:
            return cplChoices.map(FilterItemBehavior.cpl)
        case .color:
            return exposureLoss.map { FilterItemBehavior.color($0, opticalColor) }
        case .effect:
            return exposureLoss.map(FilterItemBehavior.effect)
        }
    }

    /// No Set exists yet, so the destination is a proposed New Filter
    /// Set made on Save (FILTER-ITEM-009).
    private var proposesNewFilterSet: Bool {
        viewModel.filterInventory.filterSets.isEmpty
    }

    private var trimmedProposedFilterSetName: String {
        proposedFilterSetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasDestination: Bool {
        if proposesNewFilterSet {
            return !trimmedProposedFilterSetName.isEmpty
        }
        return filterSetID.flatMap(viewModel.filterSet(withID:)) != nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && behavior != nil && hasDestination
    }

    var body: some View {
        NavigationStack {
            // Compact and keyboard-aware (FILTER-ITEM-010): the destination,
            // name, kind, and the active kind's value fit above the software
            // keyboard on iPhone at the default text size; the guidance
            // follows below them and stays reachable by scrolling.
            Form {
                Section {
                    // Tight vertical insets on the controls that are
                    // taller than a text row keep every input and its
                    // explanation above the keyboard (FILTER-ITEM-010);
                    // touch targets stay 44 points.
                    filterSetRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
                    TextField("Filter name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("filter-item-name-field")
                    Picker("Kind", selection: $kind) {
                        ForEach(context.selectableKinds, id: \.self) { kind in
                            Text(FilterWheelPresenter.kindName(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .accessibilityIdentifier("filter-item-kind-picker")
                }

                switch kind {
                case .fixed, .gnd:
                    valueSection
                case .cpl:
                    cplSection
                case .color:
                    displayColorSection
                case .effect:
                    lossSection
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle(context.item == nil ? Text("New filter") : Text("Edit filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("filter-item-save-button")
                }
            }
            .alert(
                Text("Cannot save"),
                isPresented: Binding(
                    get: { blockedSave != nil },
                    set: { if !$0 { blockedSave = nil } }
                ),
                presenting: blockedSave
            ) { _ in
                Button("OK", role: .cancel) { blockedSave = nil }
            } message: { blocked in
                switch blocked.reason {
                case .exceedsTotalLimit:
                    Text("This value would push the filter stack past 30 stops on \(blocked.cameras.joined(separator: ", ")). Change the mounted filters there first, or use a smaller value.")
                case .removesSelectedChoice:
                    Text("A choice of this filter is currently selected on \(blocked.cameras.joined(separator: ", ")). Keep that choice, or change the wheel selection on those cameras first.")
                case .tooManyNDWheels:
                    Text("This filter is mounted on \(blocked.cameras.joined(separator: ", ")), where the ND wheels are already full. Remove an ND wheel there first, or keep this filter's kind.")
                }
            }
            .onAppear {
                if context.item == nil {
                    DispatchQueue.main.async { focusedField = .name }
                }
            }
            .sheet(item: $creationDraft) { draft in
                FilterSetEditorSheet(
                    draft: draft,
                    onSave: { saved in
                        // Back in this editor with the new set selected;
                        // the entered values are this view's state and
                        // stay as they were.
                        if let created = viewModel.createFilterSet(name: saved.name, color: saved.color) {
                            filterSetID = created.id
                        }
                        creationDraft = nil
                    },
                    onCancel: { creationDraft = nil }
                )
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// The Filter Set the filter is saved into, always visible and
    /// enabled (FILTER-ITEM-009): every inventory Set, never Standard,
    /// with Add Filter Set at the trailing edge of the same row. Saving an
    /// existing filter into another set moves it there with its identity.
    /// With no Set yet, the row proposes a New Filter Set whose name can
    /// be edited; it is created only when the filter saves.
    private var filterSetRow: some View {
        HStack(spacing: 12) {
            if proposesNewFilterSet {
                HStack(spacing: 6) {
                    Text("Filter Set")
                    Spacer(minLength: 8)
                    FilterSetColorSwatch(color: context.proposedFilterSetColor, size: 11)
                    // Sized to the name so the swatch stays beside it.
                    TextField("Filter Set name", text: $proposedFilterSetName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color.secondary)
                        .textInputAutocapitalization(.words)
                        .fixedSize()
                        .accessibilityIdentifier("filter-item-proposed-filter-set-name")
                }
                .frame(minHeight: 44)
            } else {
                filterSetMenu
            }
            Button {
                creationDraft = FilterSetDraft(name: "", color: viewModel.suggestFilterSetCreationColor())
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Add Filter Set"))
            .accessibilityIdentifier("filter-item-add-filter-set-button")
        }
    }

    /// The choice among the inventory Sets. The selected Set's source
    /// color sits beside its name, and the same cue on every choice;
    /// never the item's display color.
    private var filterSetMenu: some View {
        Menu {
            Picker("Filter Set", selection: $filterSetID) {
                ForEach(viewModel.filterInventory.filterSets) { filterSet in
                    Label {
                        Text(filterSet.name)
                    } icon: {
                        Image(uiImage: FilterSetSwatchImage.image(for: filterSet.color))
                    }
                    .tag(Optional(filterSet.id))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Filter Set")
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                if let selected = filterSetID.flatMap(viewModel.filterSet(withID:)) {
                    FilterSetColorSwatch(color: selected.color, size: 11)
                    Text(selected.name)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                } else {
                    Text("Choose")
                        .foregroundStyle(Color.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("filter-item-filter-set-picker")
    }

    private var valueSection: some View {
        Section {
            HStack {
                TextField("Value", text: $valueText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .value)
                    .accessibilityIdentifier("filter-item-value-field")
                Picker("Unit", selection: $unit) {
                    ForEach(FilterValueUnit.allCases, id: \.self) { unit in
                        Text(FilterWheelPresenter.unitName(unit)).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
                .accessibilityIdentifier("filter-item-unit-picker")
            }
            if let registeredValue, let stops = registeredValue.canonicalStops {
                Text("= \(FilterWheelPresenter.stopsText(stops))")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("filter-item-conversion-text")
            }
            if let valueErrorText {
                Text(valueErrorText)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        } header: {
            Text(kind == .gnd ? "Full density" : "Exposure loss")
        } footer: {
            // ND has no explanation; a GND's modes say what it adds
            // (FILTER-ITEM-010).
            if kind == .gnd {
                Text("While shooting, Record only uses 0 stops; Apply to exposure uses the registered value.")
            }
        }
    }

    /// Display color of a Color filter (FILTER-COLOR-001): a visual
    /// reference chosen from the same palette as Filter Sets, each choice
    /// drawn in its color with the selected one marked; the explicit loss
    /// follows on its own labelled row. The palette's label sits in its
    /// row rather than a section header, so the explanation below the
    /// loss stays above the keyboard (FILTER-ITEM-010).
    private var displayColorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("Display color")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                FilterSetColorGrid(selection: $opticalColor)
                    .accessibilityIdentifier("filter-item-optical-color-picker")
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
            lossRow
        } footer: {
            lossFooter
        }
    }

    /// Explicit loss of an Effect filter in stops (FILTER-COLOR-002).
    private var lossSection: some View {
        Section {
            lossRow
        } header: {
            Text("Exposure loss")
        } footer: {
            lossFooter
        }
    }

    /// What a Color or Effect filter adds (FILTER-ITEM-010).
    private var lossFooter: some View {
        Text("The entered exposure loss is added to the exposure calculation.")
    }

    /// Explicit loss of a Color or Effect filter in stops
    /// (FILTER-COLOR-001/002): user-supplied, zero allowed, never inferred
    /// from the color or the name. A Color filter's row is labelled, as
    /// it follows the palette.
    @ViewBuilder
    private var lossRow: some View {
        HStack {
            if kind == .color {
                Text("Exposure loss")
            }
            TextField("Value", text: $valueText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(kind == .color ? .trailing : .leading)
                .focused($focusedField, equals: .value)
                .accessibilityIdentifier("filter-item-loss-field")
            Text("stops")
                .foregroundStyle(.secondary)
        }
        if let valueErrorText {
            Text(valueErrorText)
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    /// The three CPL exposure-loss fields on one row (FILTER-CPL-001).
    private var cplSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(0..<CPLExposureLossChoices.fieldCount, id: \.self) { index in
                    TextField("Empty", text: $cplFields[index])
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                        .focused($focusedField, equals: .cpl(index))
                        .accessibilityLabel(Text("Exposure loss choice \(index + 1)"))
                        .accessibilityIdentifier("filter-item-cpl-field-\(index)")
                }
                Text("stops")
                    .foregroundStyle(.secondary)
            }
            if cplParses.contains(.invalid) {
                Text("Use 0.1 to 9.9 with at most one decimal digit.")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            if cplParses.allSatisfy({ $0 == .empty }) {
                Text("At least one choice is required.")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        } header: {
            Text("Exposure loss choices")
        } footer: {
            Text("Register up to three exposure-loss values to choose from while shooting.")
        }
    }

    private func save() {
        guard let behavior, !trimmedName.isEmpty, hasDestination else { return }
        let item = FilterItem(
            id: context.item?.id ?? .generate(),
            name: trimmedName,
            behavior: behavior
        )
        // The proposed New Filter Set is made only now, together with the
        // valid filter in one save; Cancel or an invalid filter makes
        // neither (FILTER-ITEM-009).
        if proposesNewFilterSet {
            guard viewModel.createFilterSet(name: trimmedProposedFilterSetName, color: context.proposedFilterSetColor, holding: item) != nil else {
                return
            }
            onSaved(item)
            onDismiss()
            return
        }
        guard let filterSetID else { return }
        switch viewModel.saveFilterItem(item, in: filterSetID) {
        case .saved:
            onSaved(item)
            onDismiss()
        case .blocked(let cameras, let reason):
            blockedSave = BlockedSave(cameras: cameras, reason: reason)
        }
    }
}

/// A filled circle in a Filter Set's color, drawn as an original-color
/// image so a menu shows the color (FILTER-ITEM-010).
enum FilterSetSwatchImage {
    static func image(for color: FilterSetColor) -> UIImage {
        let size = CGSize(width: 14, height: 14)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(Color.filterSet(color)).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)).fill()
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
