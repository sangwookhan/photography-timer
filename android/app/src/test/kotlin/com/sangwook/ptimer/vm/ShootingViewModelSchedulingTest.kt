package com.sangwook.ptimer.vm

import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.timer.InMemoryTimerStore
import com.sangwook.ptimer.timer.TimerCompletionScheduler
import com.sangwook.ptimer.timer.TimerSnapshotCodec
import com.sangwook.ptimer.timer.TimerStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * Background-completion scheduling coverage. The Android AlarmManager impl is
 * assemble-only (framework), so the app workflow is driven against a recording
 * [FakeScheduler] to prove the schedule/cancel contract. Same
 * StandardTestDispatcher + InMemoryTimerStore round-trip approach as the other
 * ViewModel tests (no Robolectric). Scheduling runs synchronously inside
 * `onEvent`, so live-event assertions need no dispatcher advance; restore-driven
 * scheduling is observed after `runCurrent()`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingViewModelSchedulingTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    /** Records calls and tracks the NET set of currently-scheduled ids. */
    private open class FakeScheduler : TimerCompletionScheduler {
        val scheduleCalls = mutableListOf<PersistentTimerSnapshot>()
        val titleById = mutableMapOf<String, String>()
        val subtitleById = mutableMapOf<String, String>()
        val current = linkedMapOf<String, PersistentTimerSnapshot>()
        override fun schedule(snapshot: PersistentTimerSnapshot, title: String, subtitle: String) {
            scheduleCalls += snapshot; titleById[snapshot.id] = title
            subtitleById[snapshot.id] = subtitle; current[snapshot.id] = snapshot
        }
        override fun cancel(timerId: String) { current.remove(timerId) }
        override fun cancelAll(timerIds: Collection<String>) = timerIds.forEach { cancel(it) }
    }

    private class ThrowingScheduler : FakeScheduler() {
        override fun schedule(snapshot: PersistentTimerSnapshot, title: String, subtitle: String): Unit =
            throw RuntimeException("scheduler boom")
    }

    private fun vm(
        scheduler: TimerCompletionScheduler,
        timerStore: TimerStore = InMemoryTimerStore(),
        sessionStore: TimerStore = InMemoryTimerStore(),
        customStore: TimerStore = InMemoryTimerStore(),
    ): ShootingViewModel {
        val model = ShootingViewModel(timerStore, sessionStore, customStore, NoOpTimerNotifier, scheduler)
        dispatcher.scheduler.runCurrent() // finish restore; park any tick loop
        return model
    }

    private fun longTimerVm(scheduler: TimerCompletionScheduler): ShootingViewModel {
        val model = vm(scheduler)
        model.onEvent(ShootingIntent.SetNdStops(10)) // ~34s adjusted → stays running
        return model
    }

    // 1 — start schedules completion
    @Test
    fun startSchedulesCompletion() {
        val s = FakeScheduler()
        val model = longTimerVm(s)
        model.onEvent(ShootingIntent.StartAdjusted)
        val id = model.timerState.value.active.single().id
        assertTrue(s.current.containsKey(id))
        assertNotNull(s.current[id]!!.expectedCompletionAt) // alarm time present
    }

    // 2 — pause cancels schedule
    @Test
    fun pauseCancelsSchedule() {
        val s = FakeScheduler()
        val model = longTimerVm(s)
        model.onEvent(ShootingIntent.StartAdjusted)
        val id = model.timerState.value.active.single().id
        model.onEvent(ShootingIntent.Pause(id))
        assertFalse(s.current.containsKey(id))
    }

    // 3 — resume reschedules completion
    @Test
    fun resumeReschedulesCompletion() {
        val s = FakeScheduler()
        val model = longTimerVm(s)
        model.onEvent(ShootingIntent.StartAdjusted)
        val id = model.timerState.value.active.single().id
        model.onEvent(ShootingIntent.Pause(id))
        model.onEvent(ShootingIntent.Resume(id))
        assertTrue(s.current.containsKey(id)) // scheduled again after resume
    }

    // 4 — remove cancels schedule
    @Test
    fun removeCancelsSchedule() {
        val s = FakeScheduler()
        val model = longTimerVm(s)
        model.onEvent(ShootingIntent.StartAdjusted)
        val id = model.timerState.value.active.single().id
        model.onEvent(ShootingIntent.Remove(id))
        assertFalse(s.current.containsKey(id))
    }

    // 5 — completed timer does not remain scheduled (restored completed → not scheduled)
    @Test
    fun completedTimerIsNotScheduled() {
        val past = Instant.parse("2026-06-01T00:00:00Z")
        val json = TimerSnapshotCodec.encode(
            listOf(TimerState.Completed("timer-0", 30.0, past, past.plusSeconds(30))),
            mapOf("timer-0" to "Camera 1 · X"), mapOf("timer-0" to "sub"),
            mapOf("timer-0" to "meta"), mapOf("timer-0" to ExposureTimerSource.DIGITAL_RESULT),
        )
        val s = FakeScheduler()
        val model = vm(s, timerStore = InMemoryTimerStore(json))
        assertTrue("completed timer must not be scheduled", s.current.isEmpty())
        assertEquals(1, model.timerState.value.completed.size)
    }

    // 6 — Start again creates a fresh schedule with a fresh id
    @Test
    fun startAgainSchedulesFreshIdNotTheCompletedOne() {
        val past = Instant.parse("2026-06-01T00:00:00Z")
        val json = TimerSnapshotCodec.encode(
            listOf(TimerState.Completed("timer-0", 30.0, past, past.plusSeconds(30))),
            mapOf("timer-0" to "Camera 1 · X"), mapOf("timer-0" to "sub"),
            mapOf("timer-0" to "meta"), mapOf("timer-0" to ExposureTimerSource.FILM_CORRECTED_EXPOSURE),
        )
        val s = FakeScheduler()
        val model = vm(s, timerStore = InMemoryTimerStore(json))
        model.onEvent(ShootingIntent.StartAgain("timer-0"))
        val newId = model.timerState.value.active.single().id
        assertTrue(newId != "timer-0")
        assertEquals(setOf(newId), s.current.keys) // only the fresh id is scheduled
    }

    // 7 — restore of a pending (future) running timer schedules completion
    @Test
    fun restorePendingRunningTimerSchedulesCompletion() {
        val now = System.currentTimeMillis()
        val json = """{"schemaVersion":1,"timers":[{"id":"timer-5","title":"Cam · X","subtitle":"s","metadata":"m","source":"DIGITAL_RESULT","status":"running","durationSeconds":3600.0,"startEpochMs":${now - 1000},"expectedCompletionEpochMs":${now + 3_600_000}}]}"""
        val s = FakeScheduler()
        val model = vm(s, timerStore = InMemoryTimerStore(json))
        assertTrue(s.current.containsKey("timer-5"))
        assertEquals(TimerState.running("x", 1.0, Instant.now()).status, model.timerState.value.active.singleOrNull()?.status)
    }

    // 8 — restore of an overdue running timer reconciles completed (and is not scheduled)
    @Test
    fun restoreOverdueRunningTimerReconcilesCompletedAndIsNotScheduled() {
        val now = System.currentTimeMillis()
        val json = """{"schemaVersion":1,"timers":[{"id":"timer-7","title":"Cam · X","subtitle":"s","metadata":"m","source":"DIGITAL_RESULT","status":"running","durationSeconds":30.0,"startEpochMs":${now - 3_600_000},"expectedCompletionEpochMs":${now - 1000}}]}"""
        val s = FakeScheduler()
        val model = vm(s, timerStore = InMemoryTimerStore(json))
        assertFalse(s.current.containsKey("timer-7"))                 // overdue → not scheduled
        assertEquals(1, model.timerState.value.completed.size)        // reconciled to completed
        assertTrue(model.timerState.value.active.isEmpty())           // no phantom active timer
    }

    // 9 — scheduling identity is immutable across a later slot rename
    @Test
    fun scheduledIdentityIsImmutableAcrossSlotRename() {
        val s = FakeScheduler()
        val model = longTimerVm(s)
        model.onEvent(ShootingIntent.StartAdjusted)
        val id = model.timerState.value.active.single().id
        val titleAtStart = s.titleById[id]
        assertNotNull(titleAtStart)
        model.onEvent(ShootingIntent.RenameSlot("camera1", "Renamed Body"))
        assertEquals(titleAtStart, s.titleById[id]) // schedule keeps the start-time identity
    }

    // 10 — custom-film corrected timer schedules with the custom-film identity
    @Test
    fun customFilmCorrectedTimerSchedulesWithCustomIdentity() {
        val s = FakeScheduler()
        val model = vm(s)
        model.onEvent(ShootingIntent.CreateCustomFormula("Acme 100", exponent = 1.3, noCorrectionThroughSeconds = 1.0))
        model.onEvent(ShootingIntent.SetNdStops(8)) // corrected quantified and long enough to stay running
        model.onEvent(ShootingIntent.StartCorrected)
        val active = model.timerState.value.active.single()
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, active.source)
        assertTrue(s.current.containsKey(active.id))
        assertTrue(s.titleById[active.id]!!.contains("Acme 100"))            // primary identity
        // Source/subtitle line is captured into the scheduled completion, so the
        // alarm receiver can display it and corrected-source identity is not lost.
        assertTrue(s.subtitleById[active.id]!!.contains("Corrected Exposure"))
    }

    // 11 — scheduler failure does not crash the workflow
    @Test
    fun schedulerFailureDoesNotCrashWorkflow() {
        val model = longTimerVm(ThrowingScheduler())
        model.onEvent(ShootingIntent.StartAdjusted) // would throw if syncSchedules did not swallow
        assertTrue(model.timerState.value.active.isNotEmpty()) // timer still started
    }

    // 12 — no duplicate schedule for the same timer after restore round-trip
    @Test
    fun noDuplicateScheduleAfterRestoreRoundTrip() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val first = vm(FakeScheduler(), ts, ss, cs)
        first.onEvent(ShootingIntent.SetNdStops(10))
        first.onEvent(ShootingIntent.StartAdjusted)
        val id = first.timerState.value.active.single().id
        dispatcher.scheduler.runCurrent() // flush persistence

        val s2 = FakeScheduler()
        val second = vm(s2, ts, ss, cs) // relaunch
        assertEquals(setOf(id), s2.current.keys)       // exactly one schedule, no duplicate
        assertEquals(1, s2.scheduleCalls.count { it.id == id })
    }
}
