import SwiftUI

/// Sheet-presented editor for authoring a custom reciprocity
/// formula profile. The form is a compact list of rows: a
/// display-name header, a Basic card (manufacturer / label /
/// ISO), a Formula card that bundles the model text, exponent
/// input (with quick chips + fine adjusters), scale/offset
/// summary, and application range, then a Preview card and a
/// Reference URL row.
///
/// Toolbar:
/// - Top-left `×`: cancel without saving
/// - Top-right `✓`: save (disabled when validation fails)
struct CustomFilmEditorView: View {
    let editing: FilmIdentity?
    let onSave: (FilmIdentity) -> Void
    let onCancel: () -> Void

    @State private var formState: CustomFilmEditorFormState
    @State private var validationErrors: CustomFilmEditorValidationErrors = CustomFilmEditorValidationErrors([])

    init(
        editing: FilmIdentity? = nil,
        onSave: @escaping (FilmIdentity) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.editing = editing
        self.onSave = onSave
        self.onCancel = onCancel
        let initialState = editing.flatMap(CustomFilmEditorFormState.from(film:))
            ?? CustomFilmEditorFormState()
        self._formState = State(initialValue: initialState)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("custom-film-editor-display-name")
                }
                .listRowBackground(Color.clear)

                basicCard
                formulaCard
                previewCard
                referenceURLSection
            }
            .navigationTitle(editing == nil ? "New custom film" : "Edit custom film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .accessibilityLabel("Cancel")
                    }
                    .accessibilityIdentifier("custom-film-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .accessibilityLabel("Save")
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("custom-film-editor-save")
                }
            }
        }
    }

    // MARK: - Basic card

    @ViewBuilder
    private var basicCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                editorRow(label: "Manufacturer") {
                    TextField("Optional", text: $formState.manufacturerText)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .accessibilityIdentifier("custom-film-editor-manufacturer")
                }
                chipRow(values: Self.commonManufacturers) { value in
                    formState.manufacturerText = value
                }
            }

            editorRow(label: "Label") {
                TextField("e.g. NB1", text: $formState.filmLabel)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .accessibilityIdentifier("custom-film-editor-film-label")
            }
            if validationErrors.contains(.missingFilmLabel) {
                fieldErrorText("Label is required.")
            }

            VStack(alignment: .leading, spacing: 4) {
                editorRow(label: "ISO") {
                    TextField("e.g. 100", text: $formState.isoText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("custom-film-editor-iso")
                }
                chipRow(values: Self.commonISOs) { value in
                    formState.isoText = value
                }
            }
            if validationErrors.contains(.invalidISO) {
                fieldErrorText(
                    "Enter an ISO between \(CustomFilmEditorFormState.minISO) and \(CustomFilmEditorFormState.maxISO)."
                )
            }
        }
    }

    // MARK: - Formula card

    @ViewBuilder
    private var formulaCard: some View {
        Section("Formula model") {
            Text("Tc = base Tc × (Tm / base Tm)^exponent + offset")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("custom-film-editor-formula-model")

            editorRow(label: "Base Tm") {
                TextField("1s", text: $formState.baseTmText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier("custom-film-editor-base-tm")
            }
            if validationErrors.contains(.invalidBaseTm) {
                fieldErrorText("Base Tm must be a positive duration (e.g. 1s, 5m).")
            }

            editorRow(label: "Base Tc") {
                TextField("1s", text: $formState.baseTcText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier("custom-film-editor-base-tc")
            }
            if validationErrors.contains(.invalidBaseTc) {
                fieldErrorText("Base Tc must be a positive duration (e.g. 1s, 5m).")
            }

            VStack(alignment: .leading, spacing: 4) {
                editorRow(label: "Exponent") {
                    TextField("e.g. 1.30", text: $formState.exponentText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("custom-film-editor-exponent")
                }
                chipRow(values: Self.commonExponents) { value in
                    formState.exponentText = value
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button { adjustExponent(by: -0.01) } label: {
                        Text("-0.01")
                            .font(.footnote.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("custom-film-editor-exponent-decrement")
                    Button { adjustExponent(by: 0.01) } label: {
                        Text("+0.01")
                            .font(.footnote.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("custom-film-editor-exponent-increment")
                }
            }
            if validationErrors.contains(.missingFormulaExponent) {
                fieldErrorText("Exponent is required.")
            }
            if validationErrors.contains(.invalidFormulaExponent) {
                fieldErrorText("Enter a positive number.")
            }
            if validationErrors.contains(.formulaShortensExposure) {
                fieldErrorText("Corrected time must be equal to or longer than metered time.")
            }

            editorRow(label: "Offset") {
                TextField("0s", text: $formState.offsetSecondsText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier("custom-film-editor-offset")
            }
            if validationErrors.contains(.invalidFormulaOffset) {
                fieldErrorText("Offset must be a duration (e.g. 0s, 1s).")
            }

            editorRow(label: "No correction up to") {
                TextField("1s", text: $formState.noCorrectionThroughText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier("custom-film-editor-no-correction-through")
            }
            if validationErrors.contains(.invalidNoCorrectionThrough) {
                fieldErrorText("Enter a positive duration (e.g. 1s, 5m).")
            }

            editorRow(label: "Source range through") {
                TextField("Unlimited", text: $formState.validThroughText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("custom-film-editor-valid-through")
            }
            if validationErrors.contains(.invalidValidThrough) {
                fieldErrorText("Enter a duration greater than no-correction, or `Unlimited`.")
            }
        }
    }

    // MARK: - Preview card

    @ViewBuilder
    private var previewCard: some View {
        Section("Preview") {
            // Render the editor preview through the same
            // `FilmModeDetailsGraph` view the runtime Reciprocity
            // Details sheet uses, so the same formula parameters
            // produce the same shape / viewport / boundary
            // semantics on both surfaces.
            if let graphState = CustomFilmEditorPreviewGraphPresenter
                .graphDisplayState(for: formState) {
                FilmModeDetailsGraph(graph: graphState)
                    .accessibilityIdentifier("custom-film-editor-preview-chart")
            } else {
                previewPlaceholder
                    .accessibilityIdentifier("custom-film-editor-preview-chart")
            }
            CustomFilmEditorPreviewTable(form: formState)
                .accessibilityIdentifier("custom-film-editor-preview-table")
        }
    }

    @ViewBuilder
    private var previewPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                Text("Invalid formula input")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
            .frame(height: 196)
            .accessibilityIdentifier("custom-film-editor-preview-placeholder")
        }
    }

    // MARK: - Reference URL row

    @ViewBuilder
    private var referenceURLSection: some View {
        Section {
            editorRow(label: "Reference URL") {
                TextField("Optional", text: $formState.referenceURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("custom-film-editor-reference-url")
            }
        }
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func editorRow<Value: View>(
        label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            value()
        }
    }

    @ViewBuilder
    private func chipRow(
        values: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Button {
                        onSelect(value)
                    } label: {
                        Text(value)
                            .font(.footnote.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Computed copy

    private var displayName: String {
        let trimmedISO = formState.isoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = Int(trimmedISO)
        let composed = CustomFilmEditorFormState.composeDisplayName(
            manufacturer: formState.manufacturerText,
            label: formState.filmLabel,
            iso: iso
        )
        return composed.isEmpty ? "New custom film" : composed
    }

    private var canSave: Bool {
        if case .success = formState.validate() {
            return true
        }
        return false
    }

    // MARK: - Mutations

    private func adjustExponent(by delta: Double) {
        let trimmed = formState.exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = Double(trimmed) ?? 1.3
        let next = current + delta
        formState.exponentText = String(format: "%.2f", next)
    }

    private func save() {
        // Edit-mode reuse rule: the form must keep the original
        // film/profile ids so the library upserts in place. The
        // generator yields the profile id first, then the film id
        // — matching `buildFilmIdentity`'s call order.
        let result: Result<FilmIdentity, CustomFilmEditorValidationErrors>
        if let editing {
            let profileID = editing.profiles.first?.id ?? UUID().uuidString
            var idQueue = [profileID, editing.id]
            result = formState.validate {
                idQueue.isEmpty ? UUID().uuidString : idQueue.removeFirst()
            }
        } else {
            result = formState.validate()
        }
        switch result {
        case .success(let film):
            validationErrors = CustomFilmEditorValidationErrors([])
            onSave(film)
        case .failure(let errors):
            validationErrors = errors
        }
    }

    @ViewBuilder
    private func fieldErrorText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.red.opacity(0.85))
    }

    // MARK: - Chip values

    private static let commonManufacturers: [String] = [
        "ADOX", "Kodak", "Ilford", "Fujifilm", "Foma", "Rollei",
    ]
    private static let commonISOs: [String] = [
        "6", "12", "20", "25", "50", "64", "80", "100", "125",
        "160", "200", "400", "800", "1600", "3200",
    ]
    private static let commonExponents: [String] = [
        "1.10", "1.20", "1.30", "1.40", "1.50", "1.60", "1.70", "1.80", "1.90",
    ]
}

/// Editor preview table. Renders the presenter's sample rows with
/// `Tm | Tc | Δstop or status` so the photographer can
/// sanity-check the formula across common metered exposures
/// before saving.
private struct CustomFilmEditorPreviewTable: View {
    let form: CustomFilmEditorFormState

    private var rows: [CustomFilmEditorPreviewPresenter.Row] {
        CustomFilmEditorPreviewPresenter.rows(form: form)
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.meteredSeconds) { row in
                HStack(alignment: .center) {
                    Text(metricLabel(row.meteredSeconds))
                        .frame(width: 60, alignment: .leading)
                        .font(.footnote.monospacedDigit())
                    Text(correctedLabel(for: row))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.footnote.monospacedDigit())
                    Text(statusLabel(for: row))
                        .font(.caption)
                        .foregroundStyle(statusColor(for: row.status))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func metricLabel(_ seconds: Double) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            return minutes == minutes.rounded() ? "\(Int(minutes))m" : String(format: "%.1fm", minutes)
        }
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        }
        return seconds == seconds.rounded() ? "\(Int(seconds))s" : String(format: "%.1fs", seconds)
    }

    private func correctedLabel(for row: CustomFilmEditorPreviewPresenter.Row) -> String {
        guard let corrected = row.correctedSeconds else {
            return "—"
        }
        return metricLabel(corrected)
    }

    private func statusLabel(for row: CustomFilmEditorPreviewPresenter.Row) -> String {
        switch row.status {
        case .noCorrection:
            return row.status.displayLabel
        case .formulaApplied, .beyondSourceRange:
            // Beyond-source-range still carries a numeric result
            // with a real Δstop, so the table reads "+N stops"
            // alongside the reduced confidence label rather than
            // dropping the value.
            if let delta = row.stopDelta {
                return String(format: "+%.1f stop%@", delta, delta < 1.5 ? "" : "s")
            }
            return row.status.displayLabel
        case .invalidFormulaResult:
            return row.status.displayLabel
        }
    }

    private func statusColor(for status: CustomFilmEditorPreviewPresenter.RowStatus) -> Color {
        switch status {
        case .noCorrection: return Color.secondary
        case .formulaApplied: return Color.accentColor
        case .beyondSourceRange: return Color.orange
        case .invalidFormulaResult: return Color.red.opacity(0.8)
        }
    }
}
