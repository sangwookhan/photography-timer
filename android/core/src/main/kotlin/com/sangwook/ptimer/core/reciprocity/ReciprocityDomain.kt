package com.sangwook.ptimer.core.reciprocity

import kotlinx.serialization.Serializable

// Faithful port of iOS PTimerCore ReciprocityDomain (PROTECTED AREA for the
// evaluators and policy that consume these types). Enum constants are named to
// match the on-disk JSON schema exactly so the bundled catalog decodes without
// custom serializers. Polymorphic rules/adjustments use the iOS shape
// `{"kind": "<tag>", "<tag>": { ... }}`, reproduced here as a discriminator
// plus parallel nullable payload fields.

/**
 * Boundary policy for the no-correction band, used by the TABLE evaluator only.
 * The formula evaluator keeps a strict boundary.
 */
object ReciprocityNoCorrectionBoundary {
    const val RELATIVE_TOLERANCE: Double = 0.10

    fun isWithinNoCorrection(meteredSeconds: Double, throughSeconds: Double): Boolean =
        meteredSeconds <= throughSeconds * (1 + RELATIVE_TOLERANCE)
}

enum class FilmIdentityKind { preset, custom, unknown }

enum class FilmProductionStatus { current, discontinued, unknown }

@Serializable
data class FilmIdentity(
    val id: String,
    val kind: FilmIdentityKind,
    val canonicalStockName: String,
    val manufacturer: String? = null,
    val brandLabel: String? = null,
    val aliases: List<String>,
    val iso: Int,
    val productionStatus: FilmProductionStatus,
    val profiles: List<ReciprocityProfile>,
    val userMetadata: UserEditableMetadata? = null,
)

@Serializable
data class UserEditableMetadata(
    val displayNameOverride: String? = null,
    val tags: List<String> = emptyList(),
    val notes: List<String> = emptyList(),
    val customSourceType: CustomProfileSourceType? = null,
    val customManufacturer: String? = null,
    val referenceURL: String? = null,
    /** PTIMER-180 display-only link to a custom table film; never read by calc. */
    val referenceTableFilmID: String? = null,
)

/**
 * User-facing source classification for a custom (user-authored) profile.
 * Descriptive metadata only — never read by the calculation policy.
 */
enum class CustomProfileSourceType {
    userDefined,
    personalTest,
    communityReference,
    unknown;

    val displayLabel: String
        get() = when (this) {
            userDefined -> "User-defined"
            personalTest -> "Personal test"
            communityReference -> "Community reference"
            unknown -> "Unknown source"
        }
}

@Serializable
data class ReciprocityProfile(
    val id: String,
    val name: String,
    val source: ReciprocitySourceProvenance,
    val rules: List<ReciprocityRule>,
    val notes: List<String> = emptyList(),
    val userMetadata: UserEditableMetadata? = null,
    val sourceEvidence: List<ReciprocitySourceEvidenceRow> = emptyList(),
    val modelBasis: ReciprocityProfileModelBasis? = null,
    val selectorLabel: String? = null,
)

@Serializable
data class ReciprocitySourceEvidenceRow(
    val meteredExposure: MeteredExposureSelector,
    val adjustments: List<ReciprocityAdjustment>,
    val notes: List<String> = emptyList(),
    val isSourceEvidenceOnly: Boolean = false,
)

enum class ReciprocitySourceModel {
    manufacturerFormula,
    manufacturerTable,
    manufacturerGraphTable,
    manufacturerRangeGuidance,
    manufacturerLimitedGuidance,
    practicalCommunityGuidance,
    userDefined,
    unknown,
}

enum class ReciprocityCalculationModel {
    guardedFormula,
    limitedGuidance,
    unsupported,
    tableLookup,
    tableLogLogInterpolation,
}

@Serializable
data class ReciprocityProfileModelBasis(
    val sourceModel: ReciprocitySourceModel,
    val calculationModel: ReciprocityCalculationModel,
)

@Serializable
data class ReciprocitySourceProvenance(
    val kind: ReciprocitySourceKind,
    val authority: ReciprocityAuthority,
    val confidence: ReciprocityConfidence = ReciprocityConfidence.unknown,
    val publisher: String,
    val title: String? = null,
    val citation: String? = null,
    val sourceVersion: String? = null,
)

enum class ReciprocitySourceKind {
    manufacturerPublished,
    manufacturerArchive,
    thirdPartyPublication,
    userDefined,
    unknown,
}

