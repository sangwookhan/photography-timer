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

    /// Best-effort parse of the form state. Mirrors the validate()
    /// parsing rules but tolerates missing optional fields (uses
    /// defaults) so the preview shows useful guidance even while
    /// the user is still typing.
    static func parse(form: CustomFilmEditorFormState) -> ParsedFormula? {
        guard let exponent = Double(form.exponentText.trimmingCharacters(in: .whitespacesAndNewlines)),
              exponent.isFinite, exponent > 0 else {
            return nil
        }
        let baseTm = parseAnchor(form.baseTmText) ?? 1.0
        let baseTc = parseAnchor(form.baseTcText) ?? 1.0
        let offset = Double(form.offsetSecondsText.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? 0.0
        let noCorrectionThrough = Double(
            form.noCorrectionThroughText.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? 1.0
        let validThrough = Double(
            form.validThroughText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard baseTm.isFinite, baseTm > 0,
              baseTc.isFinite, baseTc > 0,
              offset.isFinite,
              noCorrectionThrough.isFinite, noCorrectionThrough >= 0 else {
            return nil
        }
        if let validThrough, !(validThrough.isFinite && validThrough > noCorrectionThrough) {
            return nil
        }
        return ParsedFormula(
            exponent: exponent,
            baseTm: baseTm,
            baseTc: baseTc,
            offsetSeconds: offset,
            noCorrectionThrough: noCorrectionThrough,
            validThrough: validThrough
        )
    }

    private static func parseAnchor(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
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
