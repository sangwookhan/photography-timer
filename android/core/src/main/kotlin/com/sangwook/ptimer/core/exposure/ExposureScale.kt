// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import kotlin.math.abs
import kotlin.math.pow

/**
 * Granularity of one increment along an exposure scale. `oneThirdStop` is a
 * first-class step (the shipping product runs on the one-third-stop shutter
 * ladder); the ND ladder is whole stops plus three commercial fractional
 * presets in every shipping mode. `fullStop` is retained as a reserved scale
 * for tests and a future Settings preference.
 *
 * Port of iOS `ExposureScaleMode` (PTimerCore). Behavior parity.
 */
enum class ExposureScaleMode {
    FULL_STOP,
    ONE_THIRD_STOP;

    /** Stops covered by one step on this scale. */
    val stopsPerStep: Double
        get() = when (this) {
            FULL_STOP -> 1.0
            ONE_THIRD_STOP -> 1.0 / 3.0
        }
}

/** One shutter-speed entry on an exposure scale's shutter ladder. */
data class ShutterStep(val seconds: Double)

/**
 * One ND-filter entry, expressed in stops. The shipping ND picker enumerates
 * whole stops plus the three commercial fractional presets (PTIMER-209); the
 * fractional-capable type also stays reserved infrastructure for a future
 * custom / variable-ND workflow. `wholeStops` is non-null only on a whole-stop
 * boundary.
 */
data class NDStep(val stops: Double) {

    val isWholeStop: Boolean
        get() = abs(stops - stops.swiftRounded()) <= ExposureCalculator.STABILITY_EPSILON

    val wholeStops: Int?
        get() = if (isWholeStop) stops.swiftRounded().toInt() else null

    /**
     * Whether the step lies on the one-third-stop grid (0, 1/3, 2/3, 1, …).
     * Whole stops are also third-stops. Distinguishes the reserved third-stop
     * path from the PTIMER-209 commercial ND presets (6.6, 7.6, 16.6), which
     * are neither whole nor third-stop.
     */
    val isThirdStop: Boolean
        get() = abs(stops * 3 - (stops * 3).swiftRounded()) <= ExposureCalculator.STABILITY_EPSILON

    /** Count of one-third-stop increments this step represents. */
    val thirdStopCount: Int
        get() = (stops * 3).swiftRounded().toInt()

    companion object {
        /** Builds an [NDStep] from a count of one-third-stops. */
        fun fromThirdStopCount(thirds: Int): NDStep = NDStep(thirds.toDouble() / 3.0)
    }
}

/**
 * Canonical scale data for one [ExposureScaleMode]. The scale is the single
 * source of truth for "what values does the user pick from".
 */
