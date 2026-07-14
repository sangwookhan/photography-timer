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

    // --- PTIMER-209 commercial fractional presets ---

    /**
     * The three permanent Stops-wheel presets map to their marketed labels in
     * every notation. Stops render as a decimal (not a third-stop mixed
     * fraction); OD falls out of stops × 0.3; the factor uses the commercial
     * label, not 2^stops. Parity with iOS.
     */
    @Test fun commercialPresetsRenderInEveryNotation() {
        data class Case(val stops: Double, val stopsLabel: String, val od: String, val nd: String)
        val cases = listOf(
            Case(6.6, "6.6", "OD 2.0", "ND100"),
            Case(7.6, "7.6", "OD 2.3", "ND200"),
            Case(16.6, "16.6", "OD 5.0", "ND100k"),
        )
        for (c in cases) {
            assertEquals(c.stopsLabel, NDNotationFormatter.display(c.stops, NDNotationMode.STOPS).value)
            assertEquals("${c.stopsLabel} stops", inline(c.stops, NDNotationMode.STOPS))
            assertEquals(c.od, inline(c.stops, NDNotationMode.OPTICAL_DENSITY))
            assertEquals(c.nd, inline(c.stops, NDNotationMode.FILTER_FACTOR))
        }
    }

    /**
     * Drift guard for the split product definition (stop values live in
     * ExposureScale; factor labels live in the formatter). Every domain preset
     * must resolve to a commercial factor label — an override, not the raw
     * 2^stops rounding — and the labels must be distinct.
     */
    @Test fun everyDomainPresetHasADistinctOverriddenFactorLabel() {
        val labels = ExposureScale.commercialFractionalNDStops.map { stops ->
            val label = NDNotationFormatter.display(stops, NDNotationMode.FILTER_FACTOR).value
            assertNotEquals(
                "preset $stops must use a commercial label, not 2^stops",
                Math.pow(2.0, stops).let { Math.round(it).toString() }, label,
            )
            label
        }
        assertEquals(ExposureScale.commercialFractionalNDStops.size, labels.toSet().size)
    }
}
