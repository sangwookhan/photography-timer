package com.sangwook.ptimer.core.reciprocity

/** Calculation basis. Mirrors iOS `ReciprocityCalculationBasis` (5 cases). */
enum class ReciprocityCalculationBasis {
    OFFICIAL_THRESHOLD_NO_CORRECTION,
    LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION,
    UNSUPPORTED_OUT_OF_POLICY_RANGE,
    FORMULA_DERIVED,
    TABLE_LOG_LOG_DERIVED,
}

enum class ReciprocitySourceAuthorityImpact { CURRENT_OFFICIAL, ARCHIVAL_OFFICIAL, UNOFFICIAL_SECONDARY, USER_DEFINED }

enum class ReciprocityCalculationRangeStatus { WITHIN_STATED_RANGE, BEYOND_LAST_REPRESENTATIVE_POINT, BEYOND_POLICY_LIMIT }

enum class ReciprocityCalculationWarningLevel { NONE, NOTE, CAUTION, STRONG_WARNING }

enum class ReciprocityPolicyNoteToken {
    THRESHOLD_GUIDANCE_ONLY,
    LIMITED_GUIDANCE_CONTINUATION_ONLY,
    BEYOND_OFFICIAL_QUANTIFIED_RANGE,
    ARCHIVAL_OFFICIAL_SOURCE,
    UNOFFICIAL_SECONDARY_SOURCE,
    USER_DEFINED_SOURCE,
    UNSUPPORTED_BY_POLICY,
}

data class ReciprocityPolicyNote(val token: ReciprocityPolicyNoteToken?, val text: String)

data class ReciprocityResultMetadata(
    val basis: ReciprocityCalculationBasis,
    val sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
    val rangeStatus: ReciprocityCalculationRangeStatus,
    val warningLevel: ReciprocityCalculationWarningLevel,
    val notes: List<ReciprocityPolicyNote> = emptyList(),
)

/**
 * Tagged-union reciprocity outcome. Quantified always carries a corrected
 * exposure; limited-guidance carries none; unsupported optionally carries a
 * numeric continuation (formula/table prediction past the source range).
 * Mirrors iOS `ReciprocityResult`.
 */
sealed interface ReciprocityResult {
    val meteredExposureSeconds: Double
    val metadata: ReciprocityResultMetadata
    val correctedExposureSeconds: Double?
    val hasCalculatedExposureTime: Boolean get() = correctedExposureSeconds != null

    data class Quantified(
        override val meteredExposureSeconds: Double,
        val corrected: Double,
        override val metadata: ReciprocityResultMetadata,
    ) : ReciprocityResult {
        override val correctedExposureSeconds: Double get() = corrected
    }

    data class LimitedGuidance(
        override val meteredExposureSeconds: Double,
        override val metadata: ReciprocityResultMetadata,
    ) : ReciprocityResult {
        override val correctedExposureSeconds: Double? get() = null
    }

    data class Unsupported(
        override val meteredExposureSeconds: Double,
        val correctedContinuation: Double?,
        override val metadata: ReciprocityResultMetadata,
    ) : ReciprocityResult {
        override val correctedExposureSeconds: Double? get() = correctedContinuation
    }
}
