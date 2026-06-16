import Foundation
import PTimerCore

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
public enum CustomFilmEditorPreviewPresenter {

    /// Sample metered exposures (in seconds) the editor preview
    /// table renders by default. A compact 5-row ladder spanning
    /// the long-exposure photography range so the photographer
    /// can scan the formula at decade boundaries without the
    /// table dominating the editor screen.
    public static let defaultSampleSeconds: [Double] = [1, 10, 60, 300, 1_000]

    /// Three representative samples (1s, 10s, 1m) used by the
    /// Formula card's inline Live Check block. Smaller set than
    /// `defaultSampleSeconds` so the live numeric feedback fits
    /// next to the formula inputs without duplicating the full
    /// Preview table.
    public static let liveCheckSampleSeconds: [Double] = [1, 10, 60]

    public enum RowStatus: Equatable, Hashable {
        case noCorrection
        case formulaApplied
        /// Table input kind (PTIMER-178): the corrected value came
        /// from log-log interpolation of the photographer's anchor
        /// rows. Reuses the Details surface's "Table-derived"
        /// vocabulary so the preview and runtime never disagree.
        case tableApplied
        /// Source/fitting confidence boundary: a sample whose
        /// metered exposure sits above `sourceRangeThroughSeconds`
        /// still has a corrected value (the formula keeps
        /// producing one); the status flags the reduced confidence
        /// so the table reads it as beyond the photographer's
        /// stated source range, not as a calculation stop.
        case beyondSourceRange
        case invalidFormulaResult

        public var displayLabel: String {
            switch self {
            case .noCorrection: return "No correction"
            case .formulaApplied: return "Formula applied"
            case .tableApplied: return "Table-derived"
            case .beyondSourceRange: return "Beyond source range"
            case .invalidFormulaResult: return "Invalid formula result"
            }
        }
    }

    public struct Row: Equatable, Hashable {
        public let meteredSeconds: Double
        /// `nil` only for `.invalidFormulaResult` rows so the view
        /// does not render a misleading numeric corrected value
        /// when the formula did not legitimately produce one.
        /// `.beyondSourceRange` rows still carry a numeric value
        /// — the formula keeps producing one past the
        /// source-range boundary; the status flags reduced
        /// confidence rather than a missing calculation.
        public let correctedSeconds: Double?
        public let status: RowStatus
        /// Optional stop delta between Tm and Tc, populated when
        /// the formula produced a finite positive Tc — including
        /// `.beyondSourceRange` rows.
        public let stopDelta: Double?
        public init(meteredSeconds: Double, correctedSeconds: Double?, status: RowStatus, stopDelta: Double?) {
            self.meteredSeconds = meteredSeconds
            self.correctedSeconds = correctedSeconds
            self.status = status
            self.stopDelta = stopDelta
        }
    }

    /// Numeric coefficients extracted from the form state. `nil`
    /// when the exponent (the only required formula field) cannot
    /// be parsed, in which case the presenter still returns rows
    /// but every row is `.invalidFormulaResult`.
    public struct ParsedFormula: Equatable {
        public let exponent: Double
        /// Photographer-entered metered-exposure anchor. Defaults
        /// to 1s when the form field is blank.
        public let baseTm: Double
        /// Photographer-entered corrected-exposure anchor.
        public let baseTc: Double
        public let offsetSeconds: Double
        public let noCorrectionThrough: Double
        public let validThrough: Double?
        public init(exponent: Double, baseTm: Double, baseTc: Double, offsetSeconds: Double, noCorrectionThrough: Double, validThrough: Double?) {
            self.exponent = exponent
            self.baseTm = baseTm
            self.baseTc = baseTc
            self.offsetSeconds = offsetSeconds
            self.noCorrectionThrough = noCorrectionThrough
            self.validThrough = validThrough
        }
    }

