package com.sangwook.ptimer.core.reciprocity

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.pow

/** Reciprocity formula family. Exhaustive on purpose. Mirrors iOS `FormulaFamily`. */
@Serializable
enum class FormulaFamily {
    @SerialName("modifiedSchwarzschild")
    MODIFIED_SCHWARZSCHILD,
}

/** Outcome of a single formula evaluation. Mirrors iOS `ReciprocityFormula.EvaluationResult`. */
sealed interface FormulaEvaluationResult {
    data object NoCorrection : FormulaEvaluationResult
    data class WithinSourceRange(val correctedExposureSeconds: Double) : FormulaEvaluationResult
    data class BeyondSourceRange(val correctedExposureSeconds: Double) : FormulaEvaluationResult
    data object InvalidInput : FormulaEvaluationResult
    data object InvalidFormula : FormulaEvaluationResult
    data object FormulaOutputUnusable : FormulaEvaluationResult
    data object UnsafeShorteningFormula : FormulaEvaluationResult
}

/**
 * Shared guarded reciprocity formula `Tc = a × (Tm / Tref)^p + b`.
 * Protected behavior — exact parity with iOS `ReciprocityFormula`.
 *
 * kotlinx.serialization defaults reproduce the iOS custom decoder:
 * `formulaFamily`, `exponent`, `noCorrectionThroughSeconds` are required;
 * `coefficientSeconds`/`referenceMeteredTimeSeconds` default 1,
 * `offsetSeconds` defaults 0, `sourceRangeThroughSeconds` is nullable.
 */
@Serializable
data class ReciprocityFormula(
    val formulaFamily: FormulaFamily = FormulaFamily.MODIFIED_SCHWARZSCHILD,
    val coefficientSeconds: Double = 1.0,
    val referenceMeteredTimeSeconds: Double = 1.0,
    val exponent: Double,
    val offsetSeconds: Double = 0.0,
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double? = null,
) {
    val hasValidParameters: Boolean
        get() {
            if (!coefficientSeconds.isFinite() || coefficientSeconds <= 0) return false
            if (!referenceMeteredTimeSeconds.isFinite() || referenceMeteredTimeSeconds <= 0) return false
            if (!exponent.isFinite()) return false
            if (!offsetSeconds.isFinite()) return false
            if (!noCorrectionThroughSeconds.isFinite() || noCorrectionThroughSeconds < 0) return false
            val upper = sourceRangeThroughSeconds
            if (upper != null && !(upper.isFinite() && upper > noCorrectionThroughSeconds)) return false
            return true
        }

    /**
     * Single shared evaluator. Strict (no-tolerance) no-correction
     * boundary; unsafe-shortening safety net at `Tc < Tm − 1e-6`.
     */
    fun evaluate(meteredExposureSeconds: Double): FormulaEvaluationResult {
        if (!meteredExposureSeconds.isFinite() || meteredExposureSeconds <= 0) {
            return FormulaEvaluationResult.InvalidInput
        }
        if (!hasValidParameters) return FormulaEvaluationResult.InvalidFormula
        if (meteredExposureSeconds <= noCorrectionThroughSeconds) {
            return FormulaEvaluationResult.NoCorrection
        }

        val corrected = when (formulaFamily) {
            FormulaFamily.MODIFIED_SCHWARZSCHILD -> {
                val scaled = meteredExposureSeconds / referenceMeteredTimeSeconds
                coefficientSeconds * scaled.pow(exponent) + offsetSeconds
            }
        }

        if (!corrected.isFinite() || corrected <= 0) {
            return FormulaEvaluationResult.FormulaOutputUnusable
        }
        if (corrected < meteredExposureSeconds - 1e-6) {
            return FormulaEvaluationResult.UnsafeShorteningFormula
        }
        val upper = sourceRangeThroughSeconds
        if (upper != null && meteredExposureSeconds > upper) {
            return FormulaEvaluationResult.BeyondSourceRange(corrected)
        }
        return FormulaEvaluationResult.WithinSourceRange(corrected)
    }
}
