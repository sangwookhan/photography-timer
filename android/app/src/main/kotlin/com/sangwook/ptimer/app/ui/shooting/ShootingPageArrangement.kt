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
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.round

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
data class ShootingPageRoom(
    val width: Dp,
    val height: Dp,
    val needed: ShootingContentHeights,
    /** The page's top edge in the window, to place it against a fold. */
    val top: Dp = 0.dp,
    /** Height the camera and film context with the results need above a tabletop fold. */
    val aboveTabletopFold: Dp = 0.dp,
    /** Height the inputs need below a tabletop fold. */
    val belowTabletopFold: Dp = 0.dp,
)

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
 * Where a fold puts the page's blocks (SHELL-061/062), in page pixels.
 * Book: header and inputs in the leading region, results in the trailing
 * region. Tabletop: header and results above the fold, inputs below it.
 */
internal sealed interface FoldPlacement {
    data class Book(val leadingStart: Int, val leadingWidth: Int, val trailingStart: Int, val trailingWidth: Int) :
        FoldPlacement

    data class Tabletop(val columnStart: Int, val columnWidth: Int, val lowerTop: Int) : FoldPlacement
}

/** Measured natural heights of the page's blocks, in pixels. */
internal data class BlockHeights(val header: Int, val inputs: Int, val results: Int)

/**
 * The fold-aligned placement for a page of [pageWidth] x [pageHeight]
 * pixels, or null when the fold does not cross the page or the blocks
 * do not fit beside it. [fold] is in page pixels. Each region keeps
 * [clearance] from the fold, and the blocks are placed only where every
 * one of them fits whole, so nothing spans the fold.
 */
internal fun foldPlacement(
    fold: IntRect,
    isVertical: Boolean,
    pageWidth: Int,
    pageHeight: Int,
    blocks: BlockHeights,
    sidePadding: Int,
    clearance: Int,
    minColumnWidth: Int,
    maxColumnWidth: Int,
    stackGap: Int,
): FoldPlacement? {
    if (isVertical) {
        if (fold.left <= 0 || fold.right >= pageWidth) return null
        val leadingWidth = minOf(fold.left - clearance - sidePadding, maxColumnWidth)
        val trailingStart = fold.right + clearance
        val trailingWidth = minOf(pageWidth - sidePadding - trailingStart, maxColumnWidth)
        if (leadingWidth < minColumnWidth || trailingWidth < minColumnWidth) return null
        if (blocks.header + blocks.inputs > pageHeight || blocks.results > pageHeight) return null
        // The leading column sits against the fold so both columns read as
        // one spread around it.
        val leadingStart = fold.left - clearance - leadingWidth
        return FoldPlacement.Book(leadingStart, leadingWidth, trailingStart, trailingWidth)
    }
    if (fold.top <= 0 || fold.bottom >= pageHeight) return null
    val columnWidth = minOf(pageWidth - sidePadding * 2, maxColumnWidth)
    if (columnWidth < minColumnWidth) return null
    val upperBottom = fold.top - clearance
    val lowerTop = fold.bottom + clearance
    if (blocks.header + stackGap + blocks.results > upperBottom) return null
    if (lowerTop + blocks.inputs > pageHeight) return null
    return FoldPlacement.Tabletop((pageWidth - columnWidth) / 2, columnWidth, lowerTop)
}

