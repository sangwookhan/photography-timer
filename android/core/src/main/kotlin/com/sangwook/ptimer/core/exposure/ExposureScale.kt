package com.sangwook.ptimer.core.exposure

import kotlin.math.abs
import kotlin.math.pow

/**
 * Canonical scale data for one [ExposureScaleMode]. Single source of
 * truth for "what values does the user pick from". Mirrors iOS
 * `ExposureScale`.
 */
class ExposureScale(
    val mode: ExposureScaleMode,
    val shutterSteps: List<ShutterStep>,
    val ndSteps: List<NdStep>,
) {
    companion object {
        /** Maximum whole ND stops the calculator supports. */
        const val MAX_WHOLE_ND_STOPS: Int = 30

        private val ndLadder: List<NdStep> =
            (0..MAX_WHOLE_ND_STOPS).map { NdStep(it.toDouble()) }

        /** Full-stop scale: 19 shutter anchors + integer ND 0..30. Reserved. */
        val fullStop: ExposureScale = ExposureScale(
            mode = ExposureScaleMode.FULL_STOP,
            shutterSteps = ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS.map { ShutterStep(it) },
            ndSteps = ndLadder,
        )

        /** Shipping scale: 55-entry one-third-stop shutter ladder + integer ND 0..30. */
        val oneThirdStop: ExposureScale = ExposureScale(
            mode = ExposureScaleMode.ONE_THIRD_STOP,
            shutterSteps = oneThirdStopShutterSteps(ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS),
            ndSteps = ndLadder,
        )

        /** Shipping default scale. */
        val default: ExposureScale = oneThirdStop

        fun ndStep(forWholeStops: Int): NdStep = NdStep(forWholeStops.toDouble())

        fun scale(mode: ExposureScaleMode): ExposureScale = when (mode) {
            ExposureScaleMode.FULL_STOP -> fullStop
            ExposureScaleMode.ONE_THIRD_STOP -> oneThirdStop
        }

        /**
         * Builds the 1/3-stop densified shutter ladder from the full-stop
         * ladder by inserting two geometric-mean steps (`2^(1/3)`,
         * `2^(2/3)`) off the lower neighbor between each pair. 55 entries.
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
         * Camera-facing labels for `oneThirdStop.shutterSteps`, same length
         * and order (55 entries). Mirrors iOS
         * `oneThirdStopShutterCameraLabels`.
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

        /** Camera label for a ladder shutter value, or null if off-ladder. */
        fun oneThirdStopShutterCameraLabel(forSeconds: Double): String? {
            val ladder = oneThirdStop.shutterSteps
            if (ladder.size != oneThirdStopShutterCameraLabels.size) return null
            for (index in ladder.indices) {
                if (abs(ladder[index].seconds - forSeconds) <= ExposureCalculator.STABILITY_EPSILON) {
                    return oneThirdStopShutterCameraLabels[index]
                }
            }
            return null
        }
    }
}
