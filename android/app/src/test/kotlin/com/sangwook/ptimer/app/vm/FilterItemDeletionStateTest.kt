// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterExposureLoss
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterSetColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FILTER-ITEM-011: one-at-a-time Filter Item deletion behind a confirmation,
 * with an Edit mode that shows every row's delete control.
 */
class FilterItemDeletionStateTest {
    private val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
    private val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))

    @Test
    fun editActionAppearsOnlyWhileTheSetHasItems() {
        assertFalse(FilterItemDeletionState.showsEditAction(0))
        assertTrue(FilterItemDeletionState.showsEditAction(1))
    }

    @Test
    fun editAndDoneToggleTheRowDeleteControls() {
        val editing = FilterItemDeletionState().toggledEditing()
        assertTrue(editing.isEditing)
        assertFalse(editing.toggledEditing().isEditing)
    }

    @Test
    fun aRequestOnlyAsksForThatOneItem() {
        val asking = FilterItemDeletionState().toggledEditing().requestingDeletion(cpl)
        assertEquals("The request opens a confirmation; nothing is deleted yet.", cpl, asking.pendingItem)
        assertTrue("Asking keeps Edit mode.", asking.isEditing)
    }

    @Test
    fun aNewRequestReplacesTheTargetInsteadOfAddingOne() {
        val asking = FilterItemDeletionState().requestingDeletion(cpl).requestingDeletion(red)
        assertEquals(red, asking.pendingItem)
    }

    @Test
    fun cancelLeavesNothingToDelete() {
        val cancelled = FilterItemDeletionState().toggledEditing().requestingDeletion(red).cancelled()
        assertNull(cancelled.pendingItem)
        assertTrue("Cancel keeps Edit mode.", cancelled.isEditing)
    }

    @Test
    fun deletingOneOfSeveralItemsKeepsEditMode() {
        val state = FilterItemDeletionState().toggledEditing().afterItemsChanged(1)
        assertTrue(state.isEditing)
    }

    @Test
    fun deletingTheLastItemEndsEditModeSoALaterItemStartsOutsideIt() {
        val emptied = FilterItemDeletionState().toggledEditing().afterItemsChanged(0)
        assertFalse(emptied.isEditing)
        assertFalse("A newly added item does not inherit Edit mode.", emptied.afterItemsChanged(1).isEditing)
    }
}
