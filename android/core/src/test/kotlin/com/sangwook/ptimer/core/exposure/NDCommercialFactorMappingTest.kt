// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The shared commercial filter-factor mapping (FILTER-ITEM-004): the ND
 * notation formatter's table, inverted, so a registered ND factor lands
 * back on the canonical ladder value the label came from. Port of the
 * iOS FilterInventoryTests mapping cases.
 */
class NDCommercialFactorMappingTest {

    @Test fun commercialMappingRoundTripsEveryLadderValue() {
        val ladder = (0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS).map { it.toDouble() } +
            ExposureScale.commercialFractionalNDStops
        for (stops in ladder) {
            val factor = NDCommercialFactorMapping.commercialFactor(stops)
            assertNotNull("stops=$stops", factor)
            assertEquals(
                "stops=$stops",
                stops,
                NDCommercialFactorMapping.canonicalStops(factor!!)!!,
                0.0,
            )
        }
    }

    @Test fun ladderFactorsMatchTheStandardLabels() {
        assertEquals(1000.0, NDCommercialFactorMapping.commercialFactor(10.0)!!, 0.0)
        assertEquals(512.0, NDCommercialFactorMapping.commercialFactor(9.0)!!, 0.0)
        assertEquals(16384.0, NDCommercialFactorMapping.commercialFactor(14.0)!!, 0.0)
        assertEquals(100.0, NDCommercialFactorMapping.commercialFactor(6.6)!!, 0.0)
        assertEquals(200.0, NDCommercialFactorMapping.commercialFactor(7.6)!!, 0.0)
        assertEquals(100_000.0, NDCommercialFactorMapping.commercialFactor(16.6)!!, 0.0)
    }

    @Test fun offLadderValuesHaveNoLabel() {
        assertNull(NDCommercialFactorMapping.commercialFactor(3.3))
        assertNull(NDCommercialFactorMapping.commercialFactor(31.0))
    }

    /** ND1000 is exactly 10 stops; ND100 is the 6.6 preset; ND512 is 9. */
    @Test fun knownFactorsRecoverTheirLadderValue() {
        assertEquals(10.0, NDCommercialFactorMapping.canonicalStops(1000.0)!!, 0.0)
        assertEquals(6.6, NDCommercialFactorMapping.canonicalStops(100.0)!!, 0.0)
        assertEquals(9.0, NDCommercialFactorMapping.canonicalStops(512.0)!!, 0.0)
    }

    /** An unlabeled factor has no ladder value; the caller falls back to log2. */
    @Test fun unlabeledFactorsFallThrough() {
        assertNull(NDCommercialFactorMapping.canonicalStops(1500.0))
        assertNull(NDCommercialFactorMapping.canonicalStops(500.0))
        assertNull(NDCommercialFactorMapping.canonicalStops(0.0))
        assertNull(NDCommercialFactorMapping.canonicalStops(Double.NaN))
    }

    /**
     * Drift guard for section D: the formatter's ND label and the mapping
     * are one table, so every ladder value's rendered label is exactly the
     * factor a registered ND item converts back from.
     */
    @Test fun formatterLabelsAgreeWithTheMapping() {
        for (step in ExposureScale.shippingNDLadder) {
            val factor = NDCommercialFactorMapping.commercialFactor(step.stops)!!
            val rendered = NDNotationFormatter.display(step.stops, NDNotationMode.FILTER_FACTOR).value
            val expected = when {
                factor >= 1_073_741_824.0 -> "${(factor / 1_073_741_824.0).toLong()}G"
                factor >= 1_048_576.0 -> "${(factor / 1_048_576.0).toLong()}M"
                // ND100k is the one marketing lowercase unit.
                step.stops == 16.6 -> "100k"
                factor >= 10_000.0 -> "${(factor / 1024.0).toLong()}K"
                else -> factor.toLong().toString()
            }
            assertEquals("stops=${step.stops}", expected, rendered)
        }
    }
}
