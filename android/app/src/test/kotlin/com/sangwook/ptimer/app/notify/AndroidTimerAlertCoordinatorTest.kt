// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * PTIMER-216: reconciliation contracts for [AndroidTimerAlertCoordinator]
 * through the [TimerAlarmScheduling] / [TimerForegroundServiceControlling]
 * seams — no real AlarmManager or foreground service involved.
 */
class AndroidTimerAlertCoordinatorTest {

    private class FakeScheduling(private val exactSucceeds: Boolean = true) : TimerAlarmScheduling {
        val exactScheduled = mutableListOf<CompletionAlarm>()
        val inexactScheduled = mutableListOf<CompletionAlarm>()
        val canceled = mutableListOf<Pair<UUID, AlertStage>>()

        override fun schedule(alarm: CompletionAlarm, exact: Boolean): Boolean {
            if (exact) exactScheduled.add(alarm) else inexactScheduled.add(alarm)
            return if (exact) exactSucceeds else true
        }

        override fun cancel(timerId: UUID, stage: AlertStage) {
            canceled.add(timerId to stage)
        }
    }

    private class FakeForegroundService : TimerForegroundServiceControlling {
        var content: OngoingContent? = null
        var stopCount = 0

        override fun start(content: OngoingContent) {
            this.content = content
        }

        override fun stop() {
            content = null
            stopCount++
        }
    }

    private class FakeAvailability(private val allowed: Boolean) : ExactAlarmAvailability {
        override val isPermissionGated: Boolean = true
        override fun isAllowed(): Boolean = allowed
        override fun openSettings() {}
    }

    private fun alarm(timerId: UUID, stage: AlertStage, triggerAt: Long, seconds: Int = 0) = CompletionAlarm(
        timerId = timerId,
        triggerAtEpochMillis = triggerAt,
        title = "T",
        subtitle = "S",
        stage = stage,
        secondsBeforeCompletion = seconds,
    )

    @Test
    fun creatingRunningTimerSchedulesTheRequiredAlertStages() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 0L }
        val id = UUID.randomUUID()

        coordinator.sync(
            TimerAlertPlan(
                alarms = listOf(alarm(id, AlertStage.PRE1, 10_000, 10), alarm(id, AlertStage.MAIN, 20_000)),
                ongoing = OngoingContent("T", "text", 20_000),
            ),
        )

        assertEquals(setOf(AlertStage.PRE1, AlertStage.MAIN), scheduling.exactScheduled.map { it.stage }.toSet())
        assertEquals(20_000L, fg.content?.endAtEpochMillis)
    }

    @Test
    fun pausingTimerCancelsItsScheduledStagesAndStopsForegroundServiceWhenNoneRemain() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 0L }
        val id = UUID.randomUUID()
        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 20_000)), ongoing = OngoingContent("T", "x", 20_000)),
        )

        // Pausing removes the timer from the plan entirely — a paused timer has
        // no fixed end, so the planner never includes it.
        coordinator.sync(TimerAlertPlan(alarms = emptyList(), ongoing = null))

        assertTrue(scheduling.canceled.containsAll(AlertStage.entries.map { id to it }))
        assertEquals(1, fg.stopCount)
        assertNull(fg.content)
    }

    @Test
    fun resumingTimerReconcilesAndReschedulesStagesAtTheNewInstant() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 0L }
        val id = UUID.randomUUID()
        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 20_000)), ongoing = OngoingContent("T", "x", 20_000)),
        )
        coordinator.sync(TimerAlertPlan(alarms = emptyList(), ongoing = null)) // paused

        // Resume: remaining time is preserved, so the new end instant differs.
        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 25_000)), ongoing = OngoingContent("T", "x", 25_000)),
        )

        assertEquals(listOf(20_000L, 25_000L), scheduling.exactScheduled.map { it.triggerAtEpochMillis })
        assertEquals(25_000L, fg.content?.endAtEpochMillis)
    }

    @Test
    fun removingTimerCancelsEveryAlertStageForThatTimer() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 0L }
        val id = UUID.randomUUID()
        coordinator.sync(
            TimerAlertPlan(
                alarms = listOf(
                    alarm(id, AlertStage.PRE1, 10_000, 10),
                    alarm(id, AlertStage.PRE2, 15_000, 5),
                    alarm(id, AlertStage.MAIN, 20_000),
                ),
                ongoing = OngoingContent("T", "x", 20_000),
            ),
        )

        coordinator.sync(TimerAlertPlan(alarms = emptyList(), ongoing = null))

        assertEquals(
            AlertStage.entries.toSet(),
            scheduling.canceled.filter { it.first == id }.map { it.second }.toSet(),
        )
    }

    @Test
    fun pastPreAlertStageIsNotScheduled() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        // "Now" is already past the pre-alert's trigger instant but before MAIN.
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 15_000L }
        val id = UUID.randomUUID()

        coordinator.sync(
            TimerAlertPlan(
                alarms = listOf(alarm(id, AlertStage.PRE1, 10_000, 10), alarm(id, AlertStage.MAIN, 20_000)),
                ongoing = OngoingContent("T", "x", 20_000),
            ),
        )

        assertEquals(listOf(AlertStage.MAIN), scheduling.exactScheduled.map { it.stage })
    }

    @Test
    fun mainAlarmIsScheduledEvenWhenItsInstantIsInThePast() {
        // The completion alarm is always scheduled, unlike pre-alerts — a very
        // short resumed timer must not silently drop its completion alert.
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 25_000L }
        val id = UUID.randomUUID()

        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 20_000)), ongoing = OngoingContent("T", "x", 20_000)),
        )

        assertEquals(listOf(AlertStage.MAIN), scheduling.exactScheduled.map { it.stage })
    }

    @Test
    fun exactAlarmSchedulingFallsBackToInexactWhenPermissionUnavailable() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(false), scheduling, fg) { 0L }
        val id = UUID.randomUUID()

        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 20_000)), ongoing = OngoingContent("T", "x", 20_000)),
        )

        assertTrue(scheduling.exactScheduled.isEmpty())
        assertEquals(1, scheduling.inexactScheduled.size)
    }

    @Test
    fun exactSchedulingFailureAtCallTimeDegradesToInexact() {
        // TOCTOU: permission looked allowed at the check, but the OS call itself
        // fails (e.g. permission revoked in between).
        val scheduling = FakeScheduling(exactSucceeds = false)
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 0L }
        val id = UUID.randomUUID()

        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 20_000)), ongoing = OngoingContent("T", "x", 20_000)),
        )

        assertEquals(1, scheduling.exactScheduled.size)
        assertEquals(1, scheduling.inexactScheduled.size)
    }

    @Test
    fun foregroundServiceStartsAndStopsConsistentlyWithWhetherATimerIsRunning() {
        val scheduling = FakeScheduling()
        val fg = FakeForegroundService()
        val coordinator = AndroidTimerAlertCoordinator(FakeAvailability(true), scheduling, fg) { 0L }
        val id = UUID.randomUUID()

        coordinator.sync(TimerAlertPlan(alarms = emptyList(), ongoing = null))
        assertEquals(1, fg.stopCount)
        assertNull(fg.content)

        coordinator.sync(
            TimerAlertPlan(alarms = listOf(alarm(id, AlertStage.MAIN, 20_000)), ongoing = OngoingContent("T", "x", 20_000)),
        )
        assertEquals(20_000L, fg.content?.endAtEpochMillis)

        coordinator.sync(TimerAlertPlan(alarms = emptyList(), ongoing = null))
        assertEquals(2, fg.stopCount)
        assertNull(fg.content)
    }
}
