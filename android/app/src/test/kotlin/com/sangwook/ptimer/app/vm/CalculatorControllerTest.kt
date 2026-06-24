package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
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
}
