package com.sangwook.ptimer.calculator

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.timer.ExposureTimerSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Calculator + film + the explicit per-source start-action model. There is no
 * single generic start: each source (adjusted / corrected / target) exposes its
 * own action with independent enablement.
 */
class CalculatorControllerTest {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private fun controller() = CalculatorController(catalog)

    @Test
    fun noFilmExposesAdjustedStartAndNoCorrected() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5)
        val s = c.uiState()
        assertNull(s.filmName)
        assertEquals("32s", s.adjustedShutterLabel)
        assertTrue(s.adjustedAction.enabled)
        assertEquals(32.0, s.adjustedAction.durationSeconds!!, 1e-9)
        assertEquals(ExposureTimerSource.DIGITAL_RESULT, s.adjustedAction.source)
        assertNull(s.correctedAction)
    }

    @Test
    fun quantifiedFilmExposesBothAdjustedAndCorrectedStarts() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5) // adjusted 32s
        c.selectFilm("ilford-pan-f-plus-50")
        val s = c.uiState()
        assertTrue(s.adjustedAction.enabled)
        assertEquals(ExposureTimerSource.FILM_ADJUSTED_SHUTTER, s.adjustedAction.source)
        assertEquals(32.0, s.adjustedAction.durationSeconds!!, 1e-9)

        val corrected = s.correctedAction!!
        assertTrue(corrected.enabled)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, corrected.source)
        assertTrue(corrected.durationSeconds!! > 32.0) // reciprocity lengthens
        assertTrue(corrected.subtitle.contains("Corrected Exposure"))
        assertNotNull(s.correctedExposureLabel)
    }

    @Test
    fun limitedGuidanceKeepsAdjustedEnabledAndDisablesCorrected() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(7) // 128s, beyond Portra threshold
        c.selectFilm("kodak-portra-400")
        val s = c.uiState()
        // KEY regression guard: adjusted must remain startable.
        assertTrue(s.adjustedAction.enabled)
        assertEquals(128.0, s.adjustedAction.durationSeconds!!, 1e-9)
        assertTrue(s.adjustedAction.subtitle.contains("Limited guidance"))

        val corrected = s.correctedAction!!
        assertFalse(corrected.enabled)
        assertNull(corrected.durationSeconds)
        assertNotNull(corrected.disabledReason)
        assertNull(s.correctedExposureLabel) // no fabricated corrected value
    }

    @Test
    fun noCorrectionFilmStillAllowsCorrectedStartEqualToAdjusted() {
        val c = controller()
        c.setBaseShutterSeconds(1.0 / 30.0); c.setNdStops(0) // adjusted ~1/30 s, below Pan F no-correction
        c.selectFilm("ilford-pan-f-plus-50")
        val corrected = c.uiState().correctedAction!!
        assertTrue(corrected.enabled)
        assertEquals(c.uiState().adjustedAction.durationSeconds!!, corrected.durationSeconds!!, 1e-9)
    }

    @Test
    fun targetActionAppearsOnlyWhenSet() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5)
        assertNull(c.uiState().targetAction)
        c.setTarget(60.0)
        val target = c.uiState().targetAction!!
        assertTrue(target.enabled)
        assertEquals(60.0, target.durationSeconds!!, 1e-9)
        assertEquals(ExposureTimerSource.TARGET_SHUTTER, target.source)
    }

    @Test
    fun clearFilmReturnsToDigital() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.clearFilm()
        assertNull(c.uiState().filmName)
        assertNull(c.uiState().correctedAction)
    }

    @Test
    fun alternateModelSelectionChangesBasisAndCorrectedDuration() {
        val c = controller()
        c.setBaseShutterSeconds(1.0); c.setNdStops(5)
        c.selectFilm("foma-fomapan-100")
        assertEquals("Table-derived", c.uiState().reciprocityBadge)
        assertTrue(c.uiState().availableModels.isNotEmpty())

        c.selectModel("foma-fomapan-100-app-formula")
        assertTrue(c.uiState().reciprocityBadge!!.contains("Formula-derived"))
        assertEquals("App-derived formula", c.uiState().correctedAction!!.selectedModelLabel)
    }
}
