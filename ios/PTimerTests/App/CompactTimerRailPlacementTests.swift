// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import XCTest
@testable import PTimer

/// Side rail placement in the system side area (WORKSPACE-032..034). The
/// geometry is the iPhone Duo outer display: a 466x678pt window whose
/// 84pt side area sits beside the safe area.
final class CompactTimerRailPlacementTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 466, height: 678)
    private let cardHeight: CGFloat = 116

    func testTrailingSideAreaHoldsTheRailBelowTheStatusArea() {
        let content = CGRect(x: 0, y: 54, width: 382, height: 590)
        let rail = CompactTimerRailPlacement.placement(content: content, window: window, reserved: [], cardHeight: cardHeight)
        XCTAssertEqual(rail, CompactTimerRailPlacement(side: .trailing, minX: 382, width: 84, top: 54, height: 590))
        XCTAssertEqual(rail?.cardWidth, 72)
    }

    func testTheWiderSideWinsSoTheRailFollowsRotation() {
        let content = CGRect(x: 84, y: 20, width: 382, height: 624)
        let rail = CompactTimerRailPlacement.placement(content: content, window: window, reserved: [], cardHeight: cardHeight)
        XCTAssertEqual(rail?.side, .leading)
        XCTAssertEqual(rail?.minX, 0)
    }

    func testNoRailWhenTheSideAreaIsTooNarrowForAReadableCard() {
        let content = CGRect(x: 0, y: 54, width: 391, height: 590)
        XCTAssertNil(CompactTimerRailPlacement.placement(content: content, window: window, reserved: [], cardHeight: cardHeight))
        let phone = CGRect(x: 0, y: 62, width: 466, height: 582)
        XCTAssertNil(CompactTimerRailPlacement.placement(content: phone, window: window, reserved: [], cardHeight: cardHeight))
    }

    func testRailAvoidsAReservedRegionInTheSideArea() {
        let content = CGRect(x: 0, y: 54, width: 382, height: 590)
        let camera = CGRect(x: 400, y: 100, width: 50, height: 120)
        let rail = CompactTimerRailPlacement.placement(content: content, window: window, reserved: [camera], cardHeight: cardHeight)
        XCTAssertEqual(rail?.top, 226)
        XCTAssertEqual(rail?.height, 644 - 226)
    }

    func testReservedRegionOutsideTheSideAreaIsIgnored() {
        let content = CGRect(x: 0, y: 54, width: 382, height: 590)
        let elsewhere = CGRect(x: 100, y: 100, width: 50, height: 50)
        let rail = CompactTimerRailPlacement.placement(content: content, window: window, reserved: [elsewhere], cardHeight: cardHeight)
        XCTAssertEqual(rail?.height, 590)
    }

    func testNoRailWhenNoRunHoldsOneCard() {
        let content = CGRect(x: 0, y: 54, width: 382, height: 590)
        let tall = CGRect(x: 390, y: 120, width: 60, height: 460)
        XCTAssertNil(CompactTimerRailPlacement.placement(content: content, window: window, reserved: [tall], cardHeight: cardHeight))
    }

    func testRailShowsFewerCardsRatherThanClippingThem() {
        // Room for four cards: three items and the overflow entry.
        XCTAssertEqual(CompactTimerCardRailView.visibleCardCount(itemCount: 3, hiddenCount: 1, availableHeight: 4 * 116 + 3 * 10), 3)
        // Room for three: two items and the overflow entry for the rest.
        XCTAssertEqual(CompactTimerCardRailView.visibleCardCount(itemCount: 3, hiddenCount: 1, availableHeight: 3 * 116 + 2 * 10), 2)
        // Three items and no overflow fit three slots.
        XCTAssertEqual(CompactTimerCardRailView.visibleCardCount(itemCount: 3, hiddenCount: 0, availableHeight: 3 * 116 + 2 * 10), 3)
        // One slot: only the overflow entry.
        XCTAssertEqual(CompactTimerCardRailView.visibleCardCount(itemCount: 2, hiddenCount: 0, availableHeight: 130), 0)
    }
}
