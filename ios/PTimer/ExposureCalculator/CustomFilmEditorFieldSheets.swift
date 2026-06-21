// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerKit

/// Identifier for the field the photographer tapped in the compact
/// editor. Drives the `.sheet(item:)` modal that
/// `CustomFilmEditorView` presents — each case maps to a focused
/// edit sheet that owns its own input chrome (chips, steppers,
/// numeric field) so the main editor stays a tall stack of compact
/// summary rows.

/// Dispatching wrapper presented by `CustomFilmEditorView`'s
/// `.sheet(item:)`. Routes the tapped field identifier to the
/// concrete edit sheet, keeping the main editor view free of one
/// big switch.
struct CustomFilmEditorFieldSheet: View {
    let field: CustomFilmEditorEditField
    @Binding var formState: CustomFilmEditorFormState
    /// `true` when the editor was opened on an existing custom
    /// film. Lets the inline-validation hint policy distinguish
    /// the untouched-new-form suppression from the edit flow.
    let isEditing: Bool

    var body: some View {
        switch field {
        case .manufacturer:
            CustomFilmEditorManufacturerSheet(formState: $formState)
        case .label:
            CustomFilmEditorLabelSheet(formState: $formState, isEditing: isEditing)
        case .iso:
            CustomFilmEditorISOSheet(formState: $formState, isEditing: isEditing)
        case .exponent:
            CustomFilmEditorExponentSheet(formState: $formState, isEditing: isEditing)
        case .referenceTm:
            CustomFilmEditorDurationSheet(
                formState: $formState,
                field: .referenceTm,
                isEditing: isEditing
            )
        case .correctedAtReference:
            CustomFilmEditorDurationSheet(
                formState: $formState,
                field: .correctedAtReference,
                isEditing: isEditing
            )
        case .offset:
            CustomFilmEditorDurationSheet(
                formState: $formState,
                field: .offset,
                isEditing: isEditing
            )
        case .noCorrectionThrough:
            CustomFilmEditorDurationSheet(
                formState: $formState,
                field: .noCorrectionThrough,
                isEditing: isEditing
            )
        case .sourceRangeThrough:
            CustomFilmEditorDurationSheet(
                formState: $formState,
                field: .sourceRangeThrough,
                isEditing: isEditing
            )
        }
    }
}

// MARK: - Sheet helpers

/// Toolbar + presentation-detent chrome shared by every edit
/// sheet so the dismiss interaction stays consistent across
/// fields.
private struct EditSheetChrome<Content: View>: View {
    let title: String
    let accessibilityIdentifier: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("\(accessibilityIdentifier)-done")
                    }
                }
        }
        // `.fraction(0.7)` initial detent lets the photographer
        // see the formula display, the input field, and the chip
        // ladder on a single screen without scrolling, and the
        // `.large` detent keeps room for the keyboard on smaller
        // phones. The previous `.medium`-only configuration left
        // the chip row clipped on long ladders (ISO, exponent).
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Horizontally scrolling chip row reused by every edit sheet that
/// offers preset values. Mirrors the chrome the main editor used
/// inline before the compact-row pass so the photographer reads
/// the same affordance across the editor and its sheets.
private struct EditSheetChipRow: View {
    let values: [String]
    let onSelect: (String) -> Void
    /// Optional currently-selected value so the chip can render
    /// with a highlighted background. Compared by trimmed
    /// equality.
    var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Button {
                        onSelect(value)
                    } label: {
                        Text(value)
                            .font(.footnote.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(backgroundColor(for: value))
                            )
                            // Explicit hit shape so the chip label
                            // owns the tap area at the visible pill
                            // boundary. Without this, the enclosing
                            // SwiftUI Form / horizontal ScrollView
                            // can swallow the first tap as a scroll
                            // attempt when the sheet is at the
                            // `.large` detent, which previously
                            // required users to drag the sheet
                            // before chips became responsive.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func backgroundColor(for value: String) -> Color {
        let trimmedSelected = selected?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSelected == value {
            return Color.accentColor.opacity(0.18)
        }
        return Color.primary.opacity(0.08)
    }
}

