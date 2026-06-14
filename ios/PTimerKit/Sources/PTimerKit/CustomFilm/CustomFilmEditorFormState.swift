import Foundation
import PTimerCore

/// Photographer-facing input mode for the formula editor.
/// Drives which fields are visible in the editor; the underlying
/// shared formula model is unchanged — modes only constrain or
/// reset the values the photographer can edit.
///
/// - `basic`: only the exponent is exposed. baseTc/baseTm are
///   pinned to 1 and offset is pinned to 0. Equivalent to
///   `Tc = Tm^exponent`.
/// - `scaled`: exponent + baseTc (coefficient) + baseTm
///   (reference time). Offset is pinned to 0. Supports T-MAX
///   style anchored formulas such as
///   `Tc = 0.1 × (Tm / 0.1)^1.0966`.
/// - `advanced`: exponent + baseTc + baseTm + offset. The full
///   shared-formula surface.
public enum CustomFilmFormulaInputMode: String, CaseIterable, Equatable {
    case basic
    case scaled
    case advanced

    public var displayLabel: String {
        switch self {
        case .basic: return "Basic"
        case .scaled: return "Scaled"
        case .advanced: return "Advanced"
        }
    }
}

/// Pending input fields for the custom film / profile editor. All
/// fields are stored as `String` (and one enum) so the SwiftUI form
/// can bind directly without intermediate parsing. The struct is a
/// pure value — every mutation comes from a TextField/Picker binding
/// on the editor view — and the `validate()` method is the only
/// path that produces a domain `FilmIdentity`.
///
/// The editor is intentionally minimal: power-law formula only,
/// no source-evidence rows, no per-rule table input. The
/// validation surface is the boundary the spec names as "reject
/// invalid formula input" — domain types past this point can
/// trust that exponents are positive/finite, ISO is a positive
/// integer, and identity strings are non-empty.
public struct CustomFilmEditorFormState: Equatable {
    public var profileName: String
    public var filmLabel: String
    public var isoText: String
    public var sourceType: CustomProfileSourceType
    public var notes: String
    /// Photographer-facing input mode (Basic / Scaled / Advanced).
    /// Pure UI affordance: the validator and `buildFilmIdentity`
    /// still operate on the underlying numeric fields. Mode-
    /// switching helpers below reset hidden fields per spec.
    public var formulaInputMode: CustomFilmFormulaInputMode
    public var exponentText: String
    /// Metered-exposure anchor for the
    /// `Tc = baseTc · (Tm / baseTm)^exponent + offset` formula.
    /// Default `"1"` represents the unanchored exponent-only
    /// form `Tc = Tm^exponent + offset` (preview surfaces
    /// simplify the display when both anchors equal `1`).
    public var baseTmText: String
    /// Corrected-exposure anchor paired with `baseTmText`. Same
    /// default `"1"`.
    public var baseTcText: String
    public var offsetSecondsText: String
    /// Metered exposures up to this many seconds receive
    /// `Tc = Tm` (no correction) instead of the formula. Defaults
    /// to "1" because reciprocity behavior is a long-exposure
    /// concept and sub-1s adjustments would be misleading.
    public var noCorrectionThroughText: String
    /// Metered exposures above this many seconds fall outside the
    /// formula's stated source range. Optional: empty /
    /// "Unlimited" means the formula extrapolates upward without
    /// bound (the saved `sourceRangeThroughSeconds` is `nil`).
    public var validThroughText: String
    /// Photographer-typed manufacturer string. Stored on
    /// `UserEditableMetadata.customManufacturer`, not on
    /// `FilmIdentity.manufacturer`, so the picker keeps custom
    /// films in the "Custom films" group.
    public var manufacturerText: String
    /// Optional reference URL the photographer recorded; lives at
    /// the bottom of the editor and round-trips through
    /// `UserEditableMetadata.referenceURL`.
    public var referenceURLText: String
    /// Which calculation rule the form authors (PTIMER-178). A
    /// profile carries exactly one rule — formula XOR table — and
    /// a saved profile never converts between the two, so the Edit
    /// flow opens with the saved profile's kind fixed.
    public var calculationInputKind: CustomFilmCalculationInputKind
    /// Pending Tm/Tc anchor rows for the `.table` input kind.
    /// Empty (and ignored) while the form is in `.formula` mode.
    public var tableRows: [CustomFilmTableAnchorRowInput]

    public init(
        profileName: String = "",
        filmLabel: String = "",
        isoText: String = "",
        sourceType: CustomProfileSourceType = .userDefined,
        notes: String = "",
        formulaInputMode: CustomFilmFormulaInputMode = .basic,
        exponentText: String = "",
        baseTmText: String = "1",
        baseTcText: String = "1",
        offsetSecondsText: String = "",
        noCorrectionThroughText: String = "1",
        validThroughText: String = "",
        manufacturerText: String = "",
        referenceURLText: String = "",
        calculationInputKind: CustomFilmCalculationInputKind = .formula,
        tableRows: [CustomFilmTableAnchorRowInput] = []
    ) {
        self.profileName = profileName
        self.filmLabel = filmLabel
        self.isoText = isoText
        self.sourceType = sourceType
        self.notes = notes
        self.formulaInputMode = formulaInputMode
        self.exponentText = exponentText
        self.baseTmText = baseTmText
        self.baseTcText = baseTcText
        self.offsetSecondsText = offsetSecondsText
        self.noCorrectionThroughText = noCorrectionThroughText
        self.validThroughText = validThroughText
        self.manufacturerText = manufacturerText
        self.referenceURLText = referenceURLText
        self.calculationInputKind = calculationInputKind
        self.tableRows = tableRows
    }
}

/// Photographer-recoverable subset of the editor form state.
/// Mirrors the seven formula-related text fields the editor card
/// exposes (input mode, exponent, anchors, offset, no-correction
/// boundary, source-range boundary). The recovery action writes
/// the captured snapshot back over the form's formula fields and
/// leaves identity / source / notes / reference URL untouched.
public struct CustomFilmEditorFormulaSnapshot: Equatable {
    public let formulaInputMode: CustomFilmFormulaInputMode
    public let exponentText: String
    public let baseTmText: String
    public let baseTcText: String
    public let offsetSecondsText: String
    public let noCorrectionThroughText: String
    public let validThroughText: String
    public init(formulaInputMode: CustomFilmFormulaInputMode, exponentText: String, baseTmText: String, baseTcText: String, offsetSecondsText: String, noCorrectionThroughText: String, validThroughText: String) {
        self.formulaInputMode = formulaInputMode
        self.exponentText = exponentText
        self.baseTmText = baseTmText
        self.baseTcText = baseTcText
        self.offsetSecondsText = offsetSecondsText
        self.noCorrectionThroughText = noCorrectionThroughText
        self.validThroughText = validThroughText
    }
}

