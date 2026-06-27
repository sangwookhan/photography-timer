// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.calc

import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.ExposureScaleMode
import com.sangwook.ptimer.core.exposure.NDStep
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.reciprocity.confidencePresentation

/**
 * Pure shooting-calculation presenter. Combines the exposure engine with the
 * reciprocity policy for the active slot: a digital (no-film) workflow yields
 * the ND-adjusted shutter; a film workflow yields the corrected exposure when
 * the profile produces a quantified result. Start enablement follows the iOS
 * rule — quantified positive-finite enables the timer; limited-guidance /
 * unsupported blocks it with a hint (PTIMER-99).
 */
class ShootingCalculator(
    private val exposure: ExposureCalculator = ExposureCalculator(),
    private val policy: ReciprocityCalculationPolicyEvaluator = ReciprocityCalculationPolicyEvaluator(),
) {
    private val ladder = ExposureScale.oneThirdStop.shutterSteps

    fun result(shutterIndex: Int, ndStops: Int, profile: ReciprocityProfile?): ShootingResult {
        val base = ladder[shutterIndex.coerceIn(ladder.indices)].seconds
        val adjusted = exposure.calculate(
            baseShutterSeconds = base,
            ndStep = NDStep(ndStops.toDouble()),
            scaleMode = ExposureScaleMode.ONE_THIRD_STOP,
        )

        if (profile == null) {
            val ok = adjusted.isFinite() && adjusted > 0
            return ShootingResult(
                adjustedShutterSeconds = adjusted,
                correctedSeconds = null,
                reciprocity = null,
                confidenceLabel = null,
                startEnabled = ok,
                startDurationSeconds = if (ok) adjusted else null,
                hint = null,
            )
        }

        val recip = policy.evaluate(profile, adjusted)
        val label = recip.confidencePresentation.shortLabel
        return when (recip) {
            is ReciprocityResult.Quantified -> {
                val corrected = recip.correctedExposureSeconds
                val ok = corrected.isFinite() && corrected > 0
                ShootingResult(
                    adjustedShutterSeconds = adjusted,
                    correctedSeconds = corrected,
                    reciprocity = recip,
                    confidenceLabel = label,
                    startEnabled = ok,
                    startDurationSeconds = if (ok) corrected else null,
                    hint = null,
                )
            }
            is ReciprocityResult.LimitedGuidance, is ReciprocityResult.Unsupported -> ShootingResult(
                adjustedShutterSeconds = adjusted,
                correctedSeconds = null,
                reciprocity = recip,
                confidenceLabel = label,
                startEnabled = false,
                startDurationSeconds = null,
                hint = recip.metadata.notes.firstOrNull()?.text
                    ?: "No quantified reciprocity prediction for this exposure.",
            )
        }
    }
}

/** Display + start-enablement outcome of one shooting calculation. */
data class ShootingResult(
    val adjustedShutterSeconds: Double,
    val correctedSeconds: Double?,
    val reciprocity: ReciprocityResult?,
    val confidenceLabel: String?,
    val startEnabled: Boolean,
    val startDurationSeconds: Double?,
    val hint: String?,
) {
    val isDigital: Boolean get() = reciprocity == null
}
