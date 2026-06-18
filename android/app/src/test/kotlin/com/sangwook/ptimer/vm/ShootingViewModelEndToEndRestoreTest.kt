package com.sangwook.ptimer.vm

import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.timer.InMemoryTimerStore
import com.sangwook.ptimer.timer.TimerSnapshotCodec
import com.sangwook.ptimer.timer.TimerStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * App-level (ViewModel ↔ stores ↔ codecs ↔ controllers) restore verification.
 * The DataStore-backed stores are stood in by [InMemoryTimerStore]; the SAME
 * store instances are shared between a "before relaunch" ViewModel and an
 * "after relaunch" one, so persisted JSON round-trips through the real save /
 * load / decode / apply path. Driven on a [StandardTestDispatcher] installed as
 * Main; `runCurrent()` completes the restore coroutine and flushes the async
 * save coroutines WITHOUT advancing virtual time (so a running timer's tick
 * loop parks at its first delay instead of spinning against the wall clock).
 * No Robolectric.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShootingViewModelEndToEndRestoreTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun launch(ts: TimerStore, ss: TimerStore, cs: TimerStore): ShootingViewModel {
        val vm = ShootingViewModel(ts, ss, cs, NoOpTimerNotifier)
        dispatcher.scheduler.runCurrent() // complete restore; park any tick loop
        return vm
    }

    private fun settle() = dispatcher.scheduler.runCurrent() // flush async store saves

    // 1 — Active timer restore -------------------------------------------------

    @Test
    fun activeTimerRestoresUsableAndNewTimerDoesNotCollide() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.SetNdStops(10)) // long adjusted (~34s) → still running after restore
        vm1.onEvent(ShootingIntent.StartAdjusted)
        settle()
        val started = vm1.timerState.value.active.single()

        val vm2 = launch(ts, ss, cs)
        val restored = vm2.timerState.value.active.single()
        assertEquals(started.id, restored.id)
        assertEquals(started.title, restored.title)        // "Camera 1 · Digital"
        assertEquals(started.subtitle, restored.subtitle)  // source-identity subtitle survives
        assertEquals(ExposureTimerSource.DIGITAL_RESULT, restored.source)
        assertTrue(restored.remainingSeconds > 0.0)        // countdown usable after restore

        vm2.onEvent(ShootingIntent.StartAdjusted) // new timer must not collide with the restored id
        val ids = vm2.timerState.value.active.map { it.id }.toSet()
        assertEquals(2, ids.size)
        assertTrue(ids.contains(restored.id))
    }

    // 2 — Completed/history restore -------------------------------------------

    @Test
    fun completedTimerRestoresAndSupportsStartAgainAndRemove() {
        val past = Instant.parse("2026-06-01T00:00:00Z")
        val json = TimerSnapshotCodec.encode(
            listOf(TimerState.Completed("timer-0", 30.0, past, past.plusSeconds(30))),
            titles = mapOf("timer-0" to "Camera 1 · Velvia 50"),
            subtitles = mapOf("timer-0" to "Corrected Exposure · Velvia 50 · 00:30"),
            metadatas = mapOf("timer-0" to "Base 1s · ND 0 · Adjusted 1s"),
            sources = mapOf("timer-0" to ExposureTimerSource.FILM_CORRECTED_EXPOSURE),
        )
        val ts = InMemoryTimerStore(json)
        val vm = launch(ts, InMemoryTimerStore(), InMemoryTimerStore())

        val done = vm.timerState.value.completed.single()
        assertEquals("timer-0", done.id)
        assertEquals("Camera 1 · Velvia 50", done.title)              // identity survives
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, done.source)

        vm.onEvent(ShootingIntent.StartAgain("timer-0")) // Start again works after restore
        val clone = vm.timerState.value.active.single()
        assertEquals("Camera 1 · Velvia 50", clone.title)            // identity carried into clone
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, clone.source)
        assertTrue(clone.id != "timer-0")                            // fresh id, no collision

        vm.onEvent(ShootingIntent.Remove("timer-0")) // Remove works after restore
        assertTrue(vm.timerState.value.completed.none { it.id == "timer-0" })
    }

    // 3 — Slot / session restore ----------------------------------------------

    @Test
    fun slotSessionSelectionsRestore() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.SelectSlot("camera2"))
        vm1.onEvent(ShootingIntent.RenameSlot("camera2", "  Hasselblad  ")) // sanitation: trim
        vm1.onEvent(ShootingIntent.SetNdStops(5))
        vm1.onEvent(ShootingIntent.NudgeBaseShutter(2))
        vm1.onEvent(ShootingIntent.SelectFilm("kodak-tri-x-400"))
        vm1.onEvent(ShootingIntent.SelectModel("kodak-tri-x-official-table")) // a known alternate
        vm1.onEvent(ShootingIntent.SetTarget(60.0))
        settle()
        val baseLabel1 = vm1.calcState.value.baseShutterLabel
        val filmName1 = vm1.calcState.value.filmName

        val vm2 = launch(ts, ss, cs)
        assertEquals("camera2", vm2.slotsState.value.slots.first { it.isActive }.id) // selected slot
        assertEquals("Hasselblad", vm2.slotsState.value.activeLabel)                  // name trimmed + restored
        assertEquals(5, vm2.calcState.value.ndStops)                                  // ND restored
        assertEquals(baseLabel1, vm2.calcState.value.baseShutterLabel)                // base restored
        assertNotNull(filmName1)
        assertEquals(filmName1, vm2.calcState.value.filmName)                         // film restored
        val model = vm2.calcState.value.availableModels.firstOrNull { it.isSelected } // model restored
        assertEquals("kodak-tri-x-official-table", model?.profileId)
        assertEquals(60.0, vm2.calcState.value.targetSeconds!!, 1e-9)                 // target restored
    }

    // 4 — Custom film restore --------------------------------------------------

    @Test
    fun customFormulaPersistsReloadsRemainsSelectedAndAffectsCalc() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.CreateCustomFormula("Acme 100", exponent = 1.3, noCorrectionThroughSeconds = 1.0))
        vm1.onEvent(ShootingIntent.SetNdStops(8)) // adjusted ~8.5s > no-correction → corrected quantified
        settle()
        val film1 = vm1.calcState.value.filmName

        val vm2 = launch(ts, ss, cs)
        val custom = vm2.films.value.firstOrNull { it.isCustom }
        assertNotNull("custom formula should reload", custom)
        assertEquals(film1, vm2.calcState.value.filmName)             // still selected after relaunch
        assertEquals(custom!!.name, vm2.calcState.value.filmName)
        assertNotNull(vm2.calcState.value.correctedExposureLabel)     // selected custom affects calc
    }

    @Test
    fun customTablePersistsAndReloadsSelected() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.CreateCustomTable("Acme Table", listOf(1.0 to 2.0, 10.0 to 80.0)))
        settle()

        val vm2 = launch(ts, ss, cs)
        assertNotNull(vm2.films.value.firstOrNull { it.isCustom })
        assertNotNull(vm2.calcState.value.filmName)
        assertTrue(vm2.calcState.value.isCustomTable) // restored as a custom table
    }

    @Test
    fun tableCreatedFormulaPersistsAndReloads() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.CreateCustomTable("Acme Table", listOf(1.0 to 2.0, 10.0 to 80.0)))
        vm1.onEvent(ShootingIntent.CreateFormulaFromSelectedTable) // selects the new formula
        settle()
        val selectedAfterCreate = vm1.calcState.value.filmName

        val vm2 = launch(ts, ss, cs)
        assertEquals(2, vm2.films.value.count { it.isCustom }) // table + derived formula both persisted
        assertEquals(selectedAfterCreate, vm2.calcState.value.filmName) // derived formula stays selected
    }

    @Test
    fun deletingSelectedCustomFilmAfterRestoreFallsBackSafely() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.CreateCustomFormula("Acme 100", exponent = 1.3, noCorrectionThroughSeconds = 1.0))
        settle()

        val vm2 = launch(ts, ss, cs)
        val customId = vm2.films.value.first { it.isCustom }.id
        assertNotNull(vm2.calcState.value.filmName)
        vm2.onEvent(ShootingIntent.DeleteCustomFilm(customId))
        assertNull(vm2.calcState.value.filmName)                      // selection falls back to digital
        assertTrue(vm2.films.value.none { it.isCustom })              // library no longer lists it
    }

    // 5 — Timer identity with custom film -------------------------------------

    @Test
    fun customFilmCorrectedTimerIdentitySurvivesRestore() {
        val ts = InMemoryTimerStore(); val ss = InMemoryTimerStore(); val cs = InMemoryTimerStore()
        val vm1 = launch(ts, ss, cs)
        vm1.onEvent(ShootingIntent.CreateCustomFormula("Acme 100", exponent = 1.3, noCorrectionThroughSeconds = 1.0))
        vm1.onEvent(ShootingIntent.SetNdStops(8)) // adjusted ~8.5s → corrected ~16s, still running after restore
        vm1.onEvent(ShootingIntent.StartCorrected)
        settle()
        val started = vm1.timerState.value.active.single()
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, started.source)
        assertTrue(started.title.contains("Acme 100"))

        val vm2 = launch(ts, ss, cs)
        val restored = vm2.timerState.value.active.single()
        assertEquals(TimerStatus.RUNNING, restored.status)
        assertEquals(ExposureTimerSource.FILM_CORRECTED_EXPOSURE, restored.source) // source identity survives
        assertTrue(restored.title.contains("Acme 100"))                            // custom film name survives
        assertTrue(restored.subtitle.contains("Corrected Exposure"))
    }
}