extension CustomFilmEditorFormState {
    /// Safe default exponent for a freshly authored profile.
    /// Sits in the middle of the 1.10-1.90 chip ladder so the
    /// preview renders a recognizable correction curve immediately.
    public static let defaultResetExponentText = "1.30"

    /// Safe-default formula snapshot used when the photographer
    /// taps Reset Formula in the New custom film flow. Values match
    /// the spec's reset table: exponent 1.30, coefficient 1,
    /// reference time 1, offset 0, no-correction-through 1s,
    /// source-range-through unlimited.
    public static let resetDefaultsFormulaSnapshot = CustomFilmEditorFormulaSnapshot(
        formulaInputMode: .basic,
        exponentText: defaultResetExponentText,
        baseTmText: "1",
        baseTcText: "1",
        offsetSecondsText: "",
        noCorrectionThroughText: "1",
        validThroughText: ""
    )

    /// Captures the seven formula-related fields so the Edit flow
    /// can revert to the editor's opening state. The capture is
    /// pure value; the caller stores it alongside the live form
    /// state and applies it via `applyingFormulaSnapshot(_:)`.
    public var formulaSnapshot: CustomFilmEditorFormulaSnapshot {
        CustomFilmEditorFormulaSnapshot(
            formulaInputMode: formulaInputMode,
            exponentText: exponentText,
            baseTmText: baseTmText,
            baseTcText: baseTcText,
            offsetSecondsText: offsetSecondsText,
            noCorrectionThroughText: noCorrectionThroughText,
            validThroughText: validThroughText
        )
    }

    /// Returns a copy of the form with the formula-related fields
    /// replaced by `snapshot`. Identity (manufacturer / label /
    /// ISO), source type, notes, and reference URL are preserved.
    /// Used by both the New flow's Reset Formula action (passing
    /// `resetDefaultsFormulaSnapshot`) and the Edit flow's Revert
    /// Formula action (passing the captured opening snapshot).
    public func applyingFormulaSnapshot(
        _ snapshot: CustomFilmEditorFormulaSnapshot
    ) -> CustomFilmEditorFormState {
        var next = self
        next.formulaInputMode = snapshot.formulaInputMode
        next.exponentText = snapshot.exponentText
        next.baseTmText = snapshot.baseTmText
        next.baseTcText = snapshot.baseTcText
        next.offsetSecondsText = snapshot.offsetSecondsText
        next.noCorrectionThroughText = snapshot.noCorrectionThroughText
        next.validThroughText = snapshot.validThroughText
        return next
    }
}

extension CustomFilmEditorFormState {
    /// Pure-value reset applied when the photographer flips the
    /// input mode. Reproduces the spec rules:
    ///
    /// - `.basic` resets baseTm / baseTc to `1` and offset to `0`.
    /// - `.scaled` resets offset to `0` (baseTm/baseTc are kept so
    ///   the photographer's current anchors survive the toggle).
    /// - `.advanced` is a pure widening — no field is reset.
    ///
    /// Returns a copy so the editor view can apply the result with
    /// a single state-write and keep SwiftUI bindings consistent.
    public func switching(to mode: CustomFilmFormulaInputMode) -> CustomFilmEditorFormState {
        guard mode != formulaInputMode else { return self }
        var next = self
        next.formulaInputMode = mode
        switch mode {
        case .basic:
            next.baseTmText = "1"
            next.baseTcText = "1"
            next.offsetSecondsText = ""
        case .scaled:
            next.offsetSecondsText = ""
        case .advanced:
            break
        }
        return next
    }
}

/// Field-level reason a candidate form state failed validation.
/// Returned as an unordered set so the editor can highlight every
/// invalid field on Save rather than only the first one.
public enum CustomFilmEditorValidationError: Error, Equatable, Hashable {
    /// Retired — the photographer's `Manufacturer + Label + ISO`
    /// composition drives the auto-generated profile name. The
    /// hidden `profileName` text field stays for backward compat
    /// but the validator never raises this case anymore.
    case missingProfileName
    case missingFilmLabel
    case invalidISO
    case missingFormulaExponent
    case invalidFormulaExponent
    /// Retired in favour of `.invalidBaseTm` / `.invalidBaseTc`.
    /// Kept in the enum so stored references in callers compile,
    /// but the validator no longer raises it.
    case invalidFormulaCoefficient
    case invalidBaseTm
    case invalidBaseTc
    case invalidFormulaOffset
    case invalidNoCorrectionThrough
    /// Retired — empty / "Unlimited" is now the documented
    /// default state. Kept so callers that reference the case in
    /// `Set.contains` compile.
    case missingValidThrough
    case invalidValidThrough
    /// The photographer's combination of anchors/exponent/offset
    /// would produce a corrected exposure shorter than the
    /// metered exposure inside the formula's usable range. The
    /// editor blocks save so the calculator never emits
    /// misleading "long-exposure correction makes the shot
    /// shorter" guidance.
    case formulaShortensExposure
    /// Table input kind: fewer than two complete, valid Tm/Tc
    /// anchor rows (PTIMER-178). Blank rows are ignored; partially
    /// filled or unparseable rows raise `.invalidTableAnchors`.
    case insufficientTableAnchors
    /// Table input kind: at least one anchor row is unparseable,
    /// non-positive, shortens the exposure (Tc < Tm), or breaks
    /// the strictly-ascending metered-time order. Row-level
    /// wording comes from `tableRowValidationReason(at:isEditing:)`.
    case invalidTableAnchors
}

/// `Result` requires the failure type to conform to `Error`. `Set`
/// does not, so the validate path wraps the collected reasons in
/// this thin envelope. Hashable + Equatable conformance preserves
/// test ergonomics for asserting against the full reason set.
public struct CustomFilmEditorValidationErrors: Error, Equatable, Hashable {
    public let errors: Set<CustomFilmEditorValidationError>

    public init(_ errors: Set<CustomFilmEditorValidationError>) {
        self.errors = errors
    }

    public func contains(_ error: CustomFilmEditorValidationError) -> Bool {
        errors.contains(error)
    }

    public var isEmpty: Bool { errors.isEmpty }
}

