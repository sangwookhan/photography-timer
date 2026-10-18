// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.round
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker

/**
 * A fold that divides the window (SHELL-061): half-open, or a hinge that
 * separates the display. [bounds] are in window pixels as the platform
 * reports them; a line-shaped fold has zero width or height.
 */
data class WindowFold(val bounds: IntRect, val isVertical: Boolean)

/**
 * Space kept clear on each side of a fold so content beside it stays
 * readable and operable, even when the fold is reported as a line.
 */
val FoldClearance = 12.dp

/**
 * The fold dividing this window, or null when there is none or it lies
 * flat. Read from the platform's reported display features, never from
 * the screen midpoint or a device name.
 */
@Composable
fun rememberWindowFold(): WindowFold? {
    val activity = LocalContext.current.findActivity() ?: return null
    val fold by produceState<WindowFold?>(initialValue = null, activity) {
        WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity).collect { info ->
            value = info.displayFeatures
                .filterIsInstance<FoldingFeature>()
                .firstOrNull { it.isSeparating }
                ?.let { feature ->
                    val b = feature.bounds
                    WindowFold(
                        bounds = IntRect(b.left, b.top, b.right, b.bottom),
                        isVertical = feature.orientation == FoldingFeature.Orientation.VERTICAL,
                    )
                }
        }
    }
    return fold
}

/** Which side of a fold [besideFold] keeps content on. */
enum class FoldSide {
    /** Left of a vertical fold, above a horizontal one. */
    Leading,

    /** Whichever side has more room. */
    Larger,
}

/**
 * Keeps this element's content on one side of [fold] instead of spanning
 * it (SHELL-061): beside a vertical fold the content is narrowed to that
 * side and centered there. An element that fills the window height
 * ([fillsHeight]) is also limited to one side of a horizontal fold;
 * shorter elements are placed by their parent clear of it. Without a fold
 * crossing the element, nothing changes.
 */
@Composable
fun Modifier.besideFold(fold: WindowFold?, side: FoldSide, fillsHeight: Boolean = false): Modifier {
    if (fold == null) return this
    var origin by remember { mutableStateOf(IntOffset.Zero) }
    return onPlaced { origin = it.positionInWindow().round() }.layout { measurable, constraints ->
        val f = fold.bounds.translate(-origin)
        val c = FoldClearance.roundToPx()
        val w = constraints.maxWidth
        val h = constraints.maxHeight
        if (fold.isVertical && constraints.hasBoundedWidth && f.left > 0 && f.right < w) {
            val leadingEnd = f.left - c
            val trailingStart = f.right + c
            val leading = side == FoldSide.Leading || leadingEnd >= w - trailingStart
            val start = if (leading) 0 else trailingStart
            val width = if (leading) leadingEnd else w - trailingStart
            val placeable = measurable.measure(constraints.copy(minWidth = 0, maxWidth = width))
            layout(w, placeable.height) { placeable.place(start + (width - placeable.width) / 2, 0) }
        } else if (!fold.isVertical && fillsHeight && constraints.hasBoundedHeight && f.top > 0 && f.bottom < h) {
            val upperEnd = f.top - c
            val lowerStart = f.bottom + c
            val upper = side == FoldSide.Leading || upperEnd >= h - lowerStart
            val top = if (upper) 0 else lowerStart
            val height = if (upper) upperEnd else h - lowerStart
            val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = height))
            layout(placeable.width, h) { placeable.place(0, top) }
        } else {
            val placeable = measurable.measure(constraints)
            layout(placeable.width, placeable.height) { placeable.place(0, 0) }
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
