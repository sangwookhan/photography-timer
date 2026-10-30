// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.ui.component

import kotlin.math.abs

/** A rendered frame's motion and row alignment, not a rounded row alone. */
internal data class SnapWheelSettlementFrame(
    val touchActive: Boolean,
    val scrollActive: Boolean,
    val flingActive: Boolean,
    val row: Int?,
    val firstVisibleRow: Int,
    val firstVisibleOffset: Int,
    val centerDistance: Float,
)

/** Confirms quiescence across consecutive display frames, once per touch. */
internal class SnapWheelSettlementGate {
    private var previous: SnapWheelSettlementFrame? = null
    private var completed = false

    fun observe(frame: SnapWheelSettlementFrame): Int? {
        if (completed) return null
        if (frame.touchActive || frame.scrollActive || frame.flingActive ||
            frame.row == null || abs(frame.centerDistance) > 1f) {
            previous = null
            return null
        }
        if (frame == previous) {
            completed = true
            return frame.row
        }
        previous = frame
        return null
    }
}
