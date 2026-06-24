package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.timer.TimerIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CalculatorControllerTest {

    private val films = LaunchPresetFilmCatalogLoader().loadBundledCatalog()

    private fun controller(onStart: (Double, TimerIdentity) -> Unit = { _, _ -> }) =
        CalculatorController(films = films, onStart = onStart)

    @Test
    fun defaultsToDigitalWithStartableAdjustedShutter() {
        val s = controller().state.value
        assertEquals("No film", s.selectedFilmName)
        assertTrue(s.startEnabled)
        assertNull(s.correctedText)
        assertTrue(s.adjustedText.isNotEmpty())
        assertTrue(s.modelOptions.isEmpty())
    }

    @Test
    fun startDelegatesDurationAndIdentity() {
        var duration: Double? = null
        var identity: TimerIdentity? = null
        val c = controller { d, id -> duration = d; identity = id }
        c.start()
        assertNotNull(duration)
        assertTrue(duration!! > 0)
        assertNotNull(identity)
        assertTrue(identity!!.title.contains("No film"))
    }

    @Test
    fun selectingFormulaFilmProducesCorrectedExposure() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6) // 1/30 + 6 stops on the 1/3 ladder → long metered
        val s = c.state.value
        assertEquals("Pan F Plus", s.selectedFilmName)
        assertNotNull(s.correctedText)
        assertTrue(s.startEnabled)
    }

    @Test
    fun filmWithAlternatesExposesModelOptions() {
        val c = controller()
        c.selectFilm("foma-fomapan-100")
        val s = c.state.value
        assertTrue(s.modelOptions.size > 1)
    }

    @Test
    fun ndIndexChangesAdjustedShutter() {
        val c = controller()
        val before = c.state.value.adjustedText
        c.setNdIndex(10)
        assertTrue(c.state.value.adjustedText != before)
    }

    @Test
    fun switchingSlotCapturesAndRestoresPerSlotInputs() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)
        val camera1State = c.state.value

        // Camera 2 starts fresh: no film, default ND.
        c.selectSlot(CameraSlotId.camera2)
        val camera2State = c.state.value
        assertEquals("Camera 2", camera2State.activeSlotName)
        assertEquals("No film", camera2State.selectedFilmName)
        assertEquals(0, camera2State.ndIndex)

        // Returning to Camera 1 restores its film + ND.
        c.selectSlot(CameraSlotId.camera1)
        val restored = c.state.value
        assertEquals(camera1State.selectedFilmName, restored.selectedFilmName)
        assertEquals(camera1State.ndIndex, restored.ndIndex)
    }

    @Test
    fun renameActiveSlotFlowsIntoStateAndTimerIdentity() {
        var identity: TimerIdentity? = null
        val c = controller { _, id -> identity = id }
        c.renameActiveSlot("Hasselblad")
        assertEquals("Hasselblad", c.state.value.activeSlotName)
        c.start()
        assertTrue(identity!!.title.startsWith("Hasselblad"))
        assertEquals("C1", identity!!.slotLabel)
    }
}