data class ExposureScale(
    val mode: ExposureScaleMode,
    val shutterSteps: List<ShutterStep>,
    val ndSteps: List<NDStep>,
) {
    companion object {
        /** Maximum whole ND stops the calculator supports. */
        const val MAXIMUM_WHOLE_ND_STOPS: Int = 30

        /**
         * App-configured commercial fixed-ND presets: the one-decimal stop
         * values chosen to represent products that would lose materially if
         * rounded to a whole stop (PTIMER-209). These are the app's canonical
         * values, not the exact log2 of the marketed factor (`ND100` is `6.6`
         * here, not `log2(100) ≈ 6.644`). The presentation layer maps each to
         * its marketed label: `6.6 → ND100 / OD 2.0`, `7.6 → ND200 / OD 2.3`,
         * `16.6 → ND100k / OD 5.0`. These are the only non-integer values the
         * shipping ND picker exposes, and the only off-grid values eligible
         * for commercial labels and exact persistence. Parity with iOS
         * `ExposureScale.commercialFractionalNDStops`.
         */
        val commercialFractionalNDStops: List<Double> = listOf(6.6, 7.6, 16.6)

        /**
         * The shipping ND ladder: whole stops `0…MAXIMUM_WHOLE_ND_STOPS` plus
         * the commercial fractional presets, merged in numeric order so the
         * wheel reads `… 6, 6.6, 7, 7.6, 8, … 16, 16.6, 17 …`. Shared by both
         * scales so the ND ladder stays identical across modes.
         */
        val shippingNDLadder: List<NDStep> =
            ((0..MAXIMUM_WHOLE_ND_STOPS).map { it.toDouble() } + commercialFractionalNDStops)
                .sorted()
                .map { NDStep(it) }

        /** Default full-stop scale; shares the shipping ND ladder. */
        val fullStop: ExposureScale = ExposureScale(
            mode = ExposureScaleMode.FULL_STOP,
            shutterSteps = ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS.map { ShutterStep(it) },
            ndSteps = shippingNDLadder,
        )

        /** Densified shutter ladder (55 entries) paired with the shared ND ladder. */
        val oneThirdStop: ExposureScale = ExposureScale(
            mode = ExposureScaleMode.ONE_THIRD_STOP,
            shutterSteps = oneThirdStopShutterSteps(ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS),
            ndSteps = shippingNDLadder,
        )

        /** The shipping calculator scale. */
        val default: ExposureScale = oneThirdStop

        /** Canonical [NDStep] for a whole-stop value. */
        fun ndStep(forWholeStops: Int): NDStep = NDStep(forWholeStops.toDouble())

        /**
         * The canonical commercial preset stop value matching [matching] within
         * the stability epsilon, or `null` when it is not one of the supported
         * presets. Keeps the fixed product set a domain invariant: exact
         * persistence and commercial notation labels apply only to these values,
         * and a near-match is normalized to the canonical value rather than kept
         * as a drifting [Double]. Parity with iOS `commercialNDPresetStop`.
         */
        fun commercialNDPresetStop(matching: Double): Double? =
            commercialFractionalNDStops.firstOrNull {
                abs(it - matching) <= ExposureCalculator.STABILITY_EPSILON
            }

        /** Returns the canonical scale for a given mode. */
        fun scale(mode: ExposureScaleMode): ExposureScale = when (mode) {
            ExposureScaleMode.FULL_STOP -> fullStop
            ExposureScaleMode.ONE_THIRD_STOP -> oneThirdStop
        }

        /**
         * Builds a 1/3-stop densified shutter ladder from the full-stop ladder
         * by inserting two intermediate steps between neighbors at the
         * geometric-mean ratios 2^(1/3) and 2^(2/3).
         */
        private fun oneThirdStopShutterSteps(fullStops: List<Double>): List<ShutterStep> {
            if (fullStops.size < 2) return fullStops.map { ShutterStep(it) }

            val oneThirdRatio = 2.0.pow(1.0 / 3.0)
            val twoThirdsRatio = 2.0.pow(2.0 / 3.0)

            val steps = ArrayList<ShutterStep>(fullStops.size * 3 - 2)
            for (index in fullStops.indices) {
                val lower = fullStops[index]
                steps.add(ShutterStep(lower))
                if (index < fullStops.size - 1) {
                    steps.add(ShutterStep(lower * oneThirdRatio))
                    steps.add(ShutterStep(lower * twoThirdsRatio))
                }
            }
            return steps
        }

        /**
         * Camera-facing labels for each entry on `oneThirdStop.shutterSteps`,
         * indexed by ladder position (19 full-stop anchors + 36 intermediates
         * = 55 entries). Sub-1-second values render as `1/N`; values ≥ 1s as
         * integer or `N.Ns` per camera convention.
         */
        val oneThirdStopShutterCameraLabels: List<String> = listOf(
            "1/8000", "1/6400", "1/5000",
            "1/4000", "1/3200", "1/2500",
            "1/2000", "1/1600", "1/1250",
            "1/1000", "1/800", "1/640",
            "1/500", "1/400", "1/320",
            "1/250", "1/200", "1/160",
            "1/125", "1/100", "1/80",
            "1/60", "1/50", "1/40",
            "1/30", "1/25", "1/20",
            "1/15", "1/13", "1/10",
            "1/8", "1/6", "1/5",
            "1/4", "1/3", "1/2.5",
            "1/2", "1/1.6", "1/1.3",
            "1s", "1.3s", "1.6s",
            "2s", "2.5s", "3s",
            "4s", "5s", "6s",
            "8s", "10s", "13s",
            "15s", "20s", "25s",
            "30s",
        )

        /**
         * Camera-facing label for a one-third-stop shutter value if it sits on
         * the canonical 1/3-stop ladder; otherwise null.
         */
        fun oneThirdStopShutterCameraLabel(forSeconds: Double): String? {
            val ladder = oneThirdStop.shutterSteps
            if (ladder.size != oneThirdStopShutterCameraLabels.size) return null
            for ((index, step) in ladder.withIndex()) {
                if (abs(step.seconds - forSeconds) <= ExposureCalculator.STABILITY_EPSILON) {
                    return oneThirdStopShutterCameraLabels[index]
                }
            }
            return null
        }
    }
}

/**
 * Swift `Double.rounded()` semantics: round half away from zero. Kotlin's
 * stdlib rounds half toward positive infinity, so we reproduce Swift exactly
 * to keep snap/format parity for negative and tie values.
 */
internal fun Double.swiftRounded(): Double =
    if (this < 0) -kotlin.math.floor(-this + 0.5) else kotlin.math.floor(this + 0.5)
