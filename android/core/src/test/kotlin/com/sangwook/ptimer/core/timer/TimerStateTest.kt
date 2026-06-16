package com.sangwook.ptimer.core.timer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Pause/resume/complete transition invariants. Protected behavior. */
class TimerStateTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")

    @Test
    fun resumeAfterPauseWindowExpiredKeepsRemaining() {
        val paused = TimerState.Paused("t", 10.0, base, pausedRemainingSeconds = 6.0, pausedAt = base.plusSeconds(2))
        val now = base.plusSeconds(9) // pausedAt + 7
        val resumed = paused.resume(now)
        assertTrue(resumed is TimerState.Running)
        assertEquals(6.0, resumed.remainingTime(now), 1e-6)
        assertEquals(now.plusSeconds(6), resumed.endDate)
    }

    @Test
    fun resumeWithZeroRemainingCompletes() {
        val paused = TimerState.Paused("t", 10.0, base, pausedRemainingSeconds = 0.0, pausedAt = base.plusSeconds(2))
        assertTrue(paused.resume(base.plusSeconds(3)) is TimerState.Completed)
    }

    @Test
    fun pausingWhenRemainingZeroImmediatelyCompletes() {
        val running = TimerState.running("t", 10.0, base)
        val completed = running.pausing(running.endDate)
        assertTrue(completed is TimerState.Completed)
        assertEquals(0.0, completed.remainingTime(running.endDate), 0.0)
    }

    @Test
    fun pauseFreezesRemainingRegardlessOfWallClock() {
        val running = TimerState.running("t", 100.0, base)
        val paused = running.pausing(base.plusSeconds(40))
        assertTrue(paused is TimerState.Paused)
        assertEquals(60.0, paused.remainingTime(base.plusSeconds(40)), 1e-6)
        // Wall clock advancing does not change a paused timer's remaining.
        assertEquals(60.0, paused.remainingTime(base.plusSeconds(9999)), 1e-6)
    }

    @Test
    fun runningCompletesAtEndAndPreservesDuration() {
        val running = TimerState.running("t", 30.0, base)
        val completed = running.updatingStatus(base.plusSeconds(30))
        assertEquals(TimerStatus.COMPLETED, completed.status)
        assertEquals(30.0, completed.durationSeconds, 0.0)
        assertEquals(0.0, completed.remainingTime(base.plusSeconds(30)), 0.0)
    }

    @Test
    fun runningRemainingCountsDown() {
        val running = TimerState.running("t", 100.0, base)
        assertEquals(70.0, running.remainingTime(base.plusSeconds(30)), 1e-6)
    }
}
