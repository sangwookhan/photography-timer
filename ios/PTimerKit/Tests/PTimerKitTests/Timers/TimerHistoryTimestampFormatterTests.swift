// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Absolute event timestamps in timer History (completed / canceled, and the
/// shared running "Ends" / paused rows) must render in the device's local time
/// zone, not UTC. Regression guard for PTIMER-146.
final class TimerHistoryTimestampFormatterTests: XCTestCase {
    @MainActor
    func testAbsoluteTimestampUsesDeviceLocalTimeZone() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        // Expected = the same stable format rendered in the device-local zone.
        let local = DateFormatter()
        local.calendar = Calendar(identifier: .gregorian)
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"

        XCTAssertEqual(viewModel.formatDateTime(date), local.string(from: date))
    }
}
