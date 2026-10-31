// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.reciprocity.*
import kotlin.math.*

sealed interface RequiredNDResult {
    data class Value(val stops: Double, val beyondSourceRange: Boolean) : RequiredNDResult
    data class Unavailable(val reason: Reason) : RequiredNDResult
    enum class Reason { InvalidInput, NoQuantifiedInverse, MultipleSolutions, NumericalFailure, NegativeAttenuation }
}

/** Read-only inverse; every candidate is verified by the unchanged forward policy. */
class RequiredNDEvaluator {
    fun evaluate(baseSeconds: Double, targetSeconds: Double, profile: ReciprocityProfile?): RequiredNDResult {
        if (!baseSeconds.isFinite() || baseSeconds <= 0 || !targetSeconds.isFinite() || targetSeconds <= 0)
            return RequiredNDResult.Unavailable(RequiredNDResult.Reason.InvalidInput)
        if (profile == null) return attenuation(targetSeconds, baseSeconds, false)
        val candidates = candidates(profile, targetSeconds)?.toMutableList()
            ?: return RequiredNDResult.Unavailable(RequiredNDResult.Reason.NumericalFailure)
        // An exact forward match is exactly zero stops, without inverse roundoff.
        if (ReciprocityCalculationPolicyEvaluator().evaluate(profile, baseSeconds).calculatedCorrectedSeconds == targetSeconds)
            candidates.add(0, baseSeconds)
        val solutions = mutableListOf<Pair<Double, Boolean>>()
        for (candidate in candidates.filter { it.isFinite() && it > 0 }) {
            val forward = ReciprocityCalculationPolicyEvaluator().evaluate(profile, candidate)
            val corrected = forward.calculatedCorrectedSeconds ?: continue
            if (close(corrected, targetSeconds) && solutions.none { close(it.first, candidate) })
                solutions += candidate to (forward.metadata.rangeStatus != ReciprocityCalculationRangeStatus.withinStatedRange)
        }
        if (solutions.size > 1) return RequiredNDResult.Unavailable(RequiredNDResult.Reason.MultipleSolutions)
        val solution = solutions.singleOrNull() ?: return RequiredNDResult.Unavailable(
            if (candidates.any { !it.isFinite() || it <= 0 }) RequiredNDResult.Reason.NumericalFailure
            else RequiredNDResult.Reason.NoQuantifiedInverse)
        return attenuation(solution.first, baseSeconds, solution.second)
    }

    private fun candidates(profile: ReciprocityProfile, target: Double): List<Double>? {
        val formula = profile.rules.firstNotNullOfOrNull { it.formula?.formula }
        if (formula != null) {
            if (!formula.hasValidParameters) return null
            val values = mutableListOf(target)
            val power = (target - formula.offsetSeconds) / formula.coefficientSeconds
            if (formula.exponent == 0.0) {
                val constant = formula.coefficientSeconds + formula.offsetSeconds
                // The forward shortening guard accepts a constant up to 1e-6
                // below metered, including just above the identity boundary.
                if (close(constant, target))
                    values += interior(formula.noCorrectionThroughSeconds, constant + 1e-6)
            } else if (power > 0) {
                values += exp(ln(formula.referenceMeteredTimeSeconds) + ln(power) / formula.exponent)
            }
            return values
        }
        val values = mutableListOf(target)
        val table = profile.rules.firstNotNullOfOrNull { it.tableInterpolation } ?: return values
        if (!table.hasValidParameters) return null
        val anchors = table.sortedAnchors
        val points = listOf(TableAnchor(table.noCorrectionThroughSeconds, table.noCorrectionThroughSeconds)) + anchors
        points.zipWithNext().forEach { (a, b) -> values += segment(target, a, b, false) }
        values += segment(target, anchors[anchors.size - 2], anchors.last(), true)
        return values
    }

    private fun segment(target: Double, lower: TableAnchor, upper: TableAnchor, extrapolate: Boolean): List<Double> {
        if (lower.meteredSeconds <= 0 || lower.correctedSeconds <= 0) return emptyList()
        val slope = (ln(upper.correctedSeconds) - ln(lower.correctedSeconds)) /
            (ln(upper.meteredSeconds) - ln(lower.meteredSeconds))
        val start = if (extrapolate) upper.meteredSeconds else lower.meteredSeconds
        val end = if (extrapolate) max(start, target) else upper.meteredSeconds
        if (slope == 0.0) return if (close(target, lower.correctedSeconds)) interior(start, end) else emptyList()
        val root = exp(ln(lower.meteredSeconds) + (ln(target) - ln(lower.correctedSeconds)) / slope)
        return if (root.isFinite() && root >= start * (1 - 1e-10) &&
            (extrapolate || root <= end * (1 + 1e-10))) listOf(root) else emptyList()
    }

    private fun interior(lower: Double, upper: Double): List<Double> =
        if (upper > lower) listOf(lower + (upper - lower) / 3, lower + 2 * (upper - lower) / 3) else emptyList()

    private fun attenuation(metered: Double, base: Double, beyond: Boolean): RequiredNDResult {
        val stops = log2(metered) - log2(base)
        return when {
            !stops.isFinite() -> RequiredNDResult.Unavailable(RequiredNDResult.Reason.NumericalFailure)
            stops < 0 -> RequiredNDResult.Unavailable(RequiredNDResult.Reason.NegativeAttenuation)
            else -> RequiredNDResult.Value(stops, beyond)
        }
    }

    private fun close(a: Double, b: Double) = abs(a - b) <= max(abs(a), abs(b)) * 1e-10
}
