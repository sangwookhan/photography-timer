// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import com.sangwook.ptimer.app.notify.TimerAlarmPlayer
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.persistence.ScopePersistenceWriter
import com.sangwook.ptimer.core.customfilm.CustomFilmLibrary
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.SlotSessionStoring
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.util.UUID

/**
 * Lifecycle-boundary tests for [ShootingAppViewModel] (PTIMER-223): the
 * one-shot timer restore, the debounced calculator persistence collector, the
 * tick loop, and the clear-time flush — all owned by `viewModelScope` rather
 * than the composition. Runs on the JVM: the main dispatcher is swapped for a
 * test dispatcher, and virtual time drives the debounce window and tick loop.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingAppViewModelTest {

    private val t0: Instant = Instant.parse("2026-07-18T00:00:00Z")

    private val scheduler = TestCoroutineScheduler()
    private val dispatcher = StandardTestDispatcher(scheduler)

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private class FakeWorkspaceStore : WorkspacePersistenceStoring {
        var toLoad: PersistentWorkspaceSnapshot? = null
        var loadCount = 0
            private set
        var saved: PersistentWorkspaceSnapshot? = null

        override fun loadSnapshot(): PersistentWorkspaceSnapshot? {
            loadCount++
            return toLoad
        }

        override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) { saved = snapshot }
        override fun clearSnapshot() { saved = null }
    }

    private class FakeSlotStore : SlotSessionStoring {
        val saved = mutableListOf<PersistentSlotSession>()
        override fun loadSession(): PersistentSlotSession? = null
        override fun saveSession(session: PersistentSlotSession) { saved += session }
        override fun clearSession() {}
    }

    /** In-memory alarm player; no Context, no real playback. */
    private class FakeAlarmPlayer : TimerAlarmPlayer {
        private val _soundingTimerId = MutableStateFlow<UUID?>(null)
        override val soundingTimerId: StateFlow<UUID?> = _soundingTimerId.asStateFlow()
        override fun playAlarm(timerId: UUID) { _soundingTimerId.value = timerId }
        override fun stop() { _soundingTimerId.value = null }
    }

    private val identity = TimerIdentity(title = "Camera 1 · No film", slotLabel = "C1")

    private fun holder(
        timerStore: WorkspacePersistenceStoring = FakeWorkspaceStore(),
        slotStore: SlotSessionStoring = FakeSlotStore(),
        initialSession: PersistentSlotSession? = null,
        completionNotifier: TimerCompletionNotifier = TimerCompletionNotifier {},
        clock: () -> Instant = { t0 },
    ): ShootingAppViewModel = ShootingAppViewModel(
        films = emptyList(),
        library = CustomFilmLibrary(),
        initialSession = initialSession,
        timerStore = timerStore,
        alarmPlayer = FakeAlarmPlayer(),
        slotStore = slotStore,
        completionNotifier = completionNotifier,
        clock = clock,
        // Shares the test scheduler so ordered reads and submitted writes run
        // under virtual time and the tests can assert exact debounce timing.
        persistence = ScopePersistenceWriter(dispatcher),
    )

    /** A persisted workspace snapshot holding one running 100 s timer started at [t0]. */
    private fun seededWorkspaceSnapshot(): PersistentWorkspaceSnapshot {
        val seed = FakeWorkspaceStore()
        val seeder = ShootingViewModel(
            store = seed,
            clock = { t0 },
            alarmPlayer = FakeAlarmPlayer(),
            persistenceWriter = PersistenceWriter { it() },
        )
        seeder.onEvent(ShootingIntent.StartTimer(100.0, identity))
        return seed.saved!!
    }

    @Test
    fun initRestoresPersistedTimersExactlyOnce() {
        val store = FakeWorkspaceStore().apply { toLoad = seededWorkspaceSnapshot() }
        val sut = holder(timerStore = store, clock = { t0.plusSeconds(40) })

        // runCurrent, not advanceUntilIdle: the restored timer is running, so
        // the tick loop would keep rescheduling forever under a fixed clock.
        scheduler.runCurrent()

        assertEquals(1, sut.timers.uiState.value.active.size)
        assertEquals(60.0, sut.timers.uiState.value.active.first().remainingSeconds, 1e-6)
        // One read per ViewModel lifetime: a recreation reuses the retained
        // instance, so no further composition-driven read can happen.
        assertEquals(1, store.loadCount)
    }

    @Test
    fun calculatorChangePersistsOnlyAfterTheDebounceWindow() {
        val slotStore = FakeSlotStore()
        val sut = holder(slotStore = slotStore)
        scheduler.advanceUntilIdle()

        sut.calculator.setShutterIndex(5)
        scheduler.advanceTimeBy(399)
        scheduler.runCurrent()
        assertEquals(0, slotStore.saved.size)

        scheduler.advanceTimeBy(1)
        scheduler.advanceUntilIdle()
        assertEquals(1, slotStore.saved.size)
        assertEquals(5, slotStore.saved.single().snapshots[CameraSlotId.camera1]?.shutterIndex)
    }

    @Test
    fun rapidCalculatorChangesCoalesceIntoOneLatestWrite() {
        val slotStore = FakeSlotStore()
        val sut = holder(slotStore = slotStore)
        scheduler.advanceUntilIdle()

        sut.calculator.setShutterIndex(3)
        scheduler.advanceTimeBy(200)
        sut.calculator.setShutterIndex(7)
        scheduler.advanceTimeBy(400)
        scheduler.advanceUntilIdle()

        assertEquals(1, slotStore.saved.size)
        assertEquals(7, slotStore.saved.single().snapshots[CameraSlotId.camera1]?.shutterIndex)
    }

    @Test
    fun freshLaunchWithoutCalculatorChangesWritesNoSlotSession() {
        val slotStore = FakeSlotStore()
        holder(slotStore = slotStore)
        scheduler.advanceUntilIdle()
        scheduler.advanceTimeBy(1_000)
        scheduler.advanceUntilIdle()

        assertEquals(0, slotStore.saved.size)
    }

    @Test
    fun tickLoopAdvancesAndAutoCompletesRunningTimers() {
        var now = t0
        val sut = holder(clock = { now })
        scheduler.advanceUntilIdle()

        sut.timers.onEvent(ShootingIntent.StartTimer(10.0, identity))
        scheduler.runCurrent()
        assertTrue(sut.timers.hasRunningTimers)

        now = t0.plusSeconds(1)
        scheduler.advanceTimeBy(1_000)
        assertEquals(9.0, sut.timers.uiState.value.active.first().remainingSeconds, 1e-6)

        now = t0.plusSeconds(11)
        scheduler.advanceTimeBy(10_000)
        scheduler.advanceUntilIdle()
        assertEquals(0, sut.timers.uiState.value.active.size)
        assertEquals(TimerStatus.completed, sut.timers.uiState.value.history.first().status)
        assertTrue(!sut.timers.hasRunningTimers)
    }

    @Test
    fun completionWhileNoUiIsAttachedNotifiesExactlyOnce() {
        // JVM tests have no composition at all, so this exercises exactly the
        // reviewed gap: the tick loop completes a timer while no UI collector
        // exists (mid-recreation), and the owner-scoped transition tracking
        // must still deliver the alert — once.
        var now = t0
        val notified = mutableListOf<UUID>()
        val sut = holder(
            completionNotifier = { card -> notified += card.id },
            clock = { now },
        )
        scheduler.advanceUntilIdle()

        sut.timers.onEvent(ShootingIntent.StartTimer(5.0, identity))
        scheduler.runCurrent()

        now = t0.plusSeconds(6)
        scheduler.advanceTimeBy(6_000)
        scheduler.advanceUntilIdle()
        assertEquals(1, notified.size)

        // Later state emissions in which the completed entry is still present
        // in history (here: a second timer starting) must not re-notify it.
        val completedId = sut.timers.uiState.value.history.single().id
        sut.timers.onEvent(ShootingIntent.StartTimer(100.0, identity))
        scheduler.runCurrent()
        assertEquals(TimerStatus.completed, sut.timers.uiState.value.history.single().status)
        assertEquals(listOf(completedId), notified)
    }

    @Test
    fun notifierFailureDoesNotKillTheCollectorAndRetriesOnTheNextEmission() {
        // The notifier shares a collector with the tick-loop control, so a
        // throwing notification path must not terminate it. Retry policy: a
        // failed id is not marked notified and is retried on the next state
        // emission.
        var now = t0
        var failNext = true
        val notified = mutableListOf<UUID>()
        val sut = holder(
            completionNotifier = { card ->
                if (failNext) {
                    failNext = false
                    throw RuntimeException("notification path failed")
                }
                notified += card.id
            },
            clock = { now },
        )
        scheduler.advanceUntilIdle()

        sut.timers.onEvent(ShootingIntent.StartTimer(5.0, identity))
        scheduler.runCurrent()
        now = t0.plusSeconds(6)
        scheduler.advanceTimeBy(6_000)
        scheduler.advanceUntilIdle()
        // The delivery attempt threw; the failed id was not marked notified.
        assertEquals(0, notified.size)

        // The collector is still alive: starting a second timer produces the
        // next emission, which retries the failed id, and the tick loop keeps
        // being driven — the second timer still auto-completes and notifies.
        sut.timers.onEvent(ShootingIntent.StartTimer(5.0, identity))
        scheduler.runCurrent()
        assertEquals(1, notified.size)
        assertTrue(sut.timers.hasRunningTimers)

        now = t0.plusSeconds(12)
        scheduler.advanceTimeBy(6_000)
        scheduler.advanceUntilIdle()
        assertEquals(2, notified.size)
        assertEquals(0, sut.timers.uiState.value.active.size)
    }

    @Test
    fun restoredCompletedTimersDoNotNotifyOnLaunch() {
        // Contract: completed history entries restored into a new owner are
        // not retroactively re-notified solely because they were restored —
        // this owner never saw them running.
        var now = t0
        val seed = FakeWorkspaceStore()
        val seeder = ShootingViewModel(
            store = seed,
            clock = { now },
            alarmPlayer = FakeAlarmPlayer(),
            persistenceWriter = PersistenceWriter { it() },
        )
        seeder.onEvent(ShootingIntent.StartTimer(5.0, identity))
        now = t0.plusSeconds(6)
        seeder.tick(now)
        val snapshotWithCompleted = seed.saved!!

        val notified = mutableListOf<UUID>()
        val store = FakeWorkspaceStore().apply { toLoad = snapshotWithCompleted }
        holder(
            timerStore = store,
            completionNotifier = { card -> notified += card.id },
            clock = { now },
        )
        scheduler.advanceUntilIdle()
        assertEquals(0, notified.size)
    }

    @Test
    fun secondActivityGenerationReceivesTheRetainedOwnerAndSlotState() {
        val slotStore = FakeSlotStore()
        val timerStore = FakeWorkspaceStore()
        val vmStore = ViewModelStore()
        var built = 0
        val factory = object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                built++
                @Suppress("UNCHECKED_CAST")
                return holder(timerStore = timerStore, slotStore = slotStore) as T
            }
        }

        // First Activity generation: distinct state on both camera slots,
        // Camera 2 active, and a change still inside the debounce window
        // when the recreation happens.
        val gen1 = ViewModelProvider(vmStore, factory)[ShootingAppViewModel::class.java]
        scheduler.advanceUntilIdle()
        gen1.calculator.setShutterIndex(3)
        gen1.calculator.selectSlot(CameraSlotId.camera2)
        gen1.calculator.setShutterIndex(9)

        // Second generation (Activity recreation): the same ViewModelStore
        // must hand back the same owner, factory untouched.
        val gen2 = ViewModelProvider(vmStore, factory)[ShootingAppViewModel::class.java]
        assertSame(gen1, gen2)
        assertEquals(1, built)

        val session = gen2.calculator.exportSession()
        assertEquals(CameraSlotId.camera2, session.activeSlotId)
        assertEquals(3, session.snapshots[CameraSlotId.camera1]?.shutterIndex)
        assertEquals(9, session.snapshots[CameraSlotId.camera2]?.shutterIndex)
        // Retention did not depend on a persistence round trip: one workspace
        // read for the whole owner lifetime, across both generations.
        assertEquals(1, timerStore.loadCount)

        // The debounce window that was open across the generation swap still
        // closes with the latest committed state.
        scheduler.advanceTimeBy(400)
        scheduler.advanceUntilIdle()
        assertEquals(CameraSlotId.camera2, slotStore.saved.last().activeSlotId)
        assertEquals(9, slotStore.saved.last().snapshots[CameraSlotId.camera2]?.shutterIndex)

        vmStore.clear()
    }

    @Test
    fun aNewOwnerRestoresFromTheHandedPersistedSessionOnly() {
        // Scope: this verifies the owner-level boundary — a brand-new owner
        // reconstructs calculator state from a persisted session snapshot and
        // shares nothing with the previous owner's memory. It does NOT
        // exercise the bootstrap/DataStore read path itself (that is the
        // stores' own test territory plus the manual relaunch procedure).
        val slotStore = FakeSlotStore()
        val first = holder(slotStore = slotStore)
        scheduler.advanceUntilIdle()
        first.calculator.selectSlot(CameraSlotId.camera2)
        first.calculator.setShutterIndex(9)
        scheduler.advanceTimeBy(400)
        scheduler.advanceUntilIdle()
        val durable = slotStore.saved.last()

        val second = holder(initialSession = durable)
        scheduler.advanceUntilIdle()
        val restored = second.calculator.exportSession()
        assertEquals(CameraSlotId.camera2, restored.activeSlotId)
        assertEquals(9, restored.snapshots[CameraSlotId.camera2]?.shutterIndex)
    }

    @Test
    fun nearExpiryRestoredTimerStillNotifiesOnItsFirstTickCompletion() {
        // Pins the exact ordering boundary: restore publishes a RUNNING timer
        // (the clock is pre-expiry while the owner constructs and restores),
        // and the coordinator's very first immediate tick already sees a
        // post-expiry clock and completes it — all within one runCurrent().
        // The single ordered collector records the running id before it
        // starts the tick loop, so the completion still notifies, exactly
        // once. With two independent collectors this ordering would be
        // unspecified and the alert could be skipped.
        //
        // Clock call sites, in order: (1) ShootingViewModel construction,
        // (2) restore reconciliation, (3+) coordinator ticks. Calls 1–2 are
        // pre-expiry, calls 3+ post-expiry.
        var clockCalls = 0
        val clock = {
            clockCalls++
            if (clockCalls <= 2) t0.plusMillis(99_900) else t0.plusMillis(100_100)
        }
        val notified = mutableListOf<UUID>()
        val store = FakeWorkspaceStore().apply { toLoad = seededWorkspaceSnapshot() }
        val sut = holder(
            timerStore = store,
            completionNotifier = { card -> notified += card.id },
            clock = clock,
        )

        scheduler.runCurrent()

        assertEquals(0, sut.timers.uiState.value.active.size)
        assertEquals(TimerStatus.completed, sut.timers.uiState.value.history.single().status)
        assertEquals(1, notified.size)
    }

    @Test
    fun clearingTheOwnerFlushesAPendingDebouncedSlotSessionWrite() {
        val slotStore = FakeSlotStore()
        val sut = holder(slotStore = slotStore)
        scheduler.advanceUntilIdle()

        // Change committed, then the owner is cleared inside the debounce
        // window (Activity finish) — the pending state must still land.
        sut.calculator.setShutterIndex(9)
        val store = ViewModelStore()
        store.put("holder", sut)
        store.clear()
        scheduler.advanceUntilIdle()

        assertEquals(9, slotStore.saved.last().snapshots[CameraSlotId.camera1]?.shutterIndex)
    }
}
