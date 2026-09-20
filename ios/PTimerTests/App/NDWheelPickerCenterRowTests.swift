// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimer

/// FILTER-STACK-007 (spec revision d2550da8): the live candidate is the
/// row at the picker's VISUAL center, not UIKit's settled selection, so
/// the centered number and rail, the persistent label, and the status
/// text always name the same candidate while a wheel moves.
@MainActor
final class NDWheelPickerCenterRowTests: XCTestCase {
    func testNearestMidpointWins() {
        let rows: [(row: Int, midY: CGFloat)] = [(3, 14), (4, 46), (5, 78)]
        XCTAssertEqual(NDWheelPickerCenterRow.row(nearest: 46, among: rows), 4)
        XCTAssertEqual(NDWheelPickerCenterRow.row(nearest: 60, among: rows), 4, "Still closer to row 4.")
        XCTAssertEqual(NDWheelPickerCenterRow.row(nearest: 63, among: rows), 5, "Past the half-row boundary the next candidate is centered.")
        XCTAssertEqual(NDWheelPickerCenterRow.row(nearest: 0, among: rows), 3)
    }

    func testBoundaryTieResolvesToTheLowerRowExactlyOnce() {
        let rows: [(row: Int, midY: CGFloat)] = [(4, 46), (5, 78)]
        XCTAssertEqual(NDWheelPickerCenterRow.row(nearest: 62, among: rows), 4)
    }

    func testNoHostedRowsFallsBack() {
        XCTAssertNil(NDWheelPickerCenterRow.row(nearest: 46, among: []))
    }

}
