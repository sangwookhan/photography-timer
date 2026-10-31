// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Enumerates inverse candidates for the selected forward rule, then verifies
/// each through the policy evaluator, including its identity safety handoffs.
/// Inventory, auxiliary choices and physical stack limits are not inputs.
public struct RequiredNDEvaluator {
    public init() {}

    public func evaluate(baseSeconds: Double, targetSeconds: Double, profile: ReciprocityProfile?) -> RequiredNDResult {
        guard baseSeconds.isFinite, baseSeconds > 0,
              targetSeconds.isFinite, targetSeconds > 0 else {
            return .unavailable(.invalidInput)
        }
        guard let profile else {
            return attenuation(metered: targetSeconds, base: baseSeconds, beyond: false)
        }
        guard var candidates = inverseCandidates(profile: profile, target: targetSeconds) else {
            return .unavailable(.numericalFailure)
        }
        let policy = ReciprocityCalculationPolicyEvaluator()
        // Preserve an exact forward match as an exact zero-stop solution;
        // analytic inverse roundoff must not turn it into a negative result.
        if policy.evaluate(profile: profile, meteredExposureSeconds: baseSeconds).correctedExposureSeconds == targetSeconds {
            candidates.insert(baseSeconds, at: 0)
        }
        let numericalFailure = candidates.contains { !$0.isFinite || $0 <= 0 }
        var solutions: [(metered: Double, beyond: Bool)] = []
        for candidate in candidates where candidate.isFinite && candidate > 0 {
            let forward = policy.evaluate(profile: profile, meteredExposureSeconds: candidate)
            guard let corrected = forward.correctedExposureSeconds,
                  close(corrected, targetSeconds),
                  !solutions.contains(where: { close($0.metered, candidate) }) else { continue }
            solutions.append((candidate, forward.metadata.rangeStatus != .withinStatedRange))
        }
        guard solutions.count <= 1 else { return .unavailable(.multipleSolutions) }
        guard let solution = solutions.first else {
            return .unavailable(numericalFailure ? .numericalFailure : .noQuantifiedInverse)
        }
        return attenuation(metered: solution.metered, base: baseSeconds, beyond: solution.beyond)
    }

    private func inverseCandidates(profile: ReciprocityProfile, target: Double) -> [Double]? {
        if let formula = profile.rules.compactMap({ rule -> ReciprocityFormula? in
            if case let .formula(value) = rule { return value.formula }
            return nil
        }).first {
            return formulaCandidates(formula, target: target)
        }
        var candidates = [target] // Any no-correction or safety-handoff solution.
        if let table = profile.rules.compactMap({ rule -> TableInterpolationReciprocityRule? in
            if case let .tableInterpolation(value) = rule { return value }
            return nil
        }).first {
            guard table.hasValidParameters else { return nil }
            let anchors = table.sortedAnchors
            let knee = TableAnchor(meteredSeconds: table.noCorrectionThroughSeconds,
                                   correctedSeconds: table.noCorrectionThroughSeconds)
            let points = [knee] + anchors
            for index in 1..<points.count {
                candidates += segmentCandidates(target: target, lower: points[index - 1],
                                                upper: points[index], extrapolate: false)
            }
            candidates += segmentCandidates(target: target, lower: anchors[anchors.count - 2],
                                            upper: anchors[anchors.count - 1], extrapolate: true)
        }
        return candidates
    }

    private func formulaCandidates(_ formula: ReciprocityFormula, target: Double) -> [Double]? {
        guard formula.hasValidParameters else { return nil }
        var candidates = [target]
        switch formula.formulaFamily {
        case .modifiedSchwarzschild:
            let power = (target - formula.offsetSeconds) / formula.coefficientSeconds
            if formula.exponent == 0 {
                let constant = formula.coefficientSeconds + formula.offsetSeconds
                if close(constant, target) {
                    // The forward shortening guard accepts a constant up to
                    // 1e-6 below metered, including just above the identity boundary.
                    candidates += interiorPoints(lower: formula.noCorrectionThroughSeconds, upper: constant + 1e-6)
                }
            } else if power > 0 {
                candidates.append(exp(log(formula.referenceMeteredTimeSeconds) + log(power) / formula.exponent))
            }
        }
        return candidates
    }

    private func attenuation(metered: Double, base: Double, beyond: Bool) -> RequiredNDResult {
        // Subtract logarithms to avoid overflowing an otherwise valid ratio.
        let stops = log2(metered) - log2(base)
        guard stops.isFinite else { return .unavailable(.numericalFailure) }
        guard stops >= 0 else { return .unavailable(.negativeAttenuation) }
        return .value(stops: stops, beyondSourceRange: beyond)
    }

    private func segmentCandidates(target: Double, lower: TableAnchor, upper: TableAnchor,
                                   extrapolate: Bool) -> [Double] {
        guard lower.meteredSeconds > 0, lower.correctedSeconds > 0 else { return [] }
        let slope = (log(upper.correctedSeconds) - log(lower.correctedSeconds))
            / (log(upper.meteredSeconds) - log(lower.meteredSeconds))
        let start = extrapolate ? upper.meteredSeconds : lower.meteredSeconds
        let end = extrapolate ? max(start, target) : upper.meteredSeconds
        if slope == 0 {
            return close(target, lower.correctedSeconds) ? interiorPoints(lower: start, upper: end) : []
        }
        let root = exp(log(lower.meteredSeconds) + (log(target) - log(lower.correctedSeconds)) / slope)
        guard root.isFinite, root >= start * (1 - 1e-10),
              extrapolate || root <= end * (1 + 1e-10) else { return [] }
        return [root]
    }

    private func interiorPoints(lower: Double, upper: Double) -> [Double] {
        guard upper > lower else { return [] }
        return [lower + (upper - lower) / 3, lower + 2 * (upper - lower) / 3]
    }

    private func close(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(abs(lhs), abs(rhs)) * 1e-10
    }
}
