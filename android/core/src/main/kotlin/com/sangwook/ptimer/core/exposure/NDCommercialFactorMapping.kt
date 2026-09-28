// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.exposure.ExposureCalculator.Companion.STABILITY_EPSILON
import kotlin.math.abs
import kotlin.math.pow

/**
 * The one commercial filter-factor mapping shared by the Standard ND
 * notation formatter and Filter Item registration (Filter Set contract,
 * FILTER-ITEM-004): for every value on the shipping ND ladder it yields
 * the numeric factor the Standard `ND` label shows, and the inverse
 * recovers the canonical ladder stops from such a factor — so a
 * registered ND1000 is exactly 10 stops, not `log2(1000)`.
 * (iOS: `NDCommercialFactorMapping`.)
 *
 * Factor policy (identical to the formatter's rendering rules):
 * - the three commercial presets: 6.6 → 100, 7.6 → 200, 16.6 → 100 000;
 * - 0–9 stops: the exact power of two (1 … 512);
 * - 10–13 stops: commercial thousands (1000, 2000, 4000, 8000);
 * - 14 stops and up: the exact power of two (the `K` / `M` / `G` labels
 *   are exact binary units, so 2^14 = 16 384 reads `ND16K`).
 */
object NDCommercialFactorMapping {

    /**
     * Numeric filter factor of the Standard `ND` label for a canonical
     * ladder value, or `null` when [forStops] is not on the ladder (no
     * label exists for it).
     */
    fun commercialFactor(forStops: Double): Double? {
        ExposureScale.commercialNDPresetStop(forStops)?.let { preset ->
            return when (preset) {
                6.6 -> 100.0
                7.6 -> 200.0
                else -> 100_000.0
            }
        }
        val whole = NDStep(forStops).wholeStops ?: return null
        if (whole !in 0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS) return null
        val factor = 2.0.pow(whole)
        if (factor < 1000) return factor
        if (factor < 10_000) return (factor / 1000).swiftRounded() * 1000
        return factor
    }

    /**
     * Canonical ladder stops whose Standard label factor equals
     * [matchingCommercialFactor] (within the shared stability epsilon),
     * or `null` when no label matches — callers then fall back to
     * `log2(factor)`.
     */
    fun canonicalStops(matchingCommercialFactor: Double): Double? {
        if (!matchingCommercialFactor.isFinite() || matchingCommercialFactor <= 0) return null
        val candidates = (0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS).map { it.toDouble() } +
            ExposureScale.commercialFractionalNDStops
        return candidates.firstOrNull { stops ->
            val labelFactor = commercialFactor(stops) ?: return@firstOrNull false
            abs(labelFactor - matchingCommercialFactor) <= STABILITY_EPSILON
        }
    }
}