extension CustomFilmEditorFormState {
    /// Rebuilds editor state from an existing custom `FilmIdentity`
    /// so the Edit flow can prefill every field. Returns `nil` for
    /// non-custom or otherwise unsupported shapes (the editor falls
    /// back to a blank Create form in that defensive case). Numeric
    /// fields render with the same `trim` logic the formula summary
    /// uses so a round-tripped value reads "1.3" instead of
    /// "1.300000".
    public static func from(film: FilmIdentity) -> CustomFilmEditorFormState? {
        guard film.kind == .custom,
              let profile = film.profiles.first,
              profile.source.authority == .userDefined else {
            return nil
        }
        guard let formulaRule = profile.rules.compactMap({ rule -> FormulaReciprocityRule? in
            if case .formula(let r) = rule { return r }
            return nil
        }).first else {
            // PTIMER-178: a custom profile carries exactly one
            // calculation rule — formula XOR tableInterpolation —
            // so a profile without a formula rule is either a
            // table profile (prefill the table editor) or
            // unsupported (defensive nil).
            return fromTableFilm(film, profile: profile)
        }
        let formula = formulaRule.formula
        let seed = recoveredIdentitySeed(film: film, profile: profile)

        // The shared formula carries the range boundaries on the
        // formula itself; the editor reads them directly so an
        // Edit round-trip preserves whatever the photographer
        // saved.
        let noCorrectionThrough = formula.noCorrectionThroughSeconds
        let validThrough = formula.sourceRangeThroughSeconds

        // The shared formula stores the anchor pair on the
        // formula directly: `referenceMeteredTimeSeconds` is the
        // editor's `Tm₀` (Metered point) and `coefficientSeconds`
        // is its `Tc₀` (Corrected point).
        let baseTm = formula.referenceMeteredTimeSeconds
        let baseTc = formula.coefficientSeconds
        let offsetText = abs(formula.offsetSeconds) < 1e-9
            ? ""
            : Self.formatNumeric(formula.offsetSeconds)
        return CustomFilmEditorFormState(
            profileName: profile.name,
            filmLabel: seed.labelText,
            isoText: "\(film.iso)",
            sourceType: seed.sourceType,
            notes: seed.notesValue,
            formulaInputMode: Self.inferInputMode(
                baseTm: baseTm,
                baseTc: baseTc,
                offsetSeconds: formula.offsetSeconds
            ),
            exponentText: Self.formatNumeric(formula.exponent),
            baseTmText: Self.formatNumeric(baseTm),
            baseTcText: Self.formatNumeric(baseTc),
            offsetSecondsText: offsetText,
            noCorrectionThroughText: Self.formatNumeric(noCorrectionThrough),
            validThroughText: validThrough.map(Self.formatNumeric) ?? "",
            manufacturerText: seed.manufacturerText,
            referenceURLText: seed.referenceURLText
        )
    }

    /// Identity / provenance fields recovered from a saved custom
    /// film for editor prefill. Shared by the formula and table
    /// Edit-flow branches so both recover manufacturer, label,
    /// source type, notes, and reference URL with one rule set.
    struct RecoveredIdentitySeed {
        let sourceType: CustomProfileSourceType
        let notesValue: String
        let manufacturerText: String
        let labelText: String
        let referenceURLText: String
    }

    static func recoveredIdentitySeed(
        film: FilmIdentity,
        profile: ReciprocityProfile
    ) -> RecoveredIdentitySeed {
        let sourceType = profile.userMetadata?.customSourceType
            ?? film.userMetadata?.customSourceType
            ?? .userDefined
        let notesValue = profile.userMetadata?.notes.first
            ?? film.userMetadata?.notes.first
            ?? ""
        // Recover the manufacturer and label from
        // `userMetadata.customManufacturer` and the canonical
        // stock name. Older payloads stored the full name in
        // `canonicalStockName` only; this lookup detects the
        // manufacturer prefix and splits it back into separate
        // fields so the editor surfaces a clean Label row instead
        // of leaking the manufacturer string into it.
        let storedManufacturer = profile.userMetadata?.customManufacturer
            ?? film.userMetadata?.customManufacturer
        let manufacturerText = storedManufacturer ?? ""
        let labelText: String = {
            if let storedManufacturer,
               film.canonicalStockName.hasPrefix("\(storedManufacturer) ") {
                return String(film.canonicalStockName.dropFirst(storedManufacturer.count + 1))
            }
            return film.canonicalStockName
        }()
        let referenceURLText = profile.userMetadata?.referenceURL
            ?? film.userMetadata?.referenceURL
            ?? ""
        return RecoveredIdentitySeed(
            sourceType: sourceType,
            notesValue: notesValue,
            manufacturerText: manufacturerText,
            labelText: labelText,
            referenceURLText: referenceURLText
        )
    }

    /// Picks the input mode the editor should open in when loading
    /// an existing custom film. Maps the actual formula shape into
    /// the smallest mode that can faithfully edit it without losing
    /// information — so an exponent-only profile prefills as
    /// `.basic`, a `T-MAX 100` style anchored profile prefills as
    /// `.scaled`, and any non-zero offset forces `.advanced`.
    public static func inferInputMode(
        baseTm: Double,
        baseTc: Double,
        offsetSeconds: Double
    ) -> CustomFilmFormulaInputMode {
        if abs(offsetSeconds) > 1e-9 {
            return .advanced
        }
        if abs(baseTm - 1) > 1e-9 || abs(baseTc - 1) > 1e-9 {
            return .scaled
        }
        return .basic
    }

    /// Compact numeric rendering shared by `from(film:)` (formula
    /// and table branches) so an edit round-trip reads back the
    /// same numeric strings the summaries use.
    static func formatNumeric(_ value: Double) -> String {
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
}

/// Field identifiers used by `CustomFilmEditorFormState.
/// inlineValidationReason(for:isEditing:)` so the editor view
/// can request a row-local validation hint by naming the field
/// the row represents.
public enum CustomFilmEditorField: String, Equatable, Hashable, CaseIterable {
    case label
    case iso
    case exponent
    case referenceTm
    case correctedAtReference
    case offset
    case noCorrectionThrough
    case sourceRangeThrough
}

extension CustomFilmEditorFormState {
    /// `true` when the editor preview can render its graph and
    /// checkpoint table without risking a misleading curve or
    /// per-row "Invalid formula result" pile-up. Two conditions
    /// must both hold:
    /// 1. The form parses into a `ReciprocityFormula` (so anchors,
    ///    exponent, no-correction, and source range are syntactically
    ///    sound).
    /// 2. The formula passes the stabilization guard
    ///    (`CustomFilmFormulaGuard.passesUsableRangeCheck`), so
    ///    Tc never shortens Tm inside the usable range.
    ///
    /// Identity-only validation issues (missing Label/ISO) do not
    /// affect this — the preview cares only about the formula
    /// portion of the form. Callers that need to know why the
    /// preview is unavailable should consult
    /// `CustomFilmEditorPreviewPresenter.diagnose(form:)` for
    /// field-level reasons and `saveDisabledReason(isEditing:)`
    /// for the cross-field shorten-exposure case.
    public var formulaCanRenderPreview: Bool {
        guard let formula = parsedReciprocityFormula() else {
            return false
        }
        return CustomFilmFormulaGuard.passesUsableRangeCheck(
            CustomFilmFormulaGuard.UsableRangeInput(
                exponent: formula.exponent,
                referenceMeteredTimeSeconds: formula.referenceMeteredTimeSeconds,
                coefficientSeconds: formula.coefficientSeconds,
                offsetSeconds: formula.offsetSeconds,
                noCorrectionThroughSeconds: formula.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds: formula.sourceRangeThroughSeconds
            )
        )
    }

