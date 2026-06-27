// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import kotlin.math.abs
import kotlin.math.log2

/**
 * One checkpoint row in the custom-film editor preview table: a sample metered
 * time, the corrected exposure the profile yields there, and the stop delta.
 * (iOS: CustomFilmEditorPreviewPresenter.Row, normalized subset.)
 */
data class CustomFilmCheckpointRow(
    val meteredSeconds: Double,
    val correctedSeconds: Double?,
    /** Stop difference (log2 corrected/metered); null when uncorrected / no value. */
    val stopDelta: Double?,
    /** True when the value lies beyond the profile's published source range. */
    val beyondSourceRange: Boolean,
)

/**
 * Builds the editor preview's checkpoint table by evaluating the in-progress
 * custom profile at a fixed ladder of metered times through the SAME protected
 * policy the runtime calculator uses, so the preview agrees with shooting.
 */
object CustomFilmCheckpointPresenter {
    /** Sample metered times shown in the preview table (iOS parity). */
    private val sampleSeconds = listOf(1.0, 10.0, 60.0, 300.0, 1000.0)
    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    fun rows(profile: ReciprocityProfile): List<CustomFilmCheckpointRow> =
        sampleSeconds.map { metered ->
            val result = evaluator.evaluate(profile, metered)
            val corrected = result.calculatedCorrectedSeconds
            // A delta within ~0.05 stop reads as "no correction"; below that the
            // row shows the value plainly without a misleading "+0.0 stops".
            val delta = corrected
                ?.takeIf { it > 0 && metered > 0 }
                ?.let { log2(it / metered) }
                ?.takeIf { abs(it) > 0.05 }
            CustomFilmCheckpointRow(
                meteredSeconds = metered,
                correctedSeconds = corrected,
                stopDelta = delta,
                beyondSourceRange = result is ReciprocityResult.Unsupported && corrected != null,
            )
        }
}
