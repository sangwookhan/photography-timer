// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

/**
 * One row of the reciprocity Details "Source reference" / "Guidance boundary"
 * table: the metered exposure on the left, the published correction on the
 * right, with an optional indented sub-line (color filter or development note).
 * The sub-line keeps each value tied to its metered exposure rather than a
 * context-free flat list.
 */
data class ReciprocityReferenceRow(
    val meteredText: String,
    val valueText: String,
    val belowNote: String? = null,
)

/**
 * Builds the reciprocity Details "Source reference" table and "Guidance
 * boundary" rows from a profile's source-evidence rows plus its no-correction
 * band. Faithful port of iOS `FilmModeDetailsReferencePresenter`'s
 * source-evidence sections + `ReciprocitySourceEvidenceClassifier`.
 *
 * Both sections appear only when the profile publishes source evidence;
 * formula-only catalog entries (HP5, Pan F …) keep the lean layout with no
 * reference table, matching iOS.
 */
object ReciprocitySourceReferencePresenter {
    data class Result(
        val sourceReference: List<ReciprocityReferenceRow>,
        val guidanceBoundary: List<ReciprocityReferenceRow>,
    )

    fun rows(profile: ReciprocityProfile, formatDuration: (Double) -> String): Result {
        if (profile.sourceEvidence.isEmpty()) return Result(emptyList(), emptyList())

        // (sortValue, row); the no-correction band sorts first at 0.
        val sourceReference = mutableListOf<Pair<Double, ReciprocityReferenceRow>>()
        val guidanceBoundary = mutableListOf<ReciprocityReferenceRow>()

        noCorrectionBandRow(profile, formatDuration)?.let { sourceReference.add(0.0 to it) }

        for (row in profile.sourceEvidence) {
            val item = referenceItem(row.meteredExposure, row.adjustments, formatDuration) ?: continue
            if (isGuidanceBoundary(row)) {
                guidanceBoundary.add(item)
            } else {
                sourceReference.add(sortValue(row.meteredExposure) to item)
            }
        }

        return Result(
            sourceReference = sourceReference.sortedBy { it.first }.map { it.second },
            guidanceBoundary = guidanceBoundary,
        )
    }

    /** First rule's no-correction band as a "<= Xs · No correction range" row. */
    private fun noCorrectionBandRow(
        profile: ReciprocityProfile,
        formatDuration: (Double) -> String,
    ): ReciprocityReferenceRow? {
        for (rule in profile.rules) {
            when (rule.kind) {
                ReciprocityRuleKind.threshold ->
                    rule.threshold?.let { return thresholdBandRow(it.noCorrectionRange, formatDuration) }
                ReciprocityRuleKind.formula -> rule.formula?.let { r ->
                    if (r.formula.noCorrectionThroughSeconds > 0) {
                        return ReciprocityReferenceRow(
                            upperBoundLabel(r.formula.noCorrectionThroughSeconds, formatDuration),
                            "No correction range",
                        )
                    }
                }
                ReciprocityRuleKind.tableInterpolation -> rule.tableInterpolation?.let { r ->
                    if (r.noCorrectionThroughSeconds > 0) {
                        return ReciprocityReferenceRow(
                            upperBoundLabel(r.noCorrectionThroughSeconds, formatDuration),
                            "No correction range",
                        )
                    }
                }
                ReciprocityRuleKind.limitedGuidance -> Unit
            }
        }
        return null
    }

    private fun thresholdBandRow(
        range: ReciprocityTimeRange,
        formatDuration: (Double) -> String,
    ): ReciprocityReferenceRow {
        val lower = range.minimumSeconds
        val upper = range.maximumSeconds
        val metered = when {
            lower <= 0 && upper != null -> upperBoundLabel(upper, formatDuration)
            upper != null -> "${formatDuration(lower)}-${formatDuration(upper)}"
            else -> ">= ${formatDuration(lower)}"
        }
        return ReciprocityReferenceRow(metered, "No correction range")
    }

    /**
     * Upper-bound label: rules that sit one ε below a round value (e.g. Acros
     * II's 119.999999, used so the next stop fires at exactly 120 s) render as
     * strict "< 120s"; rules whose bound is the round value keep inclusive "<=".
     */
    private fun upperBoundLabel(upper: Double, formatDuration: (Double) -> String): String {
        val ceiling = ceil(upper)
        val gap = ceiling - upper
        return if (gap > 0 && gap < 1e-3) "< ${formatDuration(ceiling)}" else "<= ${formatDuration(upper)}"
    }

