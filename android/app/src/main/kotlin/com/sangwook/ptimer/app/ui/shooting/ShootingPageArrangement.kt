// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** How a camera page places its header, shooting inputs and exposure results. */
enum class ShootingArrangement { SingleColumn, SideBySide }

/**
 * Heights the page's content needs in each arrangement, from the blocks'
 * measured natural heights (SHELL-012). Fits are decided against the room
 * the page actually gets, so the shell can compare compact-timer placements.
 */
data class ShootingContentHeights(val singleColumn: Dp, val sideBySide: Dp) {
    companion object {
        val Unknown = ShootingContentHeights(0.dp, 0.dp)
    }
}

/**
 * The room a camera page gets and the heights its content needs there,
 * reported to the shell so it can choose the compact timer placement.
 */
data class ShootingPageRoom(val width: Dp, val height: Dp, val needed: ShootingContentHeights)

/** Page side padding, shared by both arrangements. */
internal val PageSidePadding = 16.dp

/** Space between the inputs and the results when they are stacked. */
private val StackGap = 8.dp

/** Space between the inputs and results columns when side by side. */
private val ColumnGap = 24.dp

/**
 * The narrowest readable input column: the established 360dp phone page less
 * its side padding, where the filter row, wheels and notation header were
 * designed to fit. Side by side needs two of these.
 */
val MinShootingColumnWidth = 328.dp

/** Upper bound for the single column so it never stretches without limit. */
private val MaxSingleColumnWidth = 600.dp

/** Upper bound for the side-by-side pair (each column takes half). */
private val MaxSideBySideWidth = 1000.dp

/**
 * Chooses the arrangement for the given room from the content's needed
 * heights (SHELL-057/059): a bounded single column when it fits; otherwise
 * inputs and results side by side when two readable columns fit and the
 * pair fits the height. When neither fits, the arrangement that needs less
 * height is used and the caller reports the overflow.
 */
fun chooseShootingArrangement(
    width: Dp,
    height: Dp,
    needed: ShootingContentHeights,
): ShootingArrangement {
    val contentWidth = width - PageSidePadding * 2
    val sideBySidePossible = contentWidth >= MinShootingColumnWidth * 2 + ColumnGap
    return when {
        needed.singleColumn <= height -> ShootingArrangement.SingleColumn
        sideBySidePossible -> ShootingArrangement.SideBySide
        else -> ShootingArrangement.SingleColumn
    }
}

/** True when the chosen arrangement's content fits the given height. */
fun shootingContentFits(arrangement: ShootingArrangement, height: Dp, needed: ShootingContentHeights): Boolean =
    when (arrangement) {
        ShootingArrangement.SingleColumn -> needed.singleColumn <= height
        ShootingArrangement.SideBySide -> needed.sideBySide <= height
    }

/**
 * Lays out one camera page. Each block is composed once; its natural height
 * is measured where it is placed and remembered, and the next layout uses
 * those heights to pick the arrangement. The blocks' heights do not depend
 * on their width within the readable range (fixed-height rows and wheels),
 * so the choice settles after one pass.
 *
 * [availableHeight] is the room above the compact timer presence. The page
 * reports its room and needed heights through [onRoom] so the shell can
 * place the compact timers.
 */
@Composable
fun ShootingPageArrangement(
    availableHeight: Dp,
    header: @Composable () -> Unit,
    inputs: @Composable () -> Unit,
    results: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    onRoom: (ShootingPageRoom) -> Unit = {},
) {
    var needed by remember { mutableStateOf(ShootingContentHeights.Unknown) }
    // Last room reported, kept outside snapshot state so reporting the same
    // room again neither recomposes nor loops.
    val reported = remember { arrayOfNulls<ShootingPageRoom>(1) }
    Layout(
        content = {
            Box(Modifier.layoutId(Block.Header)) { header() }
            Box(Modifier.layoutId(Block.Inputs)) { inputs() }
            Box(Modifier.layoutId(Block.Results)) { results() }
        },
        modifier = modifier,
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val arrangement = chooseShootingArrangement(width.toDp(), availableHeight, needed)
        val side = PageSidePadding.roundToPx()
        val gap = StackGap.roundToPx()
        val columnGap = ColumnGap.roundToPx()
        val headerM = measurables.first { it.layoutId == Block.Header }
        val inputsM = measurables.first { it.layoutId == Block.Inputs }
        val resultsM = measurables.first { it.layoutId == Block.Results }
        fun exactWidth(w: Int) = Constraints(minWidth = w, maxWidth = w)

        when (arrangement) {
            ShootingArrangement.SingleColumn -> {
                val columnWidth = minOf(width - side * 2, MaxSingleColumnWidth.roundToPx()).coerceAtLeast(0)
                val h = headerM.measure(exactWidth(columnWidth))
                val i = inputsM.measure(exactWidth(columnWidth))
                val r = resultsM.measure(exactWidth(columnWidth))
                updateNeeded(h.height, i.height, r.height, gap) { if (it != needed) needed = it }
                val room = ShootingPageRoom(width.toDp(), availableHeight, needed)
                if (reported[0] != room) {
                    reported[0] = room
                    onRoom(room)
                }
                val total = h.height + i.height + gap + r.height
                val x = (width - columnWidth) / 2
                layout(width, total) {
                    h.place(x, 0)
                    i.place(x, h.height)
                    r.place(x, h.height + i.height + gap)
                }
            }
            ShootingArrangement.SideBySide -> {
                val pairWidth = minOf(width - side * 2, MaxSideBySideWidth.roundToPx())
                val columnWidth = (pairWidth - columnGap) / 2
                val h = headerM.measure(exactWidth(pairWidth))
                val i = inputsM.measure(exactWidth(columnWidth))
                val r = resultsM.measure(exactWidth(columnWidth))
                updateNeeded(h.height, i.height, r.height, gap) { if (it != needed) needed = it }
                val room = ShootingPageRoom(width.toDp(), availableHeight, needed)
                if (reported[0] != room) {
                    reported[0] = room
                    onRoom(room)
                }
                val total = h.height + maxOf(i.height, r.height)
                val x = (width - pairWidth) / 2
                layout(width, total) {
                    h.place(x, 0)
                    i.place(x, h.height)
                    r.place(x + columnWidth + columnGap, h.height)
                }
            }
        }
    }
}

private enum class Block { Header, Inputs, Results }

/**
 * Records the blocks' measured heights as the content's needed heights.
 * Only a change is published, so a settled layout writes nothing.
 */
private fun Density.updateNeeded(
    header: Int,
    inputs: Int,
    results: Int,
    stackGap: Int,
    publish: (ShootingContentHeights) -> Unit,
) {
    val next = ShootingContentHeights(
        singleColumn = (header + inputs + stackGap + results).toDp(),
        sideBySide = (header + maxOf(inputs, results)).toDp(),
    )
    publish(next)
}
