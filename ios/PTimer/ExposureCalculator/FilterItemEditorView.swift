// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// `.sheet(item:)` payload for the item editor: the Filter Set it
/// starts in, the item being edited (`nil` when creating), and — for a
/// new item — the notation the editing session remembers from the last
/// saved ND or GND item (FILTER-ITEM-007). A new item starts as ND
/// (FILTER-ITEM-003) in Default when Add Filter comes from Shooting
/// Filters, or in the Filter Set whose editor it comes from
/// (FILTER-ITEM-009).
struct FilterItemEditorContext: Identifiable {
    /// Every kind, ND first, for new and existing items alike: the type
    /// is chosen inside the editor, and an existing item may be
    /// corrected to any kind (FILTER-ITEM-003/008).
    let selectableKinds = FilterSetItemOrder.kinds

    let filterSetID: FilterSetID
    let item: FilterItem?
    var initialUnit: FilterValueUnit = .stops

    init(filterSetID: FilterSetID, item: FilterItem?, initialUnit: FilterValueUnit = .stops) {
        self.filterSetID = filterSetID
        self.item = item
        self.initialUnit = initialUnit
    }

    var id: String {
        "\(filterSetID.rawValue)-\(item?.id.rawValue ?? "new")"
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
    /// that holds it.
    @State private var filterSetID: FilterSetID
    /// Filter Set creation opened from the Filter Set field.
    @State private var creationDraft: FilterSetDraft?
    @State private var name: String
    @State private var kind: FilterItemKind
    @State private var valueText: String
    @State private var unit: FilterValueUnit
    @State private var cplFields: [String]
    /// Optical color of a Color filter (FILTER-COLOR-001); kept even
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

    private var canSave: Bool {
        !trimmedName.isEmpty && behavior != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                filterSetSection

                Section {
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
                    .accessibilityIdentifier("filter-item-kind-picker")
                } header: {
                    Text("Filter")
                } footer: {
                    Text("The kind is your choice; the app never guesses it from the name.")
                }

                switch kind {
                case .fixed, .gnd:
                    valueSection
                case .cpl:
                    cplSection
                case .color:
                    opticalColorSection
                    lossSection
                case .effect:
                    lossSection
                }

                if kind == .gnd {
                    Section {
                        Text("While shooting, a GND offers Record only (0 stops) and Apply to exposure (its full registered density). Record only is the default.")
                        Text("Apply to exposure suits a composition where the dark region covers nearly the entire metered frame. A base shutter metered through the mounted GND may already include its attenuation.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Calculation modes")
                    }
                    .font(.footnote)
                }
            }
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
    /// enabled (FILTER-ITEM-009): Default and every user set, plus Add
    /// Filter Set. Saving an existing filter into another set moves it
    /// there with its identity.
    private var filterSetSection: some View {
        Section {
            Picker("Filter Set", selection: $filterSetID) {
                ForEach(viewModel.filterInventory.filterSets) { filterSet in
                    Text(filterSet.name).tag(filterSet.id)
                }
            }
            .accessibilityIdentifier("filter-item-filter-set-picker")
            Button {
                creationDraft = FilterSetDraft(name: "", color: viewModel.suggestFilterSetCreationColor())
            } label: {
                Label("Add Filter Set", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("filter-item-add-filter-set-button")
        }
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
            Text("Stops are kept as entered; OD divides by 0.3; an ND factor converts as log2. The value is never snapped to the Standard ladder.")
        }
    }

    /// Color of a Color filter (FILTER-COLOR-001): chosen from the same
    /// palette as Filter Sets, each choice drawn in its actual color,
    /// with the selected color's name, separate from the loss.
    private var opticalColorSection: some View {
        Section {
            FilterSetColorGrid(selection: $opticalColor)
                .accessibilityIdentifier("filter-item-optical-color-picker")
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.filterSet(opticalColor))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(FilterWheelPresenter.opticalColorName(opticalColor))
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Optical color")
        } footer: {
            Text("The optical color identifies the filter. It never sets the exposure loss.")
        }
    }

    /// Explicit loss of a Color or Effect filter in stops
    /// (FILTER-COLOR-001/002): user-supplied, zero allowed, never
    /// inferred from the color or the name.
    private var lossSection: some View {
        Section {
            HStack {
                TextField("Value", text: $valueText)
                    .keyboardType(.decimalPad)
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
        } header: {
            Text("Exposure loss")
        } footer: {
            Text("Enter the loss in stops from the maker's data or your own metering. Zero is allowed for a filter with no measurable loss.")
        }
    }

    private var cplSection: some View {
        Section {
            ForEach(0..<CPLExposureLossChoices.fieldCount, id: \.self) { index in
                HStack {
                    Text("Choice \(index + 1)")
                    Spacer()
                    TextField("Empty", text: $cplFields[index])
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .focused($focusedField, equals: .cpl(index))
                        .accessibilityLabel(Text("Exposure loss choice \(index + 1)"))
                        .accessibilityIdentifier("filter-item-cpl-field-\(index)")
                    Text("stops")
                        .foregroundStyle(.secondary)
                }
                if cplParses[index] == .invalid {
                    Text("Use 0.1 to 9.9 with at most one decimal digit.")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if cplParses.allSatisfy({ $0 == .empty }) {
                Text("At least one choice is required.")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        } header: {
            Text("Exposure loss choices")
        } footer: {
            Text("Exposure loss choices (stops) available from the wheel while shooting. Empty fields are skipped; duplicate values appear once.")
        }
    }

    private func save() {
        guard let behavior, !trimmedName.isEmpty else { return }
        let item = FilterItem(
            id: context.item?.id ?? .generate(),
            name: trimmedName,
            behavior: behavior
        )
        switch viewModel.saveFilterItem(item, in: filterSetID) {
        case .saved:
            onSaved(item)
            onDismiss()
        case .blocked(let cameras, let reason):
            blockedSave = BlockedSave(cameras: cameras, reason: reason)
        }
    }
}
