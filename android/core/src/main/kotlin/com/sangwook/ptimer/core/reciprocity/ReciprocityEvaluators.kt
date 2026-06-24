package com.sangwook.ptimer.core.reciprocity

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow

// Evaluators for the formula and table-interpolation rules, and the
// descriptive profile model-basis inference. Faithful port of iOS
// PTimerCore ReciprocityDomain.evaluate / TableInterpolationModel
// (PROTECTED AREA — exact parity).

private val ULP_OF_ONE: Double = Math.ulp(1.0)

/** Outcome of a single guarded-formula evaluation. */
sealed interface FormulaEvaluationResult {
    data object NoCorrection : FormulaEvaluationResult
    data class WithinSourceRange(val correctedExposureSeconds: Double) : FormulaEvaluationResult
    data class BeyondSourceRange(val correctedExposureSeconds: Double) : FormulaEvaluationResult
    data object InvalidInput : FormulaEvaluationResult
    data object InvalidFormula : FormulaEvaluationResult
    data object FormulaOutputUnusable : FormulaEvaluationResult
    data object UnsafeShorteningFormula : FormulaEvaluationResult
}

val ReciprocityFormula.hasValidParameters: Boolean
    get() {
        if (!coefficientSeconds.isFinite() || coefficientSeconds <= 0) return false
        if (!referenceMeteredTimeSeconds.isFinite() || referenceMeteredTimeSeconds <= 0) return false
        if (!exponent.isFinite()) return false
        if (!offsetSeconds.isFinite()) return false
        if (!noCorrectionThroughSeconds.isFinite() || noCorrectionThroughSeconds < 0) return false
        val upper = sourceRangeThroughSeconds
        if (upper != null) {
            if (!upper.isFinite() || upper <= noCorrectionThroughSeconds) return false
        }
        return true
    }

/**
 * Single shared evaluator. `Tm <= noCorrectionThroughSeconds` → identity;
 * otherwise `Tc = a × (Tm / Tref)^p + b`, with the unsafe-shortening safety
 * net (`Tc < Tm`) and the source-range classification.
 */
fun ReciprocityFormula.evaluate(meteredExposureSeconds: Double): FormulaEvaluationResult {
    if (!meteredExposureSeconds.isFinite() || meteredExposureSeconds <= 0) {
        return FormulaEvaluationResult.InvalidInput
    }
    if (!hasValidParameters) {
        return FormulaEvaluationResult.InvalidFormula
    }
    // Strict, inclusive boundary — no nominal-shutter tolerance here.
    if (meteredExposureSeconds <= noCorrectionThroughSeconds) {
        return FormulaEvaluationResult.NoCorrection
    }

    val corrected: Double = when (formulaFamily) {
        FormulaFamily.modifiedSchwarzschild -> {
            val scaled = meteredExposureSeconds / referenceMeteredTimeSeconds
            coefficientSeconds * scaled.pow(exponent) + offsetSeconds
        }
    }

    if (!corrected.isFinite() || corrected <= 0) {
        return FormulaEvaluationResult.FormulaOutputUnusable
    }
    if (corrected < meteredExposureSeconds - 1e-6) {
        return FormulaEvaluationResult.UnsafeShorteningFormula
    }
    val upper = sourceRangeThroughSeconds
    if (upper != null && meteredExposureSeconds > upper) {
        return FormulaEvaluationResult.BeyondSourceRange(corrected)
    }
    return FormulaEvaluationResult.WithinSourceRange(corrected)
}

/** Outcome of a single table evaluation. */
sealed interface TableEvaluationResult {
    data object NoCorrection : TableEvaluationResult
    data class WithinSourceRange(val correctedExposureSeconds: Double) : TableEvaluationResult
    data class BeyondSourceRange(val correctedExposureSeconds: Double) : TableEvaluationResult
    data object InvalidInput : TableEvaluationResult
    data object InvalidRule : TableEvaluationResult
}

/** Anchors sorted ascending by metered exposure. */
val TableInterpolationReciprocityRule.sortedAnchors: List<TableAnchor>
    get() = anchors.sortedBy { it.meteredSeconds }

