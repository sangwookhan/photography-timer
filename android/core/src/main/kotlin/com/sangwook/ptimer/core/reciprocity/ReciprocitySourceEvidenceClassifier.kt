// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

/**
 * Shared source-evidence row classification. Faithful port of iOS
 * `ReciprocitySourceEvidenceClassifier`: distinguishes a guidance-boundary row
 * (a metered exposure the manufacturer flags as not recommended, with no
 * quantified exposure adjustment) from a published reference point, and
 * surfaces the reached stop-signal messages for a given metered exposure.
 */
object ReciprocitySourceEvidenceClassifier {
    /** A row whose only fact is a not-recommended warning (no exposure adjustment). */
    fun isGuidanceBoundary(row: ReciprocitySourceEvidenceRow): Boolean {
        val hasNotRecommended = row.adjustments.any {
            it.kind == ReciprocityAdjustmentKind.warning &&
                it.warning?.severity == ReciprocityWarningSeverity.notRecommended
        }
        val hasExposure = row.adjustments.any { it.kind == ReciprocityAdjustmentKind.exposure }
        return hasNotRecommended && !hasExposure
    }

    /** Metered exposure of a selector (exact, or the range's lower bound). */
    fun meteredSeconds(selector: MeteredExposureSelector): Double? = when (selector.kind) {
        MeteredExposureSelectorKind.exactSeconds -> selector.exactSeconds
        MeteredExposureSelectorKind.range -> selector.range?.minimumSeconds
    }

    /** Boundary seconds of a row (for ordering / reached comparisons). */
    fun boundarySeconds(row: ReciprocitySourceEvidenceRow): Double =
        meteredSeconds(row.meteredExposure) ?: 0.0

    /**
     * Manufacturer stop-signal messages whose boundary the metered exposure has
     * reached. Presentation-only — never read by the calculation path.
     */
    fun reachedStopSignalMessages(profile: ReciprocityProfile, meteredExposureSeconds: Double): List<String> {
        if (!meteredExposureSeconds.isFinite()) return emptyList()
        return profile.sourceEvidence
            .filter { isGuidanceBoundary(it) }
            .filter { boundarySeconds(it) <= meteredExposureSeconds }
            .flatMap { row ->
                row.adjustments.mapNotNull { adj ->
                    if (adj.kind == ReciprocityAdjustmentKind.warning &&
                        adj.warning?.severity == ReciprocityWarningSeverity.notRecommended
                    ) {
                        adj.warning?.message
                    } else {
                        null
                    }
                }
            }
    }
}
