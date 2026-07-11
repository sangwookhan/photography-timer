// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.canceled
import com.sangwook.ptimer.core.timer.completed
import com.sangwook.ptimer.core.timer.pausing
import com.sangwook.ptimer.core.timer.plusSecondsDouble
import com.sangwook.ptimer.core.timer.remainingTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.UUID

class TimerPersistenceTest {

    private val t0: Instant = Instant.parse("2026-06-19T00:00:00Z")
    private val id: UUID = UUID.fromString("00000000-0000-0000-0000-000000000009")
    private fun at(seconds: Double) = t0.plusSecondsDouble(seconds)
    private fun running(duration: Double = 100.0) =
        TimerState.Running(id, duration, t0, endDate = t0.plusSecondsDouble(duration))

    @Test
    fun runningRestoresWhenStillCounting() {
        val snap = PersistentTimerSnapshot.from(running(100.0))
        val restored = snap.restore(at(40.0))
        assertTrue(restored is TimerState.Running)
        assertEquals(at(100.0), (restored as TimerState.Running).endDate)
        assertEquals(60.0, restored.remainingTime(at(40.0)), 1e-9)
    }

    @Test
    fun runningRestoresAsCompletedWhenElapsed() {
        val snap = PersistentTimerSnapshot.from(running(100.0))
        val restored = snap.restore(at(150.0))
        assertTrue(restored is TimerState.Completed)
        assertEquals(at(100.0), (restored as TimerState.Completed).completedAt)
    }

    @Test
    fun pausedRestoresFrozenRegardlessOfWallClock() {
        val paused = running(100.0).pausing(at(30.0))
        val snap = PersistentTimerSnapshot.from(paused)
        val restored = snap.restore(at(99999.0))
        assertTrue(restored is TimerState.Paused)
        assertEquals(70.0, (restored as TimerState.Paused).pausedRemainingTime, 1e-9)
    }

    @Test
    fun corruptPausedSnapshotRestoresAsCompleted() {
        val corrupt = PersistentTimerSnapshot(
            id = id, status = SnapshotStatus.paused, duration = 100.0, startDate = t0,
            pausedRemainingDuration = null, pausedAt = null, completedAt = at(100.0),
        )
        assertTrue(corrupt.restore(at(10.0)) is TimerState.Completed)
    }

    @Test
    fun canceledRestoresRemainingAtCancel() {
        val canceled = running(100.0).canceled(at(40.0))
        val snap = PersistentTimerSnapshot.from(canceled)
        val restored = snap.restore(at(200.0))
        assertTrue(restored is TimerState.Canceled)
        assertEquals(60.0, (restored as TimerState.Canceled).remainingAtCancel, 1e-9)
    }

    @Test
    fun collectionRoundTripsThroughCodec() {
        // Distinct ids so the round-trip exercises three surviving records
        // (per-record decode de-duplicates by id, first-valid-wins).
        fun runningWithId(last: Int, duration: Double) =
            TimerState.Running(
                UUID.fromString("00000000-0000-0000-0000-00000000000$last"),
                duration, t0, t0.plusSecondsDouble(duration),
            )
        val timers = listOf(
            runningWithId(1, 100.0),
            runningWithId(2, 50.0).pausing(at(10.0)),
            runningWithId(3, 20.0).completed(at(20.0)),
        )
        val snapshot = PersistentTimerCollectionSnapshot.from(timers)
        val decoded = TimerSnapshotCodec.decode(TimerSnapshotCodec.encode(snapshot))
        assertEquals(snapshot, decoded)
    }

    @Test
    fun duplicateTimerIdsAreDeduplicated() {
        // Two timers sharing an id collapse to one (first valid wins),
        // reported as a degraded decode (PTIMER-215).
        val snapshot = PersistentTimerCollectionSnapshot.from(listOf(running(100.0), running(50.0)))
        val result = TimerSnapshotCodec.decodeWithDiagnostics(TimerSnapshotCodec.encode(snapshot))
        assertEquals(1, result.snapshot.timers.size)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
    }

    @Test
    fun unknownStatusTokenDropsOnlyThatTimer() {
        val valid = TimerSnapshotCodec.encode(
            PersistentTimerCollectionSnapshot.from(
                listOf(
                    TimerState.Running(
                        UUID.fromString("00000000-0000-0000-0000-000000000001"),
                        100.0, t0, t0.plusSecondsDouble(100.0),
                    ),
                    TimerState.Running(
                        UUID.fromString("00000000-0000-0000-0000-000000000002"),
                        50.0, t0, t0.plusSecondsDouble(50.0),
                    ),
                ),
            ),
        )
        val corrupted = valid.replaceFirst("\"status\":\"running\"", "\"status\":\"warping\"")
        val result = TimerSnapshotCodec.decodeWithDiagnostics(corrupted)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(1, result.snapshot.timers.size)
    }

    @Test
    fun legacyStoppedStatusDecodesAsPaused() {
        val jsonText = """
            {"schemaVersion":1,"timers":[
              {"id":"$id","status":"stopped","duration":100.0,"startDate":"2026-06-19T00:00:00Z",
               "pausedRemainingDuration":70.0,"pausedAt":"2026-06-19T00:00:30Z"}
            ]}
        """.trimIndent()
        val decoded = TimerSnapshotCodec.decode(jsonText)
        assertEquals(SnapshotStatus.paused, decoded!!.timers.first().status)
    }

    @Test
    fun malformedAndFutureSchemaFailSafeToNull() {
        assertNull(TimerSnapshotCodec.decode("not json"))
        assertNull(TimerSnapshotCodec.decode("""{"schemaVersion":999,"timers":[]}"""))
    }
}
