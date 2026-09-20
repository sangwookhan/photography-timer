// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit

/// FILTER-PLUS-001: tap adds, a stationary long press manages, and a
/// vertical drag browses; crossing the drag threshold cancels the long
/// press for good.
final class FilterSourcePlusGestureArbiterTests: XCTestCase {
    private func arbiter() -> FilterSourcePlusGestureArbiter {
        FilterSourcePlusGestureArbiter(settledIndex: 1, sourceCount: 3)
    }

    func testPressThenCrossingTheDragThresholdBeforeTheDeadlineBrowsesOnly() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 0, height: -2))
        XCTAssertEqual(gesture.phase, .pressing)
        XCTAssertTrue(gesture.moved(translation: CGSize(width: 0, height: -30)), "Crossing the threshold starts browsing and reports the first candidate.")
        XCTAssertEqual(gesture.phase, .browsing)
        XCTAssertEqual(gesture.candidateIndex, 2)
        XCTAssertFalse(gesture.deadlineElapsed(), "A deadline reached after the drag won never opens management.")
        XCTAssertEqual(gesture.phase, .browsing)
        XCTAssertEqual(gesture.released(), .addBrowsed(index: 2), "The changed final source adds exactly once on release.")
    }

    func testReturningToTheStartingSourceAddsNothing() {
        var gesture = arbiter()
        XCTAssertTrue(gesture.moved(translation: CGSize(width: 0, height: -30)))
        XCTAssertEqual(gesture.candidateIndex, 2)
        XCTAssertTrue(gesture.moved(translation: CGSize(width: 0, height: -4)), "Back over the starting source.")
        XCTAssertEqual(gesture.candidateIndex, 1)
        XCTAssertEqual(gesture.released(), .none, "A browse that settles on its starting source adds nothing.")
    }

    func testCrossingTheThresholdThenHoldingBeyondTheDeadlineBrowsesOnly() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 0, height: 9))
        XCTAssertEqual(gesture.phase, .browsing)
        // The finger pauses well past the long press duration.
        XCTAssertFalse(gesture.deadlineElapsed())
        gesture.moved(translation: CGSize(width: 0, height: 9))
        XCTAssertEqual(gesture.phase, .browsing)
        XCTAssertEqual(gesture.released(), .none, "A short travel below one step never left the starting source, so nothing is added.")
        var farther = arbiter()
        farther.moved(translation: CGSize(width: 0, height: 30))
        XCTAssertFalse(farther.deadlineElapsed())
        XCTAssertEqual(farther.released(), .addBrowsed(index: 0), "Holding past the deadline still adds the final source, never opens management.")
    }

    func testStationaryLongPressOpensManagementAndReleaseDoesNothingMore() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 1, height: -3))
        XCTAssertTrue(gesture.deadlineElapsed())
        XCTAssertEqual(gesture.phase, .managing)
        // Movement after management opened is ignored.
        XCTAssertFalse(gesture.moved(translation: CGSize(width: 0, height: -40)))
        XCTAssertNil(gesture.candidateIndex)
        XCTAssertEqual(gesture.released(), .managed)
    }

    func testMovementPastTheStationaryToleranceCancelsTheLongPress() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 0, height: 5))
        XCTAssertEqual(gesture.phase, .unsettled)
        XCTAssertFalse(gesture.deadlineElapsed(), "A slow drag that has already left the tolerance never opens management.")
        XCTAssertEqual(gesture.released(), .none, "Neither a tap nor a browse.")

        var resumed = arbiter()
        resumed.moved(translation: CGSize(width: 0, height: 5))
        XCTAssertFalse(resumed.deadlineElapsed())
        XCTAssertTrue(resumed.moved(translation: CGSize(width: 0, height: 20)), "The slow drag may still become a browse after the deadline.")
        XCTAssertEqual(resumed.released(), .addBrowsed(index: 0))
    }

    func testOrdinaryTapAddsTheSettledSource() {
        var gesture = arbiter()
        gesture.moved(translation: .zero)
        XCTAssertEqual(gesture.released(), .add)
    }

    func testBrowsingClampsToTheSourceRangeAndReportsOnlyChanges() {
        var gesture = arbiter()
        XCTAssertTrue(gesture.moved(translation: CGSize(width: 0, height: -200)))
        XCTAssertEqual(gesture.candidateIndex, 2)
        XCTAssertFalse(gesture.moved(translation: CGSize(width: 0, height: -260)), "Clamped at the last source: no change to report.")
        XCTAssertTrue(gesture.moved(translation: CGSize(width: 0, height: 300)))
        XCTAssertEqual(gesture.candidateIndex, 0)
    }
}