enum class ReciprocityAuthority { official, unofficial, userDefined, unknown }

enum class ReciprocityConfidence { high, medium, low, unknown }

enum class ReciprocityRuleKind { threshold, formula, limitedGuidance, tableInterpolation }

/**
 * Reciprocity rule. JSON shape `{"kind": "<tag>", "<tag>": { ... }}` is
 * reproduced as a discriminator plus parallel nullable payloads; exactly one
 * payload is non-null for a valid rule.
 */
@Serializable
data class ReciprocityRule(
    val kind: ReciprocityRuleKind,
    val threshold: ThresholdReciprocityRule? = null,
    val formula: FormulaReciprocityRule? = null,
    val limitedGuidance: LimitedGuidanceReciprocityRule? = null,
    val tableInterpolation: TableInterpolationReciprocityRule? = null,
)

@Serializable
data class ThresholdReciprocityRule(
    val noCorrectionRange: ReciprocityTimeRange,
    val adjustments: List<ReciprocityAdjustment> = emptyList(),
    val notes: List<String> = emptyList(),
)

@Serializable
data class FormulaReciprocityRule(
    val formula: ReciprocityFormula,
    val additionalAdjustments: List<ReciprocityAdjustment> = emptyList(),
    val notes: List<String> = emptyList(),
)

@Serializable
data class LimitedGuidanceReciprocityRule(
    val appliesWhenMetered: ReciprocityTimeRange? = null,
    val adjustments: List<ReciprocityAdjustment> = emptyList(),
    val notes: List<String> = emptyList(),
)

@Serializable
data class TableAnchor(
    val meteredSeconds: Double,
    val correctedSeconds: Double,
)

@Serializable
data class TableInterpolationReciprocityRule(
    val anchors: List<TableAnchor>,
    val additionalAdjustments: List<ReciprocityAdjustment> = emptyList(),
    val notes: List<String> = emptyList(),
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double,
)

@Serializable
data class ReciprocityTimeRange(
    val minimumSeconds: Double,
    val maximumSeconds: Double? = null,
)

enum class FormulaFamily { modifiedSchwarzschild }

/**
 * Shared guarded reciprocity formula (Modified Schwarzschild):
 * `Tc = a × (Tm / Tref)^p + b`. PROTECTED — see [evaluate].
 */
@Serializable
data class ReciprocityFormula(
    val formulaFamily: FormulaFamily,
    val coefficientSeconds: Double = 1.0,
    val referenceMeteredTimeSeconds: Double = 1.0,
    val exponent: Double,
    val offsetSeconds: Double = 0.0,
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double? = null,
)

@Serializable
data class MeteredExposureSelector(
    val kind: MeteredExposureSelectorKind,
    val exactSeconds: Double? = null,
    val range: ReciprocityTimeRange? = null,
)

enum class MeteredExposureSelectorKind { exactSeconds, range }

@Serializable
data class ReciprocityAdjustment(
    val kind: ReciprocityAdjustmentKind,
    val exposure: ExposureAdjustment? = null,
    val colorFilter: ColorFilterRecommendation? = null,
    val development: DevelopmentAdjustment? = null,
    val warning: ReciprocityWarning? = null,
    val note: ReciprocityNote? = null,
)

enum class ReciprocityAdjustmentKind { exposure, colorFilter, development, warning, note }

@Serializable
data class ExposureAdjustment(
    val kind: ExposureAdjustmentKind,
    val correctedTime: CorrectedTimeMapping? = null,
    val stopDelta: StopDeltaAdjustment? = null,
    val multiplier: MultiplierAdjustment? = null,
)

enum class ExposureAdjustmentKind { correctedTime, stopDelta, multiplier }

@Serializable
data class CorrectedTimeMapping(
    val meteredSeconds: Double? = null,
    val correctedSeconds: Double,
    val isApproximate: Boolean = false,
)

@Serializable
data class StopDeltaAdjustment(val stopDelta: Double)

@Serializable
data class MultiplierAdjustment(val factor: Double)

@Serializable
data class ColorFilterRecommendation(val filterName: String, val note: String? = null)

@Serializable
data class DevelopmentAdjustment(val instruction: String, val note: String? = null)

@Serializable
data class ReciprocityWarning(val severity: ReciprocityWarningSeverity, val message: String)

enum class ReciprocityWarningSeverity { caution, notRecommended }

@Serializable
data class ReciprocityNote(val text: String)
