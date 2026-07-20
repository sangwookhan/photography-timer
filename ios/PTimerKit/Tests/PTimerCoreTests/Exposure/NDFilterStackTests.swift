// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

/// PTIMER-199 M1b: domain tests for `NDFilterStack` — effective sum,
/// remaining-budget math, the commit sort rule, mutations, and the
/// budget-truncated ladder helper.
final class NDFilterStackTests: XCTestCase {
    private func stack(_ stops: [Double]) -> NDFilterStack {
        NDFilterStack(entries: stops.map(NDStep.init(stops:)))
    }

    // MARK: Effective sum

    func testSingleWheelEffectiveStepIsTheWheelValue() {
        XCTAssertEqual(stack([7]).effectiveStep, NDStep(stops: 7))
    }

    func testEffectiveStepSumsAllWheels() {
        XCTAssertEqual(stack([10, 6, 3, 0]).effectiveStep, NDStep(stops: 19))
    }

    func testPresetSumProducesFractionalEffectiveStep() {
        // 6.6 + 6.6 = 13.2 — off-ladder by design; the effective value
        // is not restricted to picker entries.
        XCTAssertEqual(
            stack([6.6, 6.6]).effectiveStep.stops,
            13.2,
            accuracy: 1e-9
        )
    }

    func testZeroWheelsDoNotChangeEffectiveStep() {
        XCTAssertEqual(stack([6.6, 0, 0, 0]).effectiveStep.stops, 6.6, accuracy: 1e-9)
    }

    // MARK: Remaining budget

    func testRemainingBudgetExcludesOnlyTheGivenWheel() {
        let subject = stack([10, 6, 3])

        XCTAssertEqual(subject.remainingBudget(excludingWheelAt: 0), 21, accuracy: 1e-9)
        XCTAssertEqual(subject.remainingBudget(excludingWheelAt: 1), 17, accuracy: 1e-9)
        XCTAssertEqual(subject.remainingBudget(excludingWheelAt: 2), 14, accuracy: 1e-9)
    }

    func testRemainingBudgetForSingleWheelIsTheFullCap() {
        XCTAssertEqual(stack([12]).remainingBudget(excludingWheelAt: 0), 30, accuracy: 1e-9)
    }

    func testRemainingBudgetAtSaturationIsZero() {
        let subject = stack([30, 0])
        XCTAssertEqual(subject.remainingBudget(excludingWheelAt: 1), 0, accuracy: 1e-9)
    }

    // MARK: Ladder truncation

    func testLadderTruncationPreservesPrefixIndices() {
        let full = ExposureScale.default.ndSteps
        let truncated = ExposureScale.default.ndSteps(upToStops: 7)

        XCTAssertEqual(Array(full.prefix(truncated.count)), truncated)
        XCTAssertEqual(truncated.last, NDStep(stops: 7))
        // 6.6 stays (≤ 7); 7.6 drops.
        XCTAssertTrue(truncated.contains(NDStep(stops: 6.6)))
        XCTAssertFalse(truncated.contains(NDStep(stops: 7.6)))
    }

    func testLadderTruncationAtZeroBudgetLeavesOnlyZero() {
        XCTAssertEqual(
            ExposureScale.default.ndSteps(upToStops: 0),
            [NDStep(stops: 0)]
        )
    }

    func testLadderTruncationKeepsPresetAtExactBudget() {
        // Budget exactly 6.6: the preset itself stays selectable.
        let truncated = ExposureScale.default.ndSteps(upToStops: 6.6)
        XCTAssertEqual(truncated.last, NDStep(stops: 6.6))
    }

    // MARK: Commit sort

    func testSortDescendingWithZerosRightmost() {
        XCTAssertEqual(
            stack([0, 10, 0, 6]).sortedForCommit(),
            stack([10, 6, 0, 0])
        )
    }

    func testSortIsStableForEqualValues() {
        // Two 6.6 presets keep their relative order; positions are
        // indistinguishable by value, so stability is observable via
        // full-array equality with an interleaved distinct value.
        XCTAssertEqual(
            stack([6.6, 3, 6.6]).sortedForCommit(),
            stack([6.6, 6.6, 3])
        )
    }

    func testSortDoesNotChangeEffectiveStep() {
        let subject = stack([0, 6.6, 16.6, 3])
        XCTAssertEqual(
            subject.sortedForCommit().effectiveStep.stops,
            subject.effectiveStep.stops,
            accuracy: 1e-9
        )
    }

    // MARK: Mutations

    func testAddingWheelAppendsZeroAtRightUpToMaximum() {
        var subject = stack([10])
        subject = subject.addingWheel().addingWheel().addingWheel()

        XCTAssertEqual(subject, stack([10, 0, 0, 0]))
        XCTAssertFalse(subject.canAddWheel)
        XCTAssertEqual(subject.addingWheel(), subject, "No-op at the maximum.")
    }

    func testRemovingRightmostEmptyWheelProtectsValues() {
        let subject = stack([0, 3, 0])

        XCTAssertEqual(subject.removingRightmostEmptyWheel(), stack([0, 3]))
        XCTAssertEqual(stack([10, 6]).removingRightmostEmptyWheel(), stack([10, 6]))
        XCTAssertEqual(stack([0]).removingRightmostEmptyWheel(), stack([0]))
    }

    func testReplacingWheelIgnoresOutOfRangeIndices() {
        let subject = stack([1, 2])

        XCTAssertEqual(subject.replacingWheel(at: 5, with: NDStep(stops: 9)), subject)
        XCTAssertEqual(
            subject.replacingWheel(at: 1, with: NDStep(stops: 9)),
            stack([1, 9])
        )
    }

    // MARK: 30-stop domain invariant

    func testReplacingWheelIgnoresNegativeAndNonFiniteValues() {
        let subject = stack([1, 2])

        XCTAssertEqual(
            subject.replacingWheel(at: 0, with: NDStep(stops: -5)),
            subject,
            "Negative stops never enter the stack."
        )
        XCTAssertEqual(
            subject.replacingWheel(at: 0, with: NDStep(stops: .infinity)),
            subject
        )
        XCTAssertEqual(
            subject.replacingWheel(at: 0, with: NDStep(stops: .nan)),
            subject
        )
    }

    func testReplacingWheelIgnoresWritesBeyondTheTotalLimit() {
        let subject = stack([25, 3])

        // 25 + 6 = 31 > 30: the write is ignored, the stack unchanged.
        XCTAssertEqual(
            subject.replacingWheel(at: 1, with: NDStep(stops: 6)),
            subject
        )
        // Exactly at the cap is allowed.
        XCTAssertEqual(
            subject.replacingWheel(at: 1, with: NDStep(stops: 5)),
            stack([25, 5])
        )
    }

    func testTotalLimitValidationHelper() {
        XCTAssertTrue(NDFilterStack.isWithinTotalLimit(steps([16.6, 13])))
        XCTAssertTrue(NDFilterStack.isWithinTotalLimit(steps([30, 0])))
        XCTAssertFalse(NDFilterStack.isWithinTotalLimit(steps([16.6, 16.6])))
        XCTAssertFalse(NDFilterStack.isWithinTotalLimit(steps([30, 0.1])))
    }

    private func steps(_ stops: [Double]) -> [NDStep] {
        stops.map(NDStep.init(stops:))
    }
}
