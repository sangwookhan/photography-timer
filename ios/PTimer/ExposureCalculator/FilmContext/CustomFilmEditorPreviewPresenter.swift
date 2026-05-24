import Foundation

/// Pure value transform that turns
/// the editor's pending form state into preview data so the
/// editor view can render a live Tm→Tc table and a small preview
/// graph without re-implementing the policy evaluator.
///
/// The presenter never throws and never mutates the form state.
/// When the form is incomplete or invalid it returns rows with
/// `.invalidFormulaResult` status so the table can communicate
/// "the formula does not produce a sensible value" before the
/// user even taps Save.
enum CustomFilmEditorPreviewPresenter {

    /// Sample metered exposures (in seconds) the editor preview
    /// table renders by default. Chosen to span the typical
    /// long-exposure photography ladder — every doubling step
    /// from 1s through 5min — so the photographer can sanity-
    /// check their formula across the relevant range at a glance.
    static let defaultSampleSeconds: [Double] = [1, 2, 4, 8, 15, 30, 60, 120, 300]

    enum RowStatus: Equatable, Hashable {
        case noCorrection
        case formulaApplied
        /// Source/fitting confidence boundary: a sample
        /// whose metered exposure sits above
        /// `sourceRangeThroughSeconds` still has a corrected value
        /// (the formula keeps producing one); the status flags the
        /// reduced confidence so the table reads it as beyond the
        /// photographer's stated source range, not as a calculation
        /// stop.
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

    /// Strict parse of the form state. Empty entries fall back to
    /// documented defaults
    /// (`baseTm = baseTc = 1`, `offset = 0`, `noCorrection = 1`,
    /// `validThrough = Unlimited`) — but a non-empty unparseable
    /// entry yields `nil`, which the preview view renders as an
    /// invalid state instead of a silently-defaulted curve. This
    /// keeps the preview honest with the editor's Save guard:
    /// if Save is disabled, the preview is too.
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
        // source/fitting confidence boundary: above
        // `sourceRangeThroughSeconds` the formula still produces a
        // corrected value; only the status flips to
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
        let stopDelta = log2(tc / meteredSeconds)
        return Row(
            meteredSeconds: meteredSeconds,
            correctedSeconds: tc,
            status: isBeyondSourceRange ? .beyondSourceRange : .formulaApplied,
            stopDelta: stopDelta
        )
    }

}
