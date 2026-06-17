package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** JVM round-trip + fail-safe tests for the timer persistence codec. */
class TimerSnapshotCodecTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")

    @Test
    fun roundTripsRunningPausedCompletedWithNames() {
        val timers = listOf(
            TimerState.running("r", 100.0, base),
            TimerState.Paused("p", 100.0, base, pausedRemainingSeconds = 40.0, pausedAt = base.plusSeconds(60)),
            TimerState.Completed("c", 30.0, base, completedAt = base.plusSeconds(30)),
        )
        val names = mapOf("r" to "Run", "p" to "Pause", "c" to "Done")
        val json = TimerSnapshotCodec.encode(timers, names)

        val restored = TimerSnapshotCodec.decode(json)
        assertEquals(3, restored.snapshots.size)
        assertEquals(names, restored.names)

        // Restore at a time before any running end keeps the running timer running.
        val running = restored.snapshots.first { it.id == "r" }.restore(base.plusSeconds(10))
        assertEquals(TimerStatus.RUNNING, running.status)
        val paused = restored.snapshots.first { it.id == "p" }.restore(base.plusSeconds(9999))
        assertEquals(TimerStatus.PAUSED, paused.status)
        assertEquals(40.0, paused.remainingTime(base.plusSeconds(9999)), 1e-6)
    }

    @Test
    fun corruptPayloadDecodesToEmpty() {
        assertTrue(TimerSnapshotCodec.decode("{ not json").snapshots.isEmpty())
        assertTrue(TimerSnapshotCodec.decode("").snapshots.isEmpty())
    }

    @Test
    fun unknownSchemaVersionDecodesToEmpty() {
        val future = """{"schemaVersion":999,"timers":[]}"""
        assertTrue(TimerSnapshotCodec.decode(future).snapshots.isEmpty())
    }
}
