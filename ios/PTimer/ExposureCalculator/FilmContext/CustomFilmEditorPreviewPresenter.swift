import Foundation

/// Pure value transform that turns the editor's pending form
/// state into preview data so the editor view can render a live
/// Tm→Tc table and a small preview graph without re-implementing
/// the policy evaluator.
///
/// The presenter never throws and never mutates the form state.
/// When the form is incomplete or invalid it returns rows with
/// `.invalidFormulaResult` status so the table can communicate
/// "the formula does not produce a sensible value" before the
/// user even taps Save.
enum CustomFilmEditorPreviewPresenter {

    /// Sample metered exposures (in seconds) the editor preview
    /// table renders by default. A compact 5-row ladder spanning
    /// the long-exposure photography range so the photographer
    /// can scan the formula at decade boundaries without the
    /// table dominating the editor screen.
    static let defaultSampleSeconds: [Double] = [1, 10, 60, 300, 1_000]

    /// Three representative samples (1s, 10s, 1m) used by the
    /// Formula card's inline Live Check block. Smaller set than
    /// `defaultSampleSeconds` so the live numeric feedback fits
    /// next to the formula inputs without duplicating the full
    /// Preview table.
    static let liveCheckSampleSeconds: [Double] = [1, 10, 60]

    enum RowStatus: Equatable, Hashable {
        case noCorrection
        case formulaApplied
        /// Source/fitting confidence boundary: a sample whose
        /// metered exposure sits above `sourceRangeThroughSeconds`
        /// still has a corrected value (the formula keeps
        /// producing one); the status flags the reduced confidence
        /// so the table reads it as beyond the photographer's
        /// stated source range, not as a calculation stop.
        case beyondSourceRange
        case invalidFormulaResult

        var displayLabel: String {
            switch self {
            case .noCorrection: return "No correction"
            case .formulaApplied: return "Formula applied"
            case .beyondSourceRange: return "Beyond source range"
            case .invalidFormulaResult: return "Invalid formula result"
            }
        }
    }

    struct Row: Equatable, Hashable {
        let meteredSeconds: Double
        /// `nil` only for `.invalidFormulaResult` rows so the view
        /// does not render a misleading numeric corrected value
        /// when the formula did not legitimately produce one.
        /// `.beyondSourceRange` rows still carry a numeric value
        /// — the formula keeps producing one past the
        /// source-range boundary; the status flags reduced
        /// confidence rather than a missing calculation.
        let correctedSeconds: Double?
        let status: RowStatus
        /// Optional stop delta between Tm and Tc, populated when
        /// the formula produced a finite positive Tc — including
        /// `.beyondSourceRange` rows.
        let stopDelta: Double?
    }

    /// Numeric coefficients extracted from the form state. `nil`
    /// when the exponent (the only required formula field) cannot
    /// be parsed, in which case the presenter still returns rows
    /// but every row is `.invalidFormulaResult`.
    struct ParsedFormula: Equatable {
        let exponent: Double
        /// Photographer-entered metered-exposure anchor. Defaults
        /// to 1s when the form field is blank.
        let baseTm: Double
        /// Photographer-entered corrected-exposure anchor.
        let baseTc: Double
        let offsetSeconds: Double
        let noCorrectionThrough: Double
        let validThrough: Double?
    }

    /// Field-level reason the editor preview cannot render. Returned
    /// by `diagnose(form:)` so the view can swap the row table for a
    /// single recovery-oriented message instead of repeating
    /// "Invalid formula result" once per sample row.
    enum InvalidReason: Equatable, Hashable {
        case emptyExponent
        case invalidExponent
        case invalidBaseTm
        case invalidBaseTc
        case invalidOffset
        case invalidNoCorrectionThrough
        /// Source range value is finite but not strictly greater
        /// than the no-correction threshold, or otherwise unparseable.
        case invalidSourceRange

