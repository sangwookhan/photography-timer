// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import XCTest
import PTimerKit

/// Focused coverage for the C8d result-row config + value API: the reusable
/// ResultValueRow takes an injected ResultRowLayout and a host-supplied value
/// color, never the app's layout style.
final class ResultValueRowTests: XCTestCase {
    func testLayoutStoresInjectedMetrics() {
        let layout = ResultRowLayout(
            labelColumnWidth: 96,
            primaryFont: .title3,
            secondsColumnWidth: 64,
            rowMinHeight: 44,
            timerAction: TimerActionMetrics(diameter: 40, iconPointSize: 17)
        )
        XCTAssertEqual(layout.labelColumnWidth, 96)
        XCTAssertEqual(layout.secondsColumnWidth, 64)
        XCTAssertEqual(layout.rowMinHeight, 44)
        XCTAssertEqual(layout.timerAction.diameter, 40)
    }

    func testValueEquatableDistinguishesCases() {
        let a = ResultValueRow.Value.duration(primary: "30s", seconds: "30s", color: .primary)
        let b = ResultValueRow.Value.duration(primary: "30s", seconds: "30s", color: .primary)
        let c = ResultValueRow.Value.status(text: "Not recommended", color: .orange)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
