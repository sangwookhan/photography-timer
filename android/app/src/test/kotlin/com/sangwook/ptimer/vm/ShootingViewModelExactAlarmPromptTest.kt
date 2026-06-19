package com.sangwook.ptimer.vm

import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot
import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.timer.AlwaysExactAlarmAvailability
import com.sangwook.ptimer.timer.ExactAlarmAvailability
import com.sangwook.ptimer.timer.InMemoryTimerStore
import com.sangwook.ptimer.timer.NoOpTimerCompletionScheduler
import com.sangwook.ptimer.timer.TimerCompletionScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The exact-alarm notice appears only when a timer is running, exact alarms are
 * not permitted, and the user has not dismissed it. The settings-return refresh
 * (refreshExactAlarmAvailability) re-checks availability, reschedules running
 * timers when it changes, and clears the notice on grant. Driven with fakes (no
 * Android).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingViewModelExactAlarmPromptTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private object ExactUnavailable : ExactAlarmAvailability {
        override fun canScheduleExact(): Boolean = false
    }

    /** Flippable availability to simulate granting/revoking in settings. */
    private class MutableExact(var available: Boolean) : ExactAlarmAvailability {
        override fun canScheduleExact(): Boolean = available
    }

    /** Records how many times each id was (re)scheduled and the net set. */
    private class CountingScheduler : TimerCompletionScheduler {
        val scheduleCountById = mutableMapOf<String, Int>()
        val current = mutableSetOf<String>()
        override fun schedule(snapshot: PersistentTimerSnapshot, title: String, subtitle: String) {
            scheduleCountById[snapshot.id] = (scheduleCountById[snapshot.id] ?: 0) + 1
            current += snapshot.id
        }
        override fun cancel(timerId: String) { current -= timerId }
        override fun cancelAll(timerIds: Collection<String>) = timerIds.forEach { cancel(it) }
    }

    private fun vm(exact: ExactAlarmAvailability, scheduler: TimerCompletionScheduler = NoOpTimerCompletionScheduler) =
        ShootingViewModel(
            InMemoryTimerStore(), InMemoryTimerStore(), InMemoryTimerStore(),
            NoOpTimerNotifier, scheduler, exact,
        ).also { dispatcher.scheduler.runCurrent() }

    private fun startLongTimer(model: ShootingViewModel) {
        model.onEvent(ShootingIntent.SetNdStops(10)) // ~34s → stays running
        model.onEvent(ShootingIntent.StartAdjusted)
    }

    @Test
    fun noPromptWhenNoRunningTimerEvenIfExactUnavailable() {
        val model = vm(ExactUnavailable)
        assertFalse(model.exactAlarmPrompt.value) // nothing running yet
    }

    @Test
    fun promptShownWhenRunningAndExactUnavailable() {
        val model = vm(ExactUnavailable)
        startLongTimer(model)
        assertTrue(model.exactAlarmPrompt.value)
    }

    @Test
    fun noPromptWhenExactIsAvailable() {
        val model = vm(AlwaysExactAlarmAvailability)
        startLongTimer(model)
        assertFalse(model.exactAlarmPrompt.value)
    }

    @Test
    fun dismissingPromptPreventsRepeatedNagging() {
        val model = vm(ExactUnavailable)
        startLongTimer(model)
        assertTrue(model.exactAlarmPrompt.value)
        model.onEvent(ShootingIntent.DismissExactAlarmPrompt)
        assertFalse(model.exactAlarmPrompt.value)
        // A later timer event must not bring the dismissed notice back.
        model.onEvent(ShootingIntent.StartAdjusted)
        assertFalse(model.exactAlarmPrompt.value)
    }

    // --- settings-return refresh ---------------------------------------------

    @Test
    fun grantingExactThenRefreshHidesPrompt() {
        val exact = MutableExact(false)
        val model = vm(exact)
        startLongTimer(model)
        assertTrue(model.exactAlarmPrompt.value)
        exact.available = true // user granted in settings
        model.refreshExactAlarmAvailability()
        assertFalse(model.exactAlarmPrompt.value)
    }

    @Test
    fun grantingExactThenRefreshReschedulesRunningTimer() {
        val exact = MutableExact(false)
        val sched = CountingScheduler()
        val model = vm(exact, sched)
        startLongTimer(model)
        val id = model.timerState.value.active.single().id
        assertEquals(1, sched.scheduleCountById[id]) // initial inexact schedule
        exact.available = true
        model.refreshExactAlarmAvailability()
        assertEquals(2, sched.scheduleCountById[id]) // rescheduled through current policy
    }

    @Test
    fun stillDeniedRefreshDoesNotReschedule() {
        val exact = MutableExact(false)
        val sched = CountingScheduler()
        val model = vm(exact, sched)
        startLongTimer(model)
        val id = model.timerState.value.active.single().id
        assertEquals(1, sched.scheduleCountById[id])
        model.refreshExactAlarmAvailability() // unchanged → no reschedule
        assertEquals(1, sched.scheduleCountById[id])
        assertTrue(model.exactAlarmPrompt.value) // still on inexact path, still prompting
    }

    @Test
    fun dismissedThenStillDeniedRefreshDoesNotRenag() {
        val exact = MutableExact(false)
        val model = vm(exact)
        startLongTimer(model)
        model.onEvent(ShootingIntent.DismissExactAlarmPrompt)
        assertFalse(model.exactAlarmPrompt.value)
        model.refreshExactAlarmAvailability() // still denied
        assertFalse(model.exactAlarmPrompt.value)
    }

    @Test
    fun dismissedThenGrantedKeepsPromptHiddenAndClearsSuppression() {
        val exact = MutableExact(false)
        val model = vm(exact)
        startLongTimer(model)
        model.onEvent(ShootingIntent.DismissExactAlarmPrompt)
        exact.available = true
        model.refreshExactAlarmAvailability()
        assertFalse(model.exactAlarmPrompt.value) // granted → hidden
        // Suppression cleared on grant: a later denial with a running timer can prompt again.
        exact.available = false
        model.refreshExactAlarmAvailability()
        assertTrue(model.exactAlarmPrompt.value)
    }

    @Test
    fun grantedThenDeniedRefreshFallsBackAndPromptCanAppear() {
        val exact = MutableExact(true)
        val sched = CountingScheduler()
        val model = vm(exact, sched)
        startLongTimer(model)
        val id = model.timerState.value.active.single().id
        assertFalse(model.exactAlarmPrompt.value) // granted → no prompt
        assertEquals(1, sched.scheduleCountById[id])
        exact.available = false // permission revoked
        model.refreshExactAlarmAvailability()
        assertEquals(2, sched.scheduleCountById[id]) // rescheduled (now inexact)
        assertTrue(model.exactAlarmPrompt.value)
    }
}
