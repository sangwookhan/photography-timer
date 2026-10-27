// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct TargetNDCandidate: Equatable {
    public let stack: FilterStack
    public let remainingError: Double
    public let requiresSourceWarning: Bool
    public let isCurrent: Bool
}

public enum TargetNDSelectionResult: Equatable {
    case available(requiredStops: Double, candidate: TargetNDCandidate)
    case unavailable(TargetNDSelectionFailure)
}

public enum TargetNDSelectionFailure: Equatable {
    case invalidInput, inverse(ReciprocityInverseFailure), negativeRequiredTotal, noCombination
}

/// Pure replacement search. All ND wheels are replaced as one value; current
/// sibling ND does not consume candidate budget. Aux is resolved unchanged by
/// the shared stack validator. No intermediate calculator mutation occurs.
public struct TargetNDSelection {
    public init() {}

    public func evaluate(baseSeconds: Double, targetSeconds: Double, profile: ReciprocityProfile?, inventory: FilterInventory, context: TargetNDSelectionContext) -> TargetNDSelectionResult {
        let selectedSets = context.selectedSets
        let current = context.current
        let allowance = context.allowance
        guard baseSeconds.isFinite, baseSeconds > 0, targetSeconds.isFinite, targetSeconds > 0 else { return .unavailable(.invalidInput) }
        let metered: Double
        var inverseWarning = false
        if let profile {
            switch ReciprocityInverse().evaluate(profile: profile, targetSeconds: targetSeconds) {
            case .available(let seconds, let evaluation):
                metered = seconds
                inverseWarning = evaluation.metadata.rangeStatus != .withinStatedRange
            case .unavailable(let reason): return .unavailable(.inverse(reason))
            }
        } else { metered = targetSeconds }
        let required = log2(metered) - log2(baseSeconds)
        guard required.isFinite else { return .unavailable(.invalidInput) }
        guard required >= 0 else { return .unavailable(.negativeRequiredTotal) }
        let items = inventory.filterSets.filter { selectedSets.contains($0.id) }
            .flatMap { set in set.ndItems.map { (set.id, $0) } }
            .sorted { lhs, rhs in
                if lhs.0.rawValue != rhs.0.rawValue { return lhs.0.rawValue < rhs.0.rawValue }
                return lhs.1.id.rawValue < rhs.1.id.rawValue
            }
        var candidates: [Ranked] = []
        func consider(_ wheels: [FilterWheel]) {
            let represented = wheels.isEmpty ? [items.first.map { FilterWheel.empty(in: $0.0) } ?? .standard(NDStep(stops: 0))] : wheels
            guard let stack = FilterStack.validated(wheels: represented, auxiliaryFilters: current.auxiliaryFilters, inventory: inventory) else { return }
            let error = required - stack.effectiveStep.stops
            // Allow only arithmetic round-off at an inclusive endpoint (for
            // example 1 - 2/3); never a photographic/display-rounding margin.
            let roundoff = 4 * max(required.ulp, stack.effectiveStep.stops.ulp)
            guard error >= allowance.lowerBound - roundoff,
                  error <= allowance.upperBound + roundoff else { return }
            var warning = inverseWarning
            if let profile {
                let candidateMetered = baseSeconds * pow(2, stack.effectiveStep.stops)
                let result = ReciprocityCalculationPolicyEvaluator().evaluate(profile: profile, meteredExposureSeconds: candidateMetered)
                guard let corrected = result.correctedExposureSeconds, corrected.isFinite, corrected > 0 else { return }
                warning = warning || result.metadata.rangeStatus != .withinStatedRange
            }
            let identity = keys(stack)
            let old = keys(current)
            let counts = Dictionary(grouping: identity, by: { $0 }).mapValues(\.count)
            let oldCounts = Dictionary(grouping: old, by: { $0 }).mapValues(\.count)
            let changes = Set(counts.keys).union(oldCounts.keys).reduce(0) {
                $0 + abs((counts[$1] ?? 0) - (oldCounts[$1] ?? 0))
            }
            candidates.append(Ranked(candidate: TargetNDCandidate(stack: stack.sortedForCommit(inventory: inventory), remainingError: error, requiresSourceWarning: warning, isCurrent: identity == old), keys: identity, changes: changes))
        }
        if items.isEmpty {
            for stop in 0...30 { consider([.standard(NDStep(stops: Double(stop)))]) }
        } else {
            let limit = FilterStack.wheelLimit(hasAuxiliaryFilters: !current.auxiliaryFilters.isEmpty)
            func search(_ start: Int, _ wheels: [FilterWheel], _ used: Set<FilterItemID>) {
                consider(wheels)
                guard wheels.count < limit, start < items.count else { return }
                for index in start..<items.count {
                    let (source, item) = items[index]
                    guard !used.contains(item.id) else { continue }
                    let wheel = FilterWheel(source: .filterSet(source), selection: .item(.init(itemID: item.id, choice: .fixed)))
                    search(index + 1, wheels + [wheel], used.union([item.id]))
                }
            }
            search(0, [], [])
        }
        guard let best = candidates.map({ abs($0.candidate.remainingError) }).min() else { return .unavailable(.noCombination) }
        let equivalent = candidates.filter {
            let roundoff = 8 * max(required.ulp, $0.candidate.stack.effectiveStep.stops.ulp)
            return abs($0.candidate.remainingError) <= best + 0.1 + roundoff
        }
        let chosen = equivalent.sorted {
            if $0.keys.count != $1.keys.count { return $0.keys.count < $1.keys.count }
            if $0.changes != $1.changes { return $0.changes < $1.changes }
            return $0.keys.lexicographicallyPrecedes($1.keys)
        }[0]
        return .available(requiredStops: required, candidate: chosen.candidate)
    }

    private struct Ranked {
        let candidate: TargetNDCandidate
        let keys: [Identity]
        let changes: Int
    }

    private func keys(_ stack: FilterStack) -> [Identity] {
        stack.wheels.compactMap { wheel -> Identity? in
            switch wheel.selection {
            case .empty: return nil
            case .standard(let value): return value.stops == 0 ? nil : .standard(value.stops)
            case .item(let selection):
                guard case .filterSet(let source) = wheel.source else { return nil }
                return .physical(source.rawValue, selection.itemID.rawValue)
            }
        }.sorted()
    }
}

private extension TargetNDSelection {
    /// Structured identity avoids delimiter collisions and decimal rounding.
    enum Identity: Hashable, Comparable {
        case standard(Double)
        case physical(String, String)

        static func < (lhs: Identity, rhs: Identity) -> Bool {
            switch (lhs, rhs) {
            case (.standard(let first), .standard(let second)): return first < second
            case (.standard, .physical): return true
            case (.physical, .standard): return false
            case (.physical(let source, let item), .physical(let otherSource, let otherItem)):
                return source == otherSource ? item < otherItem : source < otherSource
            }
        }
    }
}
