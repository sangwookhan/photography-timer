// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit

/// FILTER-STACK-005: a settled-order change is presented as one
/// whole-row transition between complete arrangements; a newer order
/// mid-transition restarts toward the newest arrangement; membership
/// changes replace the row at once.
final class FilterWheelRowOrderTransitionTests: XCTestCase {
    func testOneReorderExposesOnlyTheCompleteBeforeAndAfterArrangements() {
        var transition = FilterWheelRowOrderTransition(order: [1, 2, 3])
        XCTAssertEqual(transition.orderChanged(to: [3, 1, 2]), .fadeOut)
        XCTAssertEqual(transition.displayedOrder, [1, 2, 3], "The previous arrangement stays complete while fading out.")
        XCTAssertEqual(transition.phase, .fadingOut)
        XCTAssertEqual(transition.fadeOutCompleted(), .fadeIn)
        XCTAssertEqual(transition.displayedOrder, [3, 1, 2], "The swap is the complete new arrangement, never a mix.")
        transition.fadeInCompleted()
        XCTAssertEqual(transition.phase, .settled)
    }

    func testASecondCommittedOrderDuringTheTransitionRestartsTowardTheNewest() {
        var transition = FilterWheelRowOrderTransition(order: [1, 2, 3])
        XCTAssertEqual(transition.orderChanged(to: [2, 1, 3]), .fadeOut)
        // Before the fade-out completes a newer order lands.
        XCTAssertEqual(transition.orderChanged(to: [3, 2, 1]), .fadeOut)
        XCTAssertEqual(transition.displayedOrder, [1, 2, 3], "Still the last complete arrangement that was shown.")
        XCTAssertEqual(transition.fadeOutCompleted(), .fadeIn)
        XCTAssertEqual(transition.displayedOrder, [3, 2, 1], "The intermediate order was never displayed.")

        // A newer order during the fade-in fades the row out again.
        XCTAssertEqual(transition.orderChanged(to: [1, 3, 2]), .fadeOut)
        XCTAssertEqual(transition.displayedOrder, [3, 2, 1])
        XCTAssertEqual(transition.fadeOutCompleted(), .fadeIn)
        XCTAssertEqual(transition.displayedOrder, [1, 3, 2])
    }

    func testEveryDisplayedArrangementIsACompletePermutationWithNoDuplicateSlots() {
        var transition = FilterWheelRowOrderTransition(order: [1, 2, 3, 4])
        let orders: [[Int]] = [[4, 1, 2, 3], [2, 4, 1, 3], [3, 2, 1, 4]]
        var displayed: [[Int]] = [transition.displayedOrder]
        for order in orders {
            _ = transition.orderChanged(to: order)
            displayed.append(transition.displayedOrder)
            _ = transition.fadeOutCompleted()
            displayed.append(transition.displayedOrder)
        }
        for arrangement in displayed {
            XCTAssertEqual(Set(arrangement), Set([1, 2, 3, 4]), "Every rendered arrangement owns each wheel exactly once.")
            XCTAssertEqual(arrangement.count, 4)
            XCTAssertTrue([[1, 2, 3, 4]] .contains(arrangement) || orders.contains(arrangement), "Only committed complete arrangements are ever displayed: \(arrangement)")
        }
    }

    func testMembershipChangesReplaceTheRowImmediately() {
        var transition = FilterWheelRowOrderTransition(order: [1, 2, 3])
        XCTAssertEqual(transition.orderChanged(to: [1, 2, 3, 4]), .replaceImmediately)
        XCTAssertEqual(transition.displayedOrder, [1, 2, 3, 4])
        XCTAssertEqual(transition.phase, .settled)
        XCTAssertEqual(transition.orderChanged(to: [1, 3, 4]), .replaceImmediately)
        XCTAssertEqual(transition.displayedOrder, [1, 3, 4])
    }

    func testReturningToTheDisplayedOrderMidTransitionJustFadesBackIn() {
        var transition = FilterWheelRowOrderTransition(order: [1, 2, 3])
        XCTAssertEqual(transition.orderChanged(to: [2, 1, 3]), .fadeOut)
        XCTAssertEqual(transition.orderChanged(to: [1, 2, 3]), .fadeIn)
        XCTAssertEqual(transition.displayedOrder, [1, 2, 3])
        XCTAssertEqual(transition.orderChanged(to: [1, 2, 3]), .none)
        XCTAssertEqual(transition.fadeOutCompleted(), .none)
    }
}
