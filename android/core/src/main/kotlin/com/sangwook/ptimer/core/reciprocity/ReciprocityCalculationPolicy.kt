// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToLong

// Faithful port of iOS PTimerCore ReciprocityCalculationPolicy (PROTECTED AREA —
// the evaluation order and result/basis semantics are exact-parity). Note text
// is reproduced verbatim. ReciprocityResult JSON serialization is added with
// the persistence unit; this file ports the runtime calculation.

enum class ReciprocityCalculationBasis {
    officialThresholdNoCorrection,
    limitedGuidanceNoQuantifiedPrediction,
    unsupportedOutOfPolicyRange,
    formulaDerived,
    tableLogLogDerived,
}

enum class ReciprocitySourceAuthorityImpact {
    currentOfficial,
    archivalOfficial,
    unofficialSecondary,
    userDefined,
}

enum class ReciprocityCalculationRangeStatus {
    withinStatedRange,
    beyondLastRepresentativePoint,
    beyondPolicyLimit,
}

enum class ReciprocityCalculationWarningLevel { none, note, caution, strongWarning }

enum class ReciprocityPolicyNoteToken {
    thresholdGuidanceOnly,
    limitedGuidanceContinuationOnly,
    beyondOfficialQuantifiedRange,
    archivalOfficialSource,
    unofficialSecondarySource,
    userDefinedSource,
    unsupportedByPolicy,
}

data class ReciprocityPolicyNote(
    val token: ReciprocityPolicyNoteToken? = null,
    val text: String,
)

data class ReciprocityResultMetadata(
    val basis: ReciprocityCalculationBasis,
    val sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
    val rangeStatus: ReciprocityCalculationRangeStatus,
    val warningLevel: ReciprocityCalculationWarningLevel,
    val notes: List<ReciprocityPolicyNote> = emptyList(),
)

/**
 * Tagged-union reciprocity outcome. `Quantified` always carries a corrected
 * exposure; `LimitedGuidance` carries none; `Unsupported` may optionally carry
 * a formula/table prediction beyond the source range.
 */
sealed interface ReciprocityResult {
    val meteredExposureSeconds: Double
    val metadata: ReciprocityResultMetadata

    data class Quantified(
        override val meteredExposureSeconds: Double,
        val correctedExposureSeconds: Double,
        override val metadata: ReciprocityResultMetadata,
    ) : ReciprocityResult {
        init {
            when (metadata.basis) {
                ReciprocityCalculationBasis.officialThresholdNoCorrection ->
                    require(abs(correctedExposureSeconds - meteredExposureSeconds) < 0.000_001) {
                        "officialThresholdNoCorrection must return corrected exposure equal to metered exposure."
                    }
                ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction ->
                    error("limitedGuidanceNoQuantifiedPrediction must not be carried by a quantified payload.")
                ReciprocityCalculationBasis.unsupportedOutOfPolicyRange ->
                    error("unsupportedOutOfPolicyRange must not be carried by a quantified payload.")
                ReciprocityCalculationBasis.formulaDerived,
                ReciprocityCalculationBasis.tableLogLogDerived -> Unit
            }
        }
    }

    data class LimitedGuidance(
        override val meteredExposureSeconds: Double,
        override val metadata: ReciprocityResultMetadata,
    ) : ReciprocityResult {
        init {
            require(metadata.basis == ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction) {
                "limitedGuidance payload must carry limitedGuidanceNoQuantifiedPrediction basis."
            }
        }
    }

    data class Unsupported(
        override val meteredExposureSeconds: Double,
        val correctedExposureSeconds: Double? = null,
        override val metadata: ReciprocityResultMetadata,
    ) : ReciprocityResult {
        init {
            require(metadata.basis == ReciprocityCalculationBasis.unsupportedOutOfPolicyRange) {
                "unsupported payload must carry unsupportedOutOfPolicyRange basis."
            }
        }
    }
}

/** Corrected exposure if present (quantified, or an unsupported prediction). */
val ReciprocityResult.calculatedCorrectedSeconds: Double?
    get() = when (this) {
        is ReciprocityResult.Quantified -> correctedExposureSeconds
        is ReciprocityResult.Unsupported -> correctedExposureSeconds
        is ReciprocityResult.LimitedGuidance -> null
    }

/** True when a numeric corrected exposure was returned. */
val ReciprocityResult.hasCalculatedExposureTime: Boolean
    get() = when (this) {
        is ReciprocityResult.Quantified -> true
        is ReciprocityResult.Unsupported -> correctedExposureSeconds != null
        is ReciprocityResult.LimitedGuidance -> false
    }