val TableInterpolationReciprocityRule.hasValidParameters: Boolean
    get() {
        val sorted = sortedAnchors
        if (sorted.size < 2) return false
        if (!noCorrectionThroughSeconds.isFinite() || noCorrectionThroughSeconds < 0) return false
        if (!sourceRangeThroughSeconds.isFinite()) return false

        var previousMetered = -Double.MAX_VALUE
        for (anchor in sorted) {
            if (!anchor.meteredSeconds.isFinite() || anchor.meteredSeconds <= 0 ||
                !anchor.correctedSeconds.isFinite() || anchor.correctedSeconds <= 0
            ) {
                return false
            }
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

fun TableInterpolationReciprocityRule.evaluate(meteredExposureSeconds: Double): TableEvaluationResult {
    if (!meteredExposureSeconds.isFinite() || meteredExposureSeconds <= 0) {
        return TableEvaluationResult.InvalidInput
    }
    if (!hasValidParameters) {
        return TableEvaluationResult.InvalidRule
    }
    if (ReciprocityNoCorrectionBoundary.isWithinNoCorrection(
            meteredSeconds = meteredExposureSeconds,
            throughSeconds = noCorrectionThroughSeconds,
        )
    ) {
        return TableEvaluationResult.NoCorrection
    }

    val sorted = sortedAnchors
    // Lower interpolation knee is the no-correction boundary point (Tc = Tm).
    val kneePoint = TableAnchor(
        meteredSeconds = noCorrectionThroughSeconds,
        correctedSeconds = noCorrectionThroughSeconds,
    )
    val points = listOf(kneePoint) + sorted

    val corrected: Double = if (meteredExposureSeconds <= sorted[sorted.size - 1].meteredSeconds) {
        interpolatedCorrected(meteredExposureSeconds, points)
    } else {
        logLogValue(
            metered = meteredExposureSeconds,
            lower = sorted[sorted.size - 2],
            upper = sorted[sorted.size - 1],
        )
    }

    val safeCorrected = maxOf(corrected, meteredExposureSeconds)
    if (!safeCorrected.isFinite() || safeCorrected <= 0) {
        return TableEvaluationResult.InvalidRule
    }

    return if (meteredExposureSeconds > sourceRangeThroughSeconds) {
        TableEvaluationResult.BeyondSourceRange(safeCorrected)
    } else {
        TableEvaluationResult.WithinSourceRange(safeCorrected)
    }
}

private fun interpolatedCorrected(meteredExposureSeconds: Double, points: List<TableAnchor>): Double {
    for (index in 1 until points.size) {
        val upper = points[index]
        if (meteredExposureSeconds <= upper.meteredSeconds) {
            return logLogValue(meteredExposureSeconds, points[index - 1], upper)
        }
    }
    return points[points.size - 1].correctedSeconds
}

/** Piecewise-linear interpolation in log10–log10 space between two anchors. */
private fun logLogValue(metered: Double, lower: TableAnchor, upper: TableAnchor): Double {
    val logMeteredLower = log10(lower.meteredSeconds)
    val logMeteredUpper = log10(upper.meteredSeconds)
    val logCorrectedLower = log10(lower.correctedSeconds)
    val logCorrectedUpper = log10(upper.correctedSeconds)

    val denominator = logMeteredUpper - logMeteredLower
    if (abs(denominator) <= ULP_OF_ONE) {
        return upper.correctedSeconds
    }
    val slope = (logCorrectedUpper - logCorrectedLower) / denominator
    val logCorrected = logCorrectedLower + slope * (log10(metered) - logMeteredLower)
    return 10.0.pow(logCorrected)
}

// MARK: - Descriptive profile model-basis (display/catalog vocabulary only;
// the calculation policy never branches on these).

val ReciprocityProfile.usesTableInterpolation: Boolean
    get() = rules.any { it.kind == ReciprocityRuleKind.tableInterpolation }

val ReciprocityProfile.isConvertedFormulaProfile: Boolean
    get() {
        val hasFormulaRule = rules.any { it.kind == ReciprocityRuleKind.formula }
        return hasFormulaRule &&
            sourceEvidence.isNotEmpty() &&
            source.authority == ReciprocityAuthority.official &&
            (source.kind == ReciprocitySourceKind.manufacturerPublished ||
                source.kind == ReciprocitySourceKind.manufacturerArchive)
    }

val ReciprocityProfile.presentsBeyondSourceRange: Boolean
    get() = isConvertedFormulaProfile || usesTableInterpolation

val ReciprocityProfile.effectiveModelBasis: ReciprocityProfileModelBasis
    get() = modelBasis ?: inferredModelBasis

private val ReciprocityProfile.inferredModelBasis: ReciprocityProfileModelBasis
    get() {
        val hasFormulaRule = rules.any { it.kind == ReciprocityRuleKind.formula }
        val hasLimitedGuidanceRule = rules.any { it.kind == ReciprocityRuleKind.limitedGuidance }
        val hasTableInterpolationRule = rules.any { it.kind == ReciprocityRuleKind.tableInterpolation }

        val calculationModel = when {
            hasTableInterpolationRule -> ReciprocityCalculationModel.tableLogLogInterpolation
            hasFormulaRule -> ReciprocityCalculationModel.guardedFormula
            hasLimitedGuidanceRule -> ReciprocityCalculationModel.limitedGuidance
            else -> ReciprocityCalculationModel.unsupported
        }

        val sourceModel = when (source.kind) {
            ReciprocitySourceKind.userDefined -> ReciprocitySourceModel.userDefined
            ReciprocitySourceKind.thirdPartyPublication -> ReciprocitySourceModel.practicalCommunityGuidance
            ReciprocitySourceKind.manufacturerPublished, ReciprocitySourceKind.manufacturerArchive -> when {
                hasTableInterpolationRule -> ReciprocitySourceModel.manufacturerTable
                hasFormulaRule -> if (sourceEvidence.isEmpty()) {
                    ReciprocitySourceModel.manufacturerFormula
                } else {
                    ReciprocitySourceModel.manufacturerTable
                }
                hasLimitedGuidanceRule -> ReciprocitySourceModel.manufacturerLimitedGuidance
                else -> ReciprocitySourceModel.unknown
            }
            ReciprocitySourceKind.unknown -> ReciprocitySourceModel.unknown
        }

        return ReciprocityProfileModelBasis(sourceModel, calculationModel)
    }
