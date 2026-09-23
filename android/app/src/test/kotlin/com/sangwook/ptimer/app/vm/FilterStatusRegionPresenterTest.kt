// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FILTER-STACK-008: one region, one row, one content — rejection over
 * browsing over movement over the persistent idle summary, with the
 * Standard-only total the only state that fades.
 */
class FilterStatusRegionPresenterTest {

    private val total = "Total 8 stops"

    private val rejection = FilterRejectionNotice(
        sequence = 1,
        rejection = FilterStackRejection.exceedsTotalLimit,
    )

    private val browsing = FilterStatusLeading.BrowsingSource("NiSi kit", FilterSetColor.teal)

    private val moving = FilterStatusLeading.MovingRow(
        row = FilterWheelRowUiState(
            selection = FilterWheelSelection.Standard(3.0),
            compactValueText = "3",
            typeCategory = FilterRowTypeCategory.nd,
            contributionStops = 3.0,
            registeredStops = 3.0,
        ),
        sourceName = "Standard",
    )

    private val summary = listOf(
        FilterSourceSummaryItem(FilterSource.Standard, "Standard", 2, null),
    )

    private fun content(
        moving: FilterStatusLeading.MovingRow? = null,
        browsing: FilterStatusLeading.BrowsingSource? = null,
        rejection: FilterRejectionNotice? = null,
        idleSourceSummary: List<FilterSourceSummaryItem>? = null,
        isStandardTotalVisible: Boolean = false,
    ) = FilterStatusRegionPresenter.content(
        moving = moving,
        browsing = browsing,
        rejection = rejection,
        totalText = total,
        idleSourceSummary = idleSourceSummary,
        isStandardTotalVisible = isStandardTotalVisible,
    )

    @Test
    fun `a rejection outranks browsing and movement and holds as a warning`() {
        val result = content(
            moving = moving,
            browsing = browsing,
            rejection = rejection,
            idleSourceSummary = summary,
        )
        assertEquals(FilterStatusLeading.Rejection(rejection), result?.leading)
        assertEquals(total, result?.total)
        assertTrue(result!!.isWarning)
        assertTrue(result.isHeld)
        assertFalse(result.isSecondaryEmphasis)
    }

    @Test
    fun `browsing outranks movement and the idle summary`() {
        val result = content(moving = moving, browsing = browsing, idleSourceSummary = summary)
        assertEquals(browsing, result?.leading)
        assertTrue(result!!.isHeld)
        assertFalse(result.isWarning)
    }

    @Test
    fun `a moving wheel outranks the idle summary`() {
        val result = content(moving = moving, idleSourceSummary = summary)
        assertEquals(moving, result?.leading)
        assertTrue(result!!.isHeld)
        assertFalse(result.isSecondaryEmphasis)
    }

    @Test
    fun `the idle summary is held at secondary emphasis`() {
        val result = content(idleSourceSummary = summary, isStandardTotalVisible = true)
        assertEquals(FilterStatusLeading.IdleSummary(summary), result?.leading)
        assertTrue(result!!.isPersistentIdle)
        assertTrue(result.isSecondaryEmphasis)
    }

    @Test
    fun `a Standard-only stack shows the total alone and lets it fade`() {
        val result = content(isStandardTotalVisible = true)
        assertEquals(FilterStatusLeading.None, result?.leading)
        assertEquals(total, result?.total)
        assertFalse(result!!.isHeld)
        assertFalse(result.isPersistentIdle)
    }

    @Test
    fun `a single Standard wheel at rest shows nothing`() {
        assertNull(content())
        assertNull(content(idleSourceSummary = emptyList()))
    }
}
