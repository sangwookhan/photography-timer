package com.sangwook.ptimer.core.reciprocity

/** Confidence presentation category. Mirrors iOS `ReciprocityConfidenceCategory`. */
enum class ReciprocityConfidenceCategory { NO_CORRECTION, FORMULA_DERIVED, LIMITED_GUIDANCE, UNSUPPORTED }

enum class ReciprocityConfidenceLevel { HIGH, MEDIUM, LOW, VERY_LOW, NONE }

enum class ReciprocityConfidenceBadgeStyle { TRUSTED, MEASURED, CAUTION, LIMITED_GUIDANCE, UNSUPPORTED }

data class ReciprocityConfidencePresentation(
    val category: ReciprocityConfidenceCategory,
    val level: ReciprocityConfidenceLevel,
    val badgeStyle: ReciprocityConfidenceBadgeStyle,
    val shortLabel: String,
)

/**
 * Maps a [ReciprocityResult] to a user-facing confidence presentation.
 * Badge tone follows calculation status first. The launch vocabulary is
 * constrained — never the legacy table-era words (Exact / Estimated /
 * Interpolated / Extrapolated / Advisory). Mirrors iOS
 * `ReciprocityConfidencePresentationMapper`.
 */
object ReciprocityConfidencePresentationMapper {

    /** Words forbidden in launch-preset reciprocity presentation. */
    val FORBIDDEN_VOCABULARY = listOf("Exact", "Estimated", "Interpolated", "Extrapolated", "Advisory")

    fun map(result: ReciprocityResult): ReciprocityConfidencePresentation {
        val metadata = result.metadata
        val impact = metadata.sourceAuthorityImpact
        val category = category(metadata.basis)
        val level = level(category, metadata.basis, impact)
        return ReciprocityConfidencePresentation(
            category = category,
            level = level,
            badgeStyle = badgeStyle(category, level),
            shortLabel = shortLabel(result, category, impact),
        )
    }

    private fun category(basis: ReciprocityCalculationBasis): ReciprocityConfidenceCategory = when (basis) {
        ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION -> ReciprocityConfidenceCategory.NO_CORRECTION
        ReciprocityCalculationBasis.FORMULA_DERIVED,
        ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED -> ReciprocityConfidenceCategory.FORMULA_DERIVED
        ReciprocityCalculationBasis.LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION -> ReciprocityConfidenceCategory.LIMITED_GUIDANCE
        ReciprocityCalculationBasis.UNSUPPORTED_OUT_OF_POLICY_RANGE -> ReciprocityConfidenceCategory.UNSUPPORTED
    }

    private fun level(
        category: ReciprocityConfidenceCategory,
        basis: ReciprocityCalculationBasis,
        impact: ReciprocitySourceAuthorityImpact,
    ): ReciprocityConfidenceLevel = when (category) {
        ReciprocityConfidenceCategory.LIMITED_GUIDANCE, ReciprocityConfidenceCategory.UNSUPPORTED -> ReciprocityConfidenceLevel.NONE
        else -> when (impact) {
            ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL ->
                if (basis == ReciprocityCalculationBasis.FORMULA_DERIVED) ReciprocityConfidenceLevel.MEDIUM else ReciprocityConfidenceLevel.HIGH
            ReciprocitySourceAuthorityImpact.ARCHIVAL_OFFICIAL -> ReciprocityConfidenceLevel.MEDIUM
            ReciprocitySourceAuthorityImpact.UNOFFICIAL_SECONDARY -> ReciprocityConfidenceLevel.LOW
            ReciprocitySourceAuthorityImpact.USER_DEFINED -> ReciprocityConfidenceLevel.VERY_LOW
        }
    }

    private fun badgeStyle(
        category: ReciprocityConfidenceCategory,
        level: ReciprocityConfidenceLevel,
    ): ReciprocityConfidenceBadgeStyle = when (category) {
        ReciprocityConfidenceCategory.UNSUPPORTED -> ReciprocityConfidenceBadgeStyle.UNSUPPORTED
        ReciprocityConfidenceCategory.LIMITED_GUIDANCE -> ReciprocityConfidenceBadgeStyle.LIMITED_GUIDANCE
        ReciprocityConfidenceCategory.FORMULA_DERIVED -> when (level) {
            ReciprocityConfidenceLevel.HIGH, ReciprocityConfidenceLevel.MEDIUM -> ReciprocityConfidenceBadgeStyle.MEASURED
            else -> ReciprocityConfidenceBadgeStyle.CAUTION
        }
        ReciprocityConfidenceCategory.NO_CORRECTION -> when (level) {
            ReciprocityConfidenceLevel.HIGH -> ReciprocityConfidenceBadgeStyle.TRUSTED
            ReciprocityConfidenceLevel.MEDIUM -> ReciprocityConfidenceBadgeStyle.MEASURED
            else -> ReciprocityConfidenceBadgeStyle.CAUTION
        }
    }

    private fun shortLabel(
        result: ReciprocityResult,
        category: ReciprocityConfidenceCategory,
        impact: ReciprocitySourceAuthorityImpact,
    ): String {
        val prefix = when (impact) {
            ReciprocitySourceAuthorityImpact.CURRENT_OFFICIAL -> ""
            ReciprocitySourceAuthorityImpact.ARCHIVAL_OFFICIAL -> "Archival "
            ReciprocitySourceAuthorityImpact.UNOFFICIAL_SECONDARY -> "Secondary "
            ReciprocitySourceAuthorityImpact.USER_DEFINED -> "Custom "
        }
        val base = when (category) {
            ReciprocityConfidenceCategory.NO_CORRECTION -> "No correction"
            ReciprocityConfidenceCategory.FORMULA_DERIVED ->
                if (result.metadata.basis == ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED) "Table-derived" else "Formula-derived"
            ReciprocityConfidenceCategory.LIMITED_GUIDANCE -> "No quantified prediction"
            ReciprocityConfidenceCategory.UNSUPPORTED ->
                if (result.correctedExposureSeconds != null) "Beyond source range" else "No corrected value"
        }
        // "No correction" / "No quantified prediction" / "No corrected value" are
        // status phrases that read better without an authority prefix.
        return if (base.startsWith("No ")) base else "$prefix$base"
    }
}
