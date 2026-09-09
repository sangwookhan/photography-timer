// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// `.sheet(item:)` payload for the item editor: the owning set and
/// the item being edited (`nil` when creating).
struct FilterItemEditorContext: Identifiable {
    let filterSetID: FilterSetID
    let item: FilterItem?

    var id: String {
        "\(filterSetID.rawValue)-\(item?.id.rawValue ?? "new")"
    }
}

/// Registers or edits one physical filter (FILTER-ITEM-002/003/004,
/// FILTER-CPL-001…004, FILTER-GND-001/003). The kind is chosen
/// explicitly; Fixed and GND take a decimal value in Stops, OD, or ND
/// factor and show the canonical conversion; a CPL exposes its three
/// exposure-loss fields on a decimal-capable numeric keyboard. Saving
/// is blocked with the affected cameras when any stack would exceed
/// 30 stops (FILTER-ITEM-005).
struct FilterItemEditorView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let context: FilterItemEditorContext
    let onDismiss: () -> Void

    @State private var name: String
    @State private var kind: FilterItemKind
    @State private var valueText: String
    @State private var unit: FilterValueUnit
    @State private var cplFields: [String]
    @State private var blockedCameras: [String]?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case value
        case cpl(Int)
    }

    init(viewModel: ExposureCalculatorViewModel, context: FilterItemEditorContext, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.context = context
        self.onDismiss = onDismiss
        let item = context.item
        _name = State(initialValue: item?.name ?? "")
        _kind = State(initialValue: item?.behavior.kind ?? .fixed)
        switch item?.behavior {
        case .fixed(let value), .gnd(let value):
            _valueText = State(initialValue: FilterWheelPresenter.trimmedNumber(value.value))
            _unit = State(initialValue: value.unit)
            _cplFields = State(initialValue: Self.fieldTexts(CPLExposureLossChoices.defaults))
        case .cpl(let choices):
            _valueText = State(initialValue: "")
            _unit = State(initialValue: .stops)
            _cplFields = State(initialValue: Self.fieldTexts(choices))
        case nil:
            _valueText = State(initialValue: "")
            _unit = State(initialValue: .stops)
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

    private var valueErrorText: String? {
        guard kind != .cpl, !valueText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return registeredValue == nil ? String(localized: "Enter a value above 0 and at most 30 stops.") : nil
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
        }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && behavior != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Filter name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("filter-item-name-field")
                    Picker("Kind", selection: $kind) {
                        ForEach(FilterItemKind.allCases, id: \.self) { kind in
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
                }

                if kind == .gnd {
                    Section {
                        Text("While shooting, a GND wheel offers Record only (0 stops) and Apply full value (its full registered density). Record only is the default.")
                        Text("Apply full value suits a composition where the dark region covers nearly the entire metered frame. A base shutter metered through the mounted GND may already include its attenuation.")
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
                    get: { blockedCameras != nil },
                    set: { if !$0 { blockedCameras = nil } }
                ),
                presenting: blockedCameras
            ) { _ in
                Button("OK", role: .cancel) { blockedCameras = nil }
            } message: { cameras in
                Text("This value would push the filter stack past 30 stops on \(cameras.joined(separator: ", ")). Change the mounted filters there first, or use a smaller value.")
            }
            .onAppear {
                if context.item == nil {
                    DispatchQueue.main.async { focusedField = .name }
                }
            }
        }
        .presentationDragIndicator(.visible)
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
        switch viewModel.saveFilterItem(item, in: context.filterSetID) {
        case .saved:
            onDismiss()
        case .blocked(let cameras):
            blockedCameras = cameras
        }
    }
}
