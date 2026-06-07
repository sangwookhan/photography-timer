import SwiftUI
import PTimerCore

/// Sheet-presented editor for authoring a custom reciprocity
/// formula profile. The Formula card itself is the editing
/// surface: the four formula terms (`Tc₀`, `Tm₀`, `p`, `b`)
/// render as tappable tokens inside the live current-value line
/// of the equation, and each tap opens the existing per-field
/// sheet (see `CustomFilmEditorFieldSheets.swift`). The range
/// fields (`No correction`, `Source data`) live in a small
/// compact block below the formula so they do not visually
/// compete with the formula terms.
///
/// Section order:
///
///   1. Display-name header (auto-composed from
///      Manufacturer + Label + ISO).
///   2. Identity card (manufacturer / label / ISO compact rows).
///   3. Formula card: the two-line formula display block
///      (symbolic structure on top, interactive token line below
///      where Tc₀/Tm₀/p/b are tappable pills); a compact Range
///      block underneath for `No correction` / `Source data`; an
///      inline cross-field recovery caption when the anchor pair
///      fails the shortens-exposure guard; the Reset / Revert
///      Formula button.
///   4. Preview card (graph + Calculation basis + checkpoint
///      table). The Preview surface is the only live numerical
///      feedback — no Live Check section is embedded in the
///      Formula card or in the field sheets.
///   5. Secondary "Details" section: source type, notes, and
///      reference URL — lower-priority provenance the
///      photographer can skip.
///
/// Toolbar:
/// - Top-left `×`: cancel without saving
/// - Top-right `✓`: save (disabled when validation fails)
struct CustomFilmEditorView: View {
    let editing: FilmIdentity?
    let onSave: (FilmIdentity) -> Void
    let onCancel: () -> Void

    @State private var formState: CustomFilmEditorFormState
    /// Toggles the compact help panel inside the Formula card so
    /// the verbose per-field helper text is hidden by default and
    /// only expanded on demand.
    @State private var showsFormulaHelp: Bool = false
    /// Drives the per-field edit-sheet modal. `nil` while the
    /// editor is on the main compact-row view; set to a field
    /// case when the photographer taps one of the formula tokens
    /// or a range row.
    @State private var activeEditField: CustomFilmEditorEditField?

    /// Opening formula-related snapshot for the Edit flow. Captured
    /// once at `init` so a later Revert Formula tap restores the
    /// formula fields the editor was opened with, regardless of any
    /// per-token edits or chip-tap drift in between. `nil` in the
    /// New flow — that path uses
    /// `CustomFilmEditorFormState.resetDefaultsFormulaSnapshot`
    /// instead.
    private let editingOpeningFormulaSnapshot: CustomFilmEditorFormulaSnapshot?

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
        self.editingOpeningFormulaSnapshot = editing == nil
            ? nil
            : initialState.formulaSnapshot
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