/**
 * Lays out one camera page. Each block is composed once; its natural height
 * is measured where it is placed and remembered, and the next layout uses
 * those heights to pick the arrangement. The blocks' heights do not depend
 * on their width within the readable range (fixed-height rows and wheels),
 * so the choice settles after one pass.
 *
 * When a [fold] divides the window and the blocks fit beside it, the page
 * uses the book or tabletop placement (SHELL-061/062); otherwise it uses
 * the arrangement for its room.
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
    fold: WindowFold? = null,
    onRoom: (ShootingPageRoom) -> Unit = {},
) {
    var blocks by remember { mutableStateOf<BlockHeights?>(null) }
    // The page's position in the window, to place the fold in page pixels.
    var origin by remember { mutableStateOf(IntOffset.Zero) }
    // Last room reported, kept outside snapshot state so reporting the same
    // room again neither recomposes nor loops.
    val reported = remember { arrayOfNulls<ShootingPageRoom>(1) }
    Layout(
        content = {
            Box(Modifier.layoutId(Block.Header)) { header() }
            Box(Modifier.layoutId(Block.Inputs)) { inputs() }
            Box(Modifier.layoutId(Block.Results)) { results() }
        },
        modifier = modifier.onPlaced { origin = it.positionInWindow().round() },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val side = PageSidePadding.roundToPx()
        val gap = StackGap.roundToPx()
        val columnGap = ColumnGap.roundToPx()
        val needed = blocks?.let { neededHeights(it, gap) } ?: ShootingContentHeights.Unknown
        val headerM = measurables.first { it.layoutId == Block.Header }
        val inputsM = measurables.first { it.layoutId == Block.Inputs }
        val resultsM = measurables.first { it.layoutId == Block.Results }
        fun exactWidth(w: Int) = Constraints(minWidth = w, maxWidth = w)
        fun record(h: Placeable, i: Placeable, r: Placeable) {
            val next = BlockHeights(h.height, i.height, r.height)
            if (next != blocks) blocks = next
            val room = ShootingPageRoom(
                width = width.toDp(),
                height = availableHeight,
                needed = neededHeights(next, gap),
                top = origin.y.toDp(),
                aboveTabletopFold = (next.header + gap + next.results).toDp(),
                belowTabletopFold = next.inputs.toDp(),
            )
            if (reported[0] != room) {
                reported[0] = room
                onRoom(room)
            }
        }

        val placement = fold?.let { f ->
            blocks?.let { known ->
                foldPlacement(
                    fold = f.bounds.translate(-origin),
                    isVertical = f.isVertical,
                    pageWidth = width,
                    pageHeight = availableHeight.roundToPx(),
                    blocks = known,
                    sidePadding = side,
                    clearance = FoldClearance.roundToPx(),
                    minColumnWidth = MinShootingColumnWidth.roundToPx(),
                    maxColumnWidth = MaxSingleColumnWidth.roundToPx(),
                    stackGap = gap,
                )
            }
        }
        when (placement) {
            is FoldPlacement.Book -> {
                val h = headerM.measure(exactWidth(placement.leadingWidth))
                val i = inputsM.measure(exactWidth(placement.leadingWidth))
                val r = resultsM.measure(exactWidth(placement.trailingWidth))
                record(h, i, r)
                layout(width, maxOf(h.height + i.height, r.height)) {
                    h.place(placement.leadingStart, 0)
                    i.place(placement.leadingStart, h.height)
                    r.place(placement.trailingStart, 0)
                }
            }
            is FoldPlacement.Tabletop -> {
                val h = headerM.measure(exactWidth(placement.columnWidth))
                val i = inputsM.measure(exactWidth(placement.columnWidth))
                val r = resultsM.measure(exactWidth(placement.columnWidth))
                record(h, i, r)
                layout(width, placement.lowerTop + i.height) {
                    h.place(placement.columnStart, 0)
                    r.place(placement.columnStart, h.height + gap)
                    i.place(placement.columnStart, placement.lowerTop)
                }
            }
            null -> when (chooseShootingArrangement(width.toDp(), availableHeight, needed)) {
                ShootingArrangement.SingleColumn -> {
                    val columnWidth = minOf(width - side * 2, MaxSingleColumnWidth.roundToPx()).coerceAtLeast(0)
                    val h = headerM.measure(exactWidth(columnWidth))
                    val i = inputsM.measure(exactWidth(columnWidth))
                    val r = resultsM.measure(exactWidth(columnWidth))
                    record(h, i, r)
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
                    record(h, i, r)
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
}

private enum class Block { Header, Inputs, Results }

/** The content's needed heights in each arrangement, from its blocks. */
private fun Density.neededHeights(blocks: BlockHeights, stackGap: Int) = ShootingContentHeights(
    singleColumn = (blocks.header + blocks.inputs + stackGap + blocks.results).toDp(),
    sideBySide = (blocks.header + maxOf(blocks.inputs, blocks.results)).toDp(),
)
