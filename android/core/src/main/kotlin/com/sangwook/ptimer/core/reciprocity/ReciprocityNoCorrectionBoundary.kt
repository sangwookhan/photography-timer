package com.sangwook.ptimer.core.reciprocity

/**
 * No-correction band tolerance for the TABLE evaluator only. The formula
 * evaluator uses a strict inclusive boundary (no tolerance). Mirrors iOS
 * `ReciprocityNoCorrectionBoundary`.
 */
object ReciprocityNoCorrectionBoundary {
    /** Relative tolerance applied above `noCorrectionThroughSeconds`. */
    const val RELATIVE_TOLERANCE: Double = 0.10

    fun isWithinNoCorrection(meteredSeconds: Double, throughSeconds: Double): Boolean =
        meteredSeconds <= throughSeconds * (1 + RELATIVE_TOLERANCE)
}
