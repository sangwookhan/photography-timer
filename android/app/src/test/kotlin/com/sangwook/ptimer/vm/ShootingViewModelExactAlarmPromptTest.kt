package com.sangwook.ptimer.vm

import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.timer.AlwaysExactAlarmAvailability
import com.sangwook.ptimer.timer.ExactAlarmAvailability
import com.sangwook.ptimer.timer.InMemoryTimerStore
import com.sangwook.ptimer.timer.NoOpTimerCompletionScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The exact-alarm notice appears only when a timer is running, exact alarms are
 * not permitted, and the user has not dismissed it — and never reappears after
 * dismissal. Driven with a fake availability (no Android).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingViewModelExactAlarmPromptTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private object ExactUnavailable : ExactAlarmAvailability {
        override fun canScheduleExact(): Boolean = false
    }

    private fun vm(exact: ExactAlarmAvailability) = ShootingViewModel(
        InMemoryTimerStore(), InMemoryTimerStore(), InMemoryTimerStore(),
        NoOpTimerNotifier, NoOpTimerCompletionScheduler, exact,
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
}
