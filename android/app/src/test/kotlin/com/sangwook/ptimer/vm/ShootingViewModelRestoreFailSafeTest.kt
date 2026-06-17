package com.sangwook.ptimer.vm

import com.sangwook.ptimer.calculator.SlotCalculatorSnapshot
import com.sangwook.ptimer.customfilm.CustomFilmFactory
import com.sangwook.ptimer.customfilm.CustomFilmLibraryCodec
import com.sangwook.ptimer.customfilm.CustomFilmResult
import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.slots.CameraSlotSession
import com.sangwook.ptimer.slots.SlotSessionCodec
import com.sangwook.ptimer.timer.InMemoryTimerStore
import com.sangwook.ptimer.timer.TimerStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * A throwing/failing store load must never leave [ShootingViewModel]
 * permanently not-ready. Each store loads independently with a documented
 * fallback and `ready` is set in `finally`. Driven on a
 * [StandardTestDispatcher] installed as Main (no Robolectric).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingViewModelRestoreFailSafeTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private class ThrowingStore : TimerStore {
        override suspend fun load(): String? = throw RuntimeException("load boom")
        override suspend fun save(json: String) {}
        override suspend fun clear() {}
    }

    private fun vm(
        timerStore: TimerStore = InMemoryTimerStore(),
        sessionStore: TimerStore = InMemoryTimerStore(),
        customStore: TimerStore = InMemoryTimerStore(),
    ) = ShootingViewModel(timerStore, sessionStore, customStore, NoOpTimerNotifier)

    /** A session snapshot for camera1 that selects [filmId]. */
    private fun sessionJsonSelecting(filmId: String): String {
        val session = CameraSlotSession()
        session.store("camera1", SlotCalculatorSnapshot(1.0, 0, filmId, null, null))
        return SlotSessionCodec.encode(session)
    }

    private fun assertUsable(model: ShootingViewModel) {
        model.onEvent(ShootingIntent.StartAdjusted) // default base/ND → a valid timer
        assertTrue("app should remain usable after restore", model.timerState.value.active.isNotEmpty())
    }

    @Test
    fun timerStoreLoadFailureStillBecomesReadyAndUsable() {
        val model = vm(timerStore = ThrowingStore())
        dispatcher.scheduler.advanceUntilIdle()
        assertTrue(model.ready.value)          // failure did not strand restore
        assertTrue(model.timerState.value.active.isEmpty()) // no restored timers
        assertUsable(model)                    // starting a timer still works
    }

    @Test
    fun customStoreLoadFailureDefaultsEmptyAndSessionRefToMissingFilmFallsBack() {
        val model = vm(
            sessionStore = InMemoryTimerStore(sessionJsonSelecting("custom-ghost")),
            customStore = ThrowingStore(),
        )
        dispatcher.scheduler.advanceUntilIdle()
        assertTrue(model.ready.value)
        // Custom library defaulted empty → only preset films present.
        assertTrue(model.films.value.none { it.isCustom })
        // Session referenced a now-missing custom film → sanitized to digital.
        assertNull(model.calcState.value.filmName)
    }

    @Test
    fun sessionStoreLoadFailureUsesDefaultSlotState() {
        val model = vm(sessionStore = ThrowingStore())
        dispatcher.scheduler.advanceUntilIdle()
        assertTrue(model.ready.value)
        assertEquals("Camera 1", model.slotsState.value.activeLabel) // default slot
        assertNull(model.calcState.value.filmName)
        assertUsable(model)
    }

    @Test
    fun multipleStoreFailuresStillReadyWithDefaults() {
        val model = vm(
            timerStore = ThrowingStore(),
            sessionStore = ThrowingStore(),
            customStore = ThrowingStore(),
        )
        dispatcher.scheduler.advanceUntilIdle()
        assertTrue(model.ready.value)
        assertEquals("Camera 1", model.slotsState.value.activeLabel)
        assertUsable(model)
    }

    @Test
    fun customFilmsLoadBeforeSessionApplicationSoAValidCustomFilmResolves() {
        val film = (CustomFilmFactory.buildFormula(
            "custom-formula-0", "My Film", 100, exponent = 1.3, noCorrectionThroughSeconds = 1.0,
        ) as CustomFilmResult.Success).film
        val model = vm(
            sessionStore = InMemoryTimerStore(sessionJsonSelecting("custom-formula-0")),
            customStore = InMemoryTimerStore(CustomFilmLibraryCodec.encode(listOf(film))),
        )
        dispatcher.scheduler.advanceUntilIdle()
        assertTrue(model.ready.value)
        // Custom library loaded before the session was applied, so the
        // session's custom-film reference resolved instead of falling back.
        assertEquals(film.canonicalStockName, model.calcState.value.filmName)
    }
}
