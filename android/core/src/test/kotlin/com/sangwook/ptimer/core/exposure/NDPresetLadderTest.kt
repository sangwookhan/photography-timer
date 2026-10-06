// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

/**
 * ND-001 / ND-011 / ND-PERSIST-005: the shipping ND ladder is whole stops
 * 0…30; the three commercial fractional values are no longer new Standard
 * choices but keep their mappings, still restore as saved values, and feed
 * the exposure engine as their configured fractional stop value. Parity
 * with iOS ExposureScaleTests / ExposureCalculationAccuracyTests.
 */
class NDPresetLadderTest {
    private val eps = ExposureCalculator.STABILITY_EPSILON

    @Test fun shippingLadderIsWholeStopsOnly() {
        val stops = ExposureScale.shippingNDLadder.map { it.stops }
        assertEquals(31, stops.size)
        assertEquals((0..30).map { it.toDouble() }, stops)
        assertEquals(listOf(6.6, 7.6, 16.6), ExposureScale.commercialFractionalNDStops)
        // Both scales share the ladder.
        assertEquals(stops, ExposureScale.fullStop.ndSteps.map { it.stops })
        assertEquals(stops, ExposureScale.oneThirdStop.ndSteps.map { it.stops })
    }

    @Test fun commercialPresetMatchNormalizesAndRejectsUnsupported() {
        assertEquals(16.6, ExposureScale.commercialNDPresetStop(16.6)!!, eps)
        // Near-match normalizes to the canonical value.
        assertEquals(6.6, ExposureScale.commercialNDPresetStop(6.6 + eps / 2)!!, eps)
        // Whole stops and off-grid non-presets are not presets.
        assertNull(ExposureScale.commercialNDPresetStop(7.0))
        assertNull(ExposureScale.commercialNDPresetStop(12.4))
    }

    @Test fun presetsAreNeitherWholeNorThirdStop() {
        for (stops in ExposureScale.commercialFractionalNDStops) {
            val step = NDStep(stops)
            assertNull(step.wholeStops)
            assertTrue("$stops must not be a third-stop", !step.isThirdStop)
        }
    }

    @Test fun presetsUseConfiguredStopValueInCalculation() {
        val calc = ExposureCalculator()
        val base = 1.0 / 30.0
        for (stops in ExposureScale.commercialFractionalNDStops) {
            val result = calc.calculate(
                baseShutterSeconds = base,
                ndStep = NDStep(stops),
                scaleMode = ExposureScaleMode.ONE_THIRD_STOP,
            )
            assertEquals("stops=$stops", base * 2.0.pow(stops), result, 1e-6)
            // Materially distinct from both integer neighbours.
            assertTrue(result > base * 2.0.pow(kotlin.math.floor(stops)))
            assertTrue(result < base * 2.0.pow(kotlin.math.ceil(stops)))
        }
    }

    /** ND-PERSIST-005: a saved commercial Standard value still restores,
     *  and a wheel holding one offers it as its own row only. */
    @Test fun aSavedFractionalStandardValueRestoresAndStaysOnItsOwnWheel() {
        assertTrue(NdFilterStack.isValidRestoredStack(listOf(6.6, 2.0)))
        assertTrue(NdFilterStack.isValidRestoredStack(listOf(16.6)))
        assertTrue("Other off-ladder values are still rejected.", !NdFilterStack.isValidRestoredStack(listOf(6.5)))

        val stack = FilterStack.validated(
            listOf(FilterWheel.standard(6.6), FilterWheel.standard(2.0)),
            FilterInventory.empty,
        )!!
        val own = stack.rowOptions(0, FilterInventory.empty).map { it.row.contributionStops }
        val other = stack.rowOptions(1, FilterInventory.empty).map { it.row.contributionStops }
        assertEquals("The saved value stays selectable on its wheel.", listOf(6.6), own.filter { it != kotlin.math.floor(it) })
        assertEquals("In numeric order among the whole stops.", listOf(0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 6.6), own.take(8))
        assertTrue("Never offered as a new Standard choice.", other.all { it == kotlin.math.floor(it) })
        assertEquals("Its contribution is unchanged.", 8.6, stack.effectiveStops, eps)
    }
}
