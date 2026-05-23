import Foundation

/// Samples the formula graph's calculation curve — the identity
/// segment through the no-correction zone joined to the formula
/// segment past the no-correction upper bound. Pure value sampler:
/// no state, all inputs arrive through the `Inputs` struct.
///
/// Hosts the formula arithmetic + log-space interpolation helpers
/// the presenter also needs at tier-selection and effective-
/// no-correction-bound time; those callers reach them through the
/// `static` surface so the sampler stays the single home for
/// every formula-curve calculation.
struct FilmModeDetailsGraphCurveSampler {

    struct Inputs {
        let rule: FormulaReciprocityRule
        let profile: ReciprocityProfile
        let currentMeteredExposureSeconds: Double
        let tierUpperBoundSeconds: Double
        let viewportLowerBoundSeconds: Double
        let noCorrectionRangeUpperBoundSeconds: Double?
    }

    /// Source path drawn by the formula graph: identity (Tc = Tm)
    /// inside the no-correction zone, then the formula curve past
    /// the no-correction upper bound. The two segments join at
    /// the threshold so the curve does not appear to cut off at
    /// the edge of the green band — the green band reads as the
    /// policy zone *covered* by the identity portion of the same
    /// curve, not as a missing chunk of the formula prediction.
    ///
    /// Identity segment runs from the viewport's effective lower
    /// bound to the no-correction upper bound. Formula segment
    /// runs from the formula rule's domain up to the canonical
    /// upper sample. The threshold seam point appears at most
    /// once (the formula's first sample is anchored at the
    /// threshold so its (Tm, Tc) equals (threshold, threshold)
    /// for every catalog profile).
    func sourcePoints(_ inputs: Inputs) -> [FilmModeDetailsGraphPoint] {
        let formulaPoints = formulaSegmentPoints(
            for: inputs.rule,
            profile: inputs.profile,
            currentMeteredExposureSeconds: inputs.currentMeteredExposureSeconds,
            tierUpperBoundSeconds: inputs.tierUpperBoundSeconds
        )

        let identityPoints = identitySegmentPoints(
            viewportLowerBoundSeconds: inputs.viewportLowerBoundSeconds,
            noCorrectionRangeUpperBoundSeconds: inputs.noCorrectionRangeUpperBoundSeconds
        )

        // If the identity segment's last sample lands on the same
        // point as the formula segment's first sample (the
        // threshold seam), drop the duplicate so the stroked path
        // does not double-back over a single x.
        guard let lastIdentity = identityPoints.last,
              let firstFormula = formulaPoints.first else {
            return identityPoints + formulaPoints
        }
        let isSamePoint = abs(lastIdentity.meteredExposureSeconds - firstFormula.meteredExposureSeconds) < 1e-6
            && abs(lastIdentity.correctedExposureSeconds - firstFormula.correctedExposureSeconds) < 1e-6
        if isSamePoint {
            return identityPoints + formulaPoints.dropFirst()
        }
        return identityPoints + formulaPoints
    }

    /// Identity (Tc = Tm) samples for the no-correction segment of
    /// the calculation curve. Returns an empty array when the
    /// profile has no no-correction zone or when the zone has no
    /// visible width inside the active viewport.
    private func identitySegmentPoints(
        viewportLowerBoundSeconds: Double,
        noCorrectionRangeUpperBoundSeconds: Double?
    ) -> [FilmModeDetailsGraphPoint] {
        guard let upper = noCorrectionRangeUpperBoundSeconds,
              upper.isFinite,
              upper > 0,
              viewportLowerBoundSeconds > 0,
              viewportLowerBoundSeconds < upper else {
            return []
        }
        let sampleCount = 6
        return (0..<sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let metered = Self.logInterpolatedValue(
                minimum: viewportLowerBoundSeconds,
                maximum: upper,
                progress: progress
            )
            return FilmModeDetailsGraphPoint(
                meteredExposureSeconds: metered,
                correctedExposureSeconds: metered
            )
        }
    }

