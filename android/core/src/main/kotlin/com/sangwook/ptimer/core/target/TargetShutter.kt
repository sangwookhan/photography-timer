// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.target

import kotlin.math.abs
import kotlin.math.log2

/** Why a Target Shutter comparison is unavailable. (iOS: TargetShutterUnavailableReason.) */
enum class TargetShutterUnavailableReason { inactive, noComparisonAvailable }

/** Comparison value the card evaluates the target against. (iOS: TargetShutterComparison.) */
data class TargetShutterComparison(val label: String, val seconds: Double)

/** Stop-difference comparison form. `match` is the near-zero case. */
enum class TargetShutterStopDifferenceKind { match, longerThanComparison, shorterThanComparison }

/** Resolved stop-difference the UI renders: raw signed stops + formatted label + kind. */
data class TargetShutterStopDifference(
    val stops: Double,
    val kind: TargetShutterStopDifferenceKind,
    val formattedText: String,
)

data class TargetShutterAvailableState(
    val targetSeconds: Double,
    val comparison: TargetShutterComparison?,
    val stopDifference: TargetShutterStopDifference?,
)

/** Unified display-state for the Target Shutter card. (iOS: TargetShutterDisplayState.) */
sealed interface TargetShutterDisplayState {
    data class Unavailable(val reason: TargetShutterUnavailableReason) : TargetShutterDisplayState
    data class Available(val state: TargetShutterAvailableState) : TargetShutterDisplayState
}

/**
 * Pure-value transform from raw Target Shutter inputs (target seconds +
 * active comparison form) into the display-state the card consumes.
 * Applies the canonical stop-difference formula
 * `stopDifference = log2(targetSeconds / comparisonSeconds)`; values that
 * round to zero thirds collapse to the `0 stops` match form so a tiny
 * drift never renders as `+0.00 stops`. (iOS: TargetShutterPresenter.)
 */
object TargetShutterPresenter {
    /** Threshold below which a stop difference is considered a match (compat accessor). */
    const val MATCH_EPSILON: Double = 1.0 / 24.0

    sealed interface ComparisonSource {
        /** Digital workflow — compare against Adjusted Shutter. */
        data class AdjustedShutter(val seconds: Double) : ComparisonSource

        /** Film workflow with a quantified corrected exposure. */
        data class CorrectedExposure(val seconds: Double) : ComparisonSource

        /** No comparison value is available (film limited/unsupported or calc failure). */
        data object Unavailable : ComparisonSource
    }

    fun makeDisplayState(
        targetSeconds: Double?,
        comparisonSource: ComparisonSource,
    ): TargetShutterDisplayState {
        val target = targetSeconds
        if (target == null || !target.isFinite() || target <= 0) {
            return TargetShutterDisplayState.Unavailable(TargetShutterUnavailableReason.inactive)
        }
        return when (comparisonSource) {
            is ComparisonSource.Unavailable ->
                TargetShutterDisplayState.Available(TargetShutterAvailableState(target, null, null))
            is ComparisonSource.AdjustedShutter ->
                makeAvailable(target, "Adjusted Shutter", comparisonSource.seconds)
            is ComparisonSource.CorrectedExposure ->
                makeAvailable(target, "Corrected Exposure", comparisonSource.seconds)
        }
    }

    /** Formats a raw signed stop number into the readable comparison form. */
    fun formatStopDifference(stops: Double): TargetShutterStopDifference {
        if (!stops.isFinite()) {
            return TargetShutterStopDifference(0.0, TargetShutterStopDifferenceKind.match, "0 stops")
        }
        // Match zone is "anything that rounds to 0 thirds" — the same band
        // the third-snap formatter uses, so a small drift cannot leak out
        // as a signed `+0 stops`.
        val snappedTotalThirds = maxOf(0, roundedThirds(abs(stops)))
        if (snappedTotalThirds == 0) {
            return TargetShutterStopDifference(stops, TargetShutterStopDifferenceKind.match, "0 stops")
        }
        val kind = if (stops > 0) {
            TargetShutterStopDifferenceKind.longerThanComparison
        } else {
            TargetShutterStopDifferenceKind.shorterThanComparison
        }
        return TargetShutterStopDifference(stops, kind, formattedStopText(stops))
    }

    private fun makeAvailable(
        target: Double,
        comparisonLabel: String,
        comparisonSeconds: Double,
    ): TargetShutterDisplayState {
        if (!comparisonSeconds.isFinite() || comparisonSeconds <= 0) {
            return TargetShutterDisplayState.Available(TargetShutterAvailableState(target, null, null))
        }
        val stops = log2(target / comparisonSeconds)
        return TargetShutterDisplayState.Available(
            TargetShutterAvailableState(
                targetSeconds = target,
                comparison = TargetShutterComparison(comparisonLabel, comparisonSeconds),
                stopDifference = formatStopDifference(stops),
            ),
        )
    }

    private fun formattedStopText(stops: Double): String {
        // ASCII sign + fractions: the Unicode minus (U+2212) and vulgar
        // fractions render inconsistently on Android, making the negative
        // case read as blank, so keep this plain-ASCII.
        val sign = if (stops > 0) "+" else "-"
        val snapped = snappedToThirdStop(abs(stops))
        val unit = if (snapped.isPlural) "stops" else "stop"
        return "$sign${snapped.text} $unit"
    }

    private data class SnappedThirdStop(val text: String, val isPlural: Boolean)

    private fun snappedToThirdStop(magnitude: Double): SnappedThirdStop {
        val totalThirdsInt = maxOf(0, roundedThirds(magnitude))
        val wholePart = totalThirdsInt / 3
        val text = when (totalThirdsInt % 3) {
            1 -> if (wholePart == 0) "1/3" else "$wholePart 1/3"
            2 -> if (wholePart == 0) "2/3" else "$wholePart 2/3"
            else -> "$wholePart"
        }
        return SnappedThirdStop(text, isPlural = wholePart >= 1)
    }

    /** `(value * 3)` rounded half away from zero; value is non-negative here. */
    private fun roundedThirds(value: Double): Int = kotlin.math.round(value * 3).toInt()
}
