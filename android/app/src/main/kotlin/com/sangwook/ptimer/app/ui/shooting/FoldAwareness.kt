// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
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

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
