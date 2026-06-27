// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

// Faithful port of iOS PTimerCore ReciprocityConfidencePresentation +
// ReciprocityConfidencePresentationMapper (PROTECTED AREA — confidence
// presentation mapping is exact-parity). Consumes only policy output.

enum class ReciprocityConfidenceCategory { noCorrection, formulaDerived, limitedGuidance, unsupported }

enum class ReciprocityConfidenceLevel { high, medium, low, veryLow, none }

enum class ReciprocityConfidenceBadgeStyle { trusted, measured, caution, limitedGuidance, unsupported }

enum class ReciprocityConfidenceWarningEmphasis { none, note, caution, strong }

enum class ReciprocityConfidenceResultKind { noCorrection, formulaDerived, limitedGuidance, unsupported }

enum class ReciprocityConfidenceExplanationToken {
    thresholdGuidanceOnly,
    formulaDerived,
    currentOfficialSource,
    archivalOfficialSource,
    unofficialSecondarySource,
    userDefinedSource,
    withinStatedRange,
    beyondRepresentativePoint,
    beyondPolicyLimit,
    limitedGuidanceContinuationOnly,
    officialRangeExceeded,
    unsupportedByPolicy,
    calculatedExposureReturned,
    noCalculatedExposureReturned;

    val defaultText: String
        get() = when (this) {
            thresholdGuidanceOnly -> "Uses threshold-only official no-correction guidance."
            formulaDerived -> "Calculated from a profile formula."
            currentOfficialSource -> "Based on current official source data."
            archivalOfficialSource -> "Based on archival official source data."
            unofficialSecondarySource -> "Based on an unofficial secondary source."
            userDefinedSource -> "Based on user-supplied reciprocity data."
            withinStatedRange -> "Falls within the source's stated range."
            beyondRepresentativePoint -> "Extends beyond the source's last published reference point."
            beyondPolicyLimit -> "Falls beyond the current policy limit."
            limitedGuidanceContinuationOnly -> "Only limited guidance is available beyond the no-correction range."
            officialRangeExceeded -> "The official quantified range has been exceeded."
            unsupportedByPolicy -> "No supported calculation path is available for this result."
            calculatedExposureReturned -> "A corrected exposure time was returned."
            noCalculatedExposureReturned -> "No corrected exposure time was returned."
        }
}

data class ReciprocityConfidencePresentation(
    val category: ReciprocityConfidenceCategory,
    val level: ReciprocityConfidenceLevel,
    val badgeStyle: ReciprocityConfidenceBadgeStyle,
    val warningEmphasis: ReciprocityConfidenceWarningEmphasis,
    val resultKind: ReciprocityConfidenceResultKind,
    val shortLabel: String,
    val explanationTokens: List<ReciprocityConfidenceExplanationToken>,
    val supportingNotes: List<String>,
    val defaultExplanation: String,
    val returnsCalculatedExposureTime: Boolean,
) {
    init {
        validationError(category, badgeStyle, resultKind, explanationTokens, returnsCalculatedExposureTime)
            ?.let { error(it) }
    }
}

private fun expectedResultKind(category: ReciprocityConfidenceCategory): ReciprocityConfidenceResultKind =
    when (category) {
        ReciprocityConfidenceCategory.noCorrection -> ReciprocityConfidenceResultKind.noCorrection
        ReciprocityConfidenceCategory.formulaDerived -> ReciprocityConfidenceResultKind.formulaDerived
        ReciprocityConfidenceCategory.limitedGuidance -> ReciprocityConfidenceResultKind.limitedGuidance
        ReciprocityConfidenceCategory.unsupported -> ReciprocityConfidenceResultKind.unsupported
    }

private fun validationError(
    category: ReciprocityConfidenceCategory,
    badgeStyle: ReciprocityConfidenceBadgeStyle,
    resultKind: ReciprocityConfidenceResultKind,
    explanationTokens: List<ReciprocityConfidenceExplanationToken>,
    returnsCalculatedExposureTime: Boolean,
): String? {
    if (resultKind != expectedResultKind(category)) {
        return "resultKind must remain aligned with category."
    }
    when (category) {
        ReciprocityConfidenceCategory.limitedGuidance -> {
            if (badgeStyle == ReciprocityConfidenceBadgeStyle.unsupported) {
                return "limitedGuidance presentation must remain distinct from unsupported styling."
            }
            if (returnsCalculatedExposureTime) {
                return "limitedGuidance presentation must not imply a calculated exposure time."
            }
        }
        ReciprocityConfidenceCategory.unsupported -> {
            if (badgeStyle != ReciprocityConfidenceBadgeStyle.unsupported) {
                return "unsupported presentation must use unsupported badge styling."
            }
        }
        ReciprocityConfidenceCategory.noCorrection, ReciprocityConfidenceCategory.formulaDerived -> Unit
    }
    if (returnsCalculatedExposureTime &&
        explanationTokens.contains(ReciprocityConfidenceExplanationToken.noCalculatedExposureReturned)
    ) {
        return "Presentation cannot both return and omit a calculated exposure time."
    }
    if (!returnsCalculatedExposureTime &&
        explanationTokens.contains(ReciprocityConfidenceExplanationToken.calculatedExposureReturned)
    ) {
        return "Presentation cannot advertise a calculated exposure time when none was returned."
    }
    return null
}

