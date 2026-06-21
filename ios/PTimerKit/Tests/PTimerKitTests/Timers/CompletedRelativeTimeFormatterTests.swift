// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

final class CompletedRelativeTimeFormatterTests: XCTestCase {
    func testFormatterSupportsRequiredMinuteAndHourStrings() {
        let formatter = CompletedRelativeTimeFormatter()
        let completedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(15)),
            "just now"
        )
        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(60)),
            "1 min ago"
        )
        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(180)),
            "3 min ago"
        )
        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(3_600)),
            "1 hr ago"
        )
        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(10_800)),
            "3 hr ago"
        )
        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(86_400)),
            "1 day ago"
        )
        XCTAssertEqual(
            formatter.string(from: completedAt, relativeTo: completedAt.addingTimeInterval(172_800)),
            "2 days ago"
        )
        XCTAssertEqual(
            formatter.compactString(from: completedAt, relativeTo: completedAt.addingTimeInterval(240)),
            "4m ago"
        )
        XCTAssertEqual(
            formatter.compactString(from: completedAt, relativeTo: completedAt.addingTimeInterval(3_540)),
            "59m ago"
        )
        XCTAssertEqual(
            formatter.compactString(from: completedAt, relativeTo: completedAt.addingTimeInterval(3_600)),
            "1h ago"
        )
        XCTAssertEqual(
            formatter.compactString(from: completedAt, relativeTo: completedAt.addingTimeInterval(86_400)),
            "1d ago"
        )
        XCTAssertEqual(
            formatter.compactString(from: completedAt, relativeTo: completedAt.addingTimeInterval(172_800)),
            "2d ago"
        )
    }

    func testNextRefreshDateAdvancesAtNextDisplayBoundary() {
        let formatter = CompletedRelativeTimeFormatter()
        let completedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            formatter.nextRefreshDate(
                from: completedAt,
                relativeTo: completedAt.addingTimeInterval(15)
            ),
            completedAt.addingTimeInterval(60)
        )
        XCTAssertEqual(
            formatter.nextRefreshDate(
                from: completedAt,
                relativeTo: completedAt.addingTimeInterval(61)
            ),
            completedAt.addingTimeInterval(120)
        )
        XCTAssertEqual(
            formatter.nextRefreshDate(
                from: completedAt,
                relativeTo: completedAt.addingTimeInterval(3_601)
            ),
            completedAt.addingTimeInterval(7_200)
        )
    }
}
