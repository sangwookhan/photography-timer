// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.timer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.UUID

class TimerStateTest {

    private val t0: Instant = Instant.parse("2026-06-19T00:00:00Z")
    private val id: UUID = UUID.fromString("00000000-0000-0000-0000-000000000001")

    private fun running(duration: Double = 10.0) =
        TimerState.Running(id, duration, t0, endDate = t0.plusSecondsDouble(duration))

    private fun at(seconds: Double) = t0.plusSecondsDouble(seconds)

    @Test
    fun remainingTimeCountsDownAndClampsAtZero() {
        val timer = running(10.0)
        assertEquals(10.0, timer.remainingTime(t0), 1e-9)
        assertEquals(7.0, timer.remainingTime(at(3.0)), 1e-9)
        assertEquals(0.0, timer.remainingTime(at(10.0)), 1e-9)
        assertEquals(0.0, timer.remainingTime(at(20.0)), 1e-9)
    }

    @Test
    fun statusBecomesCompletedAtEnd() {
        val timer = running(10.0)
        assertEquals(TimerStatus.running, timer.status(at(5.0)))
        assertEquals(TimerStatus.completed, timer.status(at(10.0)))
        val updated = timer.updatingStatus(at(10.0))
        assertTrue(updated is TimerState.Completed)
        assertEquals(timer.endDate, (updated as TimerState.Completed).completedAt)
    }

    @Test
    fun pauseFreezesRemainingAndResumeRecomputesEnd() {
        val paused = running(10.0).pausing(at(4.0))
        assertTrue(paused is TimerState.Paused)
        paused as TimerState.Paused
        assertEquals(6.0, paused.pausedRemainingTime, 1e-9)
        assertEquals(at(4.0), paused.pausedAt)
        // Derived endDate stays the original completion instant.
        assertEquals(at(10.0), paused.endDate)
        // Remaining is frozen regardless of wall-clock while paused.
        assertEquals(6.0, paused.remainingTime(at(1000.0)), 1e-9)

        val resumed = paused.resume(at(100.0))
        assertTrue(resumed is TimerState.Running)
        assertEquals(at(106.0), (resumed as TimerState.Running).endDate)
    }

    @Test
    fun pausingAfterEndCompletes() {
        val done = running(10.0).pausing(at(10.0))
        assertTrue(done is TimerState.Completed)
    }

    @Test
    fun cancelRecordsRemainingAndIsTerminal() {
        val canceled = running(10.0).canceled(at(4.0))
        assertTrue(canceled is TimerState.Canceled)
        assertEquals(6.0, (canceled as TimerState.Canceled).remainingAtCancel, 1e-9)
        assertEquals(at(4.0), canceled.canceledAt)
        // A stray cancel cannot rewrite a finished record.
        val completed = running(10.0).completed(at = at(10.0))
        assertEquals(completed, completed.canceled(at(20.0)))
    }

    @Test
    fun pausedTimerCanBeCanceledWithRemaining() {
        val canceled = running(10.0).pausing(at(4.0)).canceled(at(50.0))
        assertTrue(canceled is TimerState.Canceled)
        assertEquals(6.0, (canceled as TimerState.Canceled).remainingAtCancel, 1e-9)
    }

    @Test
    fun legacyFactoryReconstructsEachState() {
        val r = TimerState.fromLegacy(id, 10.0, t0, at(10.0), null, null, TimerStatus.running)
        assertTrue(r is TimerState.Running)
        val p = TimerState.fromLegacy(id, 10.0, t0, null, 6.0, at(4.0), TimerStatus.paused)
        assertEquals(6.0, (p as TimerState.Paused).pausedRemainingTime, 1e-9)
        val c = TimerState.fromLegacy(id, 10.0, t0, at(10.0), null, null, TimerStatus.completed)
        assertTrue(c is TimerState.Completed)
        val x = TimerState.fromLegacy(id, 10.0, t0, at(8.0), 2.0, null, TimerStatus.canceled)
        assertEquals(2.0, (x as TimerState.Canceled).remainingAtCancel, 1e-9)
    }
}
