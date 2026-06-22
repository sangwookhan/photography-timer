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
    fun presentationExposesCompactDurationAndStopComparison() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5) // adjusted 32s
        // Unset: no duration or comparison line.
        assertNull(c.uiState().targetDurationLabel)
        assertNull(c.uiState().targetComparisonLabel)
        // Match: compact duration + "0 stops" (mirrors the iOS green "= 0 stops").
        c.setTarget(32.0)
        assertEquals("32s", c.uiState().targetDurationLabel)
        assertTrue(c.uiState().targetIsMatch)
        assertEquals("0 stops", c.uiState().targetComparisonLabel)
        // Longer: compact h/m/s duration + signed "+" stops.
        c.setTarget(64.0)
        assertEquals("1m 4s", c.uiState().targetDurationLabel)
        assertEquals("+1.0 stops", c.uiState().targetComparisonLabel)
        // Shorter: true minus sign (U+2212), not a hyphen.
        c.setTarget(16.0)
        assertEquals("−1.0 stops", c.uiState().targetComparisonLabel)
    }

    @Test
    fun presentationReportsComparisonUnavailableWithStableDuration() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(7) // 128s, beyond Portra threshold
        c.selectFilm("kodak-portra-400")
        c.setTarget(200.0)
        // Duration still shown (compact); comparison line is the stable fallback.
        assertEquals("3m 20s", c.uiState().targetDurationLabel)
        assertTrue(c.uiState().targetUnavailable)
        assertEquals("Comparison unavailable", c.uiState().targetComparisonLabel)
    }

    @Test
    fun quickPresetParkingMatchesNearestStop() {
        fun parked(seconds: Double) = TargetQuickPresets.seconds[TargetQuickPresets.nearestIndex(seconds)]
        // Fine 12m parks near the 15m preset (closer than 8m on a stop scale).
        assertEquals(900.0, parked(720.0), 1e-9)
        // Exact presets park on themselves (e.g. Quick 1h <-> Fine 1h).
        assertEquals(3600.0, parked(3600.0), 1e-9)
        assertEquals(60.0, parked(60.0), 1e-9)
        // Out-of-range / non-finite drafts clamp to the first preset, not crash.
        assertEquals(1.0, parked(0.4), 1e-9)
        assertEquals(0, TargetQuickPresets.nearestIndex(Double.NaN))
    }

    @Test
    fun compactDurationFormatDropsZeroComponents() {
        assertEquals("45s", TargetDurationFormat.compact(45.0))
        assertEquals("4m", TargetDurationFormat.compact(240.0))
        assertEquals("3m 20s", TargetDurationFormat.compact(200.0))
        assertEquals("2h", TargetDurationFormat.compact(7200.0))
        assertEquals("1h 5s", TargetDurationFormat.compact(3605.0))
        assertEquals("8h", TargetDurationFormat.compact(28_800.0))
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
