package com.sangwook.ptimer.core.reciprocity

import kotlin.math.exp
import kotlin.math.ln

/** Fitted two-parameter power law `Tc = coefficient × Tm^exponent`. */
data class PowerLawFit(val coefficient: Double, val exponent: Double)

/** Why a power-law fit could not be produced (a pure function of the anchors). */
enum class FitUnavailable {
    INSUFFICIENT_ANCHORS,
    NON_POSITIVE_ANCHORS,
    DEGENERATE_ANCHORS,
    NON_FINITE_RESULT,
}

/** Result of a fit attempt. */
sealed interface PowerLawFitResult {
    data class Success(val fit: PowerLawFit) : PowerLawFitResult
    data class Failure(val reason: FitUnavailable) : PowerLawFitResult
}

/**
 * Closed-form OLS fit of `Tc = a × Tm^p` in natural-log space. Deterministic
 * and order-independent. Inspection-only; never the active calculation.
 * Mirrors iOS `ReciprocityFormulaFitter`.
 */
object ReciprocityFormulaFitter {
    fun fit(anchors: List<TableAnchor>): PowerLawFitResult {
        if (anchors.size < 2) return PowerLawFitResult.Failure(FitUnavailable.INSUFFICIENT_ANCHORS)
        for (anchor in anchors) {
            if (!anchor.meteredSeconds.isFinite() || anchor.meteredSeconds <= 0 ||
                !anchor.correctedSeconds.isFinite() || anchor.correctedSeconds <= 0
            ) {
                return PowerLawFitResult.Failure(FitUnavailable.NON_POSITIVE_ANCHORS)
            }
        }

        val xs = anchors.map { ln(it.meteredSeconds) }
        val ys = anchors.map { ln(it.correctedSeconds) }
        val n = anchors.size.toDouble()
        val sx = xs.sum()
        val sy = ys.sum()
        val sxx = xs.sumOf { it * it }
        val sxy = xs.indices.sumOf { xs[it] * ys[it] }

        val denominator = n * sxx - sx * sx
        if (kotlin.math.abs(denominator) <= Math.ulp(1.0)) {
            return PowerLawFitResult.Failure(FitUnavailable.DEGENERATE_ANCHORS)
        }
        val exponent = (n * sxy - sx * sy) / denominator
        val coefficient = exp((sy - exponent * sx) / n)

        if (!exponent.isFinite() || !coefficient.isFinite()) {
            return PowerLawFitResult.Failure(FitUnavailable.NON_FINITE_RESULT)
        }
        return PowerLawFitResult.Success(PowerLawFit(coefficient, exponent))
    }
}