    private func formulaSegmentPoints(
        for rule: FormulaReciprocityRule,
        profile: ReciprocityProfile,
        currentMeteredExposureSeconds: Double,
        tierUpperBoundSeconds: Double
    ) -> [FilmModeDetailsGraphPoint] {
        // Anchor the formula curve to the formula's own supported
        // zone. When a threshold rule defines a no-correction range
        // (e.g. Provia 100F's 0…128 s), the curve must not extend
        // through that range or it reads as the active prediction
        // there. The view shades the no-correction region separately
        // so the zone left of the curve reads as policy-controlled.
        let thresholdCandidates = Self.profileThresholdUpperBounds(in: profile)
        let lowerBoundCandidates: [Double?] = [
            rule.meteredRange?.minimumSeconds,
            thresholdCandidates.min(),
            // Legacy fallback for formula profiles that carry neither
            // an explicit meteredRange nor a threshold rule. Keeps the
            // curve at 1 s when both anchors above are nil.
            (rule.meteredRange?.minimumSeconds == nil && thresholdCandidates.isEmpty) ? 1 : nil,
        ]
        // When no explicit meteredRange is defined, use a canonical practical range
        // so the graph shows a stable reference viewport rather than auto-scaling
        // tightly around the current input.
        let canonicalUpperBoundSeconds: Double = 120
        let upperBoundCandidates = [
            rule.meteredRange?.maximumSeconds,
            canonicalUpperBoundSeconds,
            currentMeteredExposureSeconds,
        ]

        let positiveLowerBound = lowerBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()
        let positiveUpperBound = upperBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()

        guard let lowerBound = positiveLowerBound,
              let upperBound = positiveUpperBound else {
            return []
        }

        // Clamp the curve's upper sample to the active tier so the
        // formula does not produce off-screen samples that distort
        // the y-range or push the curve into multi-day territory.
        // Likewise floor the lower sample at the tier lower bound
        // (1 s) so no sample sits at the left-edge clamp position
        // pretending to be a 1 s value.
        let tierClampedUpperBound = min(upperBound, tierUpperBoundSeconds)
        let tierClampedLowerBound = max(lowerBound, FilmModeDetailsGraphScaleTier.t1.lowerBoundSeconds)
        let clampedLowerBound = min(tierClampedLowerBound, tierClampedUpperBound)
        let clampedUpperBound = max(tierClampedLowerBound, tierClampedUpperBound)
        let sampleCount = 24

        return (0..<sampleCount).compactMap { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let meteredExposureSeconds = Self.logInterpolatedValue(
                minimum: clampedLowerBound,
                maximum: clampedUpperBound,
                progress: progress
            )

            guard let correctedExposureSeconds = Self.formulaCorrectedExposureSeconds(
                for: rule.formula,
                meteredExposureSeconds: meteredExposureSeconds
            ),
            correctedExposureSeconds.isFinite,
            correctedExposureSeconds > 0 else {
                return nil
            }

            return FilmModeDetailsGraphPoint(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds
            )
        }
    }

    // MARK: - Formula arithmetic helpers (shared with the presenter)

    static func profileThresholdUpperBounds(in profile: ReciprocityProfile) -> [Double] {
        profile.rules.compactMap { rule -> Double? in
            guard case let .threshold(thresholdRule) = rule else {
                return nil
            }
            return thresholdRule.noCorrectionRange.maximumSeconds
        }
    }

    static func formulaCorrectedExposureSeconds(
        for formula: ReciprocityFormula,
        meteredExposureSeconds: Double
    ) -> Double? {
        guard meteredExposureSeconds.isFinite,
              meteredExposureSeconds > 0 else {
            return nil
        }

        switch formula.kind {
        case .exponentPower:
            let coefficient = formula.coefficient ?? 1
            let offsetSeconds = formula.offsetSeconds ?? 0
            return (coefficient * pow(meteredExposureSeconds, formula.exponent)) + offsetSeconds
        }
    }

    static func logInterpolatedValue(
        minimum: Double,
        maximum: Double,
        progress: Double
    ) -> Double {
        let minimumLog = log10(minimum)
        let maximumLog = log10(maximum)
        return pow(10, minimumLog + ((maximumLog - minimumLog) * progress))
    }

    static func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        })
    }
}