                identityCard
                formulaCard
                previewCard
                secondaryDetailsSection
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
            .sheet(item: $activeEditField) { field in
                CustomFilmEditorFieldSheet(
                    field: field,
                    formState: $formState,
                    isEditing: editing != nil
                )
            }
        }
    }

    // MARK: - Identity card

    @ViewBuilder
    private var identityCard: some View {
        Section {
            CustomFilmEditorCompactRow(
                label: "Manufacturer",
                value: rowDisplayValue(formState.manufacturerText, placeholder: "Optional"),
                inlineError: nil,
                accessibilityID: "custom-film-editor-manufacturer"
            ) {
                activeEditField = .manufacturer
            }
            CustomFilmEditorCompactRow(
                label: "Label",
                value: rowDisplayValue(formState.filmLabel, placeholder: "Required"),
                inlineError: formState.inlineValidationReason(
                    for: .label,
                    isEditing: editing != nil
                ),
                accessibilityID: "custom-film-editor-film-label"
            ) {
                activeEditField = .label
            }
            CustomFilmEditorCompactRow(
                label: "ISO",
                value: rowDisplayValue(formState.isoText, placeholder: "Required"),
                inlineError: formState.inlineValidationReason(
                    for: .iso,
                    isEditing: editing != nil
                ),
                accessibilityID: "custom-film-editor-iso"
            ) {
                activeEditField = .iso
            }
        }
    }

    // MARK: - Formula card

    @ViewBuilder
    private var formulaCard: some View {
        Section {
            formulaTokenBlock
            formulaRangeBlock
            formulaRecoveryArea
        } header: {
            Text("Formula")
        }
    }

    /// Two-row formula display: the top row is a compact
    /// single-line symbolic structure (`Tc = Tc₀ × (Tm / Tm₀)ᵖ
    /// + b`) so the photographer reads the model definition in
    /// one short line that maps token-for-token onto the value
    /// row below. The bottom row goes through the math-expression
    /// renderer with tappable pills — each tap opens the matching
    /// field sheet.
    @ViewBuilder
    private var formulaTokenBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                CustomFilmFormulaSymbolicLine()
                    .accessibilityIdentifier("custom-film-editor-formula-structure")
                Spacer(minLength: 8)
                Button {
                    showsFormulaHelp.toggle()
                } label: {
                    Image(systemName: showsFormulaHelp
                          ? "info.circle.fill"
                          : "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsFormulaHelp
                                    ? "Hide formula help"
                                    : "Show formula help")
                .accessibilityIdentifier("custom-film-editor-formula-help-toggle")
            }

            CustomFilmFormulaMathView(
                tokens: formState.formulaTokenDisplays(),
                leadingText: "   = ",
                onTap: { activeEditField = $0.editField }
            )

            if showsFormulaHelp {
                CustomFilmEditorFormulaHelpPanel()
            }

            if let reason = formState.saveDisabledReason(isEditing: editing != nil) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("custom-film-editor-save-disabled-reason")
            }
        }
    }

    /// Compact two-line block for the range fields that bound
    /// the formula's domain. These are not formula terms, so they
    /// live below the formula tokens in a smaller, lighter layout
    /// — secondary-color label on the left, current value on the
    /// right, both tappable to open the matching field sheet.
    @ViewBuilder
    private var formulaRangeBlock: some View {
        VStack(spacing: 4) {
            CustomFilmEditorRangeRow(
                label: "No correction",
                value: rowDurationDisplayValue(
                    formState.noCorrectionThroughText,
                    placeholder: "1s"
                ),
                inlineError: formState.inlineValidationReason(
                    for: .noCorrectionThrough,
                    isEditing: editing != nil
                ),
                accessibilityID: "custom-film-editor-no-correction-through"
            ) {
                activeEditField = .noCorrectionThrough
            }
            CustomFilmEditorRangeRow(
                label: "Source data",
                value: rowDurationDisplayValue(
                    formState.validThroughText,
                    placeholder: "Unlimited",
                    allowsUnlimited: true
                ),
                inlineError: formState.inlineValidationReason(
                    for: .sourceRangeThrough,
                    isEditing: editing != nil
                ),
                accessibilityID: "custom-film-editor-valid-through"
            ) {
                activeEditField = .sourceRangeThrough
            }
        }
    }

    @ViewBuilder
    private var formulaRecoveryArea: some View {
        formulaRecoveryButton
    }

    /// Recovery affordances. Reset is always available — it
    /// replaces the in-editor formula fields with the documented
    /// neutral starter values (`Tc₀ = 1s`, `Tm₀ = 1s`,
    /// `p = 1.30`, `b = 0s`, `No correction = 1s`, `Source data =
    /// Unlimited`). Revert is only available in the Edit flow
    /// where an opening snapshot was captured: it restores the
    /// formula the editor was opened with so the photographer
    /// can recover from arbitrary mid-edit changes without
    /// losing the saved profile until they press Save.
    @ViewBuilder
    private var formulaRecoveryButton: some View {
        HStack(spacing: 16) {
            Spacer()
            recoveryButton(
                title: "Reset",
                accessibilityID: "custom-film-editor-reset-formula",
                action: applyFormulaReset
            )
            if canRevertFormula {
                recoveryButton(
                    title: "Revert Changes",
                    accessibilityID: "custom-film-editor-revert-formula",
                    action: applyFormulaRevert
                )
            }
        }
    }

    @ViewBuilder
    private func recoveryButton(
        title: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    /// Reset Formula: replaces the formula fields with the
    /// documented neutral starter values regardless of whether
    /// the editor is in the New or Edit flow. The Edit flow's
    /// opening snapshot stays captured so a subsequent Revert
    /// Formula tap still restores the saved profile (until the
    /// photographer presses Save).
    private func applyFormulaReset() {
        formState = formState.applyingFormulaSnapshot(
            CustomFilmEditorFormState.resetDefaultsFormulaSnapshot
        )
    }

    /// Revert Formula: restores the formula fields the editor
    /// was opened with. Only meaningful when an opening snapshot
    /// was captured (`editing != nil`); the button is hidden in
    /// the New flow where there is nothing to revert to.
    private func applyFormulaRevert() {
        guard let snapshot = editingOpeningFormulaSnapshot else { return }
        formState = formState.applyingFormulaSnapshot(snapshot)
    }

    /// True only when the editor was opened on an existing custom
    /// film and a formula snapshot was captured at init. Drives
    /// the visibility of the Revert Formula affordance in both
    /// the Formula card and the Preview recovery panel.
    private var canRevertFormula: Bool {
        editingOpeningFormulaSnapshot != nil
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
            if formState.formulaCanRenderPreview,
               let graphState = CustomFilmEditorPreviewGraphPresenter
                .graphDisplayState(for: formState) {
                FilmModeDetailsGraph(graph: graphState)
                    .accessibilityIdentifier("custom-film-editor-preview-chart")
                // Shared Calculation Basis block sits between the
                // graph and the checkpoint table so the table's
                // calculation basis reads as a single labelled
                // wording. The Formula-card top summary above is
                // still the input-assembly source of truth; this
                // block is the single in-card source of the
                // expression for the preview surface.
                if let basisText = CalculationBasisPresenter
                    .calculationBasisText(for: formState) {
                    CustomFilmEditorCalculationBasisBlock(text: basisText)
                }
                CustomFilmEditorPreviewTable(form: formState)
                    .accessibilityIdentifier("custom-film-editor-preview-table")
            } else {
                previewUnavailable
            }
        }
    }

    /// Replaces both the graph and the row-table when the formula
    /// cannot render. Renders a single recovery-oriented message
    /// (with a specific reason when one is available) plus a
    /// Reset/Revert Formula action, instead of repeating "Invalid
    /// formula result" across every sample row. The empty-form
    /// state reads as a neutral placeholder so the photographer
    /// does not see a red error before typing anything.
    @ViewBuilder
    private var previewUnavailable: some View {
        let reason = CustomFilmEditorPreviewPresenter.diagnose(form: formState)
        let isEmpty = reason == .emptyExponent

        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                VStack(spacing: 6) {
                    Text(isEmpty ? "Preview waiting" : "Preview unavailable")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(previewUnavailableMessage(for: reason))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }
            }
            .frame(height: 196)
            .accessibilityIdentifier("custom-film-editor-preview-placeholder")

            // Only the actual-invalid state surfaces the recovery
            // affordances here. Empty/incomplete forms already
            // see the buttons in the Formula card and do not
            // need duplicates in the Preview card.
            if !isEmpty {
                HStack(spacing: 16) {
                    Spacer()
                    recoveryButton(
                        title: "Reset",
                        accessibilityID: "custom-film-editor-preview-reset-formula",
                        action: applyFormulaReset
                    )
                    if canRevertFormula {
                        recoveryButton(
                            title: "Revert Changes",
                            accessibilityID: "custom-film-editor-preview-revert-formula",
                            action: applyFormulaRevert
                        )
                    }
                }
            }
        }
    }

    /// Picks the photographer-readable explanation for the
    /// preview's recovery panel. Empty-form states read as a
    /// neutral prompt; field-level reasons surface the matching
    /// label so the user knows what to fix. When the form parses
    /// cleanly but the cross-field shortens-exposure guard fails,
    /// the recovery panel takes over from the (now-suppressed)
    /// graph and surfaces the cross-field reason.
    private func previewUnavailableMessage(
        for reason: CustomFilmEditorPreviewPresenter.InvalidReason?
    ) -> String {
        if let reason {
            switch reason {
            case .emptyExponent:
                return "Enter p to preview the formula."
            default:
                return reason.displayMessage
            }
        }
        if let crossField = formState.saveDisabledReason(isEditing: editing != nil) {
            return crossField
        }
        // Defensive fallback: the unavailable branch implies
        // either an unparseable form or a guard failure, both of
        // which the branches above name. This catch-all keeps
        // the panel honest if a future guard reports failure
        // without a matching diagnostic.
        return "Fix the highlighted formula fields or reset the formula."
    }

    // MARK: - Secondary details section

    /// Lower-priority provenance fields (source type, notes,
    /// reference URL) grouped together so the formula and preview
    /// stay above the fold on iPhone. The section header reads as
    /// "Details" so it slots naturally below the Preview card.
    @ViewBuilder
    private var secondaryDetailsSection: some View {
        Section("Details") {
            // Single-source label so the row reads as
            // "Source    User-defined" rather than the earlier
            // duplicated "Source Source    User-defined" (the
            // `.menu` Picker rendered its own title alongside the
            // wrapping editorRow label).
            Picker("Source", selection: $formState.sourceType) {
                ForEach(CustomProfileSourceType.allCases, id: \.self) { type in
                    Text(type.displayLabel).tag(type)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("custom-film-editor-source-type")

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                TextField("Optional", text: $formState.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("custom-film-editor-notes")
            }

            HStack {
                Text("Reference URL")
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                TextField("Optional", text: $formState.referenceURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("custom-film-editor-reference-url")
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

    private func save() {
        // Edit-mode reuse rule: the form must keep the original
        // film/profile ids so the library upserts in place. The
        // generator yields the profile id first, then the film id
        // — matching `buildFilmIdentity`'s call order.
        //
        // The Save button is disabled whenever validation would
        // fail, so by the time this method runs the validator is
        // expected to succeed. Failure paths exist defensively;
        // they leave the form alone (the inline-row hints and the
        // cross-field summary already paint the issues for the
        // user).
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
        if case .success(let film) = result {
            onSave(film)
        }
    }
}

/// Display value for a `CustomFilmEditorCompactRow`. Bundles the
/// rendered text with a "placeholder" flag so the row dims the
/// value when the underlying form field is blank, without making
/// the caller pass two separate parameters.
struct CustomFilmEditorRowDisplayValue: Equatable {
    let text: String
    let isPlaceholder: Bool
}

/// Pure helper that converts a (raw text, placeholder) pair into
/// a row display value. Empty / whitespace-only entries render the
/// placeholder dimmed; non-empty entries render the trimmed value
/// in the primary text color.
func rowDisplayValue(_ raw: String, placeholder: String) -> CustomFilmEditorRowDisplayValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return CustomFilmEditorRowDisplayValue(text: placeholder, isPlaceholder: true)
    }
    return CustomFilmEditorRowDisplayValue(text: trimmed, isPlaceholder: false)
}

/// Duration-aware row display helper. Parses a duration-shaped
/// text field through `CustomFilmDurationParser` and renders the
/// result with seconds/minutes units so the compact row reads as
/// a photographer-friendly duration (`2s`, `3.3m`, `0.1s`) even
/// when the user typed a bare number. Unparseable input falls
/// back to the raw text so the photographer can read what they
/// typed alongside the inline validation hint.
///
/// - Parameters:
///   - allowsUnlimited: `true` only for the source-range row,
///     where the validator accepts the literal `Unlimited`
///     token. Every other duration row treats `.unlimited` as
///     unparseable.
///   - dimWhenMatches: When the parsed value renders to this
///     string, mark the result as a placeholder so the row's
///     value text reads in the dimmed (secondary) color. Used
///     to de-emphasize the formula's neutral-default values
///     (`Tc₀ = 1s`, `Tm₀ = 1s`, `b = 0s`) without hiding them
///     from the photographer's mental map of the equation.
func rowDurationDisplayValue(
    _ raw: String,
    placeholder: String,
    allowsUnlimited: Bool = false,
    dimWhenMatches: String? = nil
) -> CustomFilmEditorRowDisplayValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return CustomFilmEditorRowDisplayValue(text: placeholder, isPlaceholder: true)
    }
    switch CustomFilmDurationParser.parse(trimmed) {
    case .seconds(let value) where value.isFinite:
        let rendered = CustomFilmEditorFormState.formatDurationExpression(value)
        let isNeutral = dimWhenMatches.map { $0 == rendered } ?? false
        return CustomFilmEditorRowDisplayValue(
            text: rendered,
            isPlaceholder: isNeutral
        )
    case .unlimited where allowsUnlimited:
        return CustomFilmEditorRowDisplayValue(text: "Unlimited", isPlaceholder: false)
    case .empty, .seconds, .unlimited, .none:
        return CustomFilmEditorRowDisplayValue(text: trimmed, isPlaceholder: false)
    }
}

/// Tap-to-edit summary row used by both the Identity and Formula
/// cards. Renders `label + current value + trailing chevron` in
/// a single line. The label is the formula symbol itself for
/// formula rows (`Tc₀`, `Tm₀`, `p`, `b`, `No correction`,
/// `Source data`) and a plain word for identity rows
/// (`Manufacturer`, `Label`, `ISO`). An optional inline-
/// validation caption renders directly under the row so the
/// layout never gains/loses a separate error row — adding/
/// removing the caption only shifts the row's own height a few
/// points.
struct CustomFilmEditorCompactRow: View {
    let label: String
    let value: CustomFilmEditorRowDisplayValue
    let inlineError: String?
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(value.text)
                        .foregroundStyle(value.isPlaceholder ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if let inlineError {
                    Text(inlineError)
                        .font(.caption2)
                        .foregroundStyle(Color.red.opacity(0.85))
                        .accessibilityIdentifier("\(accessibilityID)-inline-error")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// SwiftUI rendering of the custom-profile reciprocity formula
/// laid out closer to a math expression than to a plain text
/// row. The denominator pair `Tm / Tm₀` renders as a real
/// fraction (numerator above a thin horizontal rule, denominator
/// below); the exponent `p` sits as a superscript above the
/// closing parenthesis using a `baselineOffset` so it reads as a
/// real exponent without detaching the tap target from the
/// layout flow.
///
/// The same view powers three surfaces by toggling its `onTap`
/// closure:
///
/// - editor Formula card (interactive — pills dispatch to the
///   matching per-field sheet),
/// - editor Formula card's symbolic structure row (read-only,
///   the same shape but with symbol-only tokens),
/// - per-field sheet header (read-only, the photographer reads
///   the same expression they saw on the card behind it).
struct CustomFilmFormulaMathView: View {
    let tokens: [CustomFilmEditorFormState.FormulaTokenDisplay]
    /// Visual lead-in. Top "symbolic structure" row passes
    /// `"Tc ="`, the value row passes `"   ="` so the equals
    /// glyphs align under each other in the same VStack.
    let leadingText: String
    /// `nil` renders a read-only static expression. Non-nil
    /// turns every formula term into a tappable pill that
    /// dispatches to the matching field sheet.
    let onTap: ((CustomFilmEditorFormState.FormulaTokenSlot) -> Void)?

    init(
        tokens: [CustomFilmEditorFormState.FormulaTokenDisplay],
        leadingText: String = "Tc = ",
        onTap: ((CustomFilmEditorFormState.FormulaTokenSlot) -> Void)? = nil
    ) {
        self.tokens = tokens
        self.leadingText = leadingText
        self.onTap = onTap
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(leadingText)
                .font(.footnote.monospaced())
            slot(.tcAnchor)
            Text("×")
                .font(.footnote.monospaced())
            HStack(alignment: .center, spacing: 2) {
                Text("(")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.primary)
                VStack(spacing: 1) {
                    Text("Tm")
                        .font(.footnote.monospaced())
                    Rectangle()
                        .fill(Color.primary)
                        .frame(height: 0.7)
                    slot(.tmAnchor)
                }
                Text(")")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.primary)
            }
            // Exponent pill positioned as a superscript on the
            // closing parenthesis. `baselineOffset` lifts the
            // pill above the baseline so it reads as an
            // exponent; the pill still participates in the
            // outer HStack layout so the trailing `+ b` stays
            // properly positioned.
            slot(.exponent)
                .baselineOffset(8)
            Text("+")
                .font(.footnote.monospaced())
            slot(.offset)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Interactive mode attaches the per-slot accessibility
    /// identifier so existing tap-target tests can find the
    /// pill. Read-only mode skips it so a static structure row
    /// rendered alongside the interactive value row does not
    /// duplicate the same IDs in the accessibility tree.
    @ViewBuilder
    private func slot(
        _ slot: CustomFilmEditorFormState.FormulaTokenSlot
    ) -> some View {
        let token = tokenDisplay(for: slot)
        if let onTap {
            Button {
                onTap(slot)
            } label: {
                pillLabel(token)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(slot.accessibilityID)
        } else {
            staticLabel(token)
        }
    }

    private func pillLabel(
        _ token: CustomFilmEditorFormState.FormulaTokenDisplay
    ) -> some View {
        Text(token.displayText)
            .font(.footnote.weight(.semibold).monospaced())
            .foregroundStyle(token.isPlaceholder
                             ? Color.secondary
                             : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(token.isPlaceholder ? 0.06 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        token.isInvalid
                            ? Color.red.opacity(0.7)
                            : Color.accentColor.opacity(0.25),
                        lineWidth: token.isInvalid ? 1 : 0.5
                    )
            )
            .contentShape(Rectangle())
    }

    private func staticLabel(
        _ token: CustomFilmEditorFormState.FormulaTokenDisplay
    ) -> some View {
        Text(token.displayText)
            .font(.footnote.monospaced())
            .foregroundStyle(.primary)
    }

    private func tokenDisplay(
        for slot: CustomFilmEditorFormState.FormulaTokenSlot
    ) -> CustomFilmEditorFormState.FormulaTokenDisplay {
        tokens.first(where: { $0.slot == slot })
            ?? CustomFilmEditorFormState.FormulaTokenDisplay(
                slot: slot,
                displayText: slot.symbol,
                isPlaceholder: true,
                isInvalid: false
            )
    }
}

/// Compact one-line rendering of the symbolic formula
/// structure shown above the editable value row in the Formula
/// card and above the read-only value row in field-sheet
/// headers. Uses inline `Text` concatenation with a
/// `baselineOffset`-lifted exponent so the line reads as
/// `Tc = Tc₀ × (Tm / Tm₀)ᵖ + b` on a single tight row — much
/// shorter than the full fraction-style math view used for the
/// value row below. The two rows still map token-for-token in
/// the same left-to-right order.
struct CustomFilmFormulaSymbolicLine: View {
    var body: some View {
        let head = Text("Tc = Tc₀ × (Tm / Tm₀)")
            .font(.footnote.monospaced())
        let exponent = Text("p")
            .font(.caption2.weight(.semibold).monospaced())
            .baselineOffset(5)
        let tail = Text(" + b")
            .font(.footnote.monospaced())
        return (head + exponent + tail)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Compact tap-to-edit row used by the Formula card's Range
/// block. Lighter visual weight than `CustomFilmEditorCompactRow`
/// — no chevron, smaller font, less vertical padding — so the
/// two range fields read as supporting metadata rather than
/// competing with the formula tokens above.
struct CustomFilmEditorRangeRow: View {
    let label: String
    let value: CustomFilmEditorRowDisplayValue
    let inlineError: String?
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(value.text)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(value.isPlaceholder
                                         ? Color.secondary
                                         : Color.primary)
                    // Tiny trailing chevron so the row reads as
                    // tappable rather than passive metadata. Kept
                    // intentionally light (caption2 in tertiary)
                    // so the range block does not regain the
                    // visual weight of a full compact row.
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let inlineError {
                    Text(inlineError)
                        .font(.caption2)
                        .foregroundStyle(Color.red.opacity(0.85))
                        .accessibilityIdentifier("\(accessibilityID)-inline-error")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Renders the shared **Calculation basis** wording between the
/// editor preview graph and the checkpoint table. The label sits
/// in the same compact caption shape as the graph's own header,
/// and the formula text reuses
/// `FilmModeDetailsFormulaExpressionText` so the exponent
/// superscript matches the Details surface.
private struct CustomFilmEditorCalculationBasisBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calculation basis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            FilmModeDetailsFormulaExpressionText(text)
                .accessibilityIdentifier("custom-film-editor-preview-calculation-basis")
        }
    }
}

/// Compact help panel toggled by the info icon next to "Formula
/// type". Replaces the previous always-visible per-row helper text
/// so the Formula card stays short by default and the six concept
/// definitions are only one tap away. Wording mirrors the spec
/// verbatim so the photographer reads the same language across
/// surfaces.
private struct CustomFilmEditorFormulaHelpPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.helpLines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
        .accessibilityIdentifier("custom-film-editor-formula-help-panel")
    }

    private static let helpLines: [String] = [
        "Tc₀ — corrected exposure at the metered anchor.",
        "Tm₀ — metered exposure used as the anchor.",
        "p — curve strength; higher gives stronger correction at long exposures.",
        "b — fixed time added after the curve.",
        "No correction — Tm at or below this value stays unchanged.",
        "Source data — results past this value read as Beyond source range.",
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
