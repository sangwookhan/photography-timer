import Foundation

/// Evaluator for `TableInterpolationReciprocityRule` (PTIMER-159).
///
/// Converts a manufacturer reciprocity TABLE into a corrected exposure by
/// piecewise-linear interpolation in **log10–log10** space between the
/// published anchors. Interpolation passes through every anchor exactly, so
/// Fomapan 100's official rows (1s→2s, 10s→80s, 100s→1600s) reproduce the
/// published corrected times with no fitting error.
///
/// Mirrors `ReciprocityFormula.evaluate(meteredExposureSeconds:)` so the
/// calculation policy and the graph sampler consume an identical result shape.
extension TableInterpolationReciprocityRule {

    /// Outcome of a single table evaluation. Same shape as
    /// `ReciprocityFormula.EvaluationResult` minus the formula-specific
    /// failure cases that cannot arise for a validated table.
    public enum EvaluationResult: Equatable {
        /// `Tm` sat inside the no-correction band. `Tc = Tm`.
        case noCorrection
        /// Interpolated corrected exposure within the published table range.
        case withinSourceRange(correctedExposureSeconds: Double)
        /// Corrected exposure extrapolated past the last published anchor.
        /// Carries a real value (the model never dead-ends inside the
        /// computable range); presentation classifies it as beyond source
        /// range / lower confidence.
        case beyondSourceRange(correctedExposureSeconds: Double)
        /// Metered exposure input is not a positive finite number.
        case invalidInput
        /// Rule anchors / bounds violate the safe-table contract.
        case invalidRule
    }

    /// Anchors sorted ascending by metered exposure.
    public var sortedAnchors: [TableAnchor] {
        anchors.sorted { $0.meteredSeconds < $1.meteredSeconds }
    }

    /// `true` when the rule satisfies the safe-table contract:
    /// - at least two anchors;
    /// - every metered/corrected value finite and positive;
    /// - metered values strictly ascending;
    /// - each corrected ≥ its metered (a reciprocity correction never shortens);
    /// - `noCorrectionThroughSeconds` finite, ≥ 0, and below the first anchor;
    /// - `sourceRangeThroughSeconds` finite and ≥ the last anchor's metered value.
    public var hasValidParameters: Bool {
        let sorted = sortedAnchors
        guard sorted.count >= 2 else { return false }
        guard noCorrectionThroughSeconds.isFinite, noCorrectionThroughSeconds >= 0 else { return false }
        guard sourceRangeThroughSeconds.isFinite else { return false }

        var previousMetered = -Double.greatestFiniteMagnitude
        for anchor in sorted {
            guard anchor.meteredSeconds.isFinite, anchor.meteredSeconds > 0,
                  anchor.correctedSeconds.isFinite, anchor.correctedSeconds > 0 else {
                return false
            }
            guard anchor.correctedSeconds >= anchor.meteredSeconds - 1e-6 else { return false }
            guard anchor.meteredSeconds > previousMetered else { return false }
            previousMetered = anchor.meteredSeconds
        }

        guard let first = sorted.first, let last = sorted.last else { return false }
        guard noCorrectionThroughSeconds < first.meteredSeconds else { return false }
        guard sourceRangeThroughSeconds >= last.meteredSeconds - 1e-6 else { return false }
        return true
    }

    public func evaluate(meteredExposureSeconds: Double) -> EvaluationResult {
        guard meteredExposureSeconds.isFinite, meteredExposureSeconds > 0 else {
            return .invalidInput
        }
        guard hasValidParameters else {
            return .invalidRule
        }
        if ReciprocityNoCorrectionBoundary.isWithinNoCorrection(
            meteredSeconds: meteredExposureSeconds,
            throughSeconds: noCorrectionThroughSeconds
        ) {
            return .noCorrection
        }

        let sorted = sortedAnchors
        // Lower interpolation knee is the no-correction boundary point
        // (Tc = Tm there), giving continuity from the identity band into
        // the first published anchor.
        let kneePoint = TableAnchor(
            meteredSeconds: noCorrectionThroughSeconds,
            correctedSeconds: noCorrectionThroughSeconds
        )
        let points = [kneePoint] + sorted

        let corrected: Double
        if meteredExposureSeconds <= sorted[sorted.count - 1].meteredSeconds {
            // Within published range: interpolate between the bracketing pair.
            corrected = interpolatedCorrected(
                meteredExposureSeconds: meteredExposureSeconds,
                points: points
            )
        } else {
            // Beyond the last anchor: extrapolate the final published segment.
            corrected = logLogValue(
                forMetered: meteredExposureSeconds,
                lower: sorted[sorted.count - 2],
                upper: sorted[sorted.count - 1]
            )
        }

        // Reciprocity invariant: a correction never shortens the exposure.
        let safeCorrected = max(corrected, meteredExposureSeconds)
        guard safeCorrected.isFinite, safeCorrected > 0 else {
            return .invalidRule
        }

        if meteredExposureSeconds > sourceRangeThroughSeconds {
            return .beyondSourceRange(correctedExposureSeconds: safeCorrected)
        }
        return .withinSourceRange(correctedExposureSeconds: safeCorrected)
    }

    private func interpolatedCorrected(
        meteredExposureSeconds: Double,
        points: [TableAnchor]
    ) -> Double {
        // Find the bracketing pair (points are ascending by metered).
        for index in 1..<points.count {
            let upper = points[index]
            if meteredExposureSeconds <= upper.meteredSeconds {
                return logLogValue(
                    forMetered: meteredExposureSeconds,
                    lower: points[index - 1],
                    upper: upper
                )
            }
        }
        // Unreachable for inputs within range, but fall back to the top anchor.
        return points[points.count - 1].correctedSeconds
    }

    /// Piecewise-linear interpolation in log10–log10 space between two
    /// anchors. Returns the corrected exposure for `metered`.
    private func logLogValue(
        forMetered metered: Double,
        lower: TableAnchor,
        upper: TableAnchor
    ) -> Double {
        let logMeteredLower = log10(lower.meteredSeconds)
        let logMeteredUpper = log10(upper.meteredSeconds)
        let logCorrectedLower = log10(lower.correctedSeconds)
        let logCorrectedUpper = log10(upper.correctedSeconds)

        let denominator = logMeteredUpper - logMeteredLower
        guard abs(denominator) > .ulpOfOne else {
            return upper.correctedSeconds
        }
        let slope = (logCorrectedUpper - logCorrectedLower) / denominator
        let logCorrected = logCorrectedLower + slope * (log10(metered) - logMeteredLower)
        return pow(10, logCorrected)
    }
}
