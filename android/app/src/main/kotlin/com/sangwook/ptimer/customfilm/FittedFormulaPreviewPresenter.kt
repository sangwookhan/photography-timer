package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.reciprocity.CustomFilmFormulaGuard
import com.sangwook.ptimer.core.reciprocity.PowerLawFitResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormulaFitter
import com.sangwook.ptimer.core.reciprocity.TableInterpolationRule
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow

data class AnchorComparisonRow(
    val meteredSeconds: Double,
    val sourceCorrectedSeconds: Double,
    val fittedCorrectedSeconds: Double,
    val percentError: Double,
    val stopError: Double,
)

enum class FitQuality { GOOD, BORDERLINE, POOR }

/** Inspection-only fitted-formula preview for a custom table. NEVER the active calculation. */
sealed interface FittedPreview {
    data class Available(
        val coefficient: Double,
        val exponent: Double,
        val parameterText: String,
        val rows: List<AnchorComparisonRow>,
        val worstStopError: Double,
        val quality: FitQuality,
    ) : FittedPreview

    data class Unavailable(val reason: String, val tableRemainsReliable: Boolean = true) : FittedPreview
}

/**
 * Derives an inspection-only power-law fit preview from a custom table's
 * anchors (offset 0, Tref 1) with per-anchor comparison rows, fit quality,
 * and unavailable guidance. Mirrors iOS `CustomTableFittedFormulaPresenter`.
 * The preview never enters the active calculation.
 */
object FittedFormulaPreviewPresenter {
    private const val GOOD_MAX_STOP_ERROR = 0.1
    private const val BORDERLINE_MAX_STOP_ERROR = 0.25

    fun preview(rule: TableInterpolationRule): FittedPreview {
        val fit = when (val r = ReciprocityFormulaFitter.fit(rule.anchors)) {
            is PowerLawFitResult.Success -> r.fit
            is PowerLawFitResult.Failure -> return FittedPreview.Unavailable("A formula cannot be fit to these anchors (${r.reason.name}).")
        }
        // Reject a fit that would shorten exposure anywhere in the usable range.
        val passes = CustomFilmFormulaGuard.passesUsableRangeCheck(
            CustomFilmFormulaGuard.UsableRangeInput(
                exponent = fit.exponent, referenceMeteredTimeSeconds = 1.0, coefficientSeconds = fit.coefficient,
                offsetSeconds = 0.0, noCorrectionThroughSeconds = rule.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds = rule.sourceRangeThroughSeconds,
            ),
        )
        if (!passes) {
            return FittedPreview.Unavailable("The fitted formula would shorten the exposure; the table remains your reliable calculation.")
        }

        val rows = rule.anchors.map { anchor ->
            val fitted = fit.coefficient * anchor.meteredSeconds.pow(fit.exponent)
            val percent = (fitted - anchor.correctedSeconds) / anchor.correctedSeconds * 100.0
            val stop = ln(fitted / anchor.correctedSeconds) / ln(2.0)
            AnchorComparisonRow(anchor.meteredSeconds, anchor.correctedSeconds, fitted, percent, stop)
        }
        val worst = rows.maxOf { abs(it.stopError) }
        val quality = when {
            worst <= GOOD_MAX_STOP_ERROR -> FitQuality.GOOD
            worst <= BORDERLINE_MAX_STOP_ERROR -> FitQuality.BORDERLINE
            else -> FitQuality.POOR
        }
        return FittedPreview.Available(
            coefficient = fit.coefficient, exponent = fit.exponent,
            parameterText = "Tc = ${trim(fit.coefficient)} × Tm^${trim(fit.exponent)}",
            rows = rows, worstStopError = worst, quality = quality,
        )
    }

    /** Up to 4 decimals, never scientific notation. */
    private fun trim(value: Double): String =
        String.format(Locale.ROOT, "%.4f", value).trimEnd('0').trimEnd('.')
}
