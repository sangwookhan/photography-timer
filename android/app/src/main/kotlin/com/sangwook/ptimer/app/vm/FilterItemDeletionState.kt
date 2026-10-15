// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItem

/**
 * How a Filter Set editor deletes its Filter Items (FILTER-ITEM-011): one
 * item at a time, always behind a confirmation. Edit shows a delete control
 * on every row; that control and the row swipe both only ask, so nothing
 * leaves the list until the user confirms. Edit mode ends when the Set has
 * no items left, so an item added later does not inherit it.
 * (iOS: `FilterItemDeletionState`.)
 */
data class FilterItemDeletionState(
    /** Whether the row delete controls are shown. */
    val isEditing: Boolean = false,
    /** The item the open confirmation asks about, if any. */
    val pendingItem: FilterItem? = null,
) {
    /** Edit or Done was tapped. */
    fun toggledEditing(): FilterItemDeletionState = copy(isEditing = !isEditing)

    /** A row delete control or the row swipe asked to delete [item]. */
    fun requestingDeletion(item: FilterItem): FilterItemDeletionState = copy(pendingItem = item)

    /** Cancel or dismissal: the item and every camera stay as they are. */
    fun cancelled(): FilterItemDeletionState = copy(pendingItem = null)

    /** The Set's item count changed (a deletion, an addition, a move). */
    fun afterItemsChanged(count: Int): FilterItemDeletionState =
        if (count == 0) copy(isEditing = false) else this

    companion object {
        /** Edit/Done appears only while there is something to delete. */
        fun showsEditAction(itemCount: Int): Boolean = itemCount > 0
    }
}
