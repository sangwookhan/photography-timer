package com.sangwook.ptimer.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.sangwook.ptimer.calculator.CalculatorController
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.exposure.ExposureScale
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

/** One-way UI events for the shooting/timer workspace. */
sealed interface ShootingIntent {
    data class NudgeBaseShutter(val delta: Int) : ShootingIntent
    data class SetNdStops(val stops: Int) : ShootingIntent
    data class SelectFilm(val id: String?) : ShootingIntent
    data object ClearFilm : ShootingIntent
    data class SelectModel(val profileId: String?) : ShootingIntent
    data object StartFromResult : ShootingIntent
    data class Pause(val id: String) : ShootingIntent
    data class Resume(val id: String) : ShootingIntent
    data class Remove(val id: String) : ShootingIntent
    data class StartAgain(val id: String) : ShootingIntent
    data object ClearCompleted : ShootingIntent
}

/**
 * Owns the calculator + film selection and the timer workspace. Drives the
 * ~100 ms tick loop from viewModelScope (Composables never tick), persists/
 * restores timers, and exposes immutable calculator/timer state. UI sends
 * [ShootingIntent]s one-way.
 */
class ShootingViewModel(private val store: TimerStore) : ViewModel() {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private val calc = CalculatorController(catalog)
    private val timer = TimerWorkspaceController()

    val films: List<FilmRowUi> = catalog.map { FilmRowUi(it.id, it.canonicalStockName, it.manufacturer, it.iso) }

    val timerState: StateFlow<TimerWorkspaceUiState> = timer.state

    private val _calcState = MutableStateFlow(initialCalcState())
    val calcState: StateFlow<CalculatorUiState> = _calcState.asStateFlow()

    private var baseIndex: Int = defaultBaseIndex()
    private var tickJob: Job? = null

    init {
        viewModelScope.launch {
            timer.restoreFromJson(store.load())
            ensureTicking()
        }
    }

    fun onEvent(intent: ShootingIntent) {
        when (intent) {
            is ShootingIntent.NudgeBaseShutter -> {
                baseIndex = (baseIndex + intent.delta).coerceIn(0, ExposureScale.oneThirdStop.shutterSteps.lastIndex)
                calc.setBaseShutterLadderIndex(baseIndex)
                refreshCalc()
            }
            is ShootingIntent.SetNdStops -> { calc.setNdStops(intent.stops); refreshCalc() }
            is ShootingIntent.SelectFilm -> { calc.selectFilm(intent.id); refreshCalc() }
            ShootingIntent.ClearFilm -> { calc.clearFilm(); refreshCalc() }
            is ShootingIntent.SelectModel -> { calc.selectModel(intent.profileId); refreshCalc() }
            ShootingIntent.StartFromResult -> {
                calc.startRequest()?.let { timer.start(it.name, it.durationSeconds) }
                persist(); ensureTicking()
            }
            is ShootingIntent.Pause -> { timer.pause(intent.id); persist(); ensureTicking() }
            is ShootingIntent.Resume -> { timer.resume(intent.id); persist(); ensureTicking() }
            is ShootingIntent.Remove -> { timer.remove(intent.id); persist() }
            is ShootingIntent.StartAgain -> { timer.startAgain(intent.id); persist(); ensureTicking() }
            ShootingIntent.ClearCompleted -> { timer.clearCompleted(); persist() }
        }
    }

    private fun refreshCalc() { _calcState.value = calc.uiState() }

    private fun initialCalcState(): CalculatorUiState {
        calc.setBaseShutterLadderIndex(defaultBaseIndex())
        return calc.uiState()
    }

    private fun defaultBaseIndex(): Int {
        val ladder = ExposureScale.oneThirdStop.shutterSteps
        val target = com.sangwook.ptimer.core.exposure.CalculatorDefaults.BASE_SHUTTER_SECONDS
        return ladder.indices.minByOrNull { kotlin.math.abs(ladder[it].seconds - target) } ?: 0
    }

    private fun ensureTicking() {
        if (tickJob != null || !timer.hasRunning()) return
        tickJob = viewModelScope.launch {
            while (timer.hasRunning()) {
                delay(TICK_MILLIS)
                val completed = timer.tick()
                if (completed.isNotEmpty()) persist()
            }
            persist()
            tickJob = null
        }
    }

    private fun persist() {
        val json = timer.snapshotJson()
        viewModelScope.launch { store.save(json) }
    }

    companion object {
        private const val TICK_MILLIS = 100L

        fun factory(store: TimerStore) = viewModelFactory {
            initializer { ShootingViewModel(store) }
        }
    }
}
