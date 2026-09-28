// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Decides what one touch on the Plus wheel means (FILTER-PLUS-001/003):
 * a tap adds the displayed source, a stationary long press opens Filter
 * Set management, and vertical travel browses sources and, on release,
 * adds exactly one wheel from the final snapped source when it differs
 * from the starting source. The three never compete: the long press may
 * complete only while the touch has stayed within the stationary
 * tolerance for its whole duration; crossing the drag activation
 * threshold cancels a pending long press at once and hands the touch to
 * browsing, after which management can never open on release, however
 * long the touch then lasts. Intermediate candidates and a return to the
 * starting source add nothing.
 *
 * Pure value: the view feeds it the touch's translation (in dp), the
 * long-press deadline, and the release, and renders what it reports.
 * (iOS: `FilterSourcePlusGestureArbiter`.)
 */
class FilterSourcePlusGestureArbiter(
    private val settledIndex: Int,
    private val sourceCount: Int,
) {

    /** How the touch is currently classified. */
    enum class Phase {
        /** Down, within the stationary tolerance, before the deadline. */
        pressing,

        /** Moved past the stationary tolerance but not yet to the drag
         *  threshold: the long press is cancelled, browsing has not
         *  started. Releasing here does nothing. */
        unsettled,

        /** Vertical drag won: browsing sources. */
        browsing,

        /** The stationary long press completed: management opened. */
        managing,
    }

    /** What the release of the touch means. */
    sealed class ReleaseOutcome {
        /** A tap: add one wheel for the displayed source. */
        data object Add : ReleaseOutcome()

        /** The browse settled on a different source: add one wheel for it. */
        data class AddBrowsed(val index: Int) : ReleaseOutcome()

        /** Management already opened during the press; nothing more. */
        data object Managed : ReleaseOutcome()

        /** Neither a tap nor a changed browse (a browse that returned to
         *  its starting source ends here). */
        data object None : ReleaseOutcome()
    }

    var phase: Phase = Phase.pressing
        private set

    /** The browsed source index while [phase] is [Phase.browsing]. */
    var candidateIndex: Int? = null
        private set

    private var maxTravel: Float = 0f

    /**
     * The touch moved by [dx] / [dy] **in dp** from its down point.
     * Returns true when the browsed candidate changed (the view reports
     * it and plays the selection haptic).
     */
    fun moved(dx: Float, dy: Float): Boolean {
        maxTravel = maxOf(maxTravel, abs(dy), abs(dx))
        when (phase) {
            Phase.managing -> return false
            Phase.pressing, Phase.unsettled -> when {
                maxTravel >= BROWSE_THRESHOLD_DP -> phase = Phase.browsing
                maxTravel > STATIONARY_TOLERANCE_DP -> {
                    phase = Phase.unsettled
                    return false
                }
                else -> return false
            }
            Phase.browsing -> Unit
        }
        // Drag up reveals the next source, drag down the previous one,
        // mirroring a wheel's row travel.
        val steps = (-dy / STEP_DISTANCE_DP).roundToInt()
        val next = (settledIndex + steps).coerceIn(0, (sourceCount - 1).coerceAtLeast(0))
        if (next == candidateIndex) return false
        candidateIndex = next
        return true
    }

    /**
     * The long-press deadline elapsed. Returns true when management
     * should open: only while the touch is still a stationary press.
     */
    fun deadlineElapsed(): Boolean {
        if (phase != Phase.pressing) return false
        phase = Phase.managing
        return true
    }

    /** The touch ended. */
    fun released(): ReleaseOutcome = when (phase) {
        Phase.managing -> ReleaseOutcome.Managed
        Phase.browsing -> candidateIndex
            ?.takeIf { it != settledIndex }
            ?.let { ReleaseOutcome.AddBrowsed(it) }
            ?: ReleaseOutcome.None
        Phase.pressing -> ReleaseOutcome.Add
        Phase.unsettled -> ReleaseOutcome.None
    }

    companion object {
        /** Hold duration for the management long press. */
        const val LONG_PRESS_MILLIS: Long = 500

        /** Movement the long press tolerates; beyond it the press can no
         *  longer complete as a long press. */
        const val STATIONARY_TOLERANCE_DP: Float = 4f

        /** Movement at which the touch becomes a browse (drag activation). */
        const val BROWSE_THRESHOLD_DP: Float = 8f

        /** Vertical travel per source step while browsing. */
        const val STEP_DISTANCE_DP: Float = 26f
    }
}
