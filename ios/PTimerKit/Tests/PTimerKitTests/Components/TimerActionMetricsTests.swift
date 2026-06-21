// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

/// Focused coverage for the C8c layout-config value type: the reusable
/// TimerActionButton takes a small injected TimerActionMetrics instead of the
/// app's layout style.
final class TimerActionMetricsTests: XCTestCase {
    func testMetricsStoreValuesAndAreEquatable() {
        let result = TimerActionMetrics(diameter: 44, iconPointSize: 18)
        let sameAsResult = TimerActionMetrics(diameter: 44, iconPointSize: 18)
        let target = TimerActionMetrics(diameter: 36, iconPointSize: 17)

        XCTAssertEqual(result, sameAsResult)
        XCTAssertNotEqual(result, target)
        XCTAssertEqual(result.diameter, 44)
        XCTAssertEqual(target.iconPointSize, 17)
    }

    func testButtonStyleDistinguishesAffordances() {
        XCTAssertNotEqual(TimerActionButtonStyle.recessed, .tintedWhenEnabled)
        XCTAssertEqual(TimerActionButtonStyle.recessed, .recessed)
    }
}
