// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199 M1c: content rules for the transient Total overlay —
/// stops-only formatting, the ≥ 2 wheels visibility precondition, and
/// the 30-stop Maximum marker.
final class NDStackTotalDisplayStateTests: XCTestCase {
    func testSingleWheelIsNeverAVisibleCandidate() {
        let state = NDStackTotalDisplayState(
            effectiveStep: NDStep(stops: 12),
            wheelCount: 1
        )

        XCTAssertFalse(state.isVisibleCandidate)
    }

    func testWholeSumFormatsAsInteger() {
        let state = NDStackTotalDisplayState(
            effectiveStep: NDStep(stops: 19),
            wheelCount: 3
        )

        XCTAssertEqual(state.totalStopsText, "19")
        XCTAssertTrue(state.isVisibleCandidate)
        XCTAssertFalse(state.isAtMaximum)
    }

    func testFractionalPresetSumFormatsWithOneDecimal() {
        let state = NDStackTotalDisplayState(
            effectiveStep: NDStep(stops: 13.2),
            wheelCount: 2
        )

        XCTAssertEqual(state.totalStopsText, "13.2")
    }

    func testThirtyStopSumMarksMaximum() {
        let state = NDStackTotalDisplayState(
            effectiveStep: NDStep(stops: 30),
            wheelCount: 2
        )

        XCTAssertTrue(state.isAtMaximum)
    }
}
