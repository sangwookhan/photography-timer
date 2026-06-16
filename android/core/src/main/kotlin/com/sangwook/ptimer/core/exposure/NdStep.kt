package com.sangwook.ptimer.core.exposure

import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * One ND-filter entry expressed in stops. Fractional values are
 * representable as reserved domain infrastructure; the shipping ND
 * picker enumerates whole stops only. Mirrors iOS `NDStep`.
 */
data class NdStep(val stops: Double) {

    val isWholeStop: Boolean
        get() = abs(stops - stops.roundToLong().toDouble()) <= ExposureCalculator.STABILITY_EPSILON

    val wholeStops: Int?
        get() = if (isWholeStop) stops.roundToInt() else null

    /** Count of one-third-stop increments. Stable integer identity. */
    val thirdStopCount: Int
        get() = (stops * 3).roundToInt()

    companion object {
        fun fromThirdStopCount(thirds: Int): NdStep = NdStep(thirds.toDouble() / 3.0)
    }
}