/**
 * Evaluates a reciprocity profile against a metered exposure. Evaluation order
 * is part of the policy contract: formula → table → threshold → limited
 * guidance → unsupported.
 */
class ReciprocityCalculationPolicyEvaluator {

    fun evaluate(profile: ReciprocityProfile, meteredExposureSeconds: Double): ReciprocityResult {
        val impact = mapSourceAuthorityImpact(profile.source)
        val assembler = ResultAssembler(impact)
        return evaluateRuleSelection(profile, meteredExposureSeconds, assembler)
    }

    private fun evaluateRuleSelection(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler,
    ): ReciprocityResult {
        val formulaRules = profile.rules.mapNotNull { it.formula }
        val tableRules = profile.rules.mapNotNull { it.tableInterpolation }
        val thresholdRules = profile.rules.mapNotNull { it.threshold }
        val limitedGuidanceRules = profile.rules.mapNotNull { it.limitedGuidance }

        formulaRules.firstOrNull()?.let {
            return evaluateFormulaRule(it, meteredExposureSeconds, assembler)
        }
        tableRules.firstOrNull()?.let {
            return evaluateTableInterpolationRule(it, meteredExposureSeconds, assembler)
        }
        thresholdRules.firstOrNull { it.noCorrectionRange.contains(meteredExposureSeconds) }?.let {
            return assembler.thresholdNoCorrection(meteredExposureSeconds, it)
        }
        limitedGuidanceRules.firstOrNull {
            it.appliesWhenMetered?.contains(meteredExposureSeconds) ?: true
        }?.let {
            return assembler.limitedGuidance(meteredExposureSeconds, it)
        }

        return assembler.unsupported(
            meteredExposureSeconds,
            notes = listOf(
                ReciprocityPolicyNote(
                    ReciprocityPolicyNoteToken.unsupportedByPolicy,
                    "No supported reciprocity policy path matched this metered exposure.",
                ),
            ),
        )
    }

    private fun evaluateFormulaRule(
        rule: FormulaReciprocityRule,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler,
    ): ReciprocityResult =
        when (val result = rule.formula.evaluate(meteredExposureSeconds)) {
            is FormulaEvaluationResult.NoCorrection ->
                assembler.formulaNoCorrection(meteredExposureSeconds, rule)
            is FormulaEvaluationResult.WithinSourceRange ->
                assembler.formula(meteredExposureSeconds, result.correctedExposureSeconds, rule)
            is FormulaEvaluationResult.BeyondSourceRange ->
                assembler.unsupportedFormulaOutsideSourceRange(
                    meteredExposureSeconds, result.correctedExposureSeconds, rule,
                )
            is FormulaEvaluationResult.InvalidInput -> assembler.unsupported(
                meteredExposureSeconds,
                notes = listOf(
                    ReciprocityPolicyNote(
                        ReciprocityPolicyNoteToken.unsupportedByPolicy,
                        "Metered exposure is not a positive finite number; no reciprocity correction can be computed.",
                    ),
                ),
            )
            is FormulaEvaluationResult.InvalidFormula -> assembler.unsupported(
                meteredExposureSeconds,
                notes = listOf(
                    ReciprocityPolicyNote(
                        ReciprocityPolicyNoteToken.unsupportedByPolicy,
                        "Formula parameters violate the safe-formula contract; the corrected exposure cannot be computed.",
                    ),
                ),
            )
            is FormulaEvaluationResult.FormulaOutputUnusable -> assembler.unsupported(
                meteredExposureSeconds,
                notes = listOf(
                    ReciprocityPolicyNote(
                        ReciprocityPolicyNoteToken.unsupportedByPolicy,
                        "Formula produced a non-finite or non-positive output for this metered exposure.",
                    ),
                ),
            )
            is FormulaEvaluationResult.UnsafeShorteningFormula ->
                assembler.invariantClampedNoCorrection(meteredExposureSeconds)
        }