    /// Synthesizes a `ReciprocityFormula` from the form's current
    /// inputs, or `nil` when the form cannot be parsed cleanly.
    /// Mirrors `CustomFilmEditorFormState.buildFilmIdentity`'s
    /// field-to-formula mapping so a caller that renders the
    /// formula (Calculation Basis presenter, etc.) sees the same
    /// numeric model the runtime save path would produce.
    public func parsedReciprocityFormula() -> ReciprocityFormula? {
        guard let parsed = CustomFilmEditorPreviewPresenter.parse(form: self) else {
            return nil
        }
        return ReciprocityFormula(
            formulaFamily: .modifiedSchwarzschild,
            coefficientSeconds: parsed.baseTc,
            referenceMeteredTimeSeconds: parsed.baseTm,
            exponent: parsed.exponent,
            offsetSeconds: parsed.offsetSeconds,
            noCorrectionThroughSeconds: parsed.noCorrectionThrough,
            sourceRangeThroughSeconds: parsed.validThrough
        )
    }

    /// Symbolic skeleton of the formula, rendered above the live
    /// current-value line in the Formula card. The editor exposes
    /// the same anchored shape regardless of input mode so the
    /// photographer always reads the formula as a single mental
    /// model — the row order below maps directly to the terms in
    /// this expression from left to right.
    public func formulaStructureText() -> String {
        return "Tc = Tc₀ × (Tm / Tm₀)^p + b"
    }

    /// Right-hand-side of the live formula expression, rendered
    /// under the symbolic structure line aligned on the `=` glyph.
    /// Always renders the full anchored shape so every token in
    /// `formulaStructureText()` has a matching slot here.
    ///
    /// Each slot uses the parsed numeric value with units when the
    /// field parses cleanly, and falls back to the symbol itself
    /// (`Tc₀`, `Tm₀`, `p`, `b`) when the field is missing or
    /// unparseable — never to descriptive words like `exponent`
    /// or `offset`, which would not map back to anything the
    /// photographer can edit.
    ///
    /// The leading `= ` is preserved so the caller can render the
    /// line directly without re-injecting the equals sign.
    public func formulaCurrentLineText() -> String {
        let summary = formulaExpressionSummary()
        guard let equalsIndex = summary.firstIndex(of: "=") else {
            return summary
        }
        return String(summary[equalsIndex...])
    }

    /// Full-formula RHS in the anchored shape `Tc = Tc₀ × (Tm /
    /// Tm₀)^p + b`, with each slot replaced by either the parsed
    /// numeric value (with units) or the slot's symbol when the
    /// field is blank/unparseable. Stays mode-agnostic — the
    /// editor surfaces the same shape regardless of which terms
    /// happen to be at their neutral defaults.
    ///
    /// Negative offsets render as `− |b|s` instead of `+ -Ns` so
    /// the expression reads naturally; zero offset still renders
    /// as `+ 0s` so the `b` slot stays visible and tappable in
    /// the photographer's mental map of the formula.
    public func formulaExpressionSummary() -> String {
        let tcAnchor = formulaTextDuration(baseTcText, fallback: "Tc₀", neutralFallback: "1s")
        let tmAnchor = formulaTextDuration(baseTmText, fallback: "Tm₀", neutralFallback: "1s")
        let exponentLabel = formulaTextExponent()
        let offsetSegment = formulaTextOffsetSegment()
        return "Tc = \(tcAnchor) × (Tm / \(tmAnchor))^\(exponentLabel)\(offsetSegment)"
    }

    /// Renders the exponent slot for the formula summary. Falls
    /// back to the symbol `p` (matching the editor row label) when
    /// the entry is blank or unparseable, so a mid-edit form still
    /// reads as a formula expression rather than a half-rendered
    /// string.
    private func formulaTextExponent() -> String {
        let trimmed = exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite, value > 0 else {
            return "p"
        }
        return Self.formatNumericExpression(value)
    }

    /// Renders a positive duration slot (`Tm₀`/`Tc₀`). Empty
    /// fields use the documented neutral default so the slot
    /// stays visible (the editor de-emphasizes neutral values
    /// visually rather than hiding them); non-empty but
    /// unparseable entries fall back to the symbol so the
    /// expression stays readable as the photographer types.
    private func formulaTextDuration(
        _ text: String,
        fallback: String,
        neutralFallback: String
    ) -> String {
        switch CustomFilmDurationParser.parse(text) {
        case .empty:
            return neutralFallback
        case .seconds(let value) where value.isFinite && value > 0:
            return Self.formatDurationCompact(value)
        case .seconds, .unlimited, .none:
            return fallback
        }
    }

    /// Renders the trailing `+ b` segment of the anchored formula.
    /// Empty/zero values render as `+ 0s` so the `b` slot stays
    /// visible in the photographer's mental model of the formula;
    /// negative values render as `− |b|s` so the expression reads
    /// naturally; unparseable values fall back to the symbol `b`.
    private func formulaTextOffsetSegment() -> String {
        switch CustomFilmDurationParser.parse(offsetSecondsText) {
        case .empty:
            return " + 0s"
        case .seconds(let value) where value.isFinite:
            if abs(value) < 1e-9 {
                return " + 0s"
            }
            let magnitude = Self.formatDurationCompact(abs(value))
            return value > 0 ? " + \(magnitude)" : " − \(magnitude)"
        case .seconds, .unlimited, .none:
            return " + b"
        }
    }

    /// Compact seconds rendering for the Formula card's current
    /// line. Trims trailing zeros so `0.5` reads as `0.5s` and
    /// `0.1` as `0.1s` — matching the `FormulaEquationFormatter`
    /// vocabulary used by the Calculation Basis surface so the
    /// two surfaces never disagree on the rendered numeric token
    /// for the same value. Minute-scale values delegate to
    /// `formatDurationExpression` so both surfaces share one
    /// no-decimal-minute policy.
    public static func formatDurationCompact(_ seconds: Double) -> String {
        if seconds >= 60 {
            return formatDurationExpression(seconds)
        }
        if seconds == seconds.rounded() {
            return "\(Int(seconds))s"
        }
        return "\(formatNumericExpression(seconds))s"
    }

