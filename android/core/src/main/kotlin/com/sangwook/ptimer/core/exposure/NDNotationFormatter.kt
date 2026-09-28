// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import java.util.Locale
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Pure transform from a canonical ND value (`stops`) into surface-specific
 * display fragments. Mirrors iOS `NDNotationFormatter`.
 *
 * - [Display.value]: the number text the picker wheel shows (`9`, `2.7`, `512`).
 * - [Display.unit]: the unit label (`stops`, `OD`, `ND`).
 * - [Display.inline]: the standalone label for result/basis text (`9 stops`,
 *   `OD 2.7`, `ND512`). Never the value glued to the unit, so a surface that
 *   already shows the unit does not render `512 ND` / `ND512 ND`.
 *
 * Rounding (deterministic; exercised by NDNotationFormatterTest):
 * - Stops: whole stops render as an integer; the three commercial presets
 *   (PTIMER-209: 6.6, 7.6, 16.6) render as one decimal; the reserved
 *   third-stop path renders as a mixed fraction (`1 1/3`).
 * - Optical density: `stops × 0.3`, one decimal (the presets land on
 *   `OD 2.0`, `OD 2.3`, `OD 5.0`).
 * - Filter factor: the commercial presets map to their marketed labels
 *   (`ND100`, `ND200`, `ND100k`); every other value uses `2^stops`, via
 *   PTIMER's compact app display policy (not an external standard):
 *   - 0–9 stops (factor < 1000): exact factor — `ND1`, `ND2`, `ND8`, `ND512`.
 *   - 10–13 stops (factor < 10000): commercial-familiar thousands —
 *     `ND1000`, `ND2000`, `ND4000`, `ND8000` (2^10 stays `ND1000`).
 *   - 14 stops and up: the factor against the nearest power-of-two unit
 *     (K = 2^10, M = 2^20, G = 2^30) with an UPPERCASE suffix, so exact stops
 *     land on clean labels — `ND16K` (14), `ND64K` (16), `ND1M` (20). This
 *     deliberately avoids one-significant-figure rounding, which would
 *     mislabel 2^14 as `ND20k` and 2^16 as `ND70k`.
 */
object NDNotationFormatter {
    data class Display(val value: String, val unit: String, val inline: String)

    fun display(stops: Double, mode: NDNotationMode): Display = when (mode) {
        NDNotationMode.STOPS -> {
            val value = stopsValue(stops)
            Display(value, "stops", stopsInline(stops, value))
        }
        NDNotationMode.OPTICAL_DENSITY -> {
            val value = opticalDensityValue(stops)
            Display(value, "OD", "OD $value")
        }
        NDNotationMode.FILTER_FACTOR -> {
            val value = filterFactorValue(stops)
            Display(value, "ND", "ND$value")
        }
    }

    private fun stopsValue(stops: Double): String {
        val step = NDStep(stops)
        step.wholeStops?.let { return it.toString() }
        // Supported commercial presets render as the canonical tenth of a stop
        // (normalizing any near-match); every other non-whole value falls
        // through to the reserved third-stop mixed-fraction path.
        ExposureScale.commercialNDPresetStop(stops)?.let {
            return String.format(Locale.US, "%.1f", it)
        }
        val totalThirds = step.thirdStopCount
        val whole = totalThirds / 3
        // A value whose NEAREST third is a whole stop has no fractional
        // part to name. Without this case it fell through to the `2/3`
        // branch, so 0.9 stops rendered as `1 2/3` and 29.9 as `30 2/3`
        // — the rounding policy's own answer, overstated by two thirds.
        val frac = when (totalThirds % 3) {
            0 -> null
            1 -> "1/3"
            else -> "2/3"
        }
        return when {
            frac == null -> whole.toString()
            whole == 0 -> frac
            else -> "$whole $frac"
        }
    }

    private fun stopsInline(stops: Double, value: String): String {
        val singular = NDStep(stops).wholeStops == 1
        return if (singular) "$value stop" else "$value stops"
    }

    private fun opticalDensityValue(stops: Double): String =
        String.format(Locale.US, "%.1f", stops * 0.3)

    private fun filterFactorValue(stops: Double): String {
        // Commercial fixed-ND presets carry their marketed factor label, which
        // is not 2^stops (2^6.6 = 97 is sold as ND100, 2^16.6 ≈ 99 420 as
        // ND100k). Only the three PTIMER-209 presets use this table; every
        // whole stop keeps the compact power-of-two policy below.
        commercialFactorLabel(stops)?.let { return it }

        // Ladder values take their numeric factor from the shared mapping, so
        // the formatter and Filter Item registration (FILTER-ITEM-004) can
        // never drift: whatever ND label this renders is exactly what a
        // registered ND factor converts back to. Off-ladder values (the
        // reserved third-stop path) keep the 2^stops policy below.
        val ladderFactor = NDCommercialFactorMapping.commercialFactor(stops)
        // 0–9 stops: exact factor (1, 2, 4, … 512).
        // 10–13 stops: commercial-familiar thousands (1000/2000/4000/8000).
        if (ladderFactor != null && ladderFactor < 10_000) return ladderFactor.roundToLong().toString()

        val factor = ladderFactor ?: 2.0.pow(stops)
        if (factor < 1000) return factor.roundToInt().toString()
        if (factor < 10_000) return ((factor / 1000).roundToLong() * 1000).toString()
        // 14 stops and up: nearest power-of-two unit, uppercase suffix, so
        // exact stops land on clean labels (2^14 = 16K, 2^16 = 64K, 2^20 = 1M)
        // rather than a one-sig-fig bucket (which would yield 20k / 70k).
        val units = listOf(
            1_073_741_824.0 to "G", // 2^30
            1_048_576.0 to "M",     // 2^20
            1024.0 to "K",          // 2^10
        )
        for ((threshold, suffix) in units) {
            if (factor >= threshold) return "${(factor / threshold).roundToLong()}$suffix"
        }
        return factor.roundToLong().toString()
    }

    /**
     * Marketed filter-factor label for a commercial fractional ND preset
     * (PTIMER-209), or `null` for any other stop value. Matched on the
     * canonical stop value within the shared stability epsilon; the numeric
     * factor comes from [NDCommercialFactorMapping], which is also what a
     * registered ND factor is matched against (FILTER-ITEM-004). Only
     * ND100k's marketing `k` is a rendering choice of this formatter.
     */
    private fun commercialFactorLabel(stops: Double): String? {
        if (ExposureScale.commercialNDPresetStop(stops) == null) return null
        val factor = NDCommercialFactorMapping.commercialFactor(stops) ?: return null
        return if (factor >= 1000) {
            "${(factor / 1000).roundToLong()}k"
        } else {
            factor.roundToLong().toString()
        }
    }
}
