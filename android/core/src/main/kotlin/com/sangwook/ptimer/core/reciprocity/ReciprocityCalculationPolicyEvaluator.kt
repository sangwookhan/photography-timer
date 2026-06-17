package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.ReciprocityProfile
import com.sangwook.ptimer.core.catalog.ReciprocityRule
import com.sangwook.ptimer.core.catalog.SourceProvenance

/**
 * Protected reciprocity policy evaluator. Evaluation order is part of the
 * contract: formula rule wins when present (it owns its own no-correction
 * and source-range guards), then table interpolation, then threshold
 * no-correction, then limited-guidance continuation, then unsupported.
 * Mirrors iOS `ReciprocityCalculationPolicyEvaluator`.
 *
 * Non-quantified results never carry a fabricated corrected exposure;
 * unsupported may carry a numeric continuation past the source range.
 */
class ReciprocityCalculationPolicyEvaluator {

    fun evaluate(profile: ReciprocityProfile, meteredExposureSeconds: Double): ReciprocityResult {
        val impact = mapSourceAuthorityImpact(profile.source)
        val rules = profile.typedRules

        rules.firstNotNullOfOrNull { it as? ReciprocityRule.Formula }?.let {
            return evaluateFormula(it.formula, meteredExposureSeconds, impact)
        }
        rules.firstNotNullOfOrNull { it as? ReciprocityRule.Table }?.let {
            return evaluateTable(it.rule, meteredExposureSeconds, impact)
        }
        rules.firstNotNullOfOrNull { it as? ReciprocityRule.Threshold }
            ?.takeIf { it.noCorrectionRange.contains(meteredExposureSeconds) }
            ?.let { return quantifiedNoCorrection(meteredExposureSeconds, impact, ReciprocityPolicyNoteToken.THRESHOLD_GUIDANCE_ONLY, "No correction is required within the stated official threshold range.") }
        rules.firstNotNullOfOrNull { it as? ReciprocityRule.LimitedGuidance }
            ?.takeIf { it.appliesWhenMetered?.contains(meteredExposureSeconds) ?: true }
            ?.let { return limitedGuidance(meteredExposureSeconds, impact) }

        return unsupported(meteredExposureSeconds, null, impact, "No supported reciprocity policy path matched this metered exposure.")
    }

    private fun evaluateFormula(
        formula: ReciprocityFormula,
        metered: Double,
        impact: ReciprocitySourceAuthorityImpact,
    ): ReciprocityResult = when (val r = formula.evaluate(metered)) {
        is FormulaEvaluationResult.NoCorrection ->
            quantifiedNoCorrection(metered, impact, ReciprocityPolicyNoteToken.THRESHOLD_GUIDANCE_ONLY, "Reciprocity correction is not applied within the formula's no-correction range.")
        is FormulaEvaluationResult.WithinSourceRange ->
            quantified(metered, r.correctedExposureSeconds, ReciprocityCalculationBasis.FORMULA_DERIVED, impact, "Calculated from a reciprocity formula profile.")
        is FormulaEvaluationResult.BeyondSourceRange ->
            unsupported(metered, r.correctedExposureSeconds, impact, "Outside manufacturer source range — value is a formula prediction past the published source range.")
        FormulaEvaluationResult.InvalidInput ->
            unsupported(metered, null, impact, "Metered exposure is not a positive finite number; no reciprocity correction can be computed.")
        FormulaEvaluationResult.InvalidFormula ->
            unsupported(metered, null, impact, "Formula parameters violate the safe-formula contract; the corrected exposure cannot be computed.")
        FormulaEvaluationResult.FormulaOutputUnusable ->
            unsupported(metered, null, impact, "Formula produced a non-finite or non-positive output for this metered exposure.")
        FormulaEvaluationResult.UnsafeShorteningFormula ->
            quantifiedNoCorrection(metered, impact, ReciprocityPolicyNoteToken.THRESHOLD_GUIDANCE_ONLY, "Reciprocity correction cannot shorten the adjusted shutter. Treating as No correction.")
    }

    private fun evaluateTable(
        rule: TableInterpolationRule,
        metered: Double,
        impact: ReciprocitySourceAuthorityImpact,
    ): ReciprocityResult = when (val r = rule.evaluate(metered)) {
        is TableEvaluationResult.NoCorrection ->
            quantifiedNoCorrection(metered, impact, ReciprocityPolicyNoteToken.THRESHOLD_GUIDANCE_ONLY, "Reciprocity correction cannot shorten the adjusted shutter. Treating as No correction.")
        is TableEvaluationResult.WithinSourceRange ->
            quantified(metered, r.correctedExposureSeconds, ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED, impact, "Calculated by log-log interpolation of the manufacturer reciprocity table.")
        is TableEvaluationResult.BeyondSourceRange ->
            unsupported(metered, r.correctedExposureSeconds, impact, "Beyond the published table — value is a log-log extrapolation past the published source range.")
        TableEvaluationResult.InvalidInput ->
            unsupported(metered, null, impact, "Metered exposure is not a positive finite number; no reciprocity correction can be computed.")
        TableEvaluationResult.InvalidRule ->
            unsupported(metered, null, impact, "Table anchors violate the safe-table contract; the corrected exposure cannot be computed.")
    }

    // MARK: - assembly

