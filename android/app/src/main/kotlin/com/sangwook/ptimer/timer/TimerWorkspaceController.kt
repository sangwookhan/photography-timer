package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot
import com.sangwook.ptimer.core.timer.RepresentativeTimerSelector
import com.sangwook.ptimer.core.timer.TimerRuntime
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.core.timer.TimerWorkspaceOrdering
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant

/** Immutable UI state for the timer workspace. */
data class TimerWorkspaceUiState(
    val active: List<TimerItemUi> = emptyList(),
    val completed: List<TimerItemUi> = emptyList(),
)

data class TimerItemUi(
    val id: String,
    val name: String,
    val status: TimerStatus,
    val remainingSeconds: Double,
    val remainingLabel: String,
)

/**
 * Plain (Android-free, JVM-testable) controller wrapping the pure
 * [TimerRuntime]. Owns the timer collection, display names, and the derived
 * [TimerWorkspaceUiState]. The ViewModel drives [tick] from a coroutine loop;
 * Composables never tick. Clock is injectable for deterministic tests.
 */
class TimerWorkspaceController(
    private val clock: () -> Instant = { Instant.now() },
) {
    private val runtime = TimerRuntime()
    private val calculator = ExposureCalculator()
    private val names = LinkedHashMap<String, String>()
    private var counter = 0L

    private val _state = MutableStateFlow(TimerWorkspaceUiState())
    val state: StateFlow<TimerWorkspaceUiState> = _state.asStateFlow()

    fun start(name: String, durationSeconds: Double): String? {
        val id = "timer-${counter++}"
        val started = runtime.start(id, durationSeconds, clock()) ?: return null
        names[started] = name
        refresh()
        return started
    }

    fun pause(id: String) { runtime.pause(id, clock()); refresh() }
    fun resume(id: String) { runtime.resume(id, clock()); refresh() }
    fun remove(id: String) { runtime.remove(id); names.remove(id); refresh() }
    fun clearCompleted() {
        val completedIds = runtime.timers.filter { it.status == TimerStatus.COMPLETED }.map { it.id }
        runtime.removeCompleted(); completedIds.forEach { names.remove(it) }; refresh()
    }

    /** "Start Again": clone a completed timer into a fresh running one. */
    fun startAgain(completedId: String): String? {
        val newId = "timer-${counter++}"
        val started = runtime.startAgain(completedId, newId, clock()) ?: return null
        names[started] = names[completedId] ?: "Timer"
        refresh()
        return started
    }

    /** Advance running timers; returns ids that completed on this tick. */
    fun tick(): List<String> {
        val completed = runtime.tick(clock())
        refresh()
        return completed
    }

    fun hasRunning(): Boolean = runtime.hasRunningTimers(clock())

    /** Representative running timer for the ongoing notification, or null. */
    fun representative(): TimerItemUi? =
        RepresentativeTimerSelector.select(runtime.timers, clock())?.toUi(clock())

    fun nameOf(id: String): String? = names[id]

    fun snapshotJson(): String = TimerSnapshotCodec.encode(runtime.timers, names)

    fun restoreFromJson(json: String?) {
        if (json == null) return
        val restored = TimerSnapshotCodec.decode(json)
        runtime.restoreFrom(restored.snapshots, clock())
        names.clear(); names.putAll(restored.names)
        refresh()
    }

    /** Recompute the UI state (also refreshes remaining labels at the current clock). */
    fun refresh() {
        val now = clock()
        val ordered = TimerWorkspaceOrdering.order(runtime.timers)
        _state.value = TimerWorkspaceUiState(
            active = ordered.active.map { it.toUi(now) },
            completed = ordered.completed.map { it.toUi(now) },
        )
    }

    private fun com.sangwook.ptimer.core.timer.TimerState.toUi(now: Instant): TimerItemUi {
        val remaining = remainingTime(now)
        val label = if (status == TimerStatus.COMPLETED) "Done" else calculator.formatExtendedClock(remaining)
        return TimerItemUi(
            id = id,
            name = names[id] ?: "Timer",
            status = status,
            remainingSeconds = remaining,
            remainingLabel = label,
        )
    }
}