/// Two-line static formula display used by the field sheets.
/// The top row is the same compact symbolic line the editor
/// card uses; the bottom row goes through the math-expression
/// renderer in read-only mode so the photographer reads the
/// current numeric values in the same fraction-shaped layout
/// they tapped to open the sheet.
struct CustomFilmEditorFormulaDisplayBlock: View {
    let form: CustomFilmEditorFormState
    var topAccessibilityID: String = "custom-film-editor-formula-structure"
    var bottomAccessibilityID: String = "custom-film-editor-formula-current"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CustomFilmFormulaSymbolicLine()
                .accessibilityIdentifier(topAccessibilityID)

            CustomFilmFormulaMathView(
                tokens: form.formulaTokenDisplays(),
                leadingText: "   = ",
                onTap: nil
            )
            .accessibilityIdentifier(bottomAccessibilityID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Manufacturer

private struct CustomFilmEditorManufacturerSheet: View {
    @Binding var formState: CustomFilmEditorFormState

    private static let commonManufacturers: [String] = [
        "ADOX", "Kodak", "Ilford", "Fujifilm", "Foma", "Rollei",
    ]

    var body: some View {
        EditSheetChrome(
            title: CustomFilmEditorEditField.manufacturer.sheetTitle,
            accessibilityIdentifier: "custom-film-editor-sheet-manufacturer"
        ) {
            Form {
                Section {
                    TextField("Optional", text: $formState.manufacturerText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .accessibilityIdentifier("custom-film-editor-sheet-manufacturer-input")
                }
                Section("Common") {
                    EditSheetChipRow(
                        values: Self.commonManufacturers,
                        onSelect: { formState.manufacturerText = $0 },
                        selected: formState.manufacturerText
                    )
                }
            }
        }
    }
}

// MARK: - Label

private struct CustomFilmEditorLabelSheet: View {
    @Binding var formState: CustomFilmEditorFormState
    let isEditing: Bool

    var body: some View {
        EditSheetChrome(
            title: CustomFilmEditorEditField.label.sheetTitle,
            accessibilityIdentifier: "custom-film-editor-sheet-label"
        ) {
            Form {
                Section {
                    TextField("e.g. NB1", text: $formState.filmLabel)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .accessibilityIdentifier("custom-film-editor-sheet-label-input")
                } footer: {
                    if let reason = formState.inlineValidationReason(
                        for: .label,
                        isEditing: isEditing
                    ) {
                        Text(reason)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }
            }
        }
    }
}

// MARK: - ISO

/// Common ISO box-speed chip values shown inside the ISO edit
/// sheet. Lifted to file-scope so tests can pin the order and a
/// future ISO 320 / 1000 expansion does not silently regress the
/// chip layout. Spans the full ladder a film photographer is
/// likely to encounter: 6 through 3200, including the 320 / 500
/// / 640 / 1000 / 1250 box speeds that several stocks are
/// commonly rated at (Tri-X at 320 or 500, Delta 3200 at 1000,
/// etc.).
let customFilmEditorCommonISOs: [String] = [
    "6", "12", "20", "25", "50", "64", "80", "100", "125",
    "160", "200", "250", "320", "400", "500", "640", "800",
    "1000", "1250", "1600", "3200",
]

private struct CustomFilmEditorISOSheet: View {
    @Binding var formState: CustomFilmEditorFormState
    let isEditing: Bool

    var body: some View {
        EditSheetChrome(
            title: CustomFilmEditorEditField.iso.sheetTitle,
            accessibilityIdentifier: "custom-film-editor-sheet-iso"
        ) {
            Form {
                Section {
                    TextField("e.g. 100", text: $formState.isoText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("custom-film-editor-sheet-iso-input")
                } footer: {
                    if let reason = formState.inlineValidationReason(
                        for: .iso,
                        isEditing: isEditing
                    ) {
                        Text(reason)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }
                Section("Common") {
                    EditSheetChipRow(
                        values: customFilmEditorCommonISOs,
                        onSelect: { formState.isoText = $0 },
                        selected: formState.isoText
                    )
                }
            }
        }
    }
}

// MARK: - Exponent

private struct CustomFilmEditorExponentSheet: View {
    @Binding var formState: CustomFilmEditorFormState
    let isEditing: Bool

    private static let commonExponents: [String] = [
        "1.10", "1.20", "1.30", "1.40", "1.50",
        "1.60", "1.70", "1.80", "1.90",
    ]

    var body: some View {
        EditSheetChrome(
            title: CustomFilmEditorEditField.exponent.sheetTitle,
            accessibilityIdentifier: "custom-film-editor-sheet-exponent"
        ) {
            Form {
                Section {
                    CustomFilmEditorFormulaDisplayBlock(
                        form: formState,
                        topAccessibilityID: "custom-film-editor-sheet-formula-structure",
                        bottomAccessibilityID: "custom-film-editor-sheet-formula-current"
                    )
                } header: {
                    Text("Formula")
                }

                Section {
                    // Single-row stepper layout: the `-0.01`
                    // button sits to the left of the current
                    // value, the `+0.01` button to the right.
                    // Tying the adjustment controls visually to
                    // the value they mutate makes the relationship
                    // obvious without a separate caption.
                    HStack(spacing: 12) {
                        stepButton(label: "-0.01", delta: -0.01)
                            .accessibilityIdentifier("custom-film-editor-sheet-exponent-decrement")
                        TextField("e.g. 1.30", text: $formState.exponentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("custom-film-editor-sheet-exponent-input")
                        stepButton(label: "+0.01", delta: 0.01)
                            .accessibilityIdentifier("custom-film-editor-sheet-exponent-increment")
                    }
                } footer: {
                    if let reason = formState.inlineValidationReason(
                        for: .exponent,
                        isEditing: isEditing
                    ) {
                        Text(reason)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }

                Section("Common") {
                    EditSheetChipRow(
                        values: Self.commonExponents,
                        onSelect: { formState.exponentText = $0 },
                        selected: formState.exponentText
                    )
                }
            }
        }
    }

    private func stepButton(label: String, delta: Double) -> some View {
        Button {
            adjustExponent(by: delta)
        } label: {
            Text(label)
                .font(.footnote.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func adjustExponent(by delta: Double) {
        let trimmed = formState.exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = Double(trimmed) ?? 1.3
        let next = current + delta
        formState.exponentText = String(format: "%.2f", next)
    }
}

// MARK: - Duration fields

/// Generic edit sheet for the five duration-shaped formula
/// fields (`Tm₀` Metered point, `Tc₀` Corrected point, `b` Fixed
/// add-on, `No correction until`, `Source data through`). Each
/// binds to one `CustomFilmEditorFormState` text field, surfaces
/// a sheet-local inline validation hint, and adds field-
/// appropriate preset chips. The `Source data through` case
/// additionally exposes an `Unlimited` chip that writes the
/// empty string per the validator's contract.
private struct CustomFilmEditorDurationSheet: View {
    @Binding var formState: CustomFilmEditorFormState
    let field: CustomFilmEditorEditField
    let isEditing: Bool

    private var validationField: CustomFilmEditorField? {
        switch field {
        case .referenceTm: return .referenceTm
        case .correctedAtReference: return .correctedAtReference
        case .offset: return .offset
        case .noCorrectionThrough: return .noCorrectionThrough
        case .sourceRangeThrough: return .sourceRangeThrough
        case .manufacturer, .label, .iso, .exponent: return nil
        }
    }

    private var textBinding: Binding<String> {
        switch field {
        case .referenceTm:
            return $formState.baseTmText
        case .correctedAtReference:
            return $formState.baseTcText
        case .offset:
            return $formState.offsetSecondsText
        case .noCorrectionThrough:
            return $formState.noCorrectionThroughText
        case .sourceRangeThrough:
            return $formState.validThroughText
        case .manufacturer, .label, .iso, .exponent:
            return .constant("")
        }
    }

    private var presetChips: [String] {
        switch field {
        case .referenceTm, .correctedAtReference:
            return ["0.1s", "0.5s", "1s", "2s", "5s", "10s", "30s", "1m"]
        case .offset:
            return ["-1s", "-0.5s", "0s", "0.5s", "1s", "2s"]
        case .noCorrectionThrough:
            return ["0.5s", "1s", "2s", "5s", "10s", "30s"]
        case .sourceRangeThrough:
            return ["Unlimited", "30s", "1m", "2m", "5m", "10m", "30m", "1h"]
        case .manufacturer, .label, .iso, .exponent:
            return []
        }
    }

    private var placeholder: String {
        switch field {
        case .referenceTm, .correctedAtReference, .noCorrectionThrough:
            return "1s"
        case .offset:
            return "0s"
        case .sourceRangeThrough:
            return "Unlimited"
        case .manufacturer, .label, .iso, .exponent:
            return ""
        }
    }

    private var sheetAccessibilityID: String {
        "custom-film-editor-sheet-\(field.rawValue)"
    }

    var body: some View {
        EditSheetChrome(
            title: field.sheetTitle,
            accessibilityIdentifier: sheetAccessibilityID
        ) {
            Form {
                contextSection

                Section {
                    if field == .noCorrectionThrough {
                        HStack(spacing: 12) {
                            noCorrectionStepButton(label: "−0.1s", delta: -0.1)
                                .accessibilityIdentifier(
                                    "\(sheetAccessibilityID)-decrement"
                                )
                            TextField(placeholder, text: textBinding)
                                .keyboardType(.numbersAndPunctuation)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .multilineTextAlignment(.center)
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("\(sheetAccessibilityID)-input")
                            noCorrectionStepButton(label: "+0.1s", delta: 0.1)
                                .accessibilityIdentifier(
                                    "\(sheetAccessibilityID)-increment"
                                )
                        }
                    } else {
                        TextField(placeholder, text: textBinding)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("\(sheetAccessibilityID)-input")
                    }
                } footer: {
                    if let validationField,
                       let reason = formState.inlineValidationReason(
                        for: validationField,
                        isEditing: isEditing
                       ) {
                        Text(reason)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }

                Section("Common") {
                    EditSheetChipRow(
                        values: presetChips,
                        onSelect: { value in
                            // Source range chips include `Unlimited`,
                            // which the form stores as an empty
                            // string per the validator's contract.
                            if field == .sourceRangeThrough, value == "Unlimited" {
                                textBinding.wrappedValue = ""
                            } else {
                                textBinding.wrappedValue = value
                            }
                        },
                        selected: textBinding.wrappedValue
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        if field == .noCorrectionThrough, formState.calculationInputKind == .table {
            Section {
                Text("No correction is the metered time below which the table keeps Tc = Tm. It must be below the first table anchor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("custom-film-editor-sheet-no-correction-explanation")
                if tableNoCorrectionIsShortening {
                    Text("Raise this value to inspect the fitted formula.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("custom-film-editor-sheet-no-correction-shortening-hint")
                }
            }
        } else {
            Section {
                CustomFilmEditorFormulaDisplayBlock(
                    form: formState,
                    topAccessibilityID: "custom-film-editor-sheet-formula-structure",
                    bottomAccessibilityID: "custom-film-editor-sheet-formula-current"
                )
            } header: {
                Text("Formula")
            }
        }
    }

    private var tableNoCorrectionIsShortening: Bool {
        guard let rule = formState.parsedTableInterpolationRule() else { return false }
        if case .unavailable(.unusableShorteningFit) = CustomTableFittedFormulaPresenter.outcome(for: rule) {
            return true
        }
        return false
    }

    private func noCorrectionStepButton(label: String, delta: Double) -> some View {
        Button {
            adjustNoCorrection(by: delta)
        } label: {
            Text(label)
                .font(.footnote.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func adjustNoCorrection(by delta: Double) {
        let currentSeconds: Double
        switch CustomFilmDurationParser.parse(textBinding.wrappedValue) {
        case .seconds(let v) where v.isFinite && v > 0:
            currentSeconds = v
        default:
            currentSeconds = 0.1
        }
        let next = max(0.1, ((currentSeconds + delta) * 10).rounded() / 10)
        textBinding.wrappedValue = next < 1
            ? String(format: "%.1fs", next)
            : next == next.rounded()
                ? "\(Int(next.rounded()))s"
                : String(format: "%.1fs", next)
    }
}
