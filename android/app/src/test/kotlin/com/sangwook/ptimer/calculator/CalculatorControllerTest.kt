package com.sangwook.ptimer.calculator

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Calculator + film selection + alternate-model + Start enablement parity. */
class CalculatorControllerTest {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private fun controller() = CalculatorController(catalog)

    @Test
    fun digitalAdjustedShutterAndStartEnabled() {
        val c = controller()
        c.setBaseShutterSeconds(1.0)
        c.setNdStops(5)
        val state = c.uiState()
        assertNull(state.filmName)
        assertEquals("32s", state.adjustedShutterLabel)
        assertTrue(state.canStartTimer)
        val req = c.startRequest()!!
        assertEquals(32.0, req.durationSeconds, 1e-9)
    }

    @Test
    fun formulaFilmProducesCorrectedAndEnablesStart() {
        val c = controller()
        c.setBaseShutterSeconds(1.0)
        c.setNdStops(5) // adjusted 32s
        c.selectFilm("ilford-pan-f-plus-50")
        val state = c.uiState()
        assertEquals("Pan F Plus", state.filmName)
        assertEquals("Official guidance", state.authorityLabel)
        assertNotNull(state.correctedExposureLabel)
        assertEquals("Formula-derived", state.reciprocityBadge)
        assertTrue(state.canStartTimer)
        val req = c.startRequest()!!
        assertTrue(req.durationSeconds > 32.0) // reciprocity lengthens
    }

    @Test
    fun limitedGuidanceFilmDisablesCorrectedTimer() {
        val c = controller()
        c.setBaseShutterSeconds(1.0)
        c.setNdStops(7) // adjusted 128s, beyond Portra threshold
        c.selectFilm("kodak-portra-400")
        val state = c.uiState()
        assertFalse(state.canStartTimer)
        assertNull(state.correctedExposureLabel)
        assertNotNull(state.startDisabledHint)
        assertNull(c.startRequest())
    }

    @Test
    fun clearFilmReturnsToDigital() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.clearFilm()
        assertNull(c.uiState().filmName)
    }

    @Test
    fun alternateModelSelectionChangesBasisAndLabel() {
        val c = controller()
        c.setBaseShutterSeconds(1.0)
        c.setNdStops(5) // 32s
        c.selectFilm("foma-fomapan-100")
        val tableState = c.uiState()
        assertEquals("Table-derived", tableState.reciprocityBadge)
        assertTrue(tableState.availableModels.isNotEmpty())

        c.selectModel("foma-fomapan-100-app-formula")
        val formulaState = c.uiState()
        // App-derived formula is an unofficial secondary source, so the badge
        // is "Secondary Formula-derived" — the basis switched from table to formula.
        assertTrue(formulaState.reciprocityBadge!!.contains("Formula-derived"))
        assertFalse(formulaState.reciprocityBadge.contains("Table"))
        assertEquals("App-derived formula", c.startRequest()!!.selectedModelLabel)
    }
}
