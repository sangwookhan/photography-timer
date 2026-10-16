// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import XCTest
@testable import PTimerKit

/// FILTER-ITEM-011: one-at-a-time Filter Item deletion behind a
/// confirmation, with an Edit mode that shows every row's delete control.
final class FilterItemDeletionStateTests: XCTestCase {
    private let nd = FilterItem(name: "ND400", behavior: .fixed(FilterRegisteredValue(value: 400, unit: .filterFactor)))
    private let gnd = FilterItem(name: "Soft GND", behavior: .gnd(FilterRegisteredValue(value: 3, unit: .stops)))

    func testEditActionAppearsOnlyWhileTheSetHasItems() {
        XCTAssertFalse(FilterItemDeletionState.showsEditAction(itemCount: 0))
        XCTAssertTrue(FilterItemDeletionState.showsEditAction(itemCount: 1))
    }

    func testEditAndDoneToggleTheRowDeleteControls() {
        var state = FilterItemDeletionState()
        XCTAssertFalse(state.isEditing)
        state.toggleEditing()
        XCTAssertTrue(state.isEditing)
        state.toggleEditing()
        XCTAssertFalse(state.isEditing)
    }

    func testRequestOnlyAsksAndConfirmDeletesThatOneItem() {
        var state = FilterItemDeletionState()
        state.toggleEditing()
        state.requestDeletion(of: nd)
        XCTAssertEqual(state.pendingItem, nd, "The request opens a confirmation; nothing is deleted yet.")
        XCTAssertEqual(state.confirm(), nd)
        XCTAssertNil(state.pendingItem)
        XCTAssertTrue(state.isEditing, "Deleting one of several items keeps Edit mode.")
    }

    func testCancelDeletesNothing() {
        var state = FilterItemDeletionState()
        state.requestDeletion(of: gnd)
        state.cancel()
        XCTAssertNil(state.pendingItem)
        XCTAssertNil(state.confirm(), "After Cancel there is nothing left to delete.")
    }

    func testANewRequestReplacesTheTargetInsteadOfAddingOne() {
        var state = FilterItemDeletionState()
        state.requestDeletion(of: nd)
        state.requestDeletion(of: gnd)
        XCTAssertEqual(state.confirm(), gnd)
        XCTAssertNil(state.confirm())
    }

    func testDeletingTheLastItemEndsEditModeSoALaterItemStartsOutsideIt() {
        var state = FilterItemDeletionState()
        state.toggleEditing()
        state.itemsDidChange(count: 1)
        XCTAssertTrue(state.isEditing)
        state.itemsDidChange(count: 0)
        XCTAssertFalse(state.isEditing)
        state.itemsDidChange(count: 1)
        XCTAssertFalse(state.isEditing, "A newly added item does not inherit Edit mode.")
    }
}
