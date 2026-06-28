// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

/**
 * How ND-filter strength is *displayed*. Presentation only — ND strength is
 * always stored and calculated as stops; switching the notation never changes
 * the canonical value or any exposure result. Mirrors iOS `NDNotationMode`.
 *
 * - [STOPS]: native stop count (`9 stops`).
 * - [OPTICAL_DENSITY]: optical density, `stops × 0.3` (`OD 2.7`).
 * - [FILTER_FACTOR]: light-reduction factor, `2^stops` (`ND512`).
 *
 * [STOPS] is the shipping default. Persisted by [name], so the case names are
 * part of the on-disk contract.
 */
enum class NDNotationMode {
    STOPS,
    OPTICAL_DENSITY,
    FILTER_FACTOR;

    companion object {
        val DEFAULT: NDNotationMode = STOPS

        /** Fail-safe parse: an unknown/missing name decodes to the default. */
        fun fromName(name: String?): NDNotationMode =
            entries.firstOrNull { it.name == name } ?: DEFAULT
    }
}
