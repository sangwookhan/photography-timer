package com.sangwook.ptimer.target

import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.roundToLong

/**
 * Compact h/m/s label for a target duration (`45s`, `3m 20s`, `2h 16m`).
 * Zero components are dropped. Mirrors iOS `TargetShutterCard.targetText`
 * / the input sheet's `formattedDuration`, so the Android card, the draft
 * readout, and the quick presets all read the same way.
 */
object TargetDurationFormat {
    fun compact(seconds: Double): String {
        val total = maxOf(1L, seconds.roundToLong())
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        val parts = buildList {
            if (h > 0) add("${h}h")
            if (m > 0) add("${m}m")
            if (s > 0) add("${s}s")
        }
        return if (parts.isEmpty()) "0s" else parts.joinToString(" ")
    }
}

/**
 * Quick target-shutter presets and the parking rule for the quick wheel.
 * Mirrors the iOS quick wheel: the photo shutter ladder at the short end,
 * then rounded long-exposure steps out to 8 hours. Shared by the UI so the
 * parking behavior (e.g. a 12m fine value parks near the 15m preset) is
 * JVM-testable rather than buried in a composable.
 */
object TargetQuickPresets {
    val seconds: List<Double> = listOf(
        1.0, 2.0, 4.0, 8.0, 15.0, 30.0,
        60.0, 120.0, 240.0, 480.0,
        900.0, 1800.0,
        3600.0, 7200.0, 14_400.0, 28_800.0,
    )

    /** Index of the preset closest to [target] on a stop (log2) scale. */
    fun nearestIndex(target: Double): Int {
        if (target <= 0 || !target.isFinite()) return 0
        return seconds.indices.minByOrNull { abs(ln(seconds[it] / target)) } ?: 0
    }
}

/** Comparison of a target shutter against the active result. */
data class TargetComparison(
    val targetSeconds: Double,
    val stopDifference: Double?,
    val isMatch: Boolean,
    val isUnavailable: Boolean,
)

/**
 * Compares a per-slot target shutter against the comparison value (the
 * digital adjusted shutter, or the film corrected exposure). Returns
 * unavailable when there is no quantified value to compare against (no
 * fabrication). Mirrors iOS `TargetShutterPresenter`.
 */
object TargetShutterPresenter {
    /** A difference within ~1/24 stop reads as a match (no signed zero). */
    const val MATCH_EPSILON: Double = 1.0 / 24.0

    fun compare(targetSeconds: Double, comparisonValue: Double?): TargetComparison {
        if (comparisonValue == null || comparisonValue <= 0 || !comparisonValue.isFinite()) {
            return TargetComparison(targetSeconds, null, isMatch = false, isUnavailable = true)
        }
        val diff = ln(targetSeconds / comparisonValue) / ln(2.0)
        return TargetComparison(targetSeconds, diff, isMatch = abs(diff) < MATCH_EPSILON, isUnavailable = false)
    }
}