        /// Short, photographer-readable explanation rendered in the
        /// preview's recovery panel. Wording uses the same
        /// symbol-anchored vocabulary as the Formula card rows
        /// (`p`, `Tm₀`, `Tc₀`, `b`) so the preview and the editor
        /// rows describe the same field the same way.
        var displayMessage: String {
            switch self {
            case .emptyExponent:
                return "p is required."
            case .invalidExponent:
                return "p must be > 0."
            case .invalidBaseTm:
                return "Tm₀ must be > 0."
            case .invalidBaseTc:
                return "Tc₀ must be > 0."
            case .invalidOffset:
                return "b must be a finite duration."
            case .invalidNoCorrectionThrough:
                return "No correction must be ≥ 0."
            case .invalidSourceRange:
                return "Source data must be > No correction."
            }
        }
    }

    /// Pure diagnostic that reports the first invalid formula
    /// field, or `nil` when the form parses cleanly. Order matches
    /// the editor card's row order so the reason the user sees
    /// reads as "the topmost broken field", not a randomised pick.
    /// Empty `exponent` returns `.emptyExponent` so the preview can
    /// render a neutral placeholder instead of a red error in the
    /// initial new-form state.
    static func diagnose(form: CustomFilmEditorFormState) -> InvalidReason? {
        let trimmedExponent = form.exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedExponent.isEmpty {
            return .emptyExponent
        }
        guard let exponent = Double(trimmedExponent), exponent.isFinite, exponent > 0 else {
            return .invalidExponent
        }
        if strictPositiveAnchor(form.baseTmText, default: 1.0) == nil {
            return .invalidBaseTm
        }
        if strictPositiveAnchor(form.baseTcText, default: 1.0) == nil {
            return .invalidBaseTc
        }
        if strictFiniteNumber(form.offsetSecondsText, default: 0.0) == nil {
            return .invalidOffset
        }
        guard let noCorrection = strictNonNegativeDuration(
            form.noCorrectionThroughText,
            default: 1.0
        ) else {
            return .invalidNoCorrectionThrough
        }
        if strictOptionalValidThrough(
            form.validThroughText,
            noCorrectionThrough: noCorrection
        ) == nil {
            return .invalidSourceRange
        }
        _ = exponent
        return nil
    }

    /// Strict parse of the form state. Empty entries fall back to
    /// documented defaults (`baseTm = baseTc = 1`, `offset = 0`,
    /// `noCorrection = 1`, `validThrough = Unlimited`) — but a
    /// non-empty unparseable entry yields `nil`, which the preview
    /// view renders as an invalid state instead of a
    /// silently-defaulted curve. This keeps the preview honest
    /// with the editor's Save guard: if Save is disabled, the
    /// preview is too.
    static func parse(form: CustomFilmEditorFormState) -> ParsedFormula? {
        guard let exponent = Double(form.exponentText.trimmingCharacters(in: .whitespacesAndNewlines)),
              exponent.isFinite, exponent > 0 else {
            return nil
        }
        guard let baseTm = strictPositiveAnchor(form.baseTmText, default: 1.0) else { return nil }
        guard let baseTc = strictPositiveAnchor(form.baseTcText, default: 1.0) else { return nil }
        guard let offset = strictFiniteNumber(form.offsetSecondsText, default: 0.0) else { return nil }
        guard let noCorrectionThrough = strictNonNegativeDuration(
            form.noCorrectionThroughText,
            default: 1.0
        ) else { return nil }
        guard let validThrough = strictOptionalValidThrough(
            form.validThroughText,
            noCorrectionThrough: noCorrectionThrough
        ) else { return nil }
        return ParsedFormula(
            exponent: exponent,
            baseTm: baseTm,
            baseTc: baseTc,
            offsetSeconds: offset,
            noCorrectionThrough: noCorrectionThrough,
            validThrough: validThrough.value
        )
    }

    /// Wrapped result so an "unlimited" valid-through can be
    /// distinguished from a parse failure by the caller.
    private enum OptionalValidThrough {
        case finite(Double)
        case unlimited
        var value: Double? {
            switch self {
            case .finite(let v): return v
            case .unlimited: return nil
            }
        }
    }

