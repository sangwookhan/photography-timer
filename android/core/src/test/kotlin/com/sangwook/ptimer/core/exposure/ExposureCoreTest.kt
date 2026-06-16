package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow

/** Ladder shape, scale gating, and ND-step invariants. */
class ExposureCoreTest {

    private val calculator = ExposureCalculator()

    @Test
    fun fullStopLadderHas19Entries() {
        assertEquals(19, ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS.size)
    }

    @Test
    fun oneThirdLadderHas55EntriesAndAlignsWithCameraLabels() {
        assertEquals(55, ExposureScale.oneThirdStop.shutterSteps.size)
        assertEquals(55, ExposureScale.oneThirdStopShutterCameraLabels.size)
    }

    @Test
    fun ndLadderCovers0To30() {
        assertEquals(31, ExposureScale.oneThirdStop.ndSteps.size)
        assertEquals(0.0, ExposureScale.oneThirdStop.ndSteps.first().stops, 0.0)
        assertEquals(30.0, ExposureScale.oneThirdStop.ndSteps.last().stops, 0.0)
    }

    @Test
    fun oneThirdScaleDoesNotSnapEvenWhenNdIsWhole() {
        val fractionalBase = (1.0 / 30.0) * 2.0.pow(1.0 / 3.0)
        val oneThird = calculator.calculate(fractionalBase, NdStep(0.0), ExposureScaleMode.ONE_THIRD_STOP)
        assertEquals(fractionalBase, oneThird, 1e-9)

        val fullStop = calculator.calculate(fractionalBase, NdStep(0.0), ExposureScaleMode.FULL_STOP)
        assertTrue("full-stop scale should snap to the ladder", abs(fullStop - oneThird) > 1e-6)
    }

    @Test
    fun fractionalNdAppliesBaseTimesTwoToTheStops() {
        val result = calculator.calculate(1.0, NdStep(0.5), ExposureScaleMode.ONE_THIRD_STOP)
        assertEquals(2.0.pow(0.5), result, 1e-9)
    }

    @Test
    fun snapBoundaryTransitions() {
        assertEquals(30.0, calculator.calculate(1.0, 5), 1e-9)
        assertEquals(64.0, calculator.calculate(1.0, 6), 1e-9)
        assertEquals(512.0, calculator.calculate(0.5, 10), 1e-9)
    }

    @Test
    fun ndStepWholeAndThirdSemantics() {
        assertTrue(NdStep(3.0).isWholeStop)
        assertEquals(3, NdStep(3.0).wholeStops)
        assertNull(NdStep(0.333).wholeStops)
        assertEquals(1, NdStep(1.0 / 3.0).thirdStopCount)
        assertEquals(NdStep(2.0 / 3.0), NdStep.fromThirdStopCount(2))
    }

    @Test
    fun cameraLabelLookupResolvesLadderValue() {
        val oneThirtieth = ExposureScale.oneThirdStop.shutterSteps[24].seconds
        assertEquals("1/30", ExposureScale.oneThirdStopShutterCameraLabel(oneThirtieth))
    }
}
