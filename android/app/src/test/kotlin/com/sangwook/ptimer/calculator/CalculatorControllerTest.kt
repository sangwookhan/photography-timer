package com.sangwook.ptimer.calculator

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.exposure.CalculatorDefaults
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
    fun baseShutterLadderIsExposedAndIndexSelectionDrivesTheValue() {
        val c = controller()
        val ladder = c.uiState().baseShutterLadder
        assertTrue(ladder.size > 5)
        // Selecting a ladder index sets the corresponding base shutter and the
        // reported index round-trips, so a fast picker can drive selection.
        val target = ladder.size / 2
        c.setBaseShutterLadderIndex(target)
        val s = c.uiState()
        assertEquals(target, s.baseShutterIndex)
        assertEquals(ladder[target], s.baseShutterLabel)
    }

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
    fun applyingSnapshotWithUnknownFilmFallsBackToDigital() {
        val c = controller()
        c.setCustomFilms(emptyList())
        c.apply(SlotCalculatorSnapshot(1.0, 5, selectedFilmId = "ghost-film", selectedProfileId = "ghost-profile", targetShutterSeconds = null))
        val s = c.uiState()
        assertNull(s.filmName) // unresolvable film id → digital, no crash
        assertTrue(s.adjustedAction.enabled)
        assertNull(s.correctedAction)
        // Stale ids must not be recaptured into a future snapshot.
        assertNull(c.capture().selectedFilmId)
        assertNull(c.capture().selectedProfileId)
    }

    @Test
    fun applyingSnapshotWithUnknownProfileNormalizesToPrimaryModel() {
        val c = controller()
        c.apply(SlotCalculatorSnapshot(1.0, 0, "kodak-tri-x-400", "bogus-profile", null))
        assertNull(c.capture().selectedProfileId) // stale profile dropped to primary convention
        val models = c.uiState().availableModels
        assertEquals(1, models.count { it.isSelected })
        assertTrue(models.first().isSelected) // the primary option is the selected one
    }

    @Test
    fun applyingSnapshotWithExplicitPrimaryProfileIdNormalizesToNull() {
        val c = controller()
        val primaryId = catalog.first { it.id == "kodak-tri-x-400" }.profiles.first().id
        c.apply(SlotCalculatorSnapshot(1.0, 0, "kodak-tri-x-400", primaryId, null))
        assertNull(c.capture().selectedProfileId)
        assertTrue(c.uiState().availableModels.first().isSelected)
    }

    @Test
    fun applyingSnapshotWithKnownAlternateKeepsItSelected() {
        val c = controller()
        c.apply(SlotCalculatorSnapshot(1.0, 0, "kodak-tri-x-400", "kodak-tri-x-official-table", null))
        assertEquals("kodak-tri-x-official-table", c.capture().selectedProfileId)
        val models = c.uiState().availableModels
        assertEquals(1, models.count { it.isSelected })
        assertEquals("kodak-tri-x-official-table", models.first { it.isSelected }.profileId)
    }

    @Test
    fun activeFilmModelSelectionAlwaysHasExactlyOneSelectedOption() {
        val c = controller()
        c.selectFilm("kodak-tri-x-400") // fresh selection → primary
        assertEquals(1, c.uiState().availableModels.count { it.isSelected })
        c.selectModel("kodak-tri-x-app-formula") // pick an alternate
        assertEquals(1, c.uiState().availableModels.count { it.isSelected })
    }

    @Test
    fun applyingSnapshotSanitizesCorruptTargetAndOutOfRangeNd() {
        val c = controller()
        c.apply(SlotCalculatorSnapshot(1.0, 99, null, null, targetShutterSeconds = -5.0))
        assertNull(c.uiState().targetSeconds) // negative target dropped
        assertEquals(30, c.uiState().ndStops) // ND clamped to 0..30
        c.apply(SlotCalculatorSnapshot(1.0, 0, null, null, targetShutterSeconds = Double.NaN))
        assertNull(c.uiState().targetSeconds) // NaN target dropped
    }

    @Test
    fun applyingSnapshotWithCorruptBaseFallsBackToDefaultShutter() {
        val c = controller()
        c.apply(SlotCalculatorSnapshot(-3.0, 0, null, null, null)) // negative base
        assertEquals(CalculatorDefaults.BASE_SHUTTER_SECONDS, c.currentBaseSeconds(), 1e-12)
        c.apply(SlotCalculatorSnapshot(Double.NaN, 0, null, null, null)) // NaN base
        assertEquals(CalculatorDefaults.BASE_SHUTTER_SECONDS, c.currentBaseSeconds(), 1e-12)
        // A valid persisted base is preserved verbatim.
        c.apply(SlotCalculatorSnapshot(0.5, 0, null, null, null))
        assertEquals(0.5, c.currentBaseSeconds(), 1e-12)
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