    private fun evaluateTableInterpolationRule(
        rule: TableInterpolationReciprocityRule,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler,
    ): ReciprocityResult =
        when (val result = rule.evaluate(meteredExposureSeconds)) {
            is TableEvaluationResult.NoCorrection ->
                assembler.invariantClampedNoCorrection(meteredExposureSeconds)
            is TableEvaluationResult.WithinSourceRange ->
                assembler.tableLogLog(meteredExposureSeconds, result.correctedExposureSeconds, rule)
            is TableEvaluationResult.BeyondSourceRange ->
                assembler.tableOutsideSourceRange(meteredExposureSeconds, result.correctedExposureSeconds, rule)
            is TableEvaluationResult.InvalidInput -> assembler.unsupported(
                meteredExposureSeconds,
                notes = listOf(
                    ReciprocityPolicyNote(
                        ReciprocityPolicyNoteToken.unsupportedByPolicy,
                        "Metered exposure is not a positive finite number; no reciprocity correction can be computed.",
                    ),
                ),
            )
            is TableEvaluationResult.InvalidRule -> assembler.unsupported(
                meteredExposureSeconds,
                notes = listOf(
                    ReciprocityPolicyNote(
                        ReciprocityPolicyNoteToken.unsupportedByPolicy,
                        "Table anchors violate the safe-table contract; the corrected exposure cannot be computed.",
                    ),
                ),
            )
        }

    private fun mapSourceAuthorityImpact(source: ReciprocitySourceProvenance): ReciprocitySourceAuthorityImpact =
        when (source.kind) {
            ReciprocitySourceKind.manufacturerPublished -> ReciprocitySourceAuthorityImpact.currentOfficial
            ReciprocitySourceKind.manufacturerArchive -> ReciprocitySourceAuthorityImpact.archivalOfficial
            ReciprocitySourceKind.thirdPartyPublication -> ReciprocitySourceAuthorityImpact.unofficialSecondary
            ReciprocitySourceKind.userDefined -> ReciprocitySourceAuthorityImpact.userDefined
            ReciprocitySourceKind.unknown -> when (source.authority) {
                ReciprocityAuthority.official -> ReciprocitySourceAuthorityImpact.currentOfficial
                ReciprocityAuthority.unofficial -> ReciprocitySourceAuthorityImpact.unofficialSecondary
                ReciprocityAuthority.userDefined -> ReciprocitySourceAuthorityImpact.userDefined
                ReciprocityAuthority.unknown -> ReciprocitySourceAuthorityImpact.unofficialSecondary
            }
        }
}

private class ResultAssembler(val sourceAuthorityImpact: ReciprocitySourceAuthorityImpact) {

    fun thresholdNoCorrection(
        meteredExposureSeconds: Double,
        thresholdRule: ThresholdReciprocityRule,
    ): ReciprocityResult {
        val noteText = thresholdRule.notes.firstOrNull()
            ?: "No correction is required within the stated official threshold range."
        return thresholdNoCorrectionResult(
            meteredExposureSeconds,
            listOf(ReciprocityPolicyNote(ReciprocityPolicyNoteToken.thresholdGuidanceOnly, noteText)) +
                sourceAuthorityNotes(),
        )
    }

    fun formulaNoCorrection(
        meteredExposureSeconds: Double,
        formulaRule: FormulaReciprocityRule,
    ): ReciprocityResult {
        val comparison = noCorrectionBoundaryComparisonText(formulaRule.formula.noCorrectionThroughSeconds)
        return thresholdNoCorrectionResult(
            meteredExposureSeconds,
            listOf(
                ReciprocityPolicyNote(
                    ReciprocityPolicyNoteToken.thresholdGuidanceOnly,
                    "Reciprocity correction is not applied within the formula's no-correction range ($comparison).",
                ),
            ) + sourceAuthorityNotes(),
        )
    }

    fun invariantClampedNoCorrection(meteredExposureSeconds: Double): ReciprocityResult =
        thresholdNoCorrectionResult(
            meteredExposureSeconds,
            listOf(
                ReciprocityPolicyNote(
                    ReciprocityPolicyNoteToken.thresholdGuidanceOnly,
                    "Reciprocity correction cannot shorten the adjusted shutter. Treating as No correction.",
                ),
            ) + sourceAuthorityNotes(),
        )

    fun limitedGuidance(
        meteredExposureSeconds: Double,
        limitedGuidanceRule: LimitedGuidanceReciprocityRule,
    ): ReciprocityResult {
        val noteText = limitedGuidanceRule.adjustments.firstNotNullOfOrNull { limitedGuidanceNoteText(it) }
            ?: limitedGuidanceRule.notes.firstOrNull()
            ?: "Manufacturer publishes only qualitative guidance beyond the no-correction range."
        val metadata = ReciprocityResultMetadata(
            basis = ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction,
            sourceAuthorityImpact = sourceAuthorityImpact,
            rangeStatus = ReciprocityCalculationRangeStatus.beyondLastRepresentativePoint,
            warningLevel = warningLevelFor(
                ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction, sourceAuthorityImpact,
            ),
            notes = listOf(
                ReciprocityPolicyNote(
                    ReciprocityPolicyNoteToken.limitedGuidanceContinuationOnly,
                    "Only limited guidance is available for this metered exposure.",
                ),
                ReciprocityPolicyNote(ReciprocityPolicyNoteToken.beyondOfficialQuantifiedRange, noteText),
            ) + sourceAuthorityNotes(),
        )
        return ReciprocityResult.LimitedGuidance(meteredExposureSeconds, metadata)
    }

