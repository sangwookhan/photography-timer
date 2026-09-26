// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterWheelRowOption
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.ResolvedFilterRow
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * FILTER-A11Y-004: the assistive scan skips unavailable rows, commits the
 * first available one, never wraps, and reports the actual rejection that
 * blocked it (or a plain boundary when nothing lay in that direction).
 */
class FilterWheelAccessibilityAdjustmentTest {

    private fun itemRow(id: String, unavailability: FilterStackRejection?): FilterWheelRowOption {
        val selection = FilterWheelSelection.Item(
            FilterRowSelection(FilterItemId(id), FilterRowChoice.Fixed),
        )
        return FilterWheelRowOption(
            row = ResolvedFilterRow(selection, 0.0, 0.0, null),
            unavailability = unavailability,
        )
    }

    private val emptyRow = FilterWheelRowOption(
        row = ResolvedFilterRow(FilterWheelSelection.Empty, 0.0, 0.0, null),
        unavailability = null,
    )

    private fun outcome(
        current: FilterWheelSelection,
        direction: FilterWheelAdjustmentDirection,
        options: List<FilterWheelRowOption>,
    ) = FilterWheelAccessibilityAdjustment.outcome(current, direction, options)

    @Test
    fun skipsUnavailableRowsAndCommitsTheFirstAvailableOne() {
        val options = listOf(
            emptyRow,
            itemRow("a", FilterStackRejection.itemAlreadyMounted),
            itemRow("b", FilterStackRejection.exceedsTotalLimit),
            itemRow("c", null),
        )
        assertEquals(
            FilterWheelAdjustmentOutcome.Selection(options[3].selection),
            outcome(FilterWheelSelection.Empty, FilterWheelAdjustmentDirection.increment, options),
        )
    }

    @Test
    fun reportsTheNearestRejectionWhenUnavailableRowsBlockTheWholeDirection() {
        val options = listOf(
            emptyRow,
            itemRow("a", FilterStackRejection.itemAlreadyMounted),
            itemRow("b", FilterStackRejection.exceedsTotalLimit),
        )
        assertEquals(
            FilterWheelAdjustmentOutcome.Unavailable(FilterStackRejection.itemAlreadyMounted),
            outcome(FilterWheelSelection.Empty, FilterWheelAdjustmentDirection.increment, options),
        )
    }

    @Test
    fun theEndOfTheWheelIsAPlainBoundaryAndNeverWraps() {
        val options = listOf(emptyRow, itemRow("a", null))
        assertEquals(
            FilterWheelAdjustmentOutcome.Boundary,
            outcome(options[1].selection, FilterWheelAdjustmentDirection.increment, options),
        )
        assertEquals(
            FilterWheelAdjustmentOutcome.Boundary,
            outcome(FilterWheelSelection.Empty, FilterWheelAdjustmentDirection.decrement, options),
        )
    }

    @Test
    fun decrementScansBackwardFromTheCurrentRow() {
        val options = listOf(
            emptyRow,
            itemRow("a", null),
            itemRow("b", FilterStackRejection.itemAlreadyMounted),
            itemRow("c", null),
        )
        assertEquals(
            FilterWheelAdjustmentOutcome.Selection(options[1].selection),
            outcome(options[3].selection, FilterWheelAdjustmentDirection.decrement, options),
        )
    }

    @Test
    fun anUnresolvedCurrentSelectionReportsItsOwnReason() {
        assertEquals(
            FilterWheelAdjustmentOutcome.Unavailable(FilterStackRejection.unresolvedSelection),
            outcome(FilterWheelSelection.Empty, FilterWheelAdjustmentDirection.increment, listOf(itemRow("a", null))),
        )
    }
}
