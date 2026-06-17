package com.sangwook.ptimer.vm

import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.timer.InMemoryTimerStore
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
 * Restore-ordering guard for [ShootingViewModel]. Restore runs on
 * viewModelScope; until it finishes, [ShootingViewModel.onEvent] must ignore
 * intents so an early user action cannot run against default state and then be
 * clobbered by restore. Driven on a [StandardTestDispatcher] installed as Main,
 * which queues the init coroutine so the pre-restore window is observable.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingViewModelRestoreOrderingTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    // Empty stores → restore makes no state change, so any state difference is
    // attributable to an intent (lets us prove the guard, not restore output).
    private fun newViewModel() = ShootingViewModel(
        timerStore = InMemoryTimerStore(),
        sessionStore = InMemoryTimerStore(),
        customStore = InMemoryTimerStore(),
        notifier = NoOpTimerNotifier,
    )

    @Test
    fun notReadyUntilRestoreCompletes() {
        val vm = newViewModel()
        assertFalse(vm.ready.value) // restore queued on Main, not yet run
        dispatcher.scheduler.advanceUntilIdle()
        assertTrue(vm.ready.value)
    }

    @Test
    fun intentBeforeRestoreCompletesIsIgnored() {
        val vm = newViewModel()
        vm.onEvent(ShootingIntent.SetNdStops(7)) // fired during restore
        dispatcher.scheduler.advanceUntilIdle()
        assertEquals(0, vm.calcState.value.ndStops) // ignored → still default, not 7
    }

    @Test
    fun intentAfterRestoreCompletesIsApplied() {
        val vm = newViewModel()
        dispatcher.scheduler.advanceUntilIdle()
        vm.onEvent(ShootingIntent.SetNdStops(7))
        assertEquals(7, vm.calcState.value.ndStops)
    }
}
