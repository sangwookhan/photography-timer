// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/** Locks the deterministic ND-notation conversion + rounding policy (PTIMER-187). */
class NDNotationFormatterTest {
    private fun inline(stops: Double, mode: NDNotationMode) =
        NDNotationFormatter.display(stops, mode).inline

    @Test fun stopsInlineSingularPlural() {
        assertEquals("0 stops", inline(0.0, NDNotationMode.STOPS))
        assertEquals("1 stop", inline(1.0, NDNotationMode.STOPS))
        assertEquals("3 stops", inline(3.0, NDNotationMode.STOPS))
        assertEquals("9 stops", inline(9.0, NDNotationMode.STOPS))
        assertEquals("10 stops", inline(10.0, NDNotationMode.STOPS))
    }

    @Test fun opticalDensityInline() {
        assertEquals("OD 0.0", inline(0.0, NDNotationMode.OPTICAL_DENSITY))
        assertEquals("OD 0.3", inline(1.0, NDNotationMode.OPTICAL_DENSITY))
        assertEquals("OD 0.9", inline(3.0, NDNotationMode.OPTICAL_DENSITY))
        assertEquals("OD 2.7", inline(9.0, NDNotationMode.OPTICAL_DENSITY))
        assertEquals("OD 3.0", inline(10.0, NDNotationMode.OPTICAL_DENSITY))
        assertEquals("OD 4.2", inline(14.0, NDNotationMode.OPTICAL_DENSITY))
    }

    /**
     * Full integer-stop factor table — PTIMER's compact ND display policy.
     * Exact stops land on clean power-of-two labels and never drift to a
     * one-significant-figure bucket.
     */
    @Test fun filterFactorIntegerStopTable() {
        val expected = mapOf(
            0.0 to "ND1", 1.0 to "ND2", 3.0 to "ND8", 9.0 to "ND512",
            10.0 to "ND1000", 11.0 to "ND2000", 12.0 to "ND4000", 13.0 to "ND8000",
            14.0 to "ND16K", 15.0 to "ND32K", 16.0 to "ND64K", 17.0 to "ND128K",
            18.0 to "ND256K", 19.0 to "ND512K", 20.0 to "ND1M",
        )
        for ((stops, label) in expected) {
            assertEquals("stops=$stops", label, inline(stops, NDNotationMode.FILTER_FACTOR))
        }
    }

    @Test fun filterFactorNeverUsesCoarseBuckets() {
        assertNotEquals("ND20k", inline(14.0, NDNotationMode.FILTER_FACTOR))
        assertNotEquals("ND70k", inline(16.0, NDNotationMode.FILTER_FACTOR))
        assertNotEquals("ND70k", inline(17.0, NDNotationMode.FILTER_FACTOR))
        assertEquals("ND16K", inline(14.0, NDNotationMode.FILTER_FACTOR))
        assertEquals("ND64K", inline(16.0, NDNotationMode.FILTER_FACTOR))
    }

    @Test fun surfaceFragmentsAreNotDuplicated() {
        val nd = NDNotationFormatter.display(9.0, NDNotationMode.FILTER_FACTOR)
        assertEquals("512", nd.value)
        assertEquals("ND", nd.unit)
        assertEquals("ND512", nd.inline)
    }
}
