// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A stack of one to four standard ND filter wheel values
/// (PTIMER-199). The stack is the domain shape behind the main
/// screen's ND wheel row: every entry is one wheel's committed value
/// in display order, and the whole stack collapses to a single
/// effective `NDStep` (the sum, in canonical stops) that feeds the
/// existing exposure calculation unchanged.
///
/// The 30-stop total limit is a DOMAIN INVARIANT of this type: every
/// construction and mutation boundary guarantees `sum ≤ 30`. The UI
/// additionally makes over-limit selections unrepresentable (wheels
/// select from ladders truncated to the remaining budget —
/// `remainingBudget(excludingWheelAt:)` +
/// `ExposureScale.ndSteps(upToStops:)`), but non-UI callers are held
/// to the same rule: `init` treats a violating stack as a programmer
/// error, and `replacingWheel(at:with:)` ignores a write that would
/// push the sum over the cap. Raw persisted values must be validated
/// BEFORE constructing a stack (the restore path rejects, it never
/// clamps).
public struct NDFilterStack: Equatable, Sendable {
    /// Maximum number of stacked filter wheels.
    public static let maximumWheelCount = 4

    /// One committed `NDStep` per wheel, in display order (1–4).
    public private(set) var entries: [NDStep]

    public init(entries: [NDStep]) {
        precondition(
            (1...Self.maximumWheelCount).contains(entries.count),
            "An ND filter stack holds 1...\(Self.maximumWheelCount) wheels."
        )
        precondition(
            entries.allSatisfy { $0.stops >= 0 },
            "ND filter wheels never hold negative stops."
        )
        precondition(
            Self.isWithinTotalLimit(entries),
            "An ND filter stack never exceeds \(ExposureScale.maximumWholeNDStops) stops in total."
        )
        self.entries = entries
    }

    /// Whether `entries` respect the 30-stop total limit (within the
    /// engine's stability epsilon). Exposed so validation layers
    /// (persistence restore) can check RAW values before attempting
    /// construction.
    public static func isWithinTotalLimit(_ entries: [NDStep]) -> Bool {
        entries.reduce(0) { $0 + $1.stops }
            <= Double(ExposureScale.maximumWholeNDStops)
                + ExposureCalculator.stabilityEpsilon
    }

    /// Single-wheel stack — the single-filter workflow's shape.
    public init(single step: NDStep = NDStep(stops: 0)) {
        self.init(entries: [step])
    }

    /// The one effective filter value the calculation consumes: the
    /// sum of every wheel in canonical stops.
    public var effectiveStep: NDStep {
        NDStep(stops: entries.reduce(0) { $0 + $1.stops })
    }

    /// Remaining stop budget available to the wheel at `index` under
    /// the 30-stop total limit: the cap minus every OTHER wheel's
    /// committed value. Feeds `ExposureScale.ndSteps(upToStops:)` to
    /// truncate that wheel's ladder.
    public func remainingBudget(excludingWheelAt index: Int) -> Double {
        precondition(entries.indices.contains(index), "Wheel index out of range.")
        let others = entries.enumerated()
            .filter { $0.offset != index }
            .reduce(0.0) { $0 + $1.element.stops }
        return Double(ExposureScale.maximumWholeNDStops) - others
    }

    // MARK: Mutations (all value-semantic)

    /// Whether another wheel can be added.
    public var canAddWheel: Bool {
        entries.count < Self.maximumWheelCount
    }

    /// Whether a wheel can be removed: more than one wheel AND at
    /// least one 0-stop wheel (wheels holding a value are never
    /// removed).
    public var canRemoveEmptyWheel: Bool {
        entries.count > 1 && entries.contains { $0.stops == 0 }
    }

    /// Appends one 0-stop wheel at the right; no-op at the maximum.
    /// A 0-stop wheel never changes `effectiveStep`.
    public func addingWheel() -> NDFilterStack {
        guard canAddWheel else {
            return self
        }
        var copy = self
        copy.entries.append(NDStep(stops: 0))
        return copy
    }

    /// Removes the 0-stop wheel at `index`; no-op for out-of-range
    /// indices, non-zero wheels, and single-wheel stacks. The
    /// overscroll gesture removes exactly the wheel it acted on
    /// (PTIMER-199 §4.2.3) — identity matters to the UI's reorder
    /// and removal animations even though zeros are value-identical.
    public func removingEmptyWheel(at index: Int) -> NDFilterStack {
        guard entries.indices.contains(index),
              entries[index].stops == 0,
              entries.count > 1 else {
            return self
        }
        var copy = self
        copy.entries.remove(at: index)
        return copy
    }

    /// Removes the rightmost 0-stop wheel; no-op when unavailable.
    public func removingRightmostEmptyWheel() -> NDFilterStack {
        guard canRemoveEmptyWheel,
              let index = entries.lastIndex(where: { $0.stops == 0 }) else {
            return self
        }
        var copy = self
        copy.entries.remove(at: index)
        return copy
    }

    /// Replaces one wheel's value. Out-of-range indices, negative or
    /// non-finite values, and writes that would push the total over
    /// the 30-stop limit are all ignored (defensive: the UI's
    /// budget-truncated ladders never produce any of these, so they
    /// are programmer-error shields for non-UI callers — every
    /// mutation boundary upholds the same invariants as `init`).
    public func replacingWheel(at index: Int, with step: NDStep) -> NDFilterStack {
        guard entries.indices.contains(index),
              step.stops >= 0,
              step.stops.isFinite else {
            return self
        }
        var copy = self
        copy.entries[index] = step
        guard Self.isWithinTotalLimit(copy.entries) else {
            return self
        }
        return copy
    }

    /// The post-commit ordering (agreed sort rule): descending by
    /// stops, 0-stop wheels rightmost, equal values keeping their
    /// existing relative order (stable). Never applied while a wheel
    /// is being scrolled; the caller triggers it on interaction end.
    /// Sorting reorders VALUES only, so `effectiveStep` is unchanged.
    public func sortedForCommit() -> NDFilterStack {
        var copy = self
        copy.entries = commitSortPermutation().map { entries[$0] }
        return copy
    }

    /// The index permutation `sortedForCommit()` applies:
    /// `permutation[i]` is the CURRENT index of the wheel that lands
    /// at position `i`. Exposed so a caller tracking per-wheel
    /// identity (for the reorder animation) can move companion state
    /// through the exact same stable sort.
    public func commitSortPermutation() -> [Int] {
        entries.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.stops != rhs.element.stops {
                    return lhs.element.stops > rhs.element.stops
                }
                return lhs.offset < rhs.offset
            }
            .map(\.offset)
    }
}

extension ExposureScale {
    /// The scale's ND ladder truncated FROM THE TOP to `maxStops`
    /// (PTIMER-199 budget truncation). Top-truncation preserves the
    /// remaining rows' indices, so a wheel whose ladder shrinks keeps
    /// its selected row without jumping. Fractional presets above the
    /// budget drop out naturally.
    public func ndSteps(upToStops maxStops: Double) -> [NDStep] {
        ndSteps.filter { $0.stops <= maxStops + ExposureCalculator.stabilityEpsilon }
    }
}
