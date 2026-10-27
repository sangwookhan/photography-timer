// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ReciprocityInverseFailure: Equatable, Sendable {
    case invalidInput, invalidProfile, noQuantifiedSolution, multipleSolutions, numericalFailure
}

public enum ReciprocityInverseResult: Equatable {
    case available(meteredSeconds: Double, evaluation: ReciprocityResult)
    case unavailable(ReciprocityInverseFailure)
}

/// Queries the existing forward policy without changing it. The supported
/// formula family and each log-log segment can be inverted analytically;
/// identity handoffs and flat segments are checked separately. In particular,
/// neither corrected table anchors nor custom formulas are assumed monotone.
public struct ReciprocityInverse {
    public init() {}

    public func evaluate(profile: ReciprocityProfile, targetSeconds: Double) -> ReciprocityInverseResult {
        guard targetSeconds.isFinite, targetSeconds > 0 else { return .unavailable(.invalidInput) }
        var search = Search(profile: profile, target: targetSeconds)
        // Every no-correction/clamped solution has M == T. Forward verification
        // decides whether that identity is actually active at this point.
        search.add(targetSeconds)
        if let formula = profile.rules.compactMap({ rule -> ReciprocityFormula? in
            guard case .formula(let rule) = rule else { return nil }
            return rule.formula
        }).first {
            guard formula.hasValidParameters else { return .unavailable(.invalidProfile) }
            search.formula(formula)
        } else if let table = profile.rules.compactMap({ rule -> TableInterpolationReciprocityRule? in
            guard case .tableInterpolation(let rule) = rule else { return nil }
            return rule
        }).first {
            guard table.hasValidParameters else { return .unavailable(.invalidProfile) }
            search.table(table)
        }
        return search.result
    }
}

private extension ReciprocityInverse {
    struct Search {
        let profile: ReciprocityProfile
        let target: Double
        var roots: [(Double, ReciprocityResult)] = []
        var flat = false
        var numericalFailure = false
        private let evaluator = ReciprocityCalculationPolicyEvaluator()

        init(profile: ReciprocityProfile, target: Double) {
            self.profile = profile
            self.target = target
        }

        // Floating-point round-trip tolerance, not a photographic allowance.
        func matches(_ lhs: Double, _ rhs: Double) -> Bool {
            abs(lhs - rhs) <= 64 * max(lhs.ulp, rhs.ulp)
        }

        mutating func add(_ metered: Double) {
            guard metered.isFinite, metered > 0 else { return }
            let value = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            guard let corrected = value.correctedExposureSeconds, corrected.isFinite,
                  corrected > 0, matches(corrected, target) else { return }
            guard !roots.contains(where: { matches($0.0, metered) }) else { return }
            roots.append((metered, value))
        }

        mutating func formula(_ formula: ReciprocityFormula) {
            let remainder = target - formula.offsetSeconds
            guard remainder > 0 else { return }
            if formula.exponent == 0 {
                let output = formula.coefficientSeconds + formula.offsetSeconds
                // A constant formula can match on an interval, but only above
                // its identity band and before the shortening handoff.
                let lower = formula.noCorrectionThroughSeconds
                let upper = target + 1e-6
                if matches(output, target), upper > lower {
                    let sample = lower + (upper - lower) / 2
                    let value = evaluator.evaluate(profile: profile, meteredExposureSeconds: sample)
                    flat = value.correctedExposureSeconds.map { matches($0, target) } ?? false
                }
                return
            }
            let logMetered = log(formula.referenceMeteredTimeSeconds)
                + (log(remainder) - log(formula.coefficientSeconds)) / formula.exponent
            // A raw root outside this active branch cannot survive the
            // shortening handoff. Reject it before exponentiation overflows.
            if logMetered > log(target + 1e-6) { return }
            if formula.noCorrectionThroughSeconds > 0,
               logMetered < log(formula.noCorrectionThroughSeconds) { return }
            let metered = exp(logMetered)
            guard metered.isFinite, metered > 0 else {
                numericalFailure = true
                return
            }
            // Strict formula boundary: do not widen Acros II's epsilon band.
            if metered > formula.noCorrectionThroughSeconds { add(metered) }
        }

        mutating func table(_ table: TableInterpolationReciprocityRule) {
            let anchors = table.sortedAnchors
            let knee = TableAnchor(meteredSeconds: table.noCorrectionThroughSeconds, correctedSeconds: table.noCorrectionThroughSeconds)
            let points = [knee] + anchors
            let identityLimit = table.noCorrectionThroughSeconds * (1 + ReciprocityNoCorrectionBoundary.relativeTolerance)
            for index in 1..<points.count {
                segment(points[index - 1], points[index], lower: max(points[index - 1].meteredSeconds, identityLimit), upper: points[index].meteredSeconds)
            }
            segment(anchors[anchors.count - 2], anchors[anchors.count - 1], lower: max(anchors.last!.meteredSeconds, identityLimit), upper: .infinity)
        }

        mutating func segment(_ first: TableAnchor, _ last: TableAnchor, lower: Double, upper: Double) {
            guard lower < upper else { return }
            // A zero knee is accepted by the forward validator, but log(0)
            // cannot define that segment. Other segments remain queryable.
            guard first.meteredSeconds > 0, first.correctedSeconds > 0 else { return }
            let delta = log10(last.meteredSeconds) - log10(first.meteredSeconds)
            guard delta > .ulpOfOne else { return }
            let slope = (log10(last.correctedSeconds) - log10(first.correctedSeconds)) / delta
            if slope == 0 {
                let end = min(upper, target)
                if matches(first.correctedSeconds, target), end > lower {
                    let sample = lower + (end - lower) / 2
                    let value = evaluator.evaluate(profile: profile, meteredExposureSeconds: sample)
                    if value.correctedExposureSeconds.map({ matches($0, target) }) == true { flat = true }
                }
                return
            }
            let logMetered = log10(first.meteredSeconds) + (log10(target) - log10(first.correctedSeconds)) / slope
            if lower > 0, logMetered < log10(lower) { return }
            if upper.isFinite, logMetered > log10(upper) { return }
            let metered = pow(10, logMetered)
            guard metered.isFinite, metered > 0 else {
                numericalFailure = true
                return
            }
            // The tolerance band is inclusive; the corrected curve starts
            // strictly after it. Forward-checking also rejects gap endpoints.
            if metered >= lower, metered <= upper { add(metered) }
        }

        var result: ReciprocityInverseResult {
            if flat || roots.count > 1 { return .unavailable(.multipleSolutions) }
            if numericalFailure { return .unavailable(.numericalFailure) }
            if let root = roots.first { return .available(meteredSeconds: root.0, evaluation: root.1) }
            return .unavailable(.noQuantifiedSolution)
        }
    }
}
