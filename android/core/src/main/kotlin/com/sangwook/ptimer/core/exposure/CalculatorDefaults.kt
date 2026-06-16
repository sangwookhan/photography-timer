package com.sangwook.ptimer.core.exposure

/**
 * Shipping defaults for a fresh calculator surface. One source of truth
 * for the ViewModel, fresh-slot snapshot factory, and reset paths.
 * Mirrors iOS `CalculatorDefaults`.
 */
object CalculatorDefaults {
    /** Base shutter the calculator opens with: 1/30 s. */
    const val BASE_SHUTTER_SECONDS: Double = 1.0 / 30.0

    /** ND stop the calculator opens with: whole-stop zero. */
    const val ND_STOP: Int = 0

    /** Canonical fractional ND value matching [ND_STOP]. */
    val ndStep: NdStep = NdStep(ND_STOP.toDouble())

    /** Active exposure scale for fresh surfaces: one-third-stop (shipping). */
    val scaleMode: ExposureScaleMode = ExposureScaleMode.ONE_THIRD_STOP
}
