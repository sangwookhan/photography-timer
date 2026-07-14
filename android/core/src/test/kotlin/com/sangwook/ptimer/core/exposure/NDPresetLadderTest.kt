// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

/**
 * PTIMER-209: the shipping ND ladder carries whole stops 0…30 plus the three
 * commercial fractional presets, and those presets feed the exposure engine as
 * their configured fractional stop value. Parity with iOS ExposureScaleTests /
 * ExposureCalculationAccuracyTests.
 */
class NDPresetLadderTest {
    private val eps = ExposureCalculator.STABILITY_EPSILON

    @Test fun shippingLadderInsertsPresetsInNumericOrder() {
        val expected = listOf(
            0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 6.6, 7.0, 7.6, 8.0, 9.0, 10.0, 11.0,
            12.0, 13.0, 14.0, 15.0, 16.0, 16.6, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0,
            23.0, 24.0, 25.0, 26.0, 27.0, 28.0, 29.0, 30.0,
        )
        val stops = ExposureScale.shippingNDLadder.map { it.stops }
        assertEquals(34, stops.size)
        assertEquals(expected, stops)
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
}
