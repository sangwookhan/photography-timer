package com.sangwook.ptimer.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.sangwook.ptimer.timer.TimerStore
import com.sangwook.ptimer.timer.TimerWorkspaceController
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** One-way UI events for the shooting/timer workspace. */
sealed interface ShootingIntent {
    data class StartTimer(val name: String, val durationSeconds: Double) : ShootingIntent
    data class Pause(val id: String) : ShootingIntent
    data class Resume(val id: String) : ShootingIntent
    data class Remove(val id: String) : ShootingIntent
    data class StartAgain(val id: String) : ShootingIntent
    data object ClearCompleted : ShootingIntent
}

/**
 * Owns the timer workspace state and drives the ~100 ms tick loop from
 * `viewModelScope` (Composables never tick). Persists the collection on every
 * change and restores it on launch. UI sends [ShootingIntent]s one-way and
 * observes [uiState].
 */
class ShootingViewModel(private val store: TimerStore) : ViewModel() {
    private val controller = TimerWorkspaceController()
    val uiState: StateFlow<TimerWorkspaceUiState> = controller.state

    private var tickJob: Job? = null

    init {
        viewModelScope.launch {
            controller.restoreFromJson(store.load())
            ensureTicking()
        }
    }

    fun onEvent(intent: ShootingIntent) {
        when (intent) {
            is ShootingIntent.StartTimer -> controller.start(intent.name, intent.durationSeconds)
            is ShootingIntent.Pause -> controller.pause(intent.id)
            is ShootingIntent.Resume -> controller.resume(intent.id)
            is ShootingIntent.Remove -> controller.remove(intent.id)
            is ShootingIntent.StartAgain -> controller.startAgain(intent.id)
            ShootingIntent.ClearCompleted -> controller.clearCompleted()
        }
        persist()
        ensureTicking()
    }

    private fun ensureTicking() {
        if (tickJob != null || !controller.hasRunning()) return
        tickJob = viewModelScope.launch {
            while (controller.hasRunning()) {
                delay(TICK_MILLIS)
                val completed = controller.tick()
                if (completed.isNotEmpty()) persist()
            }
            persist()
            tickJob = null
        }
    }

    private fun persist() {
        val json = controller.snapshotJson()
        viewModelScope.launch { store.save(json) }
    }

    companion object {
        private const val TICK_MILLIS = 100L

        fun factory(store: TimerStore) = viewModelFactory {
            initializer { ShootingViewModel(store) }
        }
    }
}
