package com.sangwook.ptimer.target

import kotlin.math.abs
import kotlin.math.ln

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
