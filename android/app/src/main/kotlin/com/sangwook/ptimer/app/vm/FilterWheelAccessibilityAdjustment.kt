// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterWheelRowOption
import com.sangwook.ptimer.core.exposure.FilterWheelSelection

/**
 * Platform-neutral direction for an assistive-technology adjustment of
 * one filter wheel (FILTER-A11Y-004). (iOS: `FilterWheelAdjustmentDirection`.)
 */
enum class FilterWheelAdjustmentDirection { increment, decrement }

/**
 * Result of scanning a wheel's existing row order in one direction
 * (FILTER-A11Y-004): the first available row, the nearest rejected
 * candidate when unavailable rows prevented progress, or the plain end
 * of the wheel when no candidate lay in that direction at all.
 * (iOS: `FilterWheelAdjustmentOutcome`.)
 */
sealed class FilterWheelAdjustmentOutcome {
    data class Selection(val selection: FilterWheelSelection) : FilterWheelAdjustmentOutcome()
    data class Unavailable(val rejection: FilterStackRejection) : FilterWheelAdjustmentOutcome()
    data object Boundary : FilterWheelAdjustmentOutcome()
}

/**
 * Finds the next available row for a screen reader without changing the
 * sighted picker's visible rows or its touch rejection behavior. The scan
 * skips unavailable candidates and never wraps past the end of the wheel.
 * (iOS: `FilterWheelAccessibilityAdjustment`.)
 */
object FilterWheelAccessibilityAdjustment {
    fun outcome(
        current: FilterWheelSelection,
        direction: FilterWheelAdjustmentDirection,
        options: List<FilterWheelRowOption>,
    ): FilterWheelAdjustmentOutcome {
        val currentIndex = options.indexOfFirst { it.selection == current }
        if (currentIndex < 0) {
            return FilterWheelAdjustmentOutcome.Unavailable(FilterStackRejection.unresolvedSelection)
        }
        val step = if (direction == FilterWheelAdjustmentDirection.increment) 1 else -1
        var index = currentIndex + step
        var firstRejection: FilterStackRejection? = null
        while (index in options.indices) {
            val option = options[index]
            if (option.isAvailable) return FilterWheelAdjustmentOutcome.Selection(option.selection)
            if (firstRejection == null) firstRejection = option.unavailability
            index += step
        }
        return firstRejection?.let { FilterWheelAdjustmentOutcome.Unavailable(it) }
            ?: FilterWheelAdjustmentOutcome.Boundary
    }
}