    /// Field-level reason the editor preview cannot render. Returned
    /// by `diagnose(form:)` so the view can swap the row table for a
    /// single recovery-oriented message instead of repeating
    /// "Invalid formula result" once per sample row.
    public enum InvalidReason: Equatable, Hashable {
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
        public var displayMessage: String {
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
    public static func diagnose(form: CustomFilmEditorFormState) -> InvalidReason? {
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
    public static func parse(form: CustomFilmEditorFormState) -> ParsedFormula? {
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
    public static func rows(
        form: CustomFilmEditorFormState,
        samples: [Double] = defaultSampleSeconds
    ) -> [Row] {
        let parsed = parse(form: form)
        return samples.map { row(for: $0, parsed: parsed) }
    }

    // MARK: - Table input kind (PTIMER-178)

    /// Multiplier applied past the last anchor for the single
    /// beyond-source sample row, so the preview demonstrates the
    /// reduced-confidence extrapolation state without the
    /// photographer hunting for an input.
    static let tableBeyondSourceSampleMultiplier: Double = 4

    /// Preview rows for the table input kind: one row per anchor
    /// (each must reproduce the entered Tc exactly — interpolation
    /// passes through every anchor) plus one beyond-source sample
    /// past the last anchor. Empty when the rows do not yet form a
    /// valid table; the editor shows `tableDiagnosisMessage` in
    /// that state instead.
    public static func tableRows(form: CustomFilmEditorFormState) -> [Row] {
        guard let rule = form.parsedTableInterpolationRule() else { return [] }
        let anchors = rule.sortedAnchors
        var samples = anchors.map(\.meteredSeconds)
        samples.append(rule.sourceRangeThroughSeconds * tableBeyondSourceSampleMultiplier)
        return samples.map { metered in
            switch rule.evaluate(meteredExposureSeconds: metered) {
            case .noCorrection:
                return Row(
                    meteredSeconds: metered,
                    correctedSeconds: metered,
                    status: .noCorrection,
                    stopDelta: 0
                )
            case .withinSourceRange(let corrected):
                return Row(
                    meteredSeconds: metered,
                    correctedSeconds: corrected,
                    status: .tableApplied,
                    stopDelta: log2(corrected / metered)
                )
            case .beyondSourceRange(let corrected):
                return Row(
                    meteredSeconds: metered,
                    correctedSeconds: corrected,
                    status: .beyondSourceRange,
                    stopDelta: log2(corrected / metered)
                )
            case .invalidInput, .invalidRule:
                return Row(
                    meteredSeconds: metered,
                    correctedSeconds: nil,
                    status: .invalidFormulaResult,
                    stopDelta: nil
                )
            }
        }
    }

    /// Photographer-readable reason the table preview cannot render
    /// yet, or `nil` when `tableRows(form:)` will produce rows.
    /// Coarse on purpose — row-level wording lives on the rows
    /// themselves via `tableRowValidationReason(at:isEditing:)`.
    public static func tableDiagnosisMessage(
        form: CustomFilmEditorFormState
    ) -> String? {
        guard form.parsedTableInterpolationRule() == nil else { return nil }
        if form.parsedTableAnchors() == nil {
            return "Enter at least two valid Tm/Tc anchor rows."
        }
        return "No correction must be > 0 and below the first anchor."
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

    // MARK: - Reference points + linked-table error (PTIMER-180)

    /// One reference-points row in the formula editor. Carries the
    /// formula's corrected value at `meteredSeconds`, and — only when
    /// the row coincides with a linked reference-table anchor — the
    /// table's reference corrected time plus the formula-vs-table
    /// stop error.
    public struct ReferencePointRow: Equatable, Hashable {
        public let meteredSeconds: Double
        /// `nil` only when the formula cannot produce a value
        /// (`.invalidFormulaResult`).
        public let formulaCorrectedSeconds: Double?
        /// Linked-table reference corrected time at this metered
        /// point, or `nil` for a standard preview row that has no
        /// table anchor.
        public let referenceCorrectedSeconds: Double?
        /// `log2(formula / reference)` in stops, or `nil` when there
        /// is no reference value (or the formula value is unusable).
        public let stopError: Double?
        public let status: RowStatus

        public init(
            meteredSeconds: Double,
            formulaCorrectedSeconds: Double?,
            referenceCorrectedSeconds: Double?,
            stopError: Double?,
            status: RowStatus
        ) {
            self.meteredSeconds = meteredSeconds
            self.formulaCorrectedSeconds = formulaCorrectedSeconds
            self.referenceCorrectedSeconds = referenceCorrectedSeconds
            self.stopError = stopError
            self.status = status
        }
    }

    /// Reference-points list for the formula editor (PTIMER-180 §6).
    ///
    /// When `linkedTableAnchors` is non-empty, the table's metered
    /// anchors are merged into the standard sample ladder and each
    /// anchor row carries the table's reference corrected time and the
    /// formula-vs-table stop error. Standard rows without a matching
    /// anchor carry no reference / error. A standard sample that
    /// overlaps an anchor metered time collapses to a single
    /// table-reference row (no duplicate). With no anchors this is the
    /// standard preview (every row has `nil` reference / error), so the
    /// view renders exactly as the unlinked editor does today.
    public static func referencePointRows(
        form: CustomFilmEditorFormState,
        linkedTableAnchors: [TableAnchor],
        samples: [Double] = defaultSampleSeconds
    ) -> [ReferencePointRow] {
        let parsed = parse(form: form)
        let mergedMetered = mergedSortedMetered(
            samples: samples,
            anchorMetered: linkedTableAnchors.map(\.meteredSeconds)
        )
        return mergedMetered.map { metered in
            let formulaRow = row(for: metered, parsed: parsed)
            let reference = linkedTableAnchors
                .first { approximatelyEqualMetered($0.meteredSeconds, metered) }?
                .correctedSeconds
            let stopError: Double? = {
                guard let reference, reference > 0,
                      let formula = formulaRow.correctedSeconds, formula > 0 else {
                    return nil
                }
                return log2(formula / reference)
            }()
            return ReferencePointRow(
                meteredSeconds: metered,
                formulaCorrectedSeconds: formulaRow.correctedSeconds,
                referenceCorrectedSeconds: reference,
                stopError: stopError,
                status: formulaRow.status
            )
        }
    }

    /// Merges the standard sample ladder with linked-table anchor
    /// metered times into one ascending, de-duplicated list. Overlaps
    /// (within `approximatelyEqualMetered`) collapse to one point so a
    /// shared metered time renders a single row.
    private static func mergedSortedMetered(
        samples: [Double],
        anchorMetered: [Double]
    ) -> [Double] {
        let sorted = (samples + anchorMetered).sorted()
        var result: [Double] = []
        for value in sorted where result.last.map({ !approximatelyEqualMetered($0, value) }) ?? true {
            result.append(value)
        }
        return result
    }

    private static func approximatelyEqualMetered(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(abs(a), abs(b)) * 1e-9 + 1e-9
    }

}
