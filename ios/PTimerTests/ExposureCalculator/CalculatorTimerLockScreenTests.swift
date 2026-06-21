// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Residual app-hosted lock-screen test: the only one using the
/// ActivityKit `TimerTargetLiveActivityAttributes.ContentState`. The 11
/// lock-screen target-selection / handoff tests moved off-simulator to
/// `CalculatorTimerLockScreenTests` in PTimerKitTests.
@MainActor
final class LockScreenLiveActivityContentStateTests: XCTestCase {

    func testLockScreenScheduledTargetsCanHandOffToNextTimerWithoutAppStateRefresh() {
        let state = TimerTargetLiveActivityAttributes.ContentState(
            representativeTimerName: "30s timer",
            representativeEndDate: Date(timeIntervalSince1970: 130),
            scheduledTargets: [
                ScheduledTimerTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                    timerName: "30s timer",
                    endDate: Date(timeIntervalSince1970: 130)
                ),
                ScheduledTimerTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
                    timerName: "2m timer",
                    endDate: Date(timeIntervalSince1970: 220)
                ),
            ]
        )

        XCTAssertEqual(state.displayTarget(at: Date(timeIntervalSince1970: 120))?.timerName, "30s timer")
        XCTAssertEqual(state.displayTarget(at: Date(timeIntervalSince1970: 131))?.timerName, "2m timer")
    }
}
