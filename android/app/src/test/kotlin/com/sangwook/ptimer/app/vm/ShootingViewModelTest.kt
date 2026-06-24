package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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

    private fun vm(store: WorkspacePersistenceStoring, clock: () -> Instant): ShootingViewModel {
        var counter = 0
        return ShootingViewModel(
            store = store,
            clock = clock,
            idProvider = { UUID.fromString("00000000-0000-0000-0000-%012d".format(++counter)) },
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
    fun startAgainClonesFinishedTimer() {
        val store = FakeStore()
        var now = t0
        val sut = vm(store) { now }
        sut.onEvent(ShootingIntent.StartTimer(10.0, identity))
        now = t0.plusSeconds(11)
        sut.tick(now)
        val finishedId = sut.uiState.value.history.first().id
        sut.onEvent(ShootingIntent.StartAgain(finishedId))
        assertEquals(1, sut.uiState.value.active.size)
        assertEquals(TimerStatus.running, sut.uiState.value.active.first().status)
        assertEquals(10.0, sut.uiState.value.active.first().remainingSeconds, 1e-6)
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
}