    fun unsupported(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double? = null,
        notes: List<ReciprocityPolicyNote>,
    ): ReciprocityResult {
        val metadata = ReciprocityResultMetadata(
            basis = ReciprocityCalculationBasis.unsupportedOutOfPolicyRange,
            sourceAuthorityImpact = sourceAuthorityImpact,
            rangeStatus = ReciprocityCalculationRangeStatus.beyondPolicyLimit,
            warningLevel = ReciprocityCalculationWarningLevel.strongWarning,
            notes = notes + sourceAuthorityNotes(),
        )
        return ReciprocityResult.Unsupported(meteredExposureSeconds, correctedExposureSeconds, metadata)
    }

    fun formula(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        formulaRule: FormulaReciprocityRule,
    ): ReciprocityResult {
        val noteText = formulaRule.notes.firstOrNull() ?: "Calculated from a reciprocity formula profile."
        val metadata = quantifiedMetadata(
            ReciprocityCalculationBasis.formulaDerived,
            listOf(ReciprocityPolicyNote(text = noteText)) + sourceAuthorityNotes(),
        )
        return ReciprocityResult.Quantified(meteredExposureSeconds, correctedExposureSeconds, metadata)
    }

    fun tableLogLog(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        rule: TableInterpolationReciprocityRule,
    ): ReciprocityResult {
        val noteText = rule.notes.firstOrNull()
            ?: "Calculated by log-log interpolation of the manufacturer reciprocity table."
        val metadata = quantifiedMetadata(
            ReciprocityCalculationBasis.tableLogLogDerived,
            listOf(ReciprocityPolicyNote(text = noteText)) + sourceAuthorityNotes(),
        )
        return ReciprocityResult.Quantified(meteredExposureSeconds, correctedExposureSeconds, metadata)
    }

    fun tableOutsideSourceRange(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        rule: TableInterpolationReciprocityRule,
    ): ReciprocityResult = unsupported(
        meteredExposureSeconds,
        correctedExposureSeconds,
        notes = listOf(
            ReciprocityPolicyNote(
                ReciprocityPolicyNoteToken.beyondOfficialQuantifiedRange,
                "Source table ends at ${formatBoundarySeconds(rule.sourceRangeThroughSeconds)}.",
            ),
            ReciprocityPolicyNote(
                ReciprocityPolicyNoteToken.unsupportedByPolicy,
                "Beyond the published table — value is a log-log extrapolation past the published source range.",
            ),
        ),
    )

    fun unsupportedFormulaOutsideSourceRange(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        formulaRule: FormulaReciprocityRule,
    ): ReciprocityResult {
        val upper = formulaRule.formula.sourceRangeThroughSeconds
        val boundaryText = if (upper != null) {
            "Manufacturer source range ends at ${formatBoundarySeconds(upper)}."
        } else {
            "Manufacturer source range does not cover this metered exposure."
        }
        return unsupported(
            meteredExposureSeconds,
            correctedExposureSeconds,
            notes = listOf(
                ReciprocityPolicyNote(ReciprocityPolicyNoteToken.beyondOfficialQuantifiedRange, boundaryText),
                ReciprocityPolicyNote(
                    ReciprocityPolicyNoteToken.unsupportedByPolicy,
                    "Outside manufacturer source range — value is a formula prediction outside the published source range.",
                ),
            ),
        )
    }

    private fun thresholdNoCorrectionResult(
        meteredExposureSeconds: Double,
        notes: List<ReciprocityPolicyNote>,
    ): ReciprocityResult {
        val metadata = ReciprocityResultMetadata(
            basis = ReciprocityCalculationBasis.officialThresholdNoCorrection,
            sourceAuthorityImpact = sourceAuthorityImpact,
            rangeStatus = ReciprocityCalculationRangeStatus.withinStatedRange,
            warningLevel = warningLevelFor(
                ReciprocityCalculationBasis.officialThresholdNoCorrection, sourceAuthorityImpact,
            ),
            notes = notes,
        )
        return ReciprocityResult.Quantified(meteredExposureSeconds, meteredExposureSeconds, metadata)
    }

