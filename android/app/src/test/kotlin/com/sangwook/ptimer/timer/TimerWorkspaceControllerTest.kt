package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** JVM tests for the Android-free timer workspace controller. */
class TimerWorkspaceControllerTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")
    private var now: Instant = base
    private val controller = TimerWorkspaceController { now }

    private fun TimerWorkspaceController.startAdjusted(title: String, durationSeconds: Double) =
        start(title, "Adjusted Shutter · ${durationSeconds.toInt()}s", ExposureTimerSource.FILM_ADJUSTED_SHUTTER, durationSeconds)

    @Test
    fun startAddsActiveTimerWithRemaining() {
        controller.startAdjusted("Cam 1 · Shot", 100.0)
        now = base.plusSeconds(30)
        controller.refresh()
        val item = controller.state.value.active.single()
        assertEquals("Cam 1 · Shot", item.title)
        assertEquals(ExposureTimerSource.FILM_ADJUSTED_SHUTTER, item.source)
        assertEquals(TimerStatus.RUNNING, item.status)
        assertEquals(70.0, item.remainingSeconds, 1.0)
    }

    @Test
    fun pauseAndResumeFreezeAndContinue() {
        val id = controller.startAdjusted("Shot", 100.0)!!
        now = base.plusSeconds(40)
        controller.pause(id)
        assertEquals(TimerStatus.PAUSED, controller.state.value.active.single().status)
        now = base.plusSeconds(9999)
        controller.refresh()
        assertEquals(60.0, controller.state.value.active.single().remainingSeconds, 1e-6)
        controller.resume(id)
        assertEquals(TimerStatus.RUNNING, controller.state.value.active.single().status)
    }

    @Test
    fun tickCompletesExactlyOnceAndMovesToCompleted() {
        controller.startAdjusted("A", 10.0)
        controller.startAdjusted("B", 100.0)
        now = base.plusSeconds(10)
        val completed = controller.tick()
        assertEquals(1, completed.size)
        assertTrue(controller.tick().isEmpty())
        assertEquals(1, controller.state.value.completed.size)
        assertEquals(1, controller.state.value.active.size)
    }

    @Test
    fun activeOrderingIsNewestFirst() {
        controller.startAdjusted("first", 100.0)
        now = base.plusSeconds(1)
        controller.startAdjusted("second", 100.0)
        controller.refresh()
        assertEquals(listOf("second", "first"), controller.state.value.active.map { it.title })
    }

    @Test
    fun sourceIdentityIsPreservedPerTimer() {
        controller.start("Cam · Digital", "Adjusted Shutter · 10s", ExposureTimerSource.DIGITAL_RESULT, 10.0)
        controller.start("Cam · Fomapan", "Corrected Exposure · table · 02:00", ExposureTimerSource.FILM_CORRECTED_EXPOSURE, 120.0)
        val active = controller.state.value.active
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, active.first { it.title.contains("Fomapan") }.source)
        assertEquals(ExposureTimerSource.DIGITAL_RESULT, active.first { it.title.contains("Digital") }.source)
        assertTrue(active.first { it.title.contains("Fomapan") }.subtitle.contains("Corrected Exposure"))
    }

    @Test
    fun startAgainClonesTitleSubtitleAndSource() {
        controller.start("Cam · Fomapan", "Corrected Exposure · table", ExposureTimerSource.FILM_CORRECTED_EXPOSURE, 42.0)
        now = base.plusSeconds(42)
        controller.tick()
        val completedId = controller.state.value.completed.single().id
        now = base.plusSeconds(50)
        controller.startAgain(completedId)
        val active = controller.state.value.active.single()
        assertEquals("Cam · Fomapan", active.title)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, active.source)
        assertEquals(TimerStatus.RUNNING, active.status)
    }

    @Test
    fun restoreFromJsonPreservesIdentityAndRunningRemaining() {
        controller.start("Cam 2 · Portra 400", "Adjusted Shutter · Limited guidance · 100s", ExposureTimerSource.FILM_ADJUSTED_SHUTTER, 100.0)
        now = base.plusSeconds(30)
        val json = controller.snapshotJson()

        val restored = TimerWorkspaceController { base.plusSeconds(30) }
        restored.restoreFromJson(json)
        val item = restored.state.value.active.single()
        assertEquals("Cam 2 · Portra 400", item.title)
        assertTrue(item.subtitle.contains("Limited guidance"))
        assertEquals(ExposureTimerSource.FILM_ADJUSTED_SHUTTER, item.source)
        assertEquals(70.0, item.remainingSeconds, 1.0)
    }

    @Test
    fun nonPositiveDurationDoesNotStart() {
        assertNull(controller.startAdjusted("bad", 0.0))
        assertTrue(controller.state.value.active.isEmpty())
    }
}
