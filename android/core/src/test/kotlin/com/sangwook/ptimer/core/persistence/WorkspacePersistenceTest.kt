package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.WorkspaceTimer
import com.sangwook.ptimer.core.timer.plusSecondsDouble
import com.sangwook.ptimer.core.timer.status
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.util.UUID

class WorkspacePersistenceTest {

    private val t0: Instant = Instant.parse("2026-06-20T00:00:00Z")
    private fun at(s: Double) = t0.plusSecondsDouble(s)
    private fun wt(idLast: Int, duration: Double, title: String) = WorkspaceTimer(
        state = TimerState.Running(
            UUID.fromString("00000000-0000-0000-0000-00000000000$idLast"),
            duration, t0, t0.plusSecondsDouble(duration),
        ),
        identity = TimerIdentity(title = title, slotLabel = "C$idLast"),
    )

    @Test
    fun workspaceRoundTripsThroughCodecWithIdentity() {
        val timers = listOf(wt(1, 100.0, "Camera 1 · No film"), wt(2, 50.0, "Camera 2 · HP5 Plus"))
        val snapshot = PersistentWorkspaceSnapshot.from(timers)
        val decoded = WorkspaceSnapshotCodec.decode(WorkspaceSnapshotCodec.encode(snapshot))
        assertEquals(snapshot, decoded)
        val restored = decoded!!.restore(at(10.0))
        assertEquals("Camera 1 · No film", restored.first().identity.title)
        assertEquals(TimerStatus.running, restored.first().state.status)
    }

    @Test
    fun futureSchemaAndMalformedFailSafe() {
        assertNull(WorkspaceSnapshotCodec.decode("nope"))
        assertNull(WorkspaceSnapshotCodec.decode("""{"schemaVersion":42,"timers":[]}"""))
    }
}
