package com.sangwook.ptimer.details

import com.sangwook.ptimer.core.catalog.CustomFilmReferenceTableResolver
import com.sangwook.ptimer.core.catalog.FilmIdentity
import com.sangwook.ptimer.core.catalog.ReciprocityProfile
import com.sangwook.ptimer.core.catalog.ReciprocityRule
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.reciprocity.FormulaEvaluationResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityConfidencePresentationMapper
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.customfilm.FittedFormulaPreviewPresenter
import com.sangwook.ptimer.customfilm.FittedPreview
import java.util.Locale
import kotlin.math.ln

data class DetailsRow(val label: String, val value: String)

/** Functional reciprocity-details transparency model (graph deferred). */
data class DetailsUi(
    val title: String,
    val rows: List<DetailsRow>,
    val comparisonTitle: String?,
    val comparisonLines: List<String>,
)

/**
 * Builds the source/model/calculation transparency for the selected film and
 * result: provenance, calculation model, basis badge, corrected value, source
 * range; for a custom table the inspection-only fitted comparison; for a
 * linked custom formula the reference-table error columns. Mirrors the
 * functional intent of iOS `ReciprocityModelMetadataPresenter` +
 * `FilmModeDetailsPresenter` (graph fidelity deferred).
 */
object DetailsPresenter {
    private val calculator = ExposureCalculator()

    fun build(
        film: FilmIdentity,
        profile: ReciprocityProfile,
        result: ReciprocityResult,
        meteredSeconds: Double,
        lookup: (String) -> FilmIdentity?,
    ): DetailsUi {
        val rule = profile.typedRules.firstOrNull()
        val rows = buildList {
            add(DetailsRow("Source", sourceLabel(profile)))
            add(DetailsRow("Calculation", calculationLabel(profile, rule)))
            add(DetailsRow("Basis", ReciprocityConfidencePresentationMapper.map(result).shortLabel))
            add(DetailsRow("Corrected exposure", correctedLabel(result)))
            sourceRangeSeconds(rule)?.let { add(DetailsRow("Source range through", calculator.formatExtendedClock(it))) }
        }

        var comparisonTitle: String? = null
        var comparisonLines: List<String> = emptyList()

        if (film.kind == "custom" && rule is ReciprocityRule.Table) {
            when (val preview = FittedFormulaPreviewPresenter.preview(rule.rule)) {
                is FittedPreview.Available -> {
                    comparisonTitle = "Fitted formula (inspection-only): ${preview.parameterText}"
                    comparisonLines = preview.rows.map {
                        "${fmt(it.meteredSeconds)}s → source ${fmt(it.sourceCorrectedSeconds)}s · fit ${fmt(it.fittedCorrectedSeconds)}s (${signed(it.stopError)} stops)"
                    }
                }
                is FittedPreview.Unavailable -> comparisonTitle = preview.reason
            }
        } else if (film.kind == "custom" && rule is ReciprocityRule.Formula) {
            val resolution = CustomFilmReferenceTableResolver.resolve(film, lookup)
            when {
                resolution.isLinkedButMissing -> comparisonTitle = "Reference table unavailable"
                resolution.anchors.isNotEmpty() -> {
                    comparisonTitle = "Reference table comparison (display-only)"
                    comparisonLines = resolution.anchors.map { anchor ->
                        val formulaValue = (rule.formula.evaluate(anchor.meteredSeconds) as? FormulaEvaluationResult.WithinSourceRange)?.correctedExposureSeconds
                            ?: (rule.formula.evaluate(anchor.meteredSeconds) as? FormulaEvaluationResult.BeyondSourceRange)?.correctedExposureSeconds
                        val error = if (formulaValue != null) signed(ln(formulaValue / anchor.correctedSeconds) / ln(2.0)) else "—"
                        "${fmt(anchor.meteredSeconds)}s → ref ${fmt(anchor.correctedSeconds)}s · formula ${formulaValue?.let { fmt(it) } ?: "—"}s ($error stops)"
                    }
                }
            }
        }

        return DetailsUi(
            title = "${film.canonicalStockName} · reciprocity",
            rows = rows,
            comparisonTitle = comparisonTitle,
            comparisonLines = comparisonLines,
        )
    }

    private fun calculationLabel(profile: ReciprocityProfile, rule: ReciprocityRule?): String = when (rule) {
        is ReciprocityRule.Table -> "Log-log table interpolation"
        is ReciprocityRule.Formula -> if (profile.source.authority == "userDefined") "Custom formula" else "Guarded formula"
        is ReciprocityRule.Threshold, is ReciprocityRule.LimitedGuidance -> "Threshold + limited guidance"
        null -> "Unsupported"
    }

    private fun sourceLabel(profile: ReciprocityProfile): String {
        val base = when (profile.source.authority) {
            "official" -> "Official guidance"
            "unofficial" -> "Unofficial practical"
            "userDefined" -> "Custom (user-defined)"
            else -> "Reciprocity"
        }
        val publisher = profile.source.publisher.takeIf { it.isNotBlank() }
        return if (publisher != null && profile.source.authority != "userDefined") "$base — $publisher" else base
    }

    private fun correctedLabel(result: ReciprocityResult): String =
        result.correctedExposureSeconds?.let { calculator.formatExtendedClock(it) } ?: "—"

    private fun sourceRangeSeconds(rule: ReciprocityRule?): Double? = when (rule) {
        is ReciprocityRule.Formula -> rule.formula.sourceRangeThroughSeconds
        is ReciprocityRule.Table -> rule.rule.sourceRangeThroughSeconds
        else -> null
    }

    private fun fmt(v: Double): String = String.format(Locale.ROOT, "%.4g", v).trimEnd('0').trimEnd('.')
    private fun signed(v: Double): String = String.format(Locale.ROOT, "%+.2f", v)
}