    private fun quantifiedMetadata(
        basis: ReciprocityCalculationBasis,
        notes: List<ReciprocityPolicyNote>,
    ): ReciprocityResultMetadata = ReciprocityResultMetadata(
        basis = basis,
        sourceAuthorityImpact = sourceAuthorityImpact,
        rangeStatus = ReciprocityCalculationRangeStatus.withinStatedRange,
        warningLevel = warningLevelFor(basis, sourceAuthorityImpact),
        notes = notes,
    )

    private fun formatBoundarySeconds(value: Double): String {
        if (abs(value.roundToLong() - value) < 0.000_001) {
            return "${value.roundToLong()} sec"
        }
        return String.format(Locale.ROOT, "%.3f sec", value)
    }

    private fun noCorrectionBoundaryComparisonText(value: Double): String {
        val ceiling = ceil(value)
        val gap = ceiling - value
        if (gap > 0 && gap < 1e-3) {
            return "< ${formatBoundarySeconds(ceiling)}"
        }
        return "≤ ${formatBoundarySeconds(value)}"
    }

    private fun sourceAuthorityNotes(): List<ReciprocityPolicyNote> = when (sourceAuthorityImpact) {
        ReciprocitySourceAuthorityImpact.currentOfficial -> emptyList()
        ReciprocitySourceAuthorityImpact.archivalOfficial -> listOf(
            ReciprocityPolicyNote(
                ReciprocityPolicyNoteToken.archivalOfficialSource,
                "Result is based on archival official reciprocity data.",
            ),
        )
        ReciprocitySourceAuthorityImpact.unofficialSecondary -> listOf(
            ReciprocityPolicyNote(
                ReciprocityPolicyNoteToken.unofficialSecondarySource,
                "Result is based on an unofficial secondary reciprocity source.",
            ),
        )
        ReciprocitySourceAuthorityImpact.userDefined -> listOf(
            ReciprocityPolicyNote(
                ReciprocityPolicyNoteToken.userDefinedSource,
                "Result is based on user-defined reciprocity data.",
            ),
        )
    }

    private fun limitedGuidanceNoteText(adjustment: ReciprocityAdjustment): String? =
        if (adjustment.kind == ReciprocityAdjustmentKind.note) adjustment.note?.text else null
}

private fun warningLevelFor(
    basis: ReciprocityCalculationBasis,
    impact: ReciprocitySourceAuthorityImpact,
): ReciprocityCalculationWarningLevel = when (basis) {
    ReciprocityCalculationBasis.officialThresholdNoCorrection -> when (impact) {
        ReciprocitySourceAuthorityImpact.currentOfficial -> ReciprocityCalculationWarningLevel.none
        ReciprocitySourceAuthorityImpact.archivalOfficial -> ReciprocityCalculationWarningLevel.note
        ReciprocitySourceAuthorityImpact.unofficialSecondary,
        ReciprocitySourceAuthorityImpact.userDefined -> ReciprocityCalculationWarningLevel.caution
    }
    ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction -> when (impact) {
        ReciprocitySourceAuthorityImpact.currentOfficial -> ReciprocityCalculationWarningLevel.note
        ReciprocitySourceAuthorityImpact.archivalOfficial,
        ReciprocitySourceAuthorityImpact.unofficialSecondary,
        ReciprocitySourceAuthorityImpact.userDefined -> ReciprocityCalculationWarningLevel.caution
    }
    ReciprocityCalculationBasis.unsupportedOutOfPolicyRange -> ReciprocityCalculationWarningLevel.strongWarning
    ReciprocityCalculationBasis.formulaDerived,
    ReciprocityCalculationBasis.tableLogLogDerived -> when (impact) {
        ReciprocitySourceAuthorityImpact.currentOfficial -> ReciprocityCalculationWarningLevel.none
        ReciprocitySourceAuthorityImpact.archivalOfficial -> ReciprocityCalculationWarningLevel.note
        ReciprocitySourceAuthorityImpact.unofficialSecondary,
        ReciprocitySourceAuthorityImpact.userDefined -> ReciprocityCalculationWarningLevel.caution
    }
}

private fun ReciprocityTimeRange.contains(seconds: Double): Boolean {
    if (seconds < minimumSeconds) return false
    val max = maximumSeconds ?: return true
    return seconds <= max
}
