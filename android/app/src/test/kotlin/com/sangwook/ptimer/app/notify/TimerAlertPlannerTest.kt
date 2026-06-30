// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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
        durationSeconds: Double = 0.0,
    ) = TimerCardState(
        id = UUID.randomUUID(),
        order = 1,
        identity = TimerIdentity(title = title, subtitle = subtitle, baseLine = "", slotLabel = ""),
        status = status,
        remainingSeconds = 10.0,
        endDate = Instant.ofEpochMilli(endMillis),
        remainingAtCancelSeconds = null,
        durationSeconds = durationSeconds,
    )

    @Test
    fun shortTimerSchedulesCompletionOnly() {
        val plan = TimerAlertPlanner.plan(
            listOf(card(TimerStatus.running, endMillis = 25_000, durationSeconds = 25.0)),
        ) { "clock" }
        assertEquals(listOf(AlertStage.MAIN), plan.alarms.map { it.stage })
    }

    @Test
    fun mediumTimerSchedulesPre1FiveSecondsBeforeCompletion() {
        val plan = TimerAlertPlanner.plan(
            listOf(card(TimerStatus.running, endMillis = 45_000, durationSeconds = 45.0)),
        ) { "clock" }

        val byStage = plan.alarms.associateBy { it.stage }
        assertEquals(setOf(AlertStage.PRE1, AlertStage.MAIN), byStage.keys)
        assertEquals(40_000L, byStage[AlertStage.PRE1]!!.triggerAtEpochMillis)
        assertEquals(5, byStage[AlertStage.PRE1]!!.secondsBeforeCompletion)
        assertEquals(45_000L, byStage[AlertStage.MAIN]!!.triggerAtEpochMillis)
    }

    @Test
    fun longTimerSchedulesPre1AtTenAndPre2AtFiveBeforeCompletion() {
        val plan = TimerAlertPlanner.plan(
            listOf(card(TimerStatus.running, endMillis = 75_000, durationSeconds = 75.0)),
        ) { "clock" }

        val byStage = plan.alarms.associateBy { it.stage }
        assertEquals(setOf(AlertStage.PRE1, AlertStage.PRE2, AlertStage.MAIN), byStage.keys)
        assertEquals(65_000L, byStage[AlertStage.PRE1]!!.triggerAtEpochMillis)
        assertEquals(10, byStage[AlertStage.PRE1]!!.secondsBeforeCompletion)
        assertEquals(70_000L, byStage[AlertStage.PRE2]!!.triggerAtEpochMillis)
        assertEquals(5, byStage[AlertStage.PRE2]!!.secondsBeforeCompletion)
        assertEquals(75_000L, byStage[AlertStage.MAIN]!!.triggerAtEpochMillis)
    }

    @Test
    fun preAlertsDoNotAffectOngoingOrStageSequence() {
        val plan = TimerAlertPlanner.plan(
            listOf(
                card(TimerStatus.running, endMillis = 90_000, title = "Camera 1", durationSeconds = 90.0),
                card(TimerStatus.running, endMillis = 50_000, title = "Camera 2", durationSeconds = 50.0),
            ),
        ) { millis -> "@$millis" }

        // Ongoing + stages still track completions only (the soonest end), even
        // though pre-alerts now pad plan.alarms.
        assertEquals("Camera 2", plan.ongoing!!.title)
        assertEquals(listOf(50_000L, 90_000L), plan.stages.map { it.endMillis })
        // Camera 1 (>60s) contributes pre1+pre2+main; Camera 2 (30-60s) pre1+main.
        assertEquals(5, plan.alarms.size)
    }

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
