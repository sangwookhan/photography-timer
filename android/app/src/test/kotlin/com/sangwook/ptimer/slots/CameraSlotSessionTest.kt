package com.sangwook.ptimer.slots

import com.sangwook.ptimer.calculator.CalculatorController
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Per-slot independence, capture/restore on switch, and rename isolation. */
class CameraSlotSessionTest {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()

    @Test
    fun fourSlotsExistWithCanonicalLabels() {
        val s = CameraSlotSession()
        assertEquals(4, s.slotIds.size)
        assertEquals("Camera 1", s.label("camera1"))
        assertEquals("Camera 4", s.label("camera4"))
    }

    @Test
    fun perSlotStateIsCapturedAndRestoredOnSwitch() {
        val calc = CalculatorController(catalog)
        val s = CameraSlotSession()

        // Camera 1: 1s base, ND 5, Pan F.
        calc.setBaseShutterSeconds(1.0); calc.setNdStops(5); calc.selectFilm("ilford-pan-f-plus-50")
        s.store(s.activeSlotId, calc.capture())

        // Switch to Camera 2 -> fresh defaults.
        s.activate("camera2"); calc.apply(s.snapshot("camera2"))
        assertEquals(0, calc.uiState().ndStops)
        assertNull(calc.uiState().filmName)
        calc.setNdStops(3); calc.selectFilm(null)
        s.store("camera2", calc.capture())

        // Back to Camera 1 -> restored independently.
        s.activate("camera1"); calc.apply(s.snapshot("camera1"))
        assertEquals(5, calc.uiState().ndStops)
        assertEquals("Pan F Plus", calc.uiState().filmName)
    }

    @Test
    fun renameTrimsResetsAndIsIsolatedFromCalcState() {
        val s = CameraSlotSession()
        s.setCustomName("camera1", "  Hasselblad  ")
        assertEquals("Hasselblad", s.label("camera1"))
        // Blank clears back to canonical.
        s.setCustomName("camera1", "   ")
        assertEquals("Camera 1", s.label("camera1"))
        s.setCustomName("camera1", "Rollei")
        s.resetName("camera1")
        assertEquals("Camera 1", s.label("camera1"))
    }

    @Test
    fun startedTimerLabelIsCapturedAndUnaffectedByLaterRename() {
        val s = CameraSlotSession()
        s.setCustomName("camera1", "Bronica")
        val capturedAtStart = s.activeLabel() // what a timer would embed at start
        s.setCustomName("camera1", "Mamiya")
        assertEquals("Bronica", capturedAtStart) // the captured string never mutates
        assertEquals("Mamiya", s.activeLabel())  // future labels reflect the rename
    }

    // --- restore-name sanitation (blocker 3) -------------------------------

    @Test
    fun restoreTrimsCustomNames() {
        val s = CameraSlotSession()
        s.restore("camera1", emptyMap(), mapOf("camera1" to "  Leica M6  "))
        assertEquals("Leica M6", s.label("camera1"))
    }

    @Test
    fun restoreDropsBlankCustomNames() {
        val s = CameraSlotSession()
        s.restore("camera1", emptyMap(), mapOf("camera1" to "   "))
        assertEquals("Camera 1", s.label("camera1")) // back to canonical
        assertTrue(s.customNames().isEmpty())
    }

    @Test
    fun restoreIgnoresUnknownSlotIds() {
        val s = CameraSlotSession()
        s.restore("camera1", emptyMap(), mapOf("cameraX" to "Ghost", "camera2" to "Hasselblad"))
        assertFalse(s.customNames().containsKey("cameraX"))
        assertEquals("Hasselblad", s.label("camera2"))
    }

    @Test
    fun restoreReplacesPriorCustomNamesWithoutRetainingStaleEntries() {
        val s = CameraSlotSession()
        s.setCustomName("camera1", "Old")
        s.restore("camera1", emptyMap(), mapOf("camera2" to "New"))
        assertEquals("Camera 1", s.label("camera1")) // prior entry cleared
        assertEquals("New", s.label("camera2"))
        assertEquals(setOf("camera2"), s.customNames().keys)
    }

    @Test
    fun setCustomNameIgnoresUnknownSlotIds() {
        val s = CameraSlotSession()
        s.setCustomName("cameraX", "Ghost")
        assertTrue(s.customNames().isEmpty())
    }
}