    /// Anchor fields (baseTm / baseTc) accept the same duration-
    /// string shapes the FormState validator accepts (`"1"`, `"1s"`,
    /// `"0.1s"`, `"5m"`, `"1h"`), so a value that saves cleanly also
    /// previews cleanly. `Unlimited` is rejected on anchors because
    /// the formula needs a finite reference point. Empty input
    /// falls back to the documented default so the preview reflects
    /// the editor's `1`/`1`/`0` defaults.
    private static func strictPositiveAnchor(_ text: String, default fallback: Double) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty: return fallback
        case .seconds(let value) where value.isFinite && value > 0: return value
        case .seconds, .unlimited, .none: return nil
        }
    }

    /// Offset accepts the same duration-string shapes as anchors,
    /// minus the positive-only constraint (a negative offset is a
    /// valid model when paired with a sufficiently large baseTc).
    /// `Unlimited` is rejected.
    private static func strictFiniteNumber(_ text: String, default fallback: Double) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty: return fallback
        case .seconds(let value) where value.isFinite: return value
        case .seconds, .unlimited, .none: return nil
        }
    }

    private static func strictNonNegativeDuration(_ text: String, default fallback: Double) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty: return fallback
        case .seconds(let value) where value.isFinite && value >= 0: return value
        case .seconds, .unlimited, .none: return nil
        }
    }

    private static func strictOptionalValidThrough(
        _ text: String,
        noCorrectionThrough: Double
    ) -> OptionalValidThrough? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty, .unlimited:
            return .unlimited
        case .seconds(let value) where value.isFinite && value > noCorrectionThrough:
            return .finite(value)
        case .seconds, .none:
            return nil
        }
    }

    /// Computes the preview rows for `form` over the default
    /// sample set. Each row carries either a corrected value plus
    /// status, or `.invalidFormulaResult` when the form's formula
    /// cannot be evaluated.
    static func rows(
        form: CustomFilmEditorFormState,
        samples: [Double] = defaultSampleSeconds
    ) -> [Row] {
        let parsed = parse(form: form)
        return samples.map { row(for: $0, parsed: parsed) }
    }

    private static func row(
        for meteredSeconds: Double,
        parsed: ParsedFormula?
    ) -> Row {
        guard let parsed else {
            return Row(
                meteredSeconds: meteredSeconds,
                correctedSeconds: nil,
                status: .invalidFormulaResult,
                stopDelta: nil
            )
        }
        if meteredSeconds <= parsed.noCorrectionThrough {
            return Row(
                meteredSeconds: meteredSeconds,
                correctedSeconds: meteredSeconds,
                status: .noCorrection,
                stopDelta: 0
            )
        }
        // Source range is a confidence boundary, not a calculation
        // stop. Above `sourceRangeThroughSeconds` the formula still
        // produces a corrected value; the status flips to
        // `.beyondSourceRange` so the table reads the reduced
        // confidence rather than missing data.
        let isBeyondSourceRange: Bool
        if let validThrough = parsed.validThrough, meteredSeconds > validThrough {
            isBeyondSourceRange = true
        } else {
            isBeyondSourceRange = false
        }
        // Anchored form: Tc = baseTc · (Tm / baseTm)^exponent + offset
        let tc = parsed.baseTc * pow(meteredSeconds / parsed.baseTm, parsed.exponent) + parsed.offsetSeconds
        guard tc.isFinite, tc > 0 else {
            return Row(
                meteredSeconds: meteredSeconds,
                correctedSeconds: nil,
                status: .invalidFormulaResult,
                stopDelta: nil
            )
        }
        // A sample whose Tc would shorten the metered time must
        // never read as `.formulaApplied`. Tolerate 1 ms of
        // floating-point slack so a perfectly flat boundary stays
        // valid.
        if tc + 0.001 < meteredSeconds {
            return Row(
                meteredSeconds: meteredSeconds,
                correctedSeconds: tc,
                status: .invalidFormulaResult,
                stopDelta: nil
            )
        }
        let stopDelta = log2(tc / meteredSeconds)
        return Row(
            meteredSeconds: meteredSeconds,
            correctedSeconds: tc,
            status: isBeyondSourceRange ? .beyondSourceRange : .formulaApplied,
            stopDelta: stopDelta
        )
    }

}
