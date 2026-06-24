package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import kotlin.math.abs
import kotlin.math.log2

/**
 * One reference point for a formula derived from a table (iOS PTIMER-180): a
 * source anchor's metered time, the formula's predicted corrected exposure
 * there, the table's reference corrected exposure, and their stop error.
 */
data class CustomFilmReferencePointRow(
    val meteredSeconds: Double,
    val formulaCorrectedSeconds: Double?,
    val referenceCorrectedSeconds: Double,
    val stopError: Double?,
)

/**
 * Compares a formula profile against the anchors of the table it was derived
 * from. Resolving the link at view time means the reference points reflect the
 * table's CURRENT anchors — add an anchor to the table and it appears here.
 */
object CustomFilmReferencePointsPresenter {
    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    fun rows(profile: ReciprocityProfile, referenceAnchors: List<TableAnchor>): List<CustomFilmReferencePointRow> =
        referenceAnchors.sortedBy { it.meteredSeconds }.map { anchor ->
            val formula = evaluator.evaluate(profile, anchor.meteredSeconds).calculatedCorrectedSeconds
            val error = formula
                ?.takeIf { it > 0 && anchor.correctedSeconds > 0 }
                ?.let { log2(it / anchor.correctedSeconds) }
                ?.takeIf { abs(it) > 0.005 }
            CustomFilmReferencePointRow(
                meteredSeconds = anchor.meteredSeconds,
                formulaCorrectedSeconds = formula,
                referenceCorrectedSeconds = anchor.correctedSeconds,
                stopError = error,
            )
        }
}
