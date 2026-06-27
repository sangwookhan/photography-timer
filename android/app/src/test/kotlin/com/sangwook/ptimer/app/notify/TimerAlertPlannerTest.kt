package com.sangwook.ptimer.app.notify

import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.UUID

class TimerAlertPlannerTest {

    private fun card(
        status: TimerStatus,
        endMillis: Long,
        title: String = "T",
        subtitle: String = "",
    ) = TimerCardState(
        id = UUID.randomUUID(),
        order = 1,
        identity = TimerIdentity(title = title, subtitle = subtitle, baseLine = "", slotLabel = ""),
        status = status,
        remainingSeconds = 10.0,
        endDate = Instant.ofEpochMilli(endMillis),
        remainingAtCancelSeconds = null,
    )

    @Test
    fun noRunningTimersProducesNoAlarmsAndNoOngoing() {
        val plan = TimerAlertPlanner.plan(
            listOf(card(TimerStatus.paused, 5000), card(TimerStatus.completed, 1000)),
        ) { "clock" }
        assertTrue(plan.alarms.isEmpty())
        assertNull(plan.ongoing)
    }

    @Test
    fun runningTimersYieldAlarmsAndOngoingSummaryFromSoonest() {
        val plan = TimerAlertPlanner.plan(
            listOf(
                card(TimerStatus.running, 9000, "Camera 1"),
                card(TimerStatus.running, 3000, "Camera 2"),
                card(TimerStatus.paused, 1000, "Camera 3"),
            ),
        ) { millis -> "@$millis" }

        assertEquals(2, plan.alarms.size)
        assertEquals(setOf(9000L, 3000L), plan.alarms.map { it.triggerAtEpochMillis }.toSet())
        // Ongoing reflects the soonest-ending running timer (the live-countdown
        // representative) and the running count, in the iOS wording.
        assertEquals("Camera 2", plan.ongoing!!.title)
        assertEquals(3000L, plan.ongoing!!.endAtEpochMillis)
        assertTrue(plan.ongoing!!.text.contains("Expected completion"))
        assertTrue(plan.ongoing!!.text.contains("@3000"))
        assertTrue(plan.ongoing!!.text.contains("2 timers"))
    }

    @Test
    fun stagesAdvanceThroughEachRepresentativeAsTimersComplete() {
        val plan = TimerAlertPlanner.plan(
            listOf(
                card(TimerStatus.running, 9000, "Camera 1"),
                card(TimerStatus.running, 3000, "Camera 2"),
                card(TimerStatus.paused, 1000, "Camera 3"),
            ),
        ) { millis -> "@$millis" }

        // One stage per running timer, ordered by end. The first stage equals
        // the initial ongoing; later stages drop the completed timers.
        assertEquals(listOf(3000L, 9000L), plan.stages.map { it.endMillis })
        assertEquals(plan.ongoing, plan.stages.first().content)
        // While Camera 2 (3000) is representative: 2 timers, ends @3000.
        assertEquals("Camera 2", plan.stages[0].content.title)
        assertTrue(plan.stages[0].content.text.contains("2 timers"))
        // After it completes, Camera 1 (9000) is the lone representative.
        assertEquals("Camera 1", plan.stages[1].content.title)
        assertEquals(9000L, plan.stages[1].content.endAtEpochMillis)
        assertTrue(plan.stages[1].content.text.contains("Expected completion"))
        assertTrue(plan.stages[1].content.text.contains("@9000"))
        assertTrue(!plan.stages[1].content.text.contains("timers"))
    }

    @Test
    fun completionAlarmsCarryCameraIdentityAndSourceLine() {
        val plan = TimerAlertPlanner.plan(
            listOf(
                card(TimerStatus.running, 9000, title = "Camera 1 · No film", subtitle = "Adjusted shutter · 8 stops"),
                card(TimerStatus.running, 3000, title = "Camera 2 · Velvia 50", subtitle = "Target shutter"),
            ),
        ) { millis -> "@$millis" }

        // Each completion alarm carries the camera/film title + the shooting
        // source line, so the completion notification distinguishes which timer
        // and source finished (adjusted vs target are not interchangeable).
        val byTitle = plan.alarms.associateBy { it.title }
        assertEquals(2, byTitle.size)
        assertEquals("Adjusted shutter · 8 stops", byTitle["Camera 1 · No film"]!!.subtitle)
        assertEquals("Target shutter", byTitle["Camera 2 · Velvia 50"]!!.subtitle)
    }
}