private class ConfidencePayload(
    val level: ReciprocityConfidenceLevel,
    val warningEmphasis: ReciprocityConfidenceWarningEmphasis,
    val shortLabel: String,
    val explanationTokens: List<ReciprocityConfidenceExplanationToken>,
    val supportingNotes: List<String>,
    val defaultExplanation: String,
    val returnsCalculatedExposureTime: Boolean,
)

private fun badgeStyleFor(
    category: ReciprocityConfidenceCategory,
    level: ReciprocityConfidenceLevel,
): ReciprocityConfidenceBadgeStyle = when (category) {
    ReciprocityConfidenceCategory.unsupported -> ReciprocityConfidenceBadgeStyle.unsupported
    ReciprocityConfidenceCategory.limitedGuidance -> ReciprocityConfidenceBadgeStyle.limitedGuidance
    ReciprocityConfidenceCategory.formulaDerived -> when (level) {
        ReciprocityConfidenceLevel.high, ReciprocityConfidenceLevel.medium -> ReciprocityConfidenceBadgeStyle.measured
        ReciprocityConfidenceLevel.low, ReciprocityConfidenceLevel.veryLow, ReciprocityConfidenceLevel.none ->
            ReciprocityConfidenceBadgeStyle.caution
    }
    ReciprocityConfidenceCategory.noCorrection -> when (level) {
        ReciprocityConfidenceLevel.high -> ReciprocityConfidenceBadgeStyle.trusted
        ReciprocityConfidenceLevel.medium -> ReciprocityConfidenceBadgeStyle.measured
        ReciprocityConfidenceLevel.low, ReciprocityConfidenceLevel.veryLow, ReciprocityConfidenceLevel.none ->
            ReciprocityConfidenceBadgeStyle.caution
    }
}

private fun presentation(
    category: ReciprocityConfidenceCategory,
    payload: ConfidencePayload,
): ReciprocityConfidencePresentation = when (category) {
    ReciprocityConfidenceCategory.noCorrection -> ReciprocityConfidencePresentation(
        category = ReciprocityConfidenceCategory.noCorrection,
        level = payload.level,
        badgeStyle = badgeStyleFor(ReciprocityConfidenceCategory.noCorrection, payload.level),
        warningEmphasis = payload.warningEmphasis,
        resultKind = ReciprocityConfidenceResultKind.noCorrection,
        shortLabel = payload.shortLabel,
        explanationTokens = payload.explanationTokens,
        supportingNotes = payload.supportingNotes,
        defaultExplanation = payload.defaultExplanation,
        returnsCalculatedExposureTime = payload.returnsCalculatedExposureTime,
    )
    ReciprocityConfidenceCategory.formulaDerived -> ReciprocityConfidencePresentation(
        category = ReciprocityConfidenceCategory.formulaDerived,
        level = payload.level,
        badgeStyle = badgeStyleFor(ReciprocityConfidenceCategory.formulaDerived, payload.level),
        warningEmphasis = payload.warningEmphasis,
        resultKind = ReciprocityConfidenceResultKind.formulaDerived,
        shortLabel = payload.shortLabel,
        explanationTokens = payload.explanationTokens,
        supportingNotes = payload.supportingNotes,
        defaultExplanation = payload.defaultExplanation,
        returnsCalculatedExposureTime = payload.returnsCalculatedExposureTime,
    )
    ReciprocityConfidenceCategory.limitedGuidance -> ReciprocityConfidencePresentation(
        category = ReciprocityConfidenceCategory.limitedGuidance,
        level = ReciprocityConfidenceLevel.none,
        badgeStyle = ReciprocityConfidenceBadgeStyle.limitedGuidance,
        warningEmphasis = payload.warningEmphasis,
        resultKind = ReciprocityConfidenceResultKind.limitedGuidance,
        shortLabel = payload.shortLabel,
        explanationTokens = payload.explanationTokens,
        supportingNotes = payload.supportingNotes,
        defaultExplanation = payload.defaultExplanation,
        returnsCalculatedExposureTime = false,
    )
    ReciprocityConfidenceCategory.unsupported -> ReciprocityConfidencePresentation(
        category = ReciprocityConfidenceCategory.unsupported,
        level = ReciprocityConfidenceLevel.none,
        badgeStyle = ReciprocityConfidenceBadgeStyle.unsupported,
        warningEmphasis = payload.warningEmphasis,
        resultKind = ReciprocityConfidenceResultKind.unsupported,
        shortLabel = payload.shortLabel,
        explanationTokens = payload.explanationTokens,
        supportingNotes = payload.supportingNotes,
        defaultExplanation = payload.defaultExplanation,
        returnsCalculatedExposureTime = payload.returnsCalculatedExposureTime,
    )
}

