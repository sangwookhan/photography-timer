// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// How a Filter Set editor deletes its Filter Items (FILTER-ITEM-011):
/// one item at a time, always behind a confirmation. Edit shows a
/// delete control on every row; that control and the row swipe both
/// only ask, so nothing leaves the list until the user confirms.
/// Edit mode ends when the Set has no items left, so an item added
/// later does not inherit it.
public struct FilterItemDeletionState: Equatable, Sendable {
    /// Whether the row delete controls are shown.
    public private(set) var isEditing = false
    /// The item the open confirmation asks about, if any.
    public private(set) var pendingItem: FilterItem?

    public init() {}

    /// Edit/Done appears only while there is something to delete.
    public static func showsEditAction(itemCount: Int) -> Bool {
        itemCount > 0
    }

    /// Edit or Done was tapped.
    public mutating func toggleEditing() {
        isEditing.toggle()
    }

    /// A row delete control or the row swipe asked to delete `item`.
    public mutating func requestDeletion(of item: FilterItem) {
        pendingItem = item
    }

    /// Cancel or dismissal: the item and every camera stay as they are.
    public mutating func cancel() {
        pendingItem = nil
    }

    /// The user confirmed. Returns the one item to delete.
    public mutating func confirm() -> FilterItem? {
        defer { pendingItem = nil }
        return pendingItem
    }

    /// The Set's item count changed (a deletion, an addition, a move).
    public mutating func itemsDidChange(count: Int) {
        if count == 0 {
            isEditing = false
        }
    }
}
