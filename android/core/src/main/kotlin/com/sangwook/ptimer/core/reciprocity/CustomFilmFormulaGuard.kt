package com.sangwook.ptimer.core.reciprocity

import kotlin.math.abs
import kotlin.math.pow

/**
 * Analytic no-shortening guard for custom formula profiles: returns true
 * when no `Tm` in the usable range produces `Tc < Tm`. Mirrors iOS
 * `CustomFilmFormulaGuard` (endpoint + interior-critical-point analysis,
 * not sampling).
 */
object CustomFilmFormulaGuard {
    private const val SLACK_SECONDS: Double = 1e-6

    data class UsableRangeInput(
        val exponent: Double,
        val referenceMeteredTimeSeconds: Double,
        val coefficientSeconds: Double,
        val offsetSeconds: Double,
        val noCorrectionThroughSeconds: Double,
        val sourceRangeThroughSeconds: Double?,
    )

    fun passesUsableRangeCheck(input: UsableRangeInput): Boolean {
        val exponent = input.exponent
        val referenceMeteredTime = input.referenceMeteredTimeSeconds
        val coefficient = input.coefficientSeconds
        val offset = input.offsetSeconds
        val noCorrectionThrough = input.noCorrectionThroughSeconds
        val sourceRangeThrough = input.sourceRangeThroughSeconds

        if (!(exponent.isFinite() && exponent > 0)) return false
        if (!(referenceMeteredTime.isFinite() && referenceMeteredTime > 0)) return false
        if (!(coefficient.isFinite() && coefficient > 0)) return false
        if (!offset.isFinite()) return false
        if (!(noCorrectionThrough.isFinite() && noCorrectionThrough >= 0)) return false
        if (sourceRangeThrough != null &&
            !(sourceRangeThrough.isFinite() && sourceRangeThrough > noCorrectionThrough)
        ) {
            return false
        }

        val scaledCoefficient = coefficient / referenceMeteredTime.pow(exponent)
        val lower = maxOf(noCorrectionThrough, 1e-9)
        val formula = ShorteningFormula(scaledCoefficient, exponent, offset)

        if (abs(exponent - 1.0) < 1e-9) {
            return passesLinearCase(formula, lower, sourceRangeThrough)
        }

        if (exponent < 1) {
            val upper = sourceRangeThrough ?: return false
            return formula.fIsNonNegative(lower) && formula.fIsNonNegative(upper)
        }

        // exponent > 1: convex
        if (!formula.fIsNonNegative(lower)) return false
        if (sourceRangeThrough != null && !formula.fIsNonNegative(sourceRangeThrough)) return false
        val denominator = scaledCoefficient * exponent
        if (denominator <= 0) return true
        val critical = (1.0 / denominator).pow(1.0 / (exponent - 1.0))
        val upperBound = sourceRangeThrough ?: Double.POSITIVE_INFINITY
        if (critical.isFinite() && critical > lower && critical < upperBound) {
            return formula.fIsNonNegative(critical)
        }
        return true
    }

    private fun passesLinearCase(
        formula: ShorteningFormula,
        lower: Double,
        sourceRangeThrough: Double?,
    ): Boolean {
        val slope = formula.coefficient - 1.0
        if (slope > 1e-9) return formula.fIsNonNegative(lower)
        if (slope < -1e-9) {
            val upper = sourceRangeThrough ?: return false
            return formula.fIsNonNegative(lower) && formula.fIsNonNegative(upper)
        }
        return formula.offset >= -SLACK_SECONDS
    }

    private class ShorteningFormula(
        val coefficient: Double,
        val exponent: Double,
        val offset: Double,
    ) {
        fun fIsNonNegative(t: Double): Boolean {
            if (t <= 0) return offset >= -SLACK_SECONDS
            val tc = coefficient * t.pow(exponent) + offset
            return tc >= t - SLACK_SECONDS
        }
    }
}