/**
 * Maps calculation-layer result metadata into presentation-facing confidence
 * structure. Consumes only policy output; never re-inspects domain rules.
 */
class ReciprocityConfidencePresentationMapper {

    fun map(result: ReciprocityResult): ReciprocityConfidencePresentation {
        val payload = payload(result)
        return when (result.metadata.basis) {
            ReciprocityCalculationBasis.officialThresholdNoCorrection ->
                presentation(ReciprocityConfidenceCategory.noCorrection, payload)
            ReciprocityCalculationBasis.formulaDerived,
            ReciprocityCalculationBasis.tableLogLogDerived ->
                presentation(ReciprocityConfidenceCategory.formulaDerived, payload)
            ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction ->
                presentation(ReciprocityConfidenceCategory.limitedGuidance, payload)
            ReciprocityCalculationBasis.unsupportedOutOfPolicyRange ->
                presentation(ReciprocityConfidenceCategory.unsupported, payload)
        }
    }

    private fun payload(result: ReciprocityResult): ConfidencePayload {
        val tokens = explanationTokens(result)
        val supportingNotes = result.metadata.notes.map { it.text }
        return ConfidencePayload(
            level = defaultLevel(result.metadata.basis, result.metadata.sourceAuthorityImpact),
            warningEmphasis = warningEmphasis(result.metadata.warningLevel),
            shortLabel = shortLabel(result.metadata.basis, result.metadata.sourceAuthorityImpact),
            explanationTokens = tokens,
            supportingNotes = supportingNotes,
            defaultExplanation = fallbackExplanation(tokens, supportingNotes),
            returnsCalculatedExposureTime = result.hasCalculatedExposureTime,
        )
    }

    private fun defaultLevel(
        basis: ReciprocityCalculationBasis,
        impact: ReciprocitySourceAuthorityImpact,
    ): ReciprocityConfidenceLevel = when (basis) {
        ReciprocityCalculationBasis.officialThresholdNoCorrection,
        ReciprocityCalculationBasis.formulaDerived,
        ReciprocityCalculationBasis.tableLogLogDerived -> when (impact) {
            ReciprocitySourceAuthorityImpact.currentOfficial ->
                if (basis == ReciprocityCalculationBasis.formulaDerived) {
                    ReciprocityConfidenceLevel.medium
                } else {
                    ReciprocityConfidenceLevel.high
                }
            ReciprocitySourceAuthorityImpact.archivalOfficial -> ReciprocityConfidenceLevel.medium
            ReciprocitySourceAuthorityImpact.unofficialSecondary -> ReciprocityConfidenceLevel.low
            ReciprocitySourceAuthorityImpact.userDefined -> ReciprocityConfidenceLevel.veryLow
        }
        ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction -> ReciprocityConfidenceLevel.none
        ReciprocityCalculationBasis.unsupportedOutOfPolicyRange -> ReciprocityConfidenceLevel.none
    }

    private fun warningEmphasis(
        warningLevel: ReciprocityCalculationWarningLevel,
    ): ReciprocityConfidenceWarningEmphasis = when (warningLevel) {
        ReciprocityCalculationWarningLevel.none -> ReciprocityConfidenceWarningEmphasis.none
        ReciprocityCalculationWarningLevel.note -> ReciprocityConfidenceWarningEmphasis.note
        ReciprocityCalculationWarningLevel.caution -> ReciprocityConfidenceWarningEmphasis.caution
        ReciprocityCalculationWarningLevel.strongWarning -> ReciprocityConfidenceWarningEmphasis.strong
    }

