// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Fold-aligned placement (SHELL-061/062), in page pixels. The blocks are
 * the busy page's measured heights at 420dpi on the Fold8 inner display.
 */
class FoldPlacementTest {
    private val busy = BlockHeights(header = 148, inputs = 998, results = 426)
    private val light = BlockHeights(header = 148, inputs = 798, results = 168)

    private fun place(fold: IntRect, vertical: Boolean, width: Int, height: Int, blocks: BlockHeights) =
        foldPlacement(
            fold = fold,
            isVertical = vertical,
            pageWidth = width,
            pageHeight = height,
            blocks = blocks,
            sidePadding = 42,
            clearance = 32,
            minColumnWidth = 861,
            maxColumnWidth = 1575,
            stackGap = 21,
        )

    @Test
    fun bookPutsTheColumnsAgainstTheReportedFold() {
        val book = place(IntRect(1038, 0, 1038, 1848), vertical = true, width = 2448, height = 1500, blocks = busy)
        assertEquals(FoldPlacement.Book(leadingStart = 42, leadingWidth = 964, trailingStart = 1070, trailingWidth = 1336), book)
    }

    @Test
    fun bookFollowsAnOffCenterFoldRatherThanTheMidpoint() {
        val book = place(IntRect(1300, 0, 1340, 1848), vertical = true, width = 2448, height = 1500, blocks = busy)
                as FoldPlacement.Book
        assertEquals(1300 - 32, book.leadingStart + book.leadingWidth)
        assertEquals(1340 + 32, book.trailingStart)
    }

    @Test
    fun noBookWhenOneSideIsTooNarrowForAReadableColumn() {
        assertNull(place(IntRect(800, 0, 800, 1848), vertical = true, width = 2448, height = 1500, blocks = busy))
    }

    @Test
    fun noBookWhenTheLeadingBlocksAreTallerThanThePage() {
        assertNull(place(IntRect(1038, 0, 1038, 1848), vertical = true, width = 2448, height = 1100, blocks = busy))
    }

    @Test
    fun tabletopPutsTheInputsBelowTheFold() {
        val tabletop = place(IntRect(0, 1273, 1848, 1273), vertical = false, width = 1848, height = 2164, blocks = light)
        assertEquals(FoldPlacement.Tabletop(columnStart = 136, columnWidth = 1575, lowerTop = 1305), tabletop)
    }

    @Test
    fun noTabletopWhenTheInputsDoNotFitBelowTheFold() {
        assertNull(place(IntRect(0, 1273, 1848, 1273), vertical = false, width = 1848, height = 1849, blocks = busy))
    }

    @Test
    fun noTabletopWhenTheContextAndResultsDoNotFitAboveTheFold() {
        assertNull(place(IntRect(0, 500, 1848, 500), vertical = false, width = 1848, height = 2164, blocks = busy))
    }

    @Test
    fun aFoldOutsideThePageIsIgnored() {
        assertNull(place(IntRect(0, 2300, 1848, 2300), vertical = false, width = 1848, height = 2164, blocks = light))
        assertNull(place(IntRect(2500, 0, 2500, 1848), vertical = true, width = 2448, height = 1500, blocks = busy))
    }

    // Tabletop with the compact timers kept above the fold (dp, the Fold8
    // inner display at 420dpi turned to portrait with the fold reported at
    // the panel centre: fold 466.3dp, page top 52.2dp, page height with the
    // rail 804.6dp, width with the rail 592dp).

    private fun prefersRail(width: Dp = 592.dp, above: Dp, below: Dp) = prefersTabletopRail(
        foldTop = 466.3.dp,
        foldBottom = 466.3.dp,
        pageTop = 52.2.dp,
        railPageHeight = 804.6.dp,
        railPageWidth = width,
        aboveFold = above,
        belowFold = below,
    )

    @Test
    fun tabletopUsesTheRailAboveTheFoldWhenTheInputsThenFitBelowIt() {
        // Default page: 266.7dp above, 264dp below.
        assertTrue(prefersRail(above = 266.7.dp, below = 264.dp))
    }

    @Test
    fun noTabletopRailWhenTheInputsStillDoNotFitBelowTheFold() {
        // Busy page: 380.2dp of inputs against 378.5dp below the fold.
        assertFalse(prefersRail(above = 314.7.dp, below = 380.2.dp))
    }

    @Test
    fun noTabletopRailWhenTheContextAndResultsDoNotFitAboveTheFold() {
        assertFalse(prefersRail(above = 410.dp, below = 264.dp))
    }

    @Test
    fun noTabletopRailWithoutAReadableColumnBesideIt() {
        assertFalse(prefersRail(width = 350.dp, above = 266.7.dp, below = 264.dp))
    }
}
