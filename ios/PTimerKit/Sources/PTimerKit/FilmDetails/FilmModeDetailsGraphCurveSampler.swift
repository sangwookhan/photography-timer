// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

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
public struct FilmModeDetailsGraphCurveSampler {
    public init() {}

    public struct Inputs {
        public let rule: FormulaReciprocityRule
        public let profile: ReciprocityProfile
        public let currentMeteredExposureSeconds: Double
        public let tierUpperBoundSeconds: Double
        public let viewportLowerBoundSeconds: Double
        public let noCorrectionRangeUpperBoundSeconds: Double?
        public init(rule: FormulaReciprocityRule, profile: ReciprocityProfile, currentMeteredExposureSeconds: Double, tierUpperBoundSeconds: Double, viewportLowerBoundSeconds: Double, noCorrectionRangeUpperBoundSeconds: Double?) {
            self.rule = rule
            self.profile = profile
            self.currentMeteredExposureSeconds = currentMeteredExposureSeconds
            self.tierUpperBoundSeconds = tierUpperBoundSeconds
            self.viewportLowerBoundSeconds = viewportLowerBoundSeconds
            self.noCorrectionRangeUpperBoundSeconds = noCorrectionRangeUpperBoundSeconds
        }
    }

    /// Source path drawn by the formula graph: identity (Tc = Tm)
    /// inside the no-correction zone, then the formula curve past
    /// the no-correction upper bound. The green band reads as the
    /// policy zone *covered* by the identity portion of the same
    /// curve, not as a missing chunk of the formula prediction.
    ///
    /// Identity segment runs from the viewport's effective lower
    /// bound up to and including `noCorrectionThroughSeconds`.
    /// Formula segment starts strictly above that boundary
    /// (`noCorrectionThroughSeconds × 1.001`) and runs up to the
    /// canonical upper sample — formulas with an open boundary at
    /// the threshold (e.g. Acros II) intentionally jump from the
    /// identity line to the formula curve at the boundary, so the
    /// formula's first sample is NOT anchored at
    /// `(threshold, threshold)`. The seam-deduplication guard below
    /// still drops a duplicate point in the rare case where the two
    /// segments happen to land on the same (x, y).
    public func sourcePoints(_ inputs: Inputs) -> [FilmModeDetailsGraphPoint] {
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
        // point as the formula segment's first sample, drop the
        // duplicate so the stroked path does not double-back over a
        // single x. With the formula segment offset above the
        // threshold this case is rare in practice but the guard
        // costs nothing.
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
        // Anchor the formula curve strictly above the no-correction
        // boundary so the identity segment owns the no-correction
        // zone and the formula curve takes over past it. The 0.1 %
        // nudge survives the log-interpolation round-trip — a tighter
        // ε can collapse back to the boundary value through
        // `pow(10, log10(x))`, which lets a formula sample sneak into
        // the identity zone.
        let formulaLowerBound = rule.formula.noCorrectionThroughSeconds > 0
            ? rule.formula.noCorrectionThroughSeconds * 1.001
            : 1
        // When the formula has no published source range, use a
        // canonical practical upper bound so the graph shows a stable
        // reference viewport rather than auto-scaling tightly around
        // the current input.
        let canonicalUpperBoundSeconds: Double = 120
        let upperBoundCandidates = [
            rule.formula.sourceRangeThroughSeconds,
            canonicalUpperBoundSeconds,
            currentMeteredExposureSeconds,
        ]

        let positiveUpperBound = upperBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()

        guard let upperBound = positiveUpperBound,
              formulaLowerBound > 0 else {
            return []
        }

        // Clamp the curve's upper sample to the active tier so the
        // formula does not produce off-screen samples that distort
        // the y-range or push the curve into multi-day territory.
        // Likewise floor the lower sample at the tier lower bound
        // (1 s) so no sample sits at the left-edge clamp position
        // pretending to be a 1 s value.
        let tierClampedUpperBound = min(upperBound, tierUpperBoundSeconds)
        let tierClampedLowerBound = max(formulaLowerBound, FilmModeDetailsGraphScaleTier.t1.lowerBoundSeconds)
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

    // MARK: - Table log-log curve (PTIMER-159)

    public struct TableInputs {
        public let rule: TableInterpolationReciprocityRule
        public let profile: ReciprocityProfile
        public let currentMeteredExposureSeconds: Double
        public let tierUpperBoundSeconds: Double
        public let viewportLowerBoundSeconds: Double
        public init(rule: TableInterpolationReciprocityRule, profile: ReciprocityProfile, currentMeteredExposureSeconds: Double, tierUpperBoundSeconds: Double, viewportLowerBoundSeconds: Double) {
            self.rule = rule
            self.profile = profile
            self.currentMeteredExposureSeconds = currentMeteredExposureSeconds
            self.tierUpperBoundSeconds = tierUpperBoundSeconds
            self.viewportLowerBoundSeconds = viewportLowerBoundSeconds
        }
    }

    /// Source path for a log-log table profile: identity through the
    /// no-correction zone joined to the interpolated table curve. Mirrors
    /// `sourcePoints(_:)` so the graph view renders a table model the same
    /// way it renders a formula model.
    public func tableSourcePoints(_ inputs: TableInputs) -> [FilmModeDetailsGraphPoint] {
        let curvePoints = tableSegmentPoints(
            for: inputs.rule,
            currentMeteredExposureSeconds: inputs.currentMeteredExposureSeconds,
            tierUpperBoundSeconds: inputs.tierUpperBoundSeconds
        )
        let identityPoints = identitySegmentPoints(
            viewportLowerBoundSeconds: inputs.viewportLowerBoundSeconds,
            noCorrectionRangeUpperBoundSeconds: inputs.rule.noCorrectionThroughSeconds
        )

        guard let lastIdentity = identityPoints.last,
              let firstCurve = curvePoints.first else {
            return identityPoints + curvePoints
        }
        let isSamePoint = abs(lastIdentity.meteredExposureSeconds - firstCurve.meteredExposureSeconds) < 1e-6
            && abs(lastIdentity.correctedExposureSeconds - firstCurve.correctedExposureSeconds) < 1e-6
        if isSamePoint {
            return identityPoints + curvePoints.dropFirst()
        }
        return identityPoints + curvePoints
    }

    private func tableSegmentPoints(
        for rule: TableInterpolationReciprocityRule,
        currentMeteredExposureSeconds: Double,
        tierUpperBoundSeconds: Double
    ) -> [FilmModeDetailsGraphPoint] {
        let curveLowerBound = rule.noCorrectionThroughSeconds > 0
            ? rule.noCorrectionThroughSeconds * 1.001
            : 1
        let canonicalUpperBoundSeconds: Double = 120
        let upperBoundCandidates = [
            rule.sourceRangeThroughSeconds,
            canonicalUpperBoundSeconds,
            currentMeteredExposureSeconds,
        ]
        let positiveUpperBound = upperBoundCandidates
            .filter { $0 > 0 }
            .max()

        guard let upperBound = positiveUpperBound, curveLowerBound > 0 else {
            return []
        }

        let tierClampedUpperBound = min(upperBound, tierUpperBoundSeconds)
        let tierClampedLowerBound = max(curveLowerBound, FilmModeDetailsGraphScaleTier.t1.lowerBoundSeconds)
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
            guard let correctedExposureSeconds = Self.tableCorrectedExposureSeconds(
                for: rule,
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

    /// Corrected exposure for a table rule at a metered value, using the
    /// shared evaluator so the graph curve agrees with the policy result.
    public static func tableCorrectedExposureSeconds(
        for rule: TableInterpolationReciprocityRule,
        meteredExposureSeconds: Double
    ) -> Double? {
        switch rule.evaluate(meteredExposureSeconds: meteredExposureSeconds) {
        case .noCorrection:
            return meteredExposureSeconds
        case let .withinSourceRange(corrected), let .beyondSourceRange(corrected):
            return corrected
        case .invalidInput, .invalidRule:
            return nil
        }
    }

    /// No-correction upper bounds carried by the profile's table rules,
    /// so the graph overlay can draw the green band for a table model.
    public static func profileTableNoCorrectionUpperBounds(
        in profile: ReciprocityProfile
    ) -> [Double] {
        profile.rules.compactMap { rule -> Double? in
            guard case let .tableInterpolation(tableRule) = rule else { return nil }
            let upper = tableRule.noCorrectionThroughSeconds
            return upper > 0 ? upper : nil
        }
    }

    // MARK: - Formula arithmetic helpers (shared with the presenter)

    /// Returns the formula-owned no-correction upper bounds for the
    /// profile's formula rules. Used by the graph overlay to draw the
    /// green no-correction band even though the formula now owns its
    /// own guard (the threshold rule was retired from formula
    /// profiles in PTIMER-160).
    public static func profileFormulaNoCorrectionUpperBounds(
        in profile: ReciprocityProfile
    ) -> [Double] {
        profile.rules.compactMap { rule -> Double? in
            guard case let .formula(formulaRule) = rule else {
                return nil
            }
            let upper = formulaRule.formula.noCorrectionThroughSeconds
            return upper > 0 ? upper : nil
        }
    }

    /// Source-range upper bound for the profile's first formula rule
    /// (if any). Shared by the graph presenter so the beyond-source
    /// region matches the calculation policy.
    public static func profileFormulaSourceRangeUpperBoundSeconds(
        in profile: ReciprocityProfile
    ) -> Double? {
        for rule in profile.rules {
            if case let .formula(formulaRule) = rule {
                return formulaRule.formula.sourceRangeThroughSeconds
            }
        }
        return nil
    }

    public static func formulaCorrectedExposureSeconds(
        for formula: ReciprocityFormula,
        meteredExposureSeconds: Double
    ) -> Double? {
        guard meteredExposureSeconds.isFinite,
              meteredExposureSeconds > 0,
              formula.hasValidParameters else {
            return nil
        }
        // Exhaustive switch on the formula family so PTIMER-162's
        // future `.kronHalmContinuous` addition forces a compile
        // failure here instead of silently falling back to Modified
        // Schwarzschild.
        switch formula.formulaFamily {
        case .modifiedSchwarzschild:
            let scaled = meteredExposureSeconds / formula.referenceMeteredTimeSeconds
            let powered = pow(scaled, formula.exponent)
            return (formula.coefficientSeconds * powered) + formula.offsetSeconds
        }
    }

    public static func logInterpolatedValue(
        minimum: Double,
        maximum: Double,
        progress: Double
    ) -> Double {
        let minimumLog = log10(minimum)
        let maximumLog = log10(maximum)
        return pow(10, minimumLog + ((maximumLog - minimumLog) * progress))
    }

    public static func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        })
    }
}
