import Charts
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
                HStack(spacing: 4) {
                    TextField("1", text: $formState.baseTmText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityIdentifier("custom-film-editor-base-tm")
                    Text("s").foregroundStyle(.secondary)
                }
            }
            if validationErrors.contains(.invalidBaseTm) {
                fieldErrorText("Base Tm must be a positive number of seconds.")
            }

            editorRow(label: "Base Tc") {
                HStack(spacing: 4) {
                    TextField("1", text: $formState.baseTcText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityIdentifier("custom-film-editor-base-tc")
                    Text("s").foregroundStyle(.secondary)
                }
            }
            if validationErrors.contains(.invalidBaseTc) {
                fieldErrorText("Base Tc must be a positive number of seconds.")
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
                fieldErrorText("Formula must not shorten the metered time at the no-correction boundary.")
            }

            editorRow(label: "Offset") {
                HStack(spacing: 4) {
                    TextField("0", text: $formState.offsetSecondsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityIdentifier("custom-film-editor-offset")
                    Text("s").foregroundStyle(.secondary)
                }
            }
            if validationErrors.contains(.invalidFormulaOffset) {
                fieldErrorText("Offset must be a number.")
            }

            editorRow(label: "No correction up to") {
                HStack(spacing: 4) {
                    TextField("1", text: $formState.noCorrectionThroughText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityIdentifier("custom-film-editor-no-correction-through")
                    Text("s").foregroundStyle(.secondary)
                }
            }
            if validationErrors.contains(.invalidNoCorrectionThrough) {
                fieldErrorText("Enter a positive number of seconds.")
            }

            editorRow(label: "Source range through") {
                HStack(spacing: 4) {
                    TextField("Unlimited", text: $formState.validThroughText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityIdentifier("custom-film-editor-valid-through")
                    if !formState.validThroughText.isEmpty {
                        Text("s").foregroundStyle(.secondary)
                    }
                }
            }
            if validationErrors.contains(.invalidValidThrough) {
                fieldErrorText("Valid-through must be greater than no-correction.")
            }
        }
    }

    // MARK: - Preview card

    @ViewBuilder
    private var previewCard: some View {
        Section {
            CustomFilmEditorPreviewChart(form: formState)
                .frame(height: 160)
                .accessibilityIdentifier("custom-film-editor-preview-chart")
            CustomFilmEditorPreviewTable(form: formState)
                .accessibilityIdentifier("custom-film-editor-preview-table")
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Preview")
                Spacer(minLength: 4)
                Text(previewFormulaSummary)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("custom-film-editor-preview-formula")
            }
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
        let trimmedManufacturer = formState.manufacturerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = formState.filmLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedISO = formState.isoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameParts = [trimmedManufacturer, trimmedLabel].filter { !$0.isEmpty }
        let nameJoined = nameParts.joined(separator: " ")
        let isoSegment = trimmedISO.isEmpty ? "" : "ISO \(trimmedISO)"
        let segments = [nameJoined, isoSegment].filter { !$0.isEmpty }
        return segments.isEmpty ? "New custom film" : segments.joined(separator: " · ")
    }

    /// Simplified live formula display rendered in the Preview
    /// header. Collapses the anchored form when both anchors are
    /// 1 and the offset is 0 (the editor's documented default)
    /// so the reader sees `Tc = Tm^exponent` instead of the full
    /// `Tc = 1 × (Tm / 1)^exponent + 0` boilerplate. The
    /// anchored shape is preserved verbatim when the photographer
    /// moves either anchor.
    private var previewFormulaSummary: String {
        let exponentText = formState.exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !exponentText.isEmpty, Double(exponentText) != nil else {
            return "Tc = base Tc × (Tm / base Tm)^exponent + offset"
        }
        let baseTm = Self.numberOrDefault(formState.baseTmText, default: 1.0)
        let baseTc = Self.numberOrDefault(formState.baseTcText, default: 1.0)
        let offset = Self.numberOrDefault(formState.offsetSecondsText, default: 0.0)

        let isUnanchored = abs(baseTm - 1.0) < 1e-9 && abs(baseTc - 1.0) < 1e-9
        let offsetIsZero = abs(offset) < 1e-9

        if isUnanchored {
            let body = "Tc = Tm^\(exponentText)"
            return offsetIsZero ? body : "\(body) + \(Self.formatPlain(offset))"
        }
        let baseTmDisplay = Self.formatPlain(baseTm)
        let baseTcDisplay = Self.formatPlain(baseTc)
        let body = "Tc = \(baseTcDisplay) × (Tm / \(baseTmDisplay))^\(exponentText)"
        return offsetIsZero ? body : "\(body) + \(Self.formatPlain(offset))"
    }

    private static func numberOrDefault(_ text: String, default fallback: Double) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed) ?? fallback
    }

    /// Same compact rendering rule the formula summary uses: drop
    /// trailing zeros so `1.0` reads `"1"` and `1.30` reads
    /// `"1.3"`, while preserving precision for values like
    /// `1.0966`.
    private static func formatPlain(_ value: Double) -> String {
        let formatted = String(format: "%.4f", value)
        var trimmed = formatted
        while trimmed.contains(".") && (trimmed.hasSuffix("0") || trimmed.hasSuffix(".")) {
            trimmed.removeLast()
            if trimmed.hasSuffix(".") {
                trimmed.removeLast()
                break
            }
        }
        return trimmed
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

/// Small Swift Charts preview that
/// visualises the active formula across its valid range. The chart
/// stays empty when the form's coefficients are not parseable so
/// an in-progress edit does not render a misleading curve.
private struct CustomFilmEditorPreviewChart: View {
    let form: CustomFilmEditorFormState

    private var curve: [CustomFilmEditorPreviewPresenter.Row] {
        CustomFilmEditorPreviewPresenter.curveSamples(form: form)
    }

    private var sampleDots: [CustomFilmEditorPreviewPresenter.Row] {
        CustomFilmEditorPreviewPresenter.rows(form: form)
            .filter { $0.status == .formulaApplied || $0.status == .noCorrection }
    }

    var body: some View {
        if curve.isEmpty {
            placeholder
        } else {
            Chart {
                // Reference line y = x so the formula's correction
                // is visible relative to the no-correction baseline.
                ForEach(curve, id: \.meteredSeconds) { point in
                    LineMark(
                        x: .value("Metered seconds", point.meteredSeconds),
                        y: .value("Metered seconds", point.meteredSeconds),
                        series: .value("Series", "Tm")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                ForEach(curve, id: \.meteredSeconds) { point in
                    if let tc = point.correctedSeconds {
                        LineMark(
                            x: .value("Metered seconds", point.meteredSeconds),
                            y: .value("Corrected seconds", tc),
                            series: .value("Series", "Tc")
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                }
                ForEach(sampleDots, id: \.meteredSeconds) { dot in
                    if let tc = dot.correctedSeconds {
                        PointMark(
                            x: .value("Metered seconds", dot.meteredSeconds),
                            y: .value("Corrected seconds", tc)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                        .symbolSize(35)
                    }
                }
            }
            .chartXScale(type: .log)
            .chartYScale(type: .log)
            .chartXAxisLabel("Tm (s)", position: .bottomTrailing)
            .chartYAxisLabel("Tc (s)", position: .topTrailing)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            Text("Enter a formula and range to preview the curve.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(8)
        }
    }
}

/// Editor preview table. Renders the
/// presenter's sample rows with `Tm | Tc | Δstop or status` so the
/// photographer can sanity-check the formula across common
/// metered exposures before saving.
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
        case .formulaApplied:
            if let delta = row.stopDelta {
                return String(format: "+%.1f stop%@", delta, delta < 1.5 ? "" : "s")
            }
            return row.status.displayLabel
        case .beyondValidRange, .invalidFormulaResult:
            return row.status.displayLabel
        }
    }

    private func statusColor(for status: CustomFilmEditorPreviewPresenter.RowStatus) -> Color {
        switch status {
        case .noCorrection: return Color.secondary
        case .formulaApplied: return Color.accentColor
        case .beyondValidRange: return Color.orange
        case .invalidFormulaResult: return Color.red.opacity(0.8)
        }
    }
}
