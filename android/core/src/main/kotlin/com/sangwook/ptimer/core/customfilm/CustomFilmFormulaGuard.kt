package com.sangwook.ptimer.core.customfilm

import kotlin.math.abs
import kotlin.math.pow

/**
 * Shared correctness helper for the custom-film formula model. The editor
 * validate path and the persistence sanitation path both enforce the same
 * `Tc >= Tm` (non-shortening) invariant through this guard.
 *
 * The check is analytic, not sample-based. Reparameterising
 * `Tc(t) = a·(t/Tref)^e + b` as `f(t) = c·t^e + b − t` with
 * `c = a/Tref^e` gives a function with at most one interior critical point
 * on `(0, ∞)`; verifying f at the endpoints plus the critical point covers
 * the whole interval. (iOS: CustomFilmFormulaGuard.)
 */
object CustomFilmFormulaGuard {
    /** Non-shortening slack matching the runtime evaluator's safety net. */
    private const val SLACK_SECONDS: Double = 1e-6

    data class UsableRangeInput(
        val exponent: Double,
        val referenceMeteredTimeSeconds: Double,
        val coefficientSeconds: Double,
        val offsetSeconds: Double,
        val noCorrectionThroughSeconds: Double,
        val sourceRangeThroughSeconds: Double?,
    )

    /** True when no `Tm` in the usable formula range produces `Tc < Tm`. */
    fun passesUsableRangeCheck(input: UsableRangeInput): Boolean {
        val exponent = input.exponent
        val referenceMeteredTime = input.referenceMeteredTimeSeconds
        val coefficient = input.coefficientSeconds
        val offset = input.offsetSeconds
        val noCorrectionThrough = input.noCorrectionThroughSeconds
        val sourceRangeThrough = input.sourceRangeThroughSeconds

        if (!(exponent.isFinite() && exponent > 0 &&
                referenceMeteredTime.isFinite() && referenceMeteredTime > 0 &&
                coefficient.isFinite() && coefficient > 0 &&
                offset.isFinite() &&
                noCorrectionThrough.isFinite() && noCorrectionThrough >= 0)
        ) {
            return false
        }
        if (sourceRangeThrough != null &&
            !(sourceRangeThrough.isFinite() && sourceRangeThrough > noCorrectionThrough)
        ) {
            return false
        }

        val scaledCoefficient = coefficient / referenceMeteredTime.pow(exponent)
        val lower = maxOf(noCorrectionThrough, 1e-9)
        val formula = ShorteningFormula(scaledCoefficient, exponent, offset)

        // exponent == 1: f is linear (slope = c − 1).
        if (abs(exponent - 1.0) < 1e-9) {
            return passesLinearCase(formula, lower, sourceRangeThrough)
        }

        // exponent < 1: f is concave → minimum sits at an endpoint; Unlimited
        // eventually shortens regardless of c, so reject outright.
        if (exponent < 1) {
            val upper = sourceRangeThrough ?: return false
            return formula.isNonNegative(lower) && formula.isNonNegative(upper)
        }

        // exponent > 1: f is convex. Endpoints + interior critical point.
        if (!formula.isNonNegative(lower)) return false
        if (sourceRangeThrough != null && !formula.isNonNegative(sourceRangeThrough)) return false
        val denominator = scaledCoefficient * exponent
        if (denominator <= 0) return true
        val critical = (1.0 / denominator).pow(1.0 / (exponent - 1.0))
        val upperBound = sourceRangeThrough ?: Double.POSITIVE_INFINITY
        if (critical.isFinite() && critical > lower && critical < upperBound) {
            return formula.isNonNegative(critical)
        }
        return true
    }

    private fun passesLinearCase(
        formula: ShorteningFormula,
        lower: Double,
        sourceRangeThrough: Double?,
    ): Boolean {
        val slope = formula.coefficient - 1.0
        if (slope > 1e-9) return formula.isNonNegative(lower)
        if (slope < -1e-9) {
            val upper = sourceRangeThrough ?: return false
            return formula.isNonNegative(lower) && formula.isNonNegative(upper)
        }
        // c == 1 → f(t) = offset, constant. Need offset >= 0.
        return formula.offset >= -SLACK_SECONDS
    }

    private class ShorteningFormula(
        val coefficient: Double,
        val exponent: Double,
        val offset: Double,
    ) {
        /** `Tc(t) >= t − slack`, matching the runtime evaluator's safety net. */
        fun isNonNegative(t: Double): Boolean {
            if (t <= 0) return offset >= -SLACK_SECONDS
            val tc = coefficient * t.pow(exponent) + offset
            return tc >= t - SLACK_SECONDS
        }
    }
}

/**
 * Parser for the duration-style strings the editor accepts in the
 * application-range fields (`No correction until`, `Source data through`).
 * Accepts empty (→ empty), `unlimited`, plain decimals (seconds), and
 * `s`/`m`/`h` suffixes; anything else returns null. (iOS:
 * CustomFilmDurationParser.)
 */
object CustomFilmDurationParser {
    sealed interface ParsedDuration {
        data class Seconds(val value: Double) : ParsedDuration
        data object Unlimited : ParsedDuration
        data object Empty : ParsedDuration
    }

    fun parse(text: String): ParsedDuration? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ParsedDuration.Empty
        if (trimmed.equals("unlimited", ignoreCase = true)) return ParsedDuration.Unlimited
        val lowered = trimmed.lowercase()
        lowered.toDoubleOrNull()?.let { if (it.isFinite()) return ParsedDuration.Seconds(it) }
        val unit = lowered.lastOrNull() ?: return null
        val value = lowered.dropLast(1).toDoubleOrNull()?.takeIf { it.isFinite() } ?: return null
        return when (unit) {
            's' -> ParsedDuration.Seconds(value)
            'm' -> ParsedDuration.Seconds(value * 60)
            'h' -> ParsedDuration.Seconds(value * 3600)
            else -> null
        }
    }
}
