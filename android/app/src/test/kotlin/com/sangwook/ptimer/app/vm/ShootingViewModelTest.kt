// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import android.content.Context
import com.sangwook.ptimer.app.notify.TimerAlarmPlayer
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.UUID

class ShootingViewModelTest {

    private val t0: Instant = Instant.parse("2026-06-20T00:00:00Z")

    private class FakeStore : WorkspacePersistenceStoring {
        var saved: PersistentWorkspaceSnapshot? = null
        var toLoad: PersistentWorkspaceSnapshot? = null
        override fun loadSnapshot() = toLoad
        override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) { saved = snapshot }
        override fun clearSnapshot() { saved = null }
    }

    /** In-memory alarm player so the VM's alarm wiring is testable off-device. */
    private class FakeAlarmPlayer : TimerAlarmPlayer {
        private val _soundingTimerId = MutableStateFlow<UUID?>(null)
        override val soundingTimerId: StateFlow<UUID?> = _soundingTimerId.asStateFlow()
        var stopCount = 0
            private set

        override fun playAlarm(context: Context, timerId: UUID) { _soundingTimerId.value = timerId }
        override fun stop() { stopCount++; _soundingTimerId.value = null }

        /** Set the sounding timer without needing a Context (no real playback). */
        fun simulateSounding(timerId: UUID) { _soundingTimerId.value = timerId }
    }

    /** A store whose reads and writes always fail, to test restore resilience. */
    private class ThrowingStore : WorkspacePersistenceStoring {
        override fun loadSnapshot(): PersistentWorkspaceSnapshot? = throw RuntimeException("read failed")
        override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) = throw RuntimeException("write failed")
        override fun clearSnapshot() = throw RuntimeException("clear failed")
    }

    private fun vm(
        store: WorkspacePersistenceStoring,
        alarmPlayer: TimerAlarmPlayer = FakeAlarmPlayer(),
        clock: () -> Instant,
    ): ShootingViewModel {
        var counter = 0
        return ShootingViewModel(
            store = store,
            clock = clock,
            idProvider = { UUID.fromString("00000000-0000-0000-0000-%012d".format(++counter)) },
            alarmPlayer = alarmPlayer,
        )
    }

    private val identity = TimerIdentity(title = "Camera 1 · No film", slotLabel = "C1")

    @Test
    fun startAddsRunningTimerToActiveAndPersists() {
        val store = FakeStore()
        val sut = vm(store) { t0 }
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity))
        val state = sut.uiState.value
        assertEquals(1, state.active.size)
        assertEquals(TimerStatus.running, state.active.first().status)
        assertEquals(100.0, state.active.first().remainingSeconds, 1e-9)
        assertNotNull(store.saved)
        assertTrue(sut.hasRunningTimers)
    }

    @Test
    fun pauseResumeCancelFlow() {
        val store = FakeStore()
        var nowSeconds = 0.0
        val sut = vm(store) { t0.plusSeconds(nowSeconds.toLong()) }
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity))
        val id = sut.uiState.value.active.first().id

        nowSeconds = 30.0
        sut.onEvent(ShootingIntent.Pause(id))
        assertEquals(TimerStatus.paused, sut.uiState.value.active.first().status)
        assertEquals(70.0, sut.uiState.value.active.first().remainingSeconds, 1e-6)

        nowSeconds = 1000.0
        sut.onEvent(ShootingIntent.Resume(id))
        assertEquals(TimerStatus.running, sut.uiState.value.active.first().status)
        // Resumed end recomputed from now → still ~70 s remaining.
        assertEquals(70.0, sut.uiState.value.active.first().remainingSeconds, 1e-6)

        sut.onEvent(ShootingIntent.Cancel(id))
        val history = sut.uiState.value.history
        assertEquals(1, history.size)
        assertEquals(TimerStatus.canceled, history.first().status)
        assertEquals(70.0, history.first().remainingAtCancelSeconds!!, 1e-6)
    }

    @Test
    fun tickAutoCompletesRunningTimer() {
        val store = FakeStore()
        var now = t0
        val sut = vm(store) { now }
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity))
        now = t0.plusSeconds(11)
        sut.tick(now)
        assertEquals(0, sut.uiState.value.active.size)
        assertEquals(TimerStatus.completed, sut.uiState.value.history.first().status)
    }

    @Test
    fun cloneFromRunningKeepsSourceRunning() {
        val store = FakeStore()
        val sut = vm(store) { t0 }
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity))
        val sourceId = sut.uiState.value.active.first().id

        sut.onEvent(ShootingIntent.Clone(sourceId))

        val state = sut.uiState.value
        // Source stays running; a fresh running clone is added (clone never cancels).
        assertEquals(2, state.active.size)
        assertTrue(state.active.all { it.status == TimerStatus.running })
        assertTrue(state.active.any { it.id == sourceId })
        assertEquals(0, state.history.size)
    }

    @Test
    fun cloneFromPausedKeepsSourcePaused() {
        val store = FakeStore()
        var nowSeconds = 0L
        val sut = vm(store) { t0.plusSeconds(nowSeconds) }
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity))
        val sourceId = sut.uiState.value.active.first().id
        nowSeconds = 30L
        sut.onEvent(ShootingIntent.Pause(sourceId))

        sut.onEvent(ShootingIntent.Clone(sourceId))

        val state = sut.uiState.value
        assertEquals(2, state.active.size)
        assertEquals(TimerStatus.paused, state.active.first { it.id == sourceId }.status)
        assertEquals(1, state.active.count { it.status == TimerStatus.running })
        assertEquals(0, state.history.size)
    }

    @Test
    fun cloneFromCompletedKeepsSourceAndStartsRunningClone() {
        val store = FakeStore()
        var now = t0
        val sut = vm(store) { now }
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity))
        now = t0.plusSeconds(11)
        sut.tick(now)
        val completedId = sut.uiState.value.history.first().id

        sut.onEvent(ShootingIntent.Clone(completedId))

        val state = sut.uiState.value
        assertEquals(1, state.active.size)
        assertEquals(TimerStatus.running, state.active.first().status)
        assertEquals(10.0, state.active.first().remainingSeconds, 1e-6)
        // Completed source preserved in history.
        assertEquals(1, state.history.size)
        assertEquals(completedId, state.history.first().id)
        assertEquals(TimerStatus.completed, state.history.first().status)
    }

    @Test
    fun cloneFromCanceledKeepsSourceCanceled() {
        val store = FakeStore()
        var nowSeconds = 0L
        val sut = vm(store) { t0.plusSeconds(nowSeconds) }
        sut.onEvent(ShootingIntent.StartTimer(50.0, identity))
        val id = sut.uiState.value.active.first().id
        nowSeconds = 10L
        sut.onEvent(ShootingIntent.Cancel(id))

        sut.onEvent(ShootingIntent.Clone(id))

        val state = sut.uiState.value
        assertEquals(1, state.active.size)
        assertEquals(TimerStatus.running, state.active.first().status)
        assertEquals(50.0, state.active.first().remainingSeconds, 1e-6)
        // Canceled source preserved in history.
        assertEquals(1, state.history.size)
        assertEquals(id, state.history.first().id)
        assertEquals(TimerStatus.canceled, state.history.first().status)
    }

    @Test
    fun clonePreservesShootingIdentity() {
        val store = FakeStore()
        val sut = vm(store) { t0 }
        val rich = TimerIdentity(
            title = "Camera 2 · Kodak Portra 400",
            subtitle = "Corrected Exposure",
            baseLine = "1/30 -> 2s",
            slotLabel = "C2",
        )
        sut.onEvent(ShootingIntent.StartTimer(45.0, rich))
        val sourceId = sut.uiState.value.active.first().id

        sut.onEvent(ShootingIntent.Clone(sourceId))

        val clone = sut.uiState.value.active.first { it.id != sourceId }
        assertEquals(rich, clone.identity)
    }

    @Test
    fun clearCompletedRemovesCompletedAndKeepsCanceled() {
        val store = FakeStore()
        var now = t0
        val sut = vm(store) { now }
        // First timer auto-completes.
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity))
        now = t0.plusSeconds(11)
        sut.tick(now)
        assertEquals(TimerStatus.completed, sut.uiState.value.history.first().status)
        // Second timer the user cancels.
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity))
        val canceledId = sut.uiState.value.active.first().id
        sut.onEvent(ShootingIntent.Cancel(canceledId))
        assertEquals(2, sut.uiState.value.history.size)

        sut.onEvent(ShootingIntent.ClearCompleted)

        // Completed removed; canceled preserved; not all history wiped.
        val history = sut.uiState.value.history
        assertEquals(1, history.size)
        assertEquals(canceledId, history.first().id)
        assertEquals(TimerStatus.canceled, history.first().status)
    }

    @Test
    fun removeDeletesFromHistory() {
        val store = FakeStore()
        var now = t0
        val sut = vm(store) { now }
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity))
        now = t0.plusSeconds(11); sut.tick(now)
        val id = sut.uiState.value.history.first().id
        sut.onEvent(ShootingIntent.Remove(id))
        assertEquals(0, sut.uiState.value.history.size)
    }

    @Test
    fun restoreWithFailingStoreFallsBackToEmptyAndStaysUsable() {
        val sut = vm(ThrowingStore()) { t0 }

        sut.restore() // read failure must not crash

        assertEquals(0, sut.uiState.value.active.size)
        assertEquals(0, sut.uiState.value.history.size)
        // Still usable: starting a timer works despite the failing write.
        sut.onEvent(ShootingIntent.StartTimer(100.0, identity))
        assertEquals(1, sut.uiState.value.active.size)
        assertEquals(TimerStatus.running, sut.uiState.value.active.first().status)
    }

    @Test
    fun restoreReloadsPersistedWorkspace() {
        val seed = FakeStore()
        val seeder = vm(seed) { t0 }
        seeder.onEvent(ShootingIntent.StartTimer(100.0, identity))
        val saved = seed.saved!!

        val store = FakeStore().apply { toLoad = saved }
        val sut = vm(store) { t0.plusSeconds(40) }
        sut.restore()
        assertEquals(1, sut.uiState.value.active.size)
        assertEquals(60.0, sut.uiState.value.active.first().remainingSeconds, 1e-6)
    }

    // PTIMER-73 in-app stop-alarm wiring.

    @Test
    fun soundingAlarmTimerIdReflectsThePlayerAndIsNullWhenSilent() {
        val alarm = FakeAlarmPlayer()
        val sut = vm(FakeStore(), alarmPlayer = alarm) { t0 }
        assertNull(sut.soundingAlarmTimerId.value)

        val id = UUID.randomUUID()
        alarm.simulateSounding(id)
        assertEquals(id, sut.soundingAlarmTimerId.value)
    }

    @Test
    fun stopAlarmStopsThePlayerAndClearsSoundingState() {
        val alarm = FakeAlarmPlayer()
        val sut = vm(FakeStore(), alarmPlayer = alarm) { t0 }
        alarm.simulateSounding(UUID.randomUUID())

        sut.stopAlarm()

        assertEquals(1, alarm.stopCount)
        assertNull(sut.soundingAlarmTimerId.value)
    }

    @Test
    fun stopAlarmDoesNotRemoveTheCompletedTimerOrChangeHistory() {
        val store = FakeStore()
        val alarm = FakeAlarmPlayer()
        var t = t0
        val sut = vm(store, alarmPlayer = alarm) { t }
        sut.onEvent(ShootingIntent.StartTimer(5.0, identity))
        val id = sut.uiState.value.active.first().id
        // Drive to completion so the timer is in history.
        t = t0.plusSeconds(6)
        sut.tick(t)
        alarm.simulateSounding(id)
        val historyBefore = sut.uiState.value.history

        sut.stopAlarm()

        // Sound stopped, but the completed timer/history is untouched.
        assertEquals(historyBefore, sut.uiState.value.history)
        assertTrue(sut.uiState.value.history.any { it.id == id })
    }
}
