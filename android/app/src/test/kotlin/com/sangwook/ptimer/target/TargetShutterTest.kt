package com.sangwook.ptimer.target

import com.sangwook.ptimer.calculator.CalculatorController
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.slots.CameraSlotSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.ln
import kotlin.math.pow

/** Target shutter comparison vs adjusted (digital) / corrected (film), and per-slot isolation. */
class TargetShutterTest {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private fun controller() = CalculatorController(catalog)
    private fun stops(a: Double, b: Double) = ln(a / b) / ln(2.0)

    @Test
    fun digitalComparesAgainstAdjustedShutter() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5) // adjusted 32s
        c.setTarget(32.0)
        assertTrue(c.uiState().targetIsMatch)
        c.setTarget(64.0)
        assertEquals(1.0, c.uiState().targetStopDifference!!, 1e-6)
    }

    @Test
    fun filmComparesAgainstCorrectedExposure() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5) // adjusted 32s
        c.selectFilm("ilford-pan-f-plus-50") // corrected = 32^1.33
        val corrected = 32.0.pow(1.33)
        c.setTarget(1000.0)
        // Difference must be relative to the corrected exposure, not the adjusted shutter.
        assertEquals(stops(1000.0, corrected), c.uiState().targetStopDifference!!, 1e-3)
    }

    @Test
    fun nonQuantifiedFilmReportsUnavailable() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(7) // 128s, beyond Portra threshold
        c.selectFilm("kodak-portra-400")
        c.setTarget(200.0)
        assertTrue(c.uiState().targetUnavailable)
        assertNull(c.uiState().targetStopDifference)
    }

    @Test
    fun targetIsPerSlotIsolated() {
        val c = controller()
        val s = CameraSlotSession()
        c.setTarget(120.0)
        s.store("camera1", c.capture())
        s.activate("camera2"); c.apply(s.snapshot("camera2"))
        assertNull(c.uiState().targetSeconds)
        s.activate("camera1"); c.apply(s.snapshot("camera1"))
        assertEquals(120.0, c.uiState().targetSeconds!!, 1e-9)
    }

    @Test
    fun presenterMatchEpsilonAndUnavailable() {
        assertTrue(TargetShutterPresenter.compare(100.0, 100.0).isMatch)
        assertTrue(TargetShutterPresenter.compare(100.0, null).isUnavailable)
        assertFalse(TargetShutterPresenter.compare(200.0, 100.0).isMatch)
    }
}
