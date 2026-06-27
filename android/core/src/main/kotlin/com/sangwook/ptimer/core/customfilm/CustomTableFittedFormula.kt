// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.reciprocity.FormulaEvaluationResult
import com.sangwook.ptimer.core.reciprocity.FormulaFamily
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.TableInterpolationReciprocityRule
import com.sangwook.ptimer.core.reciprocity.evaluate
import com.sangwook.ptimer.core.reciprocity.hasValidParameters
import com.sangwook.ptimer.core.reciprocity.sortedAnchors
import kotlin.math.abs
import kotlin.math.log2

/**
 * Turns a custom table profile's anchors into an inspection-only, app-derived
 * fitted-formula preview: fit `Tc = a × Tm^p`, map into the guarded formula
 * shape (b=0, Tref=1, inheriting the table's boundaries), reject any fit that
 * fails the non-shortening guard, and classify the worst per-anchor stop error.
 * The table keeps driving the real calculation; this is a candidate the
 * photographer can save as a separate formula film. (iOS:
 * CustomTableFittedFormulaPresenter.)
 */
object CustomTableFittedFormula {
    const val GOOD_FIT_MAX_STOP_ERROR = 0.1
    const val BORDERLINE_FIT_MAX_STOP_ERROR = 0.25

    enum class FitQuality(val displayLabel: String) {
        good("Good fit"),
        borderline("Borderline fit"),
        poor("Poor fit"),
    }

    data class ComparisonRow(
        val meteredSeconds: Double,
        val sourceCorrectedSeconds: Double,
        val fittedCorrectedSeconds: Double,
        val percentError: Double,
        val stopError: Double,
    )

    data class FittedFormula(
        val coefficientSeconds: Double,
        val exponent: Double,
        val offsetSeconds: Double,
        val referenceMeteredTimeSeconds: Double,
        val noCorrectionThroughSeconds: Double,
        val sourceRangeThroughSeconds: Double,
        val comparisonRows: List<ComparisonRow>,
        val worstAbsoluteStopError: Double,
        val quality: FitQuality,
        val anchorCount: Int,
    ) {
        val isTwoAnchorExactFit: Boolean get() = anchorCount == 2
    }

    sealed interface Outcome {
        data class Available(val formula: FittedFormula) : Outcome
        data class Unavailable(val message: String) : Outcome
    }

    fun outcome(rule: TableInterpolationReciprocityRule): Outcome {
        val anchors = rule.sortedAnchors
        val fit = when (val r = ReciprocityFormulaFitter.fit(anchors)) {
            is ReciprocityFormulaFitter.FitResult.Success -> r.fit
            is ReciprocityFormulaFitter.FitResult.Failure -> return Outcome.Unavailable(messageFor(r.reason))
        }

        val formula = ReciprocityFormula(
            formulaFamily = FormulaFamily.modifiedSchwarzschild,
            coefficientSeconds = fit.coefficient,
            referenceMeteredTimeSeconds = 1.0,
            exponent = fit.exponent,
            offsetSeconds = 0.0,
            noCorrectionThroughSeconds = rule.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds = rule.sourceRangeThroughSeconds,
        )
        if (!formula.hasValidParameters) {
            return Outcome.Unavailable("These anchors do not produce a usable formula.")
        }
        val guardOk = CustomFilmFormulaGuard.passesUsableRangeCheck(
            CustomFilmFormulaGuard.UsableRangeInput(
                exponent = formula.exponent,
                referenceMeteredTimeSeconds = formula.referenceMeteredTimeSeconds,
                coefficientSeconds = formula.coefficientSeconds,
                offsetSeconds = formula.offsetSeconds,
                noCorrectionThroughSeconds = formula.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds = formula.sourceRangeThroughSeconds,
            ),
        )
        if (!guardOk) {
            return Outcome.Unavailable(
                "The fitted formula would shorten exposure with the current table boundaries. " +
                    "Raise no correction or add a lower-range anchor. The table remains your reliable calculation.",
            )
        }

        val rows = anchors.map { anchor ->
            val fitted = fittedCorrectedSeconds(formula, anchor.meteredSeconds)
                ?: return Outcome.Unavailable("These anchors do not produce a usable formula.")
            val source = anchor.correctedSeconds
            ComparisonRow(
                meteredSeconds = anchor.meteredSeconds,
                sourceCorrectedSeconds = source,
                fittedCorrectedSeconds = fitted,
                percentError = (fitted - source) / source * 100,
                stopError = log2(fitted / source),
            )
        }
        val worst = rows.maxOfOrNull { abs(it.stopError) } ?: 0.0
        return Outcome.Available(
            FittedFormula(
                coefficientSeconds = formula.coefficientSeconds,
                exponent = formula.exponent,
                offsetSeconds = formula.offsetSeconds,
                referenceMeteredTimeSeconds = formula.referenceMeteredTimeSeconds,
                noCorrectionThroughSeconds = formula.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds = rule.sourceRangeThroughSeconds,
                comparisonRows = rows,
                worstAbsoluteStopError = worst,
                quality = quality(worst),
                anchorCount = anchors.size,
            ),
        )
    }

    fun quality(worstAbsoluteStopError: Double): FitQuality = when {
        worstAbsoluteStopError <= GOOD_FIT_MAX_STOP_ERROR -> FitQuality.good
        worstAbsoluteStopError <= BORDERLINE_FIT_MAX_STOP_ERROR -> FitQuality.borderline
        else -> FitQuality.poor
    }

    private fun messageFor(reason: ReciprocityFormulaFitter.UnavailableReason): String = when (reason) {
        ReciprocityFormulaFitter.UnavailableReason.insufficientAnchors -> "Add at least two anchors to fit a formula."
        ReciprocityFormulaFitter.UnavailableReason.nonPositiveAnchors -> "Anchor times must be positive to fit a formula."
        ReciprocityFormulaFitter.UnavailableReason.degenerateAnchors -> "Anchors must span more than one metered time."
        ReciprocityFormulaFitter.UnavailableReason.nonFiniteResult -> "These anchors do not produce a usable formula."
    }

    private fun fittedCorrectedSeconds(formula: ReciprocityFormula, meteredSeconds: Double): Double? =
        when (val r = formula.evaluate(meteredSeconds)) {
            is FormulaEvaluationResult.WithinSourceRange -> r.correctedExposureSeconds
            is FormulaEvaluationResult.BeyondSourceRange -> r.correctedExposureSeconds
            FormulaEvaluationResult.NoCorrection -> meteredSeconds
            else -> null
        }
}
