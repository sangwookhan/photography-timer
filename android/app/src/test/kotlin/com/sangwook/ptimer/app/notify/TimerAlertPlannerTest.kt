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

    private fun card(status: TimerStatus, endMillis: Long, title: String = "T") = TimerCardState(
        id = UUID.randomUUID(),
        order = 1,
        identity = TimerIdentity(title = title, subtitle = "", baseLine = "", slotLabel = ""),
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
        // Ongoing reflects the soonest-ending running timer and the running count.
        assertEquals("Camera 2", plan.ongoing!!.title)
        assertTrue(plan.ongoing!!.text.contains("2 timers running"))
        assertTrue(plan.ongoing!!.text.contains("@3000"))
    }
}