    // MARK: - Formula tokens

    /// Tappable slots inside the editor's interactive formula
    /// line. The slot order matches the symbolic structure
    /// `Tc = Tc₀ × (Tm / Tm₀)^p + b` from left to right, so the
    /// view can iterate over `allCases` and the test surface can
    /// assert on the rendered order without depending on view-
    /// layer plumbing.
    public enum FormulaTokenSlot: String, CaseIterable, Hashable {
        case tcAnchor
        case tmAnchor
        case exponent
        case offset

        /// Bare symbol shown in the structure line above the
        /// token line — also used as the placeholder text when a
        /// slot's underlying form field is blank or unparseable.
        public var symbol: String {
            switch self {
            case .tcAnchor: return "Tc₀"
            case .tmAnchor: return "Tm₀"
            case .exponent: return "p"
            case .offset: return "b"
            }
        }

        /// Field-sheet identifier the token tap should present so
        /// the slot maps onto the existing per-field sheet flow.
        public var editField: CustomFilmEditorEditField {
            switch self {
            case .tcAnchor: return .correctedAtReference
            case .tmAnchor: return .referenceTm
            case .exponent: return .exponent
            case .offset: return .offset
            }
        }

        /// Stable accessibility identifier for the token button.
        public var accessibilityID: String {
            switch self {
            case .tcAnchor: return "custom-film-editor-token-tc-anchor"
            case .tmAnchor: return "custom-film-editor-token-tm-anchor"
            case .exponent: return "custom-film-editor-token-exponent"
            case .offset: return "custom-film-editor-token-offset"
            }
        }
    }

    /// Rendered state for one formula token. The view renders
    /// `displayText` inside a tappable pill; `isPlaceholder`
    /// drives the dimmed (secondary) text style so a blank slot
    /// reads as "tap to enter" and a neutral default (`1s`/`0s`)
    /// stays visible-but-de-emphasized; `isInvalid` adds a red
    /// outline so a per-token problem (anchor that fails the
    /// shortens-exposure guard, unparseable input) catches the
    /// eye without a separate caption row.
    public struct FormulaTokenDisplay: Equatable {
        public let slot: FormulaTokenSlot
        public let displayText: String
        public let isPlaceholder: Bool
        public let isInvalid: Bool

        public init(slot: FormulaTokenSlot, displayText: String, isPlaceholder: Bool, isInvalid: Bool) {
            self.slot = slot
            self.displayText = displayText
            self.isPlaceholder = isPlaceholder
            self.isInvalid = isInvalid
        }
    }

    /// Returns the four token displays in formula order so the
    /// view can iterate without manual case-by-case wiring.
    public func formulaTokenDisplays() -> [FormulaTokenDisplay] {
        return FormulaTokenSlot.allCases.map(formulaTokenDisplay(for:))
    }

    /// Per-slot rendered state. Computed from the same form
    /// fields the validator reads, so a slot reads as invalid
    /// here whenever the validator would reject it.
    public func formulaTokenDisplay(for slot: FormulaTokenSlot) -> FormulaTokenDisplay {
        let errors: Set<CustomFilmEditorValidationError>
        if case .failure(let envelope) = validate() {
            errors = envelope.errors
        } else {
            errors = []
        }
        switch slot {
        case .tcAnchor:
            let token = anchorTokenText(baseTcText, neutralFallback: "1s")
            let invalid = errors.contains(.invalidBaseTc)
                || errors.contains(.formulaShortensExposure)
            return FormulaTokenDisplay(
                slot: slot,
                displayText: token.text,
                isPlaceholder: token.isPlaceholder,
                isInvalid: invalid
            )
        case .tmAnchor:
            let token = anchorTokenText(baseTmText, neutralFallback: "1s")
            let invalid = errors.contains(.invalidBaseTm)
                || errors.contains(.formulaShortensExposure)
            return FormulaTokenDisplay(
                slot: slot,
                displayText: token.text,
                isPlaceholder: token.isPlaceholder,
                isInvalid: invalid
            )
        case .exponent:
            let token = exponentTokenText()
            let invalid = errors.contains(.missingFormulaExponent)
                || errors.contains(.invalidFormulaExponent)
            return FormulaTokenDisplay(
                slot: slot,
                displayText: token.text,
                isPlaceholder: token.isPlaceholder,
                isInvalid: invalid
            )
        case .offset:
            let token = offsetTokenText()
            let invalid = errors.contains(.invalidFormulaOffset)
            return FormulaTokenDisplay(
                slot: slot,
                displayText: token.text,
                isPlaceholder: token.isPlaceholder,
                isInvalid: invalid
            )
        }
    }

    private struct TokenText {
        let text: String
        /// True when the slot is empty/unparseable or sitting on
        /// its documented neutral default. The view uses this
        /// to render the token in the secondary text color so
        /// touched vs. untouched slots stay visually distinct.
        let isPlaceholder: Bool
    }

    private func anchorTokenText(
        _ text: String,
        neutralFallback: String
    ) -> TokenText {
        switch CustomFilmDurationParser.parse(text) {
        case .empty:
            return TokenText(text: neutralFallback, isPlaceholder: true)
        case .seconds(let value) where value.isFinite && value > 0:
            let rendered = Self.formatDurationCompact(value)
            return TokenText(
                text: rendered,
                isPlaceholder: rendered == neutralFallback
            )
        case .seconds, .unlimited, .none:
            // Echo what the photographer typed so the token does
            // not silently swap to a fallback symbol while they
            // are mid-edit.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return TokenText(
                text: trimmed.isEmpty ? neutralFallback : trimmed,
                isPlaceholder: trimmed.isEmpty
            )
        }
    }