    private fun shortLabel(
        basis: ReciprocityCalculationBasis,
        impact: ReciprocitySourceAuthorityImpact,
    ): String {
        val prefix = when (impact) {
            ReciprocitySourceAuthorityImpact.currentOfficial -> ""
            ReciprocitySourceAuthorityImpact.archivalOfficial -> "Archival "
            ReciprocitySourceAuthorityImpact.unofficialSecondary -> "Secondary "
            ReciprocitySourceAuthorityImpact.userDefined -> "Custom "
        }
        return when (basis) {
            ReciprocityCalculationBasis.officialThresholdNoCorrection ->
                if (prefix.isEmpty()) "No correction" else "${prefix}no correction"
            ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction ->
                if (prefix.isEmpty()) "No quantified prediction" else "${prefix}limited guidance"
            ReciprocityCalculationBasis.unsupportedOutOfPolicyRange -> "Outside guidance"
            ReciprocityCalculationBasis.formulaDerived ->
                if (prefix.isEmpty()) "Formula-derived" else "${prefix}formula"
            ReciprocityCalculationBasis.tableLogLogDerived ->
                if (prefix.isEmpty()) "Table-derived" else "${prefix}table"
        }
    }

    private fun fallbackExplanation(
        explanationTokens: List<ReciprocityConfidenceExplanationToken>,
        supportingNotes: List<String>,
    ): String {
        if (supportingNotes.isNotEmpty()) return supportingNotes.joinToString(" ")
        return explanationTokens.joinToString(" ") { it.defaultText }
    }

    private fun explanationTokens(
        result: ReciprocityResult,
    ): List<ReciprocityConfidenceExplanationToken> {
        val tokens = mutableListOf<ReciprocityConfidenceExplanationToken>()

        when (result.metadata.basis) {
            ReciprocityCalculationBasis.officialThresholdNoCorrection ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.thresholdGuidanceOnly)
            ReciprocityCalculationBasis.limitedGuidanceNoQuantifiedPrediction ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.limitedGuidanceContinuationOnly)
            ReciprocityCalculationBasis.unsupportedOutOfPolicyRange ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.unsupportedByPolicy)
            ReciprocityCalculationBasis.formulaDerived,
            ReciprocityCalculationBasis.tableLogLogDerived ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.formulaDerived)
        }

        when (result.metadata.sourceAuthorityImpact) {
            ReciprocitySourceAuthorityImpact.currentOfficial ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.currentOfficialSource)
            ReciprocitySourceAuthorityImpact.archivalOfficial ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.archivalOfficialSource)
            ReciprocitySourceAuthorityImpact.unofficialSecondary ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.unofficialSecondarySource)
            ReciprocitySourceAuthorityImpact.userDefined ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.userDefinedSource)
        }

        when (result.metadata.rangeStatus) {
            ReciprocityCalculationRangeStatus.withinStatedRange ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.withinStatedRange)
            ReciprocityCalculationRangeStatus.beyondLastRepresentativePoint ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.beyondRepresentativePoint)
            ReciprocityCalculationRangeStatus.beyondPolicyLimit ->
                tokens.appendUnique(ReciprocityConfidenceExplanationToken.beyondPolicyLimit)
        }

        for (note in result.metadata.notes) {
            explanationToken(note.token)?.let { tokens.appendUnique(it) }
        }

        tokens.appendUnique(
            if (result.hasCalculatedExposureTime) {
                ReciprocityConfidenceExplanationToken.calculatedExposureReturned
            } else {
                ReciprocityConfidenceExplanationToken.noCalculatedExposureReturned
            },
        )

        return tokens
    }

    private fun explanationToken(
        policyToken: ReciprocityPolicyNoteToken?,
    ): ReciprocityConfidenceExplanationToken? = when (policyToken) {
        ReciprocityPolicyNoteToken.thresholdGuidanceOnly ->
            ReciprocityConfidenceExplanationToken.thresholdGuidanceOnly
        ReciprocityPolicyNoteToken.limitedGuidanceContinuationOnly ->
            ReciprocityConfidenceExplanationToken.limitedGuidanceContinuationOnly
        ReciprocityPolicyNoteToken.beyondOfficialQuantifiedRange ->
            ReciprocityConfidenceExplanationToken.officialRangeExceeded
        ReciprocityPolicyNoteToken.archivalOfficialSource ->
            ReciprocityConfidenceExplanationToken.archivalOfficialSource
        ReciprocityPolicyNoteToken.unofficialSecondarySource ->
            ReciprocityConfidenceExplanationToken.unofficialSecondarySource
        ReciprocityPolicyNoteToken.userDefinedSource ->
            ReciprocityConfidenceExplanationToken.userDefinedSource
        ReciprocityPolicyNoteToken.unsupportedByPolicy ->
            ReciprocityConfidenceExplanationToken.unsupportedByPolicy
        null -> null
    }
}

private fun MutableList<ReciprocityConfidenceExplanationToken>.appendUnique(
    token: ReciprocityConfidenceExplanationToken,
) {
    if (!contains(token)) add(token)
}

/** Convenience: presentation mapped from this result. */
val ReciprocityResult.confidencePresentation: ReciprocityConfidencePresentation
    get() = ReciprocityConfidencePresentationMapper().map(this)
