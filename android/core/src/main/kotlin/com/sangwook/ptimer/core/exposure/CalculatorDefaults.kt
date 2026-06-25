package com.sangwook.ptimer.core.exposure

/**
 * Shipping defaults for a fresh calculator surface (new camera slot, the
 * digital workflow before the user touches a wheel, a post-reset context).
 * Single source of truth. Port of iOS `CalculatorDefaults` (PTimerCore).
 */
object CalculatorDefaults {
    /** Base shutter the calculator opens with: 1/30 s. */
    const val BASE_SHUTTER_SECONDS: Double = 1.0 / 30.0

    /** ND stop the calculator opens with: whole-stop zero ("no ND"). */
    const val ND_STOP: Int = 0

    /** Canonical fractional ND value matching [ND_STOP]. */
    val ndStep: NDStep = NDStep(ND_STOP.toDouble())

    /** Active exposure scale for fresh surfaces (shipping mode). */
    val scaleMode: ExposureScaleMode = ExposureScaleMode.ONE_THIRD_STOP
}