    /** Mirrors iOS `compactReferenceColumns`. */
    private fun referenceItem(
        metered: MeteredExposureSelector,
        adjustments: List<ReciprocityAdjustment>,
        formatDuration: (Double) -> String,
    ): ReciprocityReferenceRow? {
        val meteredText = meteredText(metered, formatDuration)
        val exposureText = combinedExposureColumn(adjustments, formatDuration)

        val developmentText = adjustments.firstNotNullOfOrNull {
            if (it.kind == ReciprocityAdjustmentKind.development) it.development?.instruction else null
        }
        val colorText = adjustments.firstNotNullOfOrNull {
            if (it.kind == ReciprocityAdjustmentKind.colorFilter) it.colorFilter?.filterName else null
        }

        if (exposureText != null) {
            // Development beats color correction when both exist on one entry
            // (deterministic; the launch catalog never mixes them). The note
            // renders on its own indented line below the row.
            return ReciprocityReferenceRow(meteredText, exposureText, developmentText ?: colorText)
        }

        val notRecommended = adjustments.any {
            it.kind == ReciprocityAdjustmentKind.warning &&
                it.warning?.severity == ReciprocityWarningSeverity.notRecommended
        }
        if (notRecommended) return ReciprocityReferenceRow(meteredText, "Not recommended")

        val noteText = adjustments.firstNotNullOfOrNull {
            if (it.kind == ReciprocityAdjustmentKind.note) it.note?.text else null
        }
        if (noteText != null) return ReciprocityReferenceRow(meteredText, noteText)

        return null
    }

    /** Combined stop/multiplier · corrected-time cell (iOS `combinedExposureColumn`). */
    private fun combinedExposureColumn(
        adjustments: List<ReciprocityAdjustment>,
        formatDuration: (Double) -> String,
    ): String? {
        var stopOrMultiplier: String? = null
        var corrected: String? = null
        for (adjustment in adjustments) {
            if (adjustment.kind != ReciprocityAdjustmentKind.exposure) continue
            val exposure = adjustment.exposure ?: continue
            when (exposure.kind) {
                ExposureAdjustmentKind.correctedTime -> exposure.correctedTime?.let { mapping ->
                    val formatted = formatDuration(mapping.correctedSeconds)
                    corrected = if (mapping.isApproximate) "≈$formatted" else formatted
                }
                ExposureAdjustmentKind.stopDelta ->
                    if (stopOrMultiplier == null) {
                        exposure.stopDelta?.let { stopOrMultiplier = formattedStopDelta(it.stopDelta) }
                    }
                ExposureAdjustmentKind.multiplier ->
                    if (stopOrMultiplier == null) {
                        exposure.multiplier?.let { stopOrMultiplier = "${trimNumber(it.factor)}x" }
                    }
            }
        }
        return when {
            stopOrMultiplier != null && corrected != null -> "$stopOrMultiplier · $corrected"
            stopOrMultiplier != null -> stopOrMultiplier
            corrected != null -> corrected
            else -> null
        }
    }

    private fun formattedStopDelta(value: Double): String {
        val absolute = abs(value)
        val sign = if (value >= 0) "+" else "-"
        val unit = if (abs(absolute - 1.0) < 1e-6) " stop" else " stops"
        return "$sign${trimNumber(absolute)}$unit"
    }

    private fun meteredText(
        selector: MeteredExposureSelector,
        formatDuration: (Double) -> String,
    ): String = when (selector.kind) {
        MeteredExposureSelectorKind.exactSeconds -> formatDuration(selector.exactSeconds ?: 0.0)
        MeteredExposureSelectorKind.range -> selector.range?.let { range ->
            range.maximumSeconds
                ?.let { "${formatDuration(range.minimumSeconds)}-${formatDuration(it)}" }
                ?: "${formatDuration(range.minimumSeconds)}+"
        } ?: ""
    }

    private fun sortValue(selector: MeteredExposureSelector): Double = when (selector.kind) {
        MeteredExposureSelectorKind.exactSeconds -> selector.exactSeconds ?: 0.0
        MeteredExposureSelectorKind.range -> selector.range?.minimumSeconds ?: 0.0
    }

    /** iOS `ReciprocitySourceEvidenceClassifier.isGuidanceBoundary`. */
    private fun isGuidanceBoundary(row: ReciprocitySourceEvidenceRow): Boolean {
        val hasNotRecommended = row.adjustments.any {
            it.kind == ReciprocityAdjustmentKind.warning &&
                it.warning?.severity == ReciprocityWarningSeverity.notRecommended
        }
        val hasExposure = row.adjustments.any { it.kind == ReciprocityAdjustmentKind.exposure }
        return hasNotRecommended && !hasExposure
    }

    /** Decimal with up to 2 fraction digits, trailing zeros stripped. */
    private fun trimNumber(value: Double): String {
        val s = String.format(Locale.ROOT, "%.2f", value)
        return s.trimEnd('0').trimEnd('.')
    }
}
