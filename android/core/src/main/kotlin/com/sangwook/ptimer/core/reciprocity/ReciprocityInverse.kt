// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

enum class ReciprocityInverseFailure {
    invalidInput, invalidProfile, noQuantifiedSolution, multipleSolutions, numericalFailure,
}

sealed interface ReciprocityInverseResult {
    data class Available(val meteredSeconds: Double, val evaluation: ReciprocityResult) : ReciprocityInverseResult
    data class Unavailable(val reason: ReciprocityInverseFailure) : ReciprocityInverseResult
}

/** Piecewise inverse query; the forward policy and source data stay unchanged. */
class ReciprocityInverse {
    fun evaluate(profile: ReciprocityProfile, targetSeconds: Double): ReciprocityInverseResult {
        if (!targetSeconds.isFinite() || targetSeconds <= 0) return ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.invalidInput)
        val search = Search(profile, targetSeconds)
        search.add(targetSeconds)
        val formula = profile.rules.firstNotNullOfOrNull { it.formula }?.formula
        val table = profile.rules.firstNotNullOfOrNull { it.tableInterpolation }
        if (formula != null) {
            if (!formula.hasValidParameters) return ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.invalidProfile)
            search.formula(formula)
        } else if (table != null) {
            if (!table.hasValidParameters) return ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.invalidProfile)
            search.table(table)
        }
        return search.result()
    }

    private class Search(val profile: ReciprocityProfile, val target: Double) {
        val roots = mutableListOf<Pair<Double, ReciprocityResult>>()
        var flat = false
        var numericalFailure = false
        val evaluator = ReciprocityCalculationPolicyEvaluator()

        fun matches(lhs: Double, rhs: Double): Boolean = abs(lhs - rhs) <= 64 * max(Math.ulp(lhs), Math.ulp(rhs))

        fun add(metered: Double) {
            if (!metered.isFinite() || metered <= 0) return
            val value = evaluator.evaluate(profile, metered)
            val corrected = value.calculatedCorrectedSeconds ?: return
            if (!corrected.isFinite() || corrected <= 0 || !matches(corrected, target)) return
            if (roots.none { matches(it.first, metered) }) roots += metered to value
        }

        fun formula(formula: ReciprocityFormula) {
            val remainder = target - formula.offsetSeconds
            if (remainder <= 0) return
            if (formula.exponent == 0.0) {
                val output = formula.coefficientSeconds + formula.offsetSeconds
                val lower = formula.noCorrectionThroughSeconds
                val upper = target + 1e-6
                if (matches(output, target) && upper > lower) {
                    val value = evaluator.evaluate(profile, lower + (upper - lower) / 2)
                    flat = value.calculatedCorrectedSeconds?.let { matches(it, target) } == true
                }
                return
            }
            val logMetered = ln(formula.referenceMeteredTimeSeconds) + (ln(remainder) - ln(formula.coefficientSeconds)) / formula.exponent
            if (logMetered > ln(target + 1e-6)) return
            if (formula.noCorrectionThroughSeconds > 0 && logMetered < ln(formula.noCorrectionThroughSeconds)) return
            val metered = exp(logMetered)
            if (!metered.isFinite() || metered <= 0) {
                numericalFailure = true
                return
            }
            if (metered > formula.noCorrectionThroughSeconds) add(metered)
        }

        fun table(table: TableInterpolationReciprocityRule) {
            val anchors = table.sortedAnchors
            val points = listOf(TableAnchor(table.noCorrectionThroughSeconds, table.noCorrectionThroughSeconds)) + anchors
            val identityLimit = table.noCorrectionThroughSeconds * (1 + ReciprocityNoCorrectionBoundary.RELATIVE_TOLERANCE)
            for (index in 1 until points.size) {
                segment(points[index - 1], points[index], max(points[index - 1].meteredSeconds, identityLimit), points[index].meteredSeconds)
            }
            segment(anchors[anchors.size - 2], anchors.last(), max(anchors.last().meteredSeconds, identityLimit), Double.POSITIVE_INFINITY)
        }

        fun segment(first: TableAnchor, last: TableAnchor, lower: Double, upper: Double) {
            if (lower >= upper || first.meteredSeconds <= 0 || first.correctedSeconds <= 0) return
            val delta = log10(last.meteredSeconds) - log10(first.meteredSeconds)
            if (delta <= Math.ulp(1.0)) return
            val slope = (log10(last.correctedSeconds) - log10(first.correctedSeconds)) / delta
            if (slope == 0.0) {
                val end = min(upper, target)
                if (matches(first.correctedSeconds, target) && end > lower) {
                    val value = evaluator.evaluate(profile, lower + (end - lower) / 2)
                    if (value.calculatedCorrectedSeconds?.let { matches(it, target) } == true) flat = true
                }
                return
            }
            val logMetered = log10(first.meteredSeconds) + (log10(target) - log10(first.correctedSeconds)) / slope
            if (lower > 0 && logMetered < log10(lower)) return
            if (upper.isFinite() && logMetered > log10(upper)) return
            val metered = 10.0.pow(logMetered)
            if (!metered.isFinite() || metered <= 0) {
                numericalFailure = true
                return
            }
            if (metered >= lower && metered <= upper) add(metered)
        }

        fun result(): ReciprocityInverseResult = when {
            flat || roots.size > 1 -> ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.multipleSolutions)
            numericalFailure -> ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.numericalFailure)
            roots.isNotEmpty() -> ReciprocityInverseResult.Available(roots[0].first, roots[0].second)
            else -> ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.noQuantifiedSolution)
        }
    }
}
