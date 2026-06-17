package com.sangwook.ptimer.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.sangwook.ptimer.calculator.CalculatorController
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.slots.CameraSlotSession
import com.sangwook.ptimer.slots.SlotSessionCodec
import com.sangwook.ptimer.timer.TimerStore
import com.sangwook.ptimer.timer.TimerWorkspaceController
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class FilmRowUi(val id: String, val name: String, val manufacturer: String?, val iso: Int)
data class SlotChipUi(val id: String, val label: String, val isActive: Boolean)
data class SlotsUiState(val slots: List<SlotChipUi>, val activeLabel: String)

/** One-way UI events for the shooting/timer workspace. */
sealed interface ShootingIntent {
    data class NudgeBaseShutter(val delta: Int) : ShootingIntent
    data class SetNdStops(val stops: Int) : ShootingIntent
    data class SelectFilm(val id: String?) : ShootingIntent
    data object ClearFilm : ShootingIntent
    data class SelectModel(val profileId: String?) : ShootingIntent
    data object StartFromResult : ShootingIntent
    data class SelectSlot(val id: String) : ShootingIntent
    data class RenameSlot(val id: String, val name: String) : ShootingIntent
    data class ResetSlotName(val id: String) : ShootingIntent
    data class Pause(val id: String) : ShootingIntent
    data class Resume(val id: String) : ShootingIntent
    data class Remove(val id: String) : ShootingIntent
    data class StartAgain(val id: String) : ShootingIntent
    data object ClearCompleted : ShootingIntent
}

/**
 * Owns the per-slot calculator + film selection, the camera-slot session, and
 * the timer workspace. Drives the ~100 ms tick loop from viewModelScope
 * (Composables never tick), persists/restores timers and the slot session,
 * and exposes immutable state. Starting a timer captures the active slot's
 * label into the (immutable) timer name.
 */
class ShootingViewModel(
    private val timerStore: TimerStore,
    private val sessionStore: TimerStore,
) : ViewModel() {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private val calc = CalculatorController(catalog)
    private val timer = TimerWorkspaceController()
    private val session = CameraSlotSession()

    val films: List<FilmRowUi> = catalog.map { FilmRowUi(it.id, it.canonicalStockName, it.manufacturer, it.iso) }
    val timerState: StateFlow<TimerWorkspaceUiState> = timer.state

    private val _calcState = MutableStateFlow(CalculatorUiState("", 0, null, null, "", null, null, false, null, emptyList()))
    val calcState: StateFlow<CalculatorUiState> = _calcState.asStateFlow()
    private val _slotsState = MutableStateFlow(slotsSnapshot())
    val slotsState: StateFlow<SlotsUiState> = _slotsState.asStateFlow()

    private var tickJob: Job? = null

    init {
        calc.setBaseShutterLadderIndex(nearestBaseIndex(com.sangwook.ptimer.core.exposure.CalculatorDefaults.BASE_SHUTTER_SECONDS))
        viewModelScope.launch {
            timer.restoreFromJson(timerStore.load())
            sessionStore.load()?.let { json ->
                SlotSessionCodec.decode(json)?.let { restored ->
                    session.restore(restored.activeSlotId, restored.snapshots, restored.names)
                    calc.apply(session.snapshot(session.activeSlotId))
                }
            }
            refreshCalc(); refreshSlots(); ensureTicking()
        }
    }

    fun onEvent(intent: ShootingIntent) {
        when (intent) {
            is ShootingIntent.NudgeBaseShutter -> {
                val next = (nearestBaseIndex(calc.currentBaseSeconds()) + intent.delta)
                    .coerceIn(0, ExposureScale.oneThirdStop.shutterSteps.lastIndex)
                calc.setBaseShutterLadderIndex(next); afterCalcChange()
            }
            is ShootingIntent.SetNdStops -> { calc.setNdStops(intent.stops); afterCalcChange() }
            is ShootingIntent.SelectFilm -> { calc.selectFilm(intent.id); afterCalcChange() }
            ShootingIntent.ClearFilm -> { calc.clearFilm(); afterCalcChange() }
            is ShootingIntent.SelectModel -> { calc.selectModel(intent.profileId); afterCalcChange() }
            ShootingIntent.StartFromResult -> {
                calc.startRequest()?.let { timer.start("${session.activeLabel()} · ${it.name}", it.durationSeconds) }
                persistTimers(); ensureTicking()
            }
            is ShootingIntent.SelectSlot -> {
                session.store(session.activeSlotId, calc.capture())
                session.activate(intent.id)
                calc.apply(session.snapshot(intent.id))
                refreshCalc(); refreshSlots(); persistSession()
            }
            is ShootingIntent.RenameSlot -> { session.setCustomName(intent.id, intent.name); refreshSlots(); persistSession() }
            is ShootingIntent.ResetSlotName -> { session.resetName(intent.id); refreshSlots(); persistSession() }
            is ShootingIntent.Pause -> { timer.pause(intent.id); persistTimers(); ensureTicking() }
            is ShootingIntent.Resume -> { timer.resume(intent.id); persistTimers(); ensureTicking() }
            is ShootingIntent.Remove -> { timer.remove(intent.id); persistTimers() }
            is ShootingIntent.StartAgain -> { timer.startAgain(intent.id); persistTimers(); ensureTicking() }
            ShootingIntent.ClearCompleted -> { timer.clearCompleted(); persistTimers() }
        }
    }

    private fun afterCalcChange() { refreshCalc(); persistSession() }
    private fun refreshCalc() { _calcState.value = calc.uiState() }
    private fun refreshSlots() { _slotsState.value = slotsSnapshot() }

    private fun slotsSnapshot(): SlotsUiState = SlotsUiState(
        slots = session.slotIds.map { SlotChipUi(it, session.label(it), it == session.activeSlotId) },
        activeLabel = session.activeLabel(),
    )

    private fun nearestBaseIndex(seconds: Double): Int {
        val ladder = ExposureScale.oneThirdStop.shutterSteps
        return ladder.indices.minByOrNull { kotlin.math.abs(ladder[it].seconds - seconds) } ?: 0
    }

    private fun ensureTicking() {
        if (tickJob != null || !timer.hasRunning()) return
        tickJob = viewModelScope.launch {
            while (timer.hasRunning()) {
                delay(TICK_MILLIS)
                if (timer.tick().isNotEmpty()) persistTimers()
            }
            persistTimers(); tickJob = null
        }
    }

    private fun persistTimers() {
        val json = timer.snapshotJson()
        viewModelScope.launch { timerStore.save(json) }
    }

    private fun persistSession() {
        session.store(session.activeSlotId, calc.capture())
        val json = SlotSessionCodec.encode(session)
        viewModelScope.launch { sessionStore.save(json) }
    }

    companion object {
        private const val TICK_MILLIS = 100L

        fun factory(timerStore: TimerStore, sessionStore: TimerStore) = viewModelFactory {
            initializer { ShootingViewModel(timerStore, sessionStore) }
        }
    }
}
