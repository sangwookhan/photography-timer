// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.timer

import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode

/**
 * Builds a timer card's basis line from structured exposure inputs in the
 * current ND notation mode, instead of a precomposed string. Mirrors iOS
 * `TimerBasisPresenter`.
 *
 * Inputs only — the final exposure value is the timer duration shown elsewhere,
 * so it is never repeated:
 * - `Base <base> · <ND>` for digital / adjusted-shutter timers.
 * - `Base <base> · <ND> · Adj <adjusted>` for corrected / target timers, where
 *   the adjusted shutter is an intermediate distinct from the final duration
 *   ([includesAdjusted] = true).
 *
 * Returns null when ND/base are absent (legacy/manual), so the caller omits the
 * line and falls back as needed.
 */
object TimerBasisPresenter {
    fun basisText(
        ndStops: Double?,
        baseShutterSeconds: Double?,
        adjustedShutterSeconds: Double?,
        includesAdjusted: Boolean,
        mode: NDNotationMode,
        formatShutter: (Double) -> String,
        baseNdFormat: String = "Base %1\$s · %2\$s",
        baseNdAdjustedFormat: String = "Base %1\$s · %2\$s · Adj %3\$s",
    ): String? {
        if (ndStops == null || baseShutterSeconds == null) return null
        val nd = NDNotationFormatter.display(ndStops, mode).inline
        val base = formatShutter(baseShutterSeconds)
        return if (includesAdjusted && adjustedShutterSeconds != null) {
            String.format(baseNdAdjustedFormat, base, nd, formatShutter(adjustedShutterSeconds))
        } else {
            String.format(baseNdFormat, base, nd)
        }
    }
}
