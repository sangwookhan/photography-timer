package com.sangwook.ptimer.core.timer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Runtime collection behavior: lifecycle, tick, reconcile, restore, ordering, start-again. */
class TimerRuntimeTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")

    @Test
    fun startAddsRunningAndRejectsNonPositiveDuration() {
        val r = TimerRuntime()
        assertEquals("a", r.start("a", 10.0, base))
        assertNull(r.start("b", 0.0, base))
        assertNull(r.start("c", Double.NaN, base))
        assertEquals(1, r.timers.size)
    }

    @Test
    fun multipleTimersCountDownIndependently() {
        val r = TimerRuntime()
        r.start("a", 10.0, base)
        r.start("b", 100.0, base)
        val at = base.plusSeconds(5)
        assertEquals(5.0, r.timers.first { it.id == "a" }.remainingTime(at), 1e-6)
        assertEquals(95.0, r.timers.first { it.id == "b" }.remainingTime(at), 1e-6)
    }

    @Test
    fun tickCompletesExpiredOnceThenIsQuiet() {
        val r = TimerRuntime()
        r.start("a", 10.0, base)
        r.start("b", 100.0, base)
        val newlyCompleted = r.tick(base.plusSeconds(10))
        assertEquals(listOf("a"), newlyCompleted)
        assertEquals(TimerStatus.COMPLETED, r.timers.first { it.id == "a" }.status)
        // Second tick at the same time must not re-report a completion.
        assertTrue(r.tick(base.plusSeconds(10)).isEmpty())
    }

    @Test
    fun reconcileCompletesWithoutReportingAlerts() {
        val r = TimerRuntime()
        r.start("a", 10.0, base)
        r.reconcile(base.plusSeconds(20))
        assertEquals(TimerStatus.COMPLETED, r.timers.first().status)
    }

    @Test
    fun pauseResumeRemoveAndRemoveCompleted() {
        val r = TimerRuntime()
        r.start("a", 100.0, base)
        r.pause("a", base.plusSeconds(40))
        assertEquals(TimerStatus.PAUSED, r.timers.first().status)
        r.resume("a", base.plusSeconds(50))
        assertEquals(TimerStatus.RUNNING, r.timers.first().status)
        r.start("b", 5.0, base)
        r.tick(base.plusSeconds(10))
        r.removeCompleted()
        assertTrue(r.timers.none { it.id == "b" })
        r.remove("a")
        assertTrue(r.timers.isEmpty())
    }

    @Test
    fun hasRunningTimersGatesLoop() {
        val r = TimerRuntime()
        r.start("a", 10.0, base)
        assertTrue(r.hasRunningTimers(base.plusSeconds(5)))
        assertFalse(r.hasRunningTimers(base.plusSeconds(20)))
    }

    @Test
    fun restoreRunningPastEndCompletesAtExpectedTime() {
        val snap = PersistentTimerSnapshot(
            "a", PersistentTimerSnapshot.SnapshotStatus.RUNNING, 10.0, base,
            expectedCompletionAt = base.plusSeconds(10), pausedRemainingDuration = null, pausedAt = null, completedAt = null,
        )
        val restored = snap.restore(base.plusSeconds(20))
        assertTrue(restored is TimerState.Completed)
        assertEquals(base.plusSeconds(10), (restored as TimerState.Completed).completedAt)
    }

    @Test
    fun restoreRunningBeforeEndStaysRunning() {
        val snap = PersistentTimerSnapshot(
            "a", PersistentTimerSnapshot.SnapshotStatus.RUNNING, 10.0, base,
            expectedCompletionAt = base.plusSeconds(10), pausedRemainingDuration = null, pausedAt = null, completedAt = null,
        )
        assertTrue(snap.restore(base.plusSeconds(5)) is TimerState.Running)
    }

    @Test
    fun restorePausedStaysFrozen() {
        val snap = PersistentTimerSnapshot(
            "a", PersistentTimerSnapshot.SnapshotStatus.PAUSED, 10.0, base,
            expectedCompletionAt = null, pausedRemainingDuration = 6.0, pausedAt = base.plusSeconds(2), completedAt = null,
        )
        val restored = snap.restore(base.plusSeconds(9999))
        assertTrue(restored is TimerState.Paused)
        assertEquals(6.0, restored.remainingTime(base.plusSeconds(9999)), 1e-6)
    }

    @Test
    fun restoreCorruptPausedBecomesCompletedWithoutFabricatingFreeze() {
        val snap = PersistentTimerSnapshot(
            "a", PersistentTimerSnapshot.SnapshotStatus.PAUSED, 10.0, base,
            expectedCompletionAt = null, pausedRemainingDuration = null, pausedAt = null, completedAt = null,
        )
        val restored = snap.restore(base.plusSeconds(5))
        assertTrue(restored is TimerState.Completed)
        // Fallback completion = startDate + duration when no timestamp exists.
        assertEquals(base.plusSeconds(10), (restored as TimerState.Completed).completedAt)
    }

    @Test
    fun legacyStoppedTokenDecodesToPaused() {
        assertEquals(
            PersistentTimerSnapshot.SnapshotStatus.PAUSED,
            PersistentTimerSnapshot.SnapshotStatus.fromToken("stopped"),
        )
    }

    @Test
    fun orderingActiveNewestFirstCompletedBehind() {
        val r = TimerRuntime()
        r.start("a", 100.0, base)
        r.start("b", 100.0, base.plusSeconds(1))
        r.start("c", 5.0, base.plusSeconds(2))
        r.tick(base.plusSeconds(10)) // c completes
        val ordered = TimerWorkspaceOrdering.order(r.timers)
        assertEquals(listOf("b", "a"), ordered.active.map { it.id })
        assertEquals(listOf("c"), ordered.completed.map { it.id })
    }

    @Test
    fun startAgainClonesCompletedDuration() {
        val r = TimerRuntime()
        r.start("a", 42.0, base)
        r.tick(base.plusSeconds(42))
        assertEquals("a2", r.startAgain("a", "a2", base.plusSeconds(50)))
        val clone = r.timers.first { it.id == "a2" }
        assertEquals(42.0, clone.durationSeconds, 0.0)
        assertEquals(TimerStatus.RUNNING, clone.status)
    }
}
