package com.sangwook.ptimer.core.reciprocity

import kotlinx.serialization.Serializable
import kotlin.math.log10
import kotlin.math.pow

/** Outcome of a single table evaluation. Mirrors iOS table `EvaluationResult`. */
sealed interface TableEvaluationResult {
    data object NoCorrection : TableEvaluationResult
    data class WithinSourceRange(val correctedExposureSeconds: Double) : TableEvaluationResult
    data class BeyondSourceRange(val correctedExposureSeconds: Double) : TableEvaluationResult
    data object InvalidInput : TableEvaluationResult
    data object InvalidRule : TableEvaluationResult
}

/**
 * Manufacturer reciprocity TABLE evaluated by piecewise log10–log10
 * interpolation through published anchors (exact at anchors; extrapolates
 * the final segment beyond the last anchor). Protected behavior — exact
 * parity with iOS `TableInterpolationReciprocityRule` + its evaluator.
 *
 * Display-only `additionalAdjustments`/`notes` from the iOS rule are
 * deferred with the full catalog domain; only calculation-relevant fields
 * are modeled here.
 */
@Serializable
data class TableInterpolationRule(
    val anchors: List<TableAnchor>,
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double,
) {
    val sortedAnchors: List<TableAnchor>
        get() = anchors.sortedBy { it.meteredSeconds }

    val hasValidParameters: Boolean
        get() {
            val sorted = sortedAnchors
            if (sorted.size < 2) return false
            if (!noCorrectionThroughSeconds.isFinite() || noCorrectionThroughSeconds < 0) return false
            if (!sourceRangeThroughSeconds.isFinite()) return false

            var previousMetered = -Double.MAX_VALUE
            for (anchor in sorted) {
                if (!anchor.meteredSeconds.isFinite() || anchor.meteredSeconds <= 0) return false
                if (!anchor.correctedSeconds.isFinite() || anchor.correctedSeconds <= 0) return false
                if (anchor.correctedSeconds < anchor.meteredSeconds - 1e-6) return false
                if (anchor.meteredSeconds <= previousMetered) return false
                previousMetered = anchor.meteredSeconds
            }
            val first = sorted.first()
            val last = sorted.last()
            if (noCorrectionThroughSeconds >= first.meteredSeconds) return false
            if (sourceRangeThroughSeconds < last.meteredSeconds - 1e-6) return false
            return true
        }

    fun evaluate(meteredExposureSeconds: Double): TableEvaluationResult {
        if (!meteredExposureSeconds.isFinite() || meteredExposureSeconds <= 0) {
            return TableEvaluationResult.InvalidInput
        }
        if (!hasValidParameters) return TableEvaluationResult.InvalidRule

        if (ReciprocityNoCorrectionBoundary.isWithinNoCorrection(
                meteredSeconds = meteredExposureSeconds,
                throughSeconds = noCorrectionThroughSeconds,
            )
        ) {
            return TableEvaluationResult.NoCorrection
        }

        val sorted = sortedAnchors
        val kneePoint = TableAnchor(noCorrectionThroughSeconds, noCorrectionThroughSeconds)
        val points = listOf(kneePoint) + sorted

        val corrected: Double = if (meteredExposureSeconds <= sorted.last().meteredSeconds) {
            interpolatedCorrected(meteredExposureSeconds, points)
        } else {
            logLogValue(meteredExposureSeconds, sorted[sorted.size - 2], sorted.last())
        }

        val safeCorrected = maxOf(corrected, meteredExposureSeconds)
        if (!safeCorrected.isFinite() || safeCorrected <= 0) return TableEvaluationResult.InvalidRule

        return if (meteredExposureSeconds > sourceRangeThroughSeconds) {
            TableEvaluationResult.BeyondSourceRange(safeCorrected)
        } else {
            TableEvaluationResult.WithinSourceRange(safeCorrected)
        }
    }

    private fun interpolatedCorrected(metered: Double, points: List<TableAnchor>): Double {
        for (index in 1 until points.size) {
            val upper = points[index]
            if (metered <= upper.meteredSeconds) {
                return logLogValue(metered, points[index - 1], upper)
            }
        }
        return points.last().correctedSeconds
    }

    private fun logLogValue(metered: Double, lower: TableAnchor, upper: TableAnchor): Double {
        val logMeteredLower = log10(lower.meteredSeconds)
        val logMeteredUpper = log10(upper.meteredSeconds)
        val logCorrectedLower = log10(lower.correctedSeconds)
        val logCorrectedUpper = log10(upper.correctedSeconds)

        val denominator = logMeteredUpper - logMeteredLower
        if (kotlin.math.abs(denominator) <= Math.ulp(1.0)) return upper.correctedSeconds
        val slope = (logCorrectedUpper - logCorrectedLower) / denominator
        val logCorrected = logCorrectedLower + slope * (log10(metered) - logMeteredLower)
        return 10.0.pow(logCorrected)
    }
}
