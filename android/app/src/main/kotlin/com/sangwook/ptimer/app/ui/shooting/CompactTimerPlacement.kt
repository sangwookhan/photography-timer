// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Width of the trailing compact timer rail: one mini card plus its margins. */
val CompactTimerRailWidth = 112.dp

/** The room a camera page gets, without the content's needs. */
data class PageSpace(val width: Dp, val height: Dp)

/**
 * Whether the compact timer summary should sit in the trailing side rail
 * rather than the bottom strip (WORKSPACE-032). The bottom strip stays
 * while the content fits above it. The rail is used only when the bottom
 * strip keeps the content from fitting, moving it to the side makes it
 * fit, and at least one readable input column remains beside it.
 *
 * [bottom] and [rail] are the page's room as measured with each placement
 * for the current window. Either may be unknown; it is then estimated from
 * the other, the rail gaining at most [stripHeight] and losing [railWidth].
 * A measured room always wins over an estimate, so a rail that turns out
 * not to fit is not tried again for the same window.
 */
fun prefersSideRail(
    bottom: PageSpace?,
    rail: PageSpace?,
    needed: ShootingContentHeights,
    stripHeight: Dp,
    railWidth: Dp = CompactTimerRailWidth,
): Boolean {
    val bottomSpace = bottom
        ?: rail?.let { PageSpace(it.width + railWidth, it.height - stripHeight) }
        ?: return false
    val railSpace = rail ?: PageSpace(bottomSpace.width - railWidth, bottomSpace.height + stripHeight)
    fun fits(space: PageSpace): Boolean = shootingContentFits(
        chooseShootingArrangement(space.width, space.height, needed),
        space.height,
        needed,
    )
    if (fits(bottomSpace)) return false
    if (railSpace.width - PageSidePadding * 2 < MinShootingColumnWidth) return false
    return fits(railSpace)
}

/**
 * Whether a tabletop fold calls for the compact timers as a side rail kept
 * above the fold (WORKSPACE-032, SHELL-061/062). A bottom strip sits below
 * a tabletop fold, where it takes the room the inputs need; a rail limited
 * to the region above the fold leaves that room to them and clears the
 * fold. It is used when, with the rail, the context and results fit above
 * the fold, the inputs fit below it, and a readable column remains beside
 * the rail. All values are in the window's coordinates; [railPageHeight]
 * is the page's height with the rail instead of the strip.
 */
fun prefersTabletopRail(
    foldTop: Dp,
    foldBottom: Dp,
    pageTop: Dp,
    railPageHeight: Dp,
    railPageWidth: Dp,
    aboveFold: Dp,
    belowFold: Dp,
    clearance: Dp = FoldClearance,
): Boolean {
    if (railPageWidth - PageSidePadding * 2 < MinShootingColumnWidth) return false
    val upperRoom = foldTop - clearance - pageTop
    val lowerRoom = pageTop + railPageHeight - (foldBottom + clearance)
    return aboveFold <= upperRoom && belowFold <= lowerRoom
}
