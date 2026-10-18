// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.unit.IntRect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
