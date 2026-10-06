// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit

/// FILTER-PLUS-001: tap adds and a vertical drag browses; a touch that
/// leaves the stationary tolerance without browsing is neither.
final class FilterSourcePlusGestureArbiterTests: XCTestCase {
    private func arbiter() -> FilterSourcePlusGestureArbiter {
        FilterSourcePlusGestureArbiter(settledIndex: 1, sourceCount: 3)
    }

    func testPressThenCrossingTheDragThresholdBrowses() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 0, height: -2))
        XCTAssertEqual(gesture.phase, .pressing)
        XCTAssertTrue(gesture.moved(translation: CGSize(width: 0, height: -30)), "Crossing the threshold starts browsing and reports the first candidate.")
        XCTAssertEqual(gesture.phase, .browsing)
        XCTAssertEqual(gesture.candidateIndex, 2)
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

    func testATravelBelowOneStepAddsNothingAndAFartherOneAddsTheFinalSource() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 0, height: 9))
        XCTAssertEqual(gesture.phase, .browsing)
        gesture.moved(translation: CGSize(width: 0, height: 9))
        XCTAssertEqual(gesture.released(), .none, "A short travel below one step never left the starting source, so nothing is added.")
        var farther = arbiter()
        farther.moved(translation: CGSize(width: 0, height: 30))
        XCTAssertEqual(farther.released(), .addBrowsed(index: 0))
    }

    func testMovementPastTheStationaryToleranceIsNoTap() {
        var gesture = arbiter()
        gesture.moved(translation: CGSize(width: 0, height: 5))
        XCTAssertEqual(gesture.phase, .unsettled)
        XCTAssertEqual(gesture.released(), .none, "Neither a tap nor a browse.")

        var resumed = arbiter()
        resumed.moved(translation: CGSize(width: 0, height: 5))
        XCTAssertTrue(resumed.moved(translation: CGSize(width: 0, height: 20)), "The slow drag may still become a browse.")
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
