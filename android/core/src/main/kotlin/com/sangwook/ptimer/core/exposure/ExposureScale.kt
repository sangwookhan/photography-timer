// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import kotlin.math.abs
import kotlin.math.pow

/**
 * Granularity of one increment along an exposure scale. `oneThirdStop` is a
 * first-class step (the shipping product runs on the one-third-stop shutter
 * ladder); the ND ladder stays whole-stop in every shipping mode. `fullStop`
 * is retained as a reserved scale for tests and a future Settings preference.
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
 * One ND-filter entry, expressed in stops. Fractional values are
 * representable as reserved domain infrastructure; the shipping ND picker
 * enumerates whole stops only. `wholeStops` is non-null only on a whole-stop
 * boundary.
 */
data class NDStep(val stops: Double) {

    val isWholeStop: Boolean
        get() = abs(stops - stops.swiftRounded()) <= ExposureCalculator.STABILITY_EPSILON

    val wholeStops: Int?
        get() = if (isWholeStop) stops.swiftRounded().toInt() else null

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

        /** Default full-stop scale; ND ladder spans 0…30 stops. */
        val fullStop: ExposureScale = ExposureScale(
            mode = ExposureScaleMode.FULL_STOP,
            shutterSteps = ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS.map { ShutterStep(it) },
            ndSteps = (0..MAXIMUM_WHOLE_ND_STOPS).map { NDStep(it.toDouble()) },
        )

        /** Densified shutter ladder (55 entries) paired with whole-stop ND. */
        val oneThirdStop: ExposureScale = ExposureScale(
            mode = ExposureScaleMode.ONE_THIRD_STOP,
            shutterSteps = oneThirdStopShutterSteps(ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS),
            ndSteps = (0..MAXIMUM_WHOLE_ND_STOPS).map { NDStep(it.toDouble()) },
        )

        /** The shipping calculator scale. */
        val default: ExposureScale = oneThirdStop

        /** Canonical [NDStep] for a whole-stop value. */
        fun ndStep(forWholeStops: Int): NDStep = NDStep(forWholeStops.toDouble())

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
