// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * PTIMER-221 ND-001 / FILTER-ITEM-004 — the reserved third-stop path.
 *
 * `filter-sets.md`: a Filter Set item's value renders "through the same
 * formatter and rounding policy as Standard, showing only the numeric
 * value component". The rounding policy is the nearest third of a stop.
 *
 * Before PTIMER-221 this path was unreachable: the Standard ladder holds
 * whole stops and the three commercial presets, which the two branches
 * above it answer. FILTER-ITEM-004 lets a user register any decimal up
 * to 30 stops, so every value between the thirds now arrives here — and
 * the branch had no case for a value whose nearest third IS a whole
 * stop. It fell through to `2/3`, so an ordinary 0.9-stop filter
 * displayed as `1 2/3`: the rounding policy's own answer overstated by
 * two thirds of a stop, on the wheel, in the status detail and in the
 * timer's filter line.
 */
class NDNotationThirdStopRenderingTest {
    private fun stops(value: Double) =
        NDNotationFormatter.display(value, NDNotationMode.STOPS).value

    @Test
    fun `a value whose nearest third is a whole stop renders as that whole stop`() {
        // Each of these rounds to an exact multiple of three thirds
        // without being close enough to a whole stop for the whole-stop
        // branch above to claim it.
        assertEquals("1", stops(0.9))
        assertEquals("1", stops(1.1))
        assertEquals("5", stops(5.1))
        assertEquals("10", stops(9.9))
        assertEquals("30", stops(29.9))
        assertEquals("30", stops(29.99))
    }

    @Test
    fun `values between the thirds still render as mixed fractions`() {
        assertEquals("1/3", stops(0.3))
        assertEquals("2/3", stops(0.7))
        assertEquals("5 1/3", stops(5.2))
        assertEquals("5 2/3", stops(5.5))
        assertEquals("29 1/3", stops(29.4))
    }

    @Test
    fun `whole stops and the commercial presets are unchanged`() {
        assertEquals("0", stops(0.0))
        assertEquals("2", stops(2.0))
        assertEquals("30", stops(30.0))
        assertEquals("6.6", stops(6.6))
        assertEquals("7.6", stops(7.6))
        assertEquals("16.6", stops(16.6))
    }
}