    private func exponentTokenText() -> TokenText {
        let trimmed = exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Empty exponent reads as the symbol so the line
            // still parses as a formula at a glance.
            return TokenText(text: FormulaTokenSlot.exponent.symbol, isPlaceholder: true)
        }
        if let value = Double(trimmed), value.isFinite, value > 0 {
            return TokenText(
                text: Self.formatNumericExpression(value),
                isPlaceholder: false
            )
        }
        return TokenText(text: trimmed, isPlaceholder: false)
    }

    private func offsetTokenText() -> TokenText {
        switch CustomFilmDurationParser.parse(offsetSecondsText) {
        case .empty:
            return TokenText(text: "0s", isPlaceholder: true)
        case .seconds(let value) where value.isFinite:
            if abs(value) < 1e-9 {
                return TokenText(text: "0s", isPlaceholder: true)
            }
            let magnitude = Self.formatDurationCompact(abs(value))
            let signed = value > 0 ? magnitude : "−\(magnitude)"
            return TokenText(text: signed, isPlaceholder: false)
        case .seconds, .unlimited, .none:
            let trimmed = offsetSecondsText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return TokenText(
                text: trimmed.isEmpty ? "0s" : trimmed,
                isPlaceholder: trimmed.isEmpty
            )
        }
    }

    /// Compact numeric rendering for the exponent. Strips
    /// trailing zeros so `1.30` reads as `1.3` and `1.0966`
    /// keeps four significant digits.
    public static func formatNumericExpression(_ value: Double) -> String {
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

    /// Compact numeric duration rendering for the formula
    /// summary. Whole-minute values render as `Nm`, sub-minute
    /// values as `Nm Xs` (e.g. `1m 40s` for 100 s), sub-second
    /// values as `0.NNs`, whole seconds as `Ns`, and fractional
    /// seconds as `N.Ns`. No decimal-minute notation (`1.7m`) —
    /// that form is ambiguous for source-anchor verification.
    public static func formatDurationExpression(_ seconds: Double) -> String {
        if seconds >= 60 {
            let total = Int(seconds.rounded())
            let mins = total / 60
            let secs = total % 60
            return secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
        }
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        }
        return seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }

    /// Seconds-first format for values that the photographer entered
    /// as anchor seconds. Values ≥ 60 s render as `Xs (NmYs)` so
    /// the raw seconds value is always visible alongside the clock
    /// context — e.g. `100s (1m 40s)`, `1000s (16m 40s)`. Values
    /// < 60 s fall through to `formatDurationExpression` unchanged.
    public static func formatAnchorSeconds(_ seconds: Double) -> String {
        guard seconds >= 60 else { return formatDurationExpression(seconds) }
        let total = Int(seconds.rounded())
        let compact = formatDurationExpression(seconds)
        return "\(total)s (\(compact))"
    }

    /// Concise, per-row inline validation reason rendered under
    /// the matching compact summary row. Returns `nil` when the
    /// field passes validation, or when the photographer is still
    /// in the untouched empty new-form state.
    ///
    /// The editor view calls this once per row so the previous
    /// pass's pile of `if validationErrors.contains(...)` blocks
    /// is replaced by a single field-keyed query that returns
    /// short, action-oriented copy.
    public func inlineValidationReason(
        for field: CustomFilmEditorField,
        isEditing: Bool
    ) -> String? {
        if !isEditing, isUntouchedNewForm() {
            return nil
        }
        guard case .failure(let envelope) = validate() else {
            return nil
        }
        let errors = envelope.errors
        switch field {
        case .label:
            return errors.contains(.missingFilmLabel) ? "Required" : nil
        case .iso:
            return errors.contains(.invalidISO)
                ? "Enter \(Self.minISO)–\(Self.maxISO)"
                : nil
        case .exponent:
            // Compact constraint wording so the row reads as a
            // single concise hint instead of a paragraph. The
            // symbol matches the row label and the structure
            // line, so the photographer never has to translate.
            if errors.contains(.missingFormulaExponent) {
                return "p is required"
            }
            if errors.contains(.invalidFormulaExponent) {
                return "p must be > 0"
            }
            return nil
        case .referenceTm:
            return errors.contains(.invalidBaseTm)
                ? "Tm₀ must be > 0"
                : nil
        case .correctedAtReference:
            return errors.contains(.invalidBaseTc)
                ? "Tc₀ must be > 0"
                : nil
        case .offset:
            return errors.contains(.invalidFormulaOffset)
                ? "b must be a finite duration"
                : nil
        case .noCorrectionThrough:
            guard errors.contains(.invalidNoCorrectionThrough) else { return nil }
            // The table evaluator feeds the no-correction knee into
            // log-log interpolation, so the table editor is stricter
            // than the formula path: positive only, and strictly
            // below the first anchor.
            return calculationInputKind == .table
                ? "Must be > 0 and below the first anchor"
                : "Must be ≥ 0"
        case .sourceRangeThrough:
            return errors.contains(.invalidValidThrough)
                ? "Must be > No correction"
                : nil
        }
    }

    /// Cross-field structural reason the Save action is disabled
    /// — currently only the formula-shortens-exposure invariant
    /// (the formula would produce a corrected exposure shorter
    /// than the metered input, which the calculator must never
    /// emit). Per-field invalidations surface through
    /// `inlineValidationReason(for:isEditing:)` instead.
    ///
    /// Returns `nil` when the form is valid, when the photographer
    /// is still in the untouched empty state, or when every
    /// remaining error has a per-row inline representation.
    public func saveDisabledReason(isEditing: Bool) -> String? {
        if !isEditing, isUntouchedNewForm() {
            return nil
        }
        guard case .failure(let envelope) = validate() else {
            return nil
        }
        if envelope.errors.contains(.formulaShortensExposure) {
            return formulaShortensExposureMessage()
        }
        // Table-mode cross-row reason: the per-row hints cover
        // unparseable / shortening / out-of-order rows, so the only
        // structural message left is "not enough anchors yet".
        if envelope.errors.contains(.insufficientTableAnchors) {
            return "Enter at least 2 anchor rows (Tm → Tc)"
        }
        return nil
    }

    /// Compact formula-style recovery message for the
    /// `.formulaShortensExposure` invariant. Two lines: line 1
    /// states the constraint in symbol form so the recovery
    /// wording reads as a single concise constraint the
    /// photographer can match against the formula tokens above;
    /// line 2 names the current values so the user knows which
    /// way to move.
    ///
    /// ```
    /// Tc₀ must be ≥ Tm₀
    /// Current: 1s < 2s
    /// ```
    ///
    /// `.formulaShortensExposure` is only inserted after the
    /// anchor fields parsed cleanly, so the anchor formatting
    /// uses the parsed numeric values directly. Falls back to the
    /// raw user text if a future caller invokes this with
    /// unparseable anchors.
    private func formulaShortensExposureMessage() -> String {
        let tmDisplay = anchorDisplayLabel(baseTmText)
        let tcDisplay = anchorDisplayLabel(baseTcText)
        return """
        Tc₀ must be ≥ Tm₀
        Current: \(tcDisplay) < \(tmDisplay)
        """
    }

    /// Formats an anchor field's text as a compact duration
    /// (`2s`, `0.5s`, `3.3m`) when the field parses; falls back
    /// to the raw user-typed string so unparseable values still
    /// read as the photographer typed them.
    private func anchorDisplayLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch CustomFilmDurationParser.parse(trimmed) {
        case .seconds(let value) where value.isFinite && value > 0:
            return Self.formatDurationExpression(value)
        default:
            return trimmed.isEmpty ? "—" : trimmed
        }
    }

    /// True when every photographer-editable field is at its
    /// initial blank-form state. Used by the inline-validation
    /// and save-disabled hooks to suppress hints until the
    /// photographer has actually engaged with the form.
    public func isUntouchedNewForm() -> Bool {
        return exponentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filmLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && manufacturerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && referenceURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tableRows.allSatisfy(\.isBlank)
    }

    /// Lower bound for accepted ISO box-speed values. 1 covers
    /// long-discontinued slow film and the lowest practical pinhole
    /// targets; below 1 the calculator's metered exposure formatter
    /// would never produce meaningful guidance.
    public static let minISO = 1
    /// Upper bound is generous — current commercial stocks top out
    /// near 3200; the cap exists to reject obvious typos / overflow,
    /// not to police photographic realism.
    public static let maxISO = 100_000

    /// Validates and converts the pending input into a fully-formed
    /// custom `FilmIdentity`. Returns either the new identity or the
    /// unordered set of field-level reasons it failed. The id is
    /// supplied by the caller so the persistence layer can drive
    /// stable identifiers without the form state having to reach
    /// for a UUID generator at validation time.
    public func validate(
        idGenerator: () -> String = { UUID().uuidString }
    ) -> Result<FilmIdentity, CustomFilmEditorValidationErrors> {
        if calculationInputKind == .table {
            return validateTable(idGenerator: idGenerator)
        }
        var errors: Set<CustomFilmEditorValidationError> = []

        let trimmedFilmLabel = filmLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFilmLabel.isEmpty {
            errors.insert(.missingFilmLabel)
        }
        let iso = parseISO(errors: &errors)
        let exponent = parseExponent(errors: &errors)
        let baseTm = parseAnchor(
            baseTmText,
            invalidError: .invalidBaseTm,
            errors: &errors
        )
        let baseTc = parseAnchor(
            baseTcText,
            invalidError: .invalidBaseTc,
            errors: &errors
        )
        let offsetSeconds = optionalFinite(
            offsetSecondsText,
            invalidError: .invalidFormulaOffset,
            errors: &errors
        )
        let noCorrectionThrough = parseNoCorrectionThrough(errors: &errors)
        let validThrough = parseValidThrough(
            noCorrectionThrough: noCorrectionThrough,
            errors: &errors
        )

        if let exponent,
           let baseTm,
           let baseTc,
           let noCorrectionThrough,
           !CustomFilmFormulaGuard.passesUsableRangeCheck(
               .init(
                   exponent: exponent,
                   referenceMeteredTimeSeconds: baseTm,
                   coefficientSeconds: baseTc,
                   offsetSeconds: offsetSeconds ?? 0.0,
                   noCorrectionThroughSeconds: noCorrectionThrough,
                   sourceRangeThroughSeconds: validThrough
               )
           ) {
            errors.insert(.formulaShortensExposure)
        }

        guard errors.isEmpty,
              let exponent,
              let iso,
              let baseTm,
              let baseTc,
              let noCorrectionThrough else {
            return .failure(CustomFilmEditorValidationErrors(errors))
        }

        // The editor does not surface a separate profile-name
        // field; the auto-generated `Manufacturer + Label · ISO N`
        // string drives both the user-facing display name and the
        // internal `ReciprocityProfile.name`. The `profileName`
        // form field stays only as a fallback for callers that
        // still set it explicitly.
        let resolvedProfileName = Self.composeDisplayName(
            manufacturer: manufacturerText,
            label: trimmedFilmLabel,
            iso: iso
        )
        let fallbackName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let film = buildFilmIdentity(
            ValidatedInput(
                profileName: resolvedProfileName.isEmpty
                    ? (fallbackName.isEmpty ? trimmedFilmLabel : fallbackName)
                    : resolvedProfileName,
                filmLabel: trimmedFilmLabel,
                iso: iso,
                exponent: exponent,
                baseTm: baseTm,
                baseTc: baseTc,
                offsetSeconds: offsetSeconds,
                noCorrectionThrough: noCorrectionThrough,
                validThrough: validThrough
            ),
            idGenerator: idGenerator
        )
        return .success(film)
    }

    /// The canonical display-name composer used by both the
    /// editor's auto-generated profile name and the editor view's
    /// header text. Same rule applied in one place so the runtime
    /// / Details / timer surfaces all read the same string for a
    /// given (manufacturer, label, ISO) triple.
    public static func composeDisplayName(
        manufacturer: String,
        label: String,
        iso: Int?
    ) -> String {
        let trimmedManufacturer = manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameParts = [trimmedManufacturer, trimmedLabel].filter { !$0.isEmpty }
        let nameJoined = nameParts.joined(separator: " ")
        let isoSegment = iso.map { "ISO \($0)" } ?? ""
        let segments = [nameJoined, isoSegment].filter { !$0.isEmpty }
        return segments.joined(separator: " · ")
    }

    /// Parses an anchor field (`baseTmText` / `baseTcText`).
    /// Empty input falls back to the documented `1` default so the
    /// editor's default state behaves like an exponent-only
    /// formula; non-empty, non-finite, or non-positive input
    /// raises the matching error so the editor surfaces it.
    /// Accepts the same duration shapes (`100`, `100s`, `5m`,
    /// `1h`) as the application-range fields so the photographer
    /// can write `0.1s` for a base anchor without ambiguity.
    /// "Unlimited" makes no sense for an anchor and is rejected.
    /// Empty input still falls back to the documented `1` default.
    private func parseAnchor(
        _ text: String,
        invalidError: CustomFilmEditorValidationError,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty:
            return 1.0
        case .seconds(let value) where value.isFinite && value > 0:
            return value
        case .seconds, .unlimited, .none:
            errors.insert(invalidError)
            return nil
        }
    }

    private func parseNoCorrectionThrough(
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(noCorrectionThroughText) {
        case .empty:
            return 1.0
        case .unlimited:
            // "Unlimited" makes no sense for the no-correction
            // threshold (it would skip the formula entirely);
            // surface as invalid.
            errors.insert(.invalidNoCorrectionThrough)
            return nil
        case .seconds(let value) where value >= 0:
            return value
        case .seconds, .none:
            errors.insert(.invalidNoCorrectionThrough)
            return nil
        }
    }

    /// An empty / "Unlimited" entry means the formula has no upper
    /// bound. The validator never raises `.missingValidThrough` —
    /// the field is optional. Non-empty values still have to be
    /// finite, positive, and strictly greater than
    /// `noCorrectionThrough`.
    private func parseValidThrough(
        noCorrectionThrough: Double?,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(validThroughText) {
        case .empty, .unlimited:
            return nil
        case .seconds(let parsed) where parsed.isFinite && parsed > 0:
            if let noCorrectionThrough, parsed <= noCorrectionThrough {
                errors.insert(.invalidValidThrough)
                return nil
            }
            return parsed
        case .seconds, .none:
            errors.insert(.invalidValidThrough)
            return nil
        }
    }

    /// Bundle of validated, type-safe fields handed to
    /// `buildFilmIdentity`. The bundling exists so the build
    /// function stays under the swiftlint parameter-count limit
    /// without leaking raw `String` fields past the validation
    /// boundary.
    private struct ValidatedInput {
        let profileName: String
        let filmLabel: String
        let iso: Int
        let exponent: Double
        let baseTm: Double
        let baseTc: Double
        let offsetSeconds: Double?
        let noCorrectionThrough: Double
        /// `nil` when the photographer left the field blank /
        /// "Unlimited" — the saved formula's
        /// `sourceRangeThroughSeconds` is then `nil`.
        let validThrough: Double?
    }

    func parseISO(errors: inout Set<CustomFilmEditorValidationError>) -> Int? {
        let trimmed = isoText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Int(trimmed), (Self.minISO...Self.maxISO).contains(parsed) {
            return parsed
        }
        errors.insert(.invalidISO)
        return nil
    }

    private func parseExponent(errors: inout Set<CustomFilmEditorValidationError>) -> Double? {
        let trimmed = exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors.insert(.missingFormulaExponent)
            return nil
        }
        if let parsed = Double(trimmed), parsed.isFinite, parsed > 0 {
            return parsed
        }
        errors.insert(.invalidFormulaExponent)
        return nil
    }

    private func buildFilmIdentity(
        _ input: ValidatedInput,
        idGenerator: () -> String
    ) -> FilmIdentity {
        // Custom profiles produce the same shared
        // `ReciprocityFormula` shape preset profiles use, so the
        // runtime evaluator, the Details graph presenter, the
        // equation formatter, and the timer identity summary all
        // read one schema. Editor UI labels map onto the shared
        // field names verbatim:
        //
        //   Tm₀ (Metered point)    → referenceMeteredTimeSeconds
        //   Tc₀ (Corrected point)  → coefficientSeconds
        //   p (Curve strength)     → exponent
        //   b (Fixed add-on)       → offsetSeconds
        //   No correction until    → noCorrectionThroughSeconds
        //   Source data through    → sourceRangeThroughSeconds
        //
        // `sourceRangeThroughSeconds` is a confidence boundary
        // (not a calculation stop). Inputs strictly above it still
        // compute a corrected exposure; the policy evaluator
        // surfaces them as `unsupportedFormulaOutsideSourceRange`
        // so the Details / timer surfaces flag the prediction
        // as beyond the photographer's stated source range.
        let formula = ReciprocityFormula(
            formulaFamily: .modifiedSchwarzschild,
            coefficientSeconds: input.baseTc,
            referenceMeteredTimeSeconds: input.baseTm,
            exponent: input.exponent,
            offsetSeconds: input.offsetSeconds ?? 0,
            noCorrectionThroughSeconds: input.noCorrectionThrough,
            sourceRangeThroughSeconds: input.validThrough
        )
        let formulaRule = FormulaReciprocityRule(formula: formula)
        let profile = ReciprocityProfile(
            id: idGenerator(),
            name: input.profileName,
            source: Self.customSourceProvenance(),
            rules: [.formula(formulaRule)],
            userMetadata: customProfileMetadata()
        )
        return assembleCustomFilm(
            profile: profile,
            filmLabel: input.filmLabel,
            iso: input.iso,
            idGenerator: idGenerator
        )
    }

    /// Shared `.userDefined` provenance every custom-authored
    /// profile (formula or table) carries.
    static func customSourceProvenance() -> ReciprocitySourceProvenance {
        ReciprocitySourceProvenance(
            kind: .userDefined,
            authority: .userDefined,
            confidence: .unknown,
            publisher: ""
        )
    }

    /// Profile-level user metadata assembled from the form's
    /// provenance fields. Shared by the formula and table build
    /// paths.
    func customProfileMetadata() -> UserEditableMetadata {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteList = trimmedNotes.isEmpty ? [] : [trimmedNotes]
        return UserEditableMetadata(
            notes: noteList,
            customSourceType: sourceType,
            customManufacturer: trimmedManufacturerOrNil(),
            referenceURL: trimmedReferenceURLOrNil()
        )
    }

    private func trimmedManufacturerOrNil() -> String? {
        let trimmed = manufacturerText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimmedReferenceURLOrNil() -> String? {
        let trimmed = referenceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Wraps a validated custom profile into the `FilmIdentity`
    /// shape every downstream surface consumes. Shared by the
    /// formula and table build paths; the second `idGenerator()`
    /// call yields the film id (callers that reuse ids on Edit
    /// pass profile id first, film id second).
    func assembleCustomFilm(
        profile: ReciprocityProfile,
        filmLabel: String,
        iso: Int,
        idGenerator: () -> String
    ) -> FilmIdentity {
        let manufacturerForMetadata = trimmedManufacturerOrNil()
        let filmMetadata = UserEditableMetadata(
            customSourceType: sourceType,
            customManufacturer: manufacturerForMetadata,
            referenceURL: trimmedReferenceURLOrNil()
        )
        // Compose `canonicalStockName` from manufacturer + label so
        // every downstream surface (selector primary text, timer
        // identity, Details title) reads the full film name. The
        // top-level `FilmIdentity.manufacturer` stays `nil` so the
        // picker keeps custom rows in the "Custom films" section
        // instead of merging them with preset manufacturer groups.
        let canonical = manufacturerForMetadata
            .map { "\($0) \(filmLabel)" }
            ?? filmLabel
        return FilmIdentity(
            id: idGenerator(),
            kind: .custom,
            canonicalStockName: canonical,
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: filmMetadata
        )
    }

    private func optionalFinitePositive(
        _ text: String,
        invalidError: CustomFilmEditorValidationError,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed), value.isFinite, value > 0 {
            return value
        }
        errors.insert(invalidError)
        return nil
    }

    /// Offset accepts the duration parser's `.seconds` case
    /// (`100`, `100s`, `5m`, `1h`) but rejects `Unlimited`. Empty
    /// stays optional (the editor's documented 0s default applies
    /// in the build path).
    private func optionalFinite(
        _ text: String,
        invalidError: CustomFilmEditorValidationError,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty:
            return nil
        case .seconds(let value) where value.isFinite:
            return value
        case .seconds, .unlimited, .none:
            errors.insert(invalidError)
            return nil
        }
    }
}