    private fun quantified(
        metered: Double, corrected: Double, basis: ReciprocityCalculationBasis,
        impact: ReciprocitySourceAuthorityImpact, note: String,
    ): ReciprocityResult = ReciprocityResult.Quantified(
        metered, corrected,
        ReciprocityResultMetadata(
            basis = basis, sourceAuthorityImpact = impact,
            rangeStatus = ReciprocityCalculationRangeStatus.WITHIN_STATED_RANGE,
            warningLevel = warningLevel(basis, impact),
            notes = listOf(ReciprocityPolicyNote(null, note)) + sourceAuthorityNotes(impact),
        ),
    )

    private fun quantifiedNoCorrection(
        metered: Double, impact: ReciprocitySourceAuthorityImpact,
        token: ReciprocityPolicyNoteToken, note: String,
    ): ReciprocityResult = ReciprocityResult.Quantified(
        metered, metered,
        ReciprocityResultMetadata(
            basis = ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, sourceAuthorityImpact = impact,
            rangeStatus = ReciprocityCalculationRangeStatus.WITHIN_STATED_RANGE,
            warningLevel = warningLevel(ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, impact),
            notes = listOf(ReciprocityPolicyNote(token, note)) + sourceAuthorityNotes(impact),
        ),
    )

    private fun limitedGuidance(metered: Double, impact: ReciprocitySourceAuthorityImpact): ReciprocityResult =
        ReciprocityResult.LimitedGuidance(
            metered,
            ReciprocityResultMetadata(
                basis = ReciprocityCalculationBasis.LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION, sourceAuthorityImpact = impact,
                rangeStatus = ReciprocityCalculationRangeStatus.BEYOND_LAST_REPRESENTATIVE_POINT,
                warningLevel = warningLevel(ReciprocityCalculationBasis.LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION, impact),
                notes = listOf(
                    ReciprocityPolicyNote(ReciprocityPolicyNoteToken.LIMITED_GUIDANCE_CONTINUATION_ONLY, "Only limited guidance is available for this metered exposure."),
                ) + sourceAuthorityNotes(impact),
            ),
        )

    private fun unsupported(
        metered: Double, correctedContinuation: Double?, impact: ReciprocitySourceAuthorityImpact, note: String,
    ): ReciprocityResult = ReciprocityResult.Unsupported(
        metered, correctedContinuation,
        ReciprocityResultMetadata(
            basis = ReciprocityCalculationBasis.UNSUPPORTED_OUT_OF_POLICY_RANGE, sourceAuthorityImpact = impact,
            rangeStatus = ReciprocityCalculationRangeStatus.BEYOND_POLICY_LIMIT,
            warningLevel = ReciprocityCalculationWarningLevel.STRONG_WARNING,
            notes = listOf(ReciprocityPolicyNote(ReciprocityPolicyNoteToken.UNSUPPORTED_BY_POLICY, note)) + sourceAuthorityNotes(impact),
        ),
    )

    private fun warningLevel(
        basis: ReciprocityCalculationBasis, impact: ReciprocitySourceAuthorityImpact,
    ): ReciprocityCalculationWarningLevel = when (basis) {
        ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION,
        ReciprocityCalculationBasis.FORMULA_DERIVED,
        ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED -> when (impact) {
            ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL -> ReciprocityCalculationWarningLevel.NONE
            ReciprocitySourceAuthorityImpact.ARCHIVAL_OFFICIAL -> ReciprocityCalculationWarningLevel.NOTE
            ReciprocitySourceAuthorityImpact.UNOFFICIAL_SECONDARY,
            ReciprocitySourceAuthorityImpact.USER_DEFINED -> ReciprocityCalculationWarningLevel.CAUTION
        }
        ReciprocityCalculationBasis.LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION -> when (impact) {
            ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL -> ReciprocityCalculationWarningLevel.NOTE
            else -> ReciprocityCalculationWarningLevel.CAUTION
        }
        ReciprocityCalculationBasis.UNSUPPORTED_OUT_OF_POLICY_RANGE -> ReciprocityCalculationWarningLevel.STRONG_WARNING
    }

    private fun sourceAuthorityNotes(impact: ReciprocitySourceAuthorityImpact): List<ReciprocityPolicyNote> = when (impact) {
        ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL -> emptyList()
        ReciprocitySourceAuthorityImpact.ARCHIVAL_OFFICIAL -> listOf(ReciprocityPolicyNote(ReciprocityPolicyNoteToken.ARCHIVAL_OFFICIAL_SOURCE, "Result is based on archival official reciprocity data."))
        ReciprocitySourceAuthorityImpact.UNOFFICIAL_SECONDARY -> listOf(ReciprocityPolicyNote(ReciprocityPolicyNoteToken.UNOFFICIAL_SECONDARY_SOURCE, "Result is based on an unofficial secondary reciprocity source."))
        ReciprocitySourceAuthorityImpact.USER_DEFINED -> listOf(ReciprocityPolicyNote(ReciprocityPolicyNoteToken.USER_DEFINED_SOURCE, "Result is based on user-defined reciprocity data."))
    }

    private fun mapSourceAuthorityImpact(source: SourceProvenance): ReciprocitySourceAuthorityImpact =
        when (source.kind) {
            "manufacturerPublished" -> ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL
            "manufacturerArchive" -> ReciprocitySourceAuthorityImpact.ARCHIVAL_OFFICIAL
            "thirdPartyPublication" -> ReciprocitySourceAuthorityImpact.UNOFFICIAL_SECONDARY
            "userDefined" -> ReciprocitySourceAuthorityImpact.USER_DEFINED
            else -> when (source.authority) {
                "official" -> ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL
                "userDefined" -> ReciprocitySourceAuthorityImpact.USER_DEFINED
                else -> ReciprocitySourceAuthorityImpact.UNOFFICIAL_SECONDARY
            }
        }
}
