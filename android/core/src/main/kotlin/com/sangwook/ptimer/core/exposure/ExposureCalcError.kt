package com.sangwook.ptimer.core.exposure

/**
 * Typed exposure-calculation failures. `token` matches the iOS error
 * case name used by the shared fixture (`exposure-golden.json`).
 * Mirrors iOS `ExposureCalculatorError`.
 */
enum class ExposureCalcError(val token: String, val message: String) {
    EMPTY_BASE_SHUTTER("emptyBaseShutter", "Base shutter is required."),
    INVALID_BASE_SHUTTER("invalidBaseShutter", "Enter shutter like 1/30, 0.5, or 2s."),
    NON_POSITIVE_BASE_SHUTTER("nonPositiveBaseShutter", "Base shutter must be greater than 0."),
    NON_POSITIVE_ND("nonPositiveND", "ND stop must be 0 or greater."),
    OVERFLOW("overflow", "Calculated shutter is too large to display.");

    companion object {
        fun fromToken(token: String): ExposureCalcError? = entries.firstOrNull { it.token == token }
    }
}

/** Thrown by [ExposureCalculator] parsing/calculation, carrying a typed [error]. */
class ExposureCalcException(val error: ExposureCalcError) : Exception(error.message)
