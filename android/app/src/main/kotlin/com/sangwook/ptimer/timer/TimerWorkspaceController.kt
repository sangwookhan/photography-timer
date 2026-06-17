package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.RepresentativeTimerSelector
import com.sangwook.ptimer.core.timer.TimerRuntime
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.core.timer.TimerWorkspaceOrdering
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Immutable UI state for the timer workspace. */
data class TimerWorkspaceUiState(
    val active: List<TimerItemUi> = emptyList(),
    val completed: List<TimerItemUi> = emptyList(),
)

data class TimerItemUi(
    val id: String,
    val title: String,
    val subtitle: String,
    val metadata: String,
    val source: ExposureTimerSource,
    val status: TimerStatus,
    val statusLabel: String,
    val remainingSeconds: Double,
    val remainingLabel: String,
    val endsAtLabel: String?,
)

/**
 * Plain (Android-free, JVM-testable) controller wrapping the pure
 * [TimerRuntime]. Each timer carries an immutable title + source-identity
 * subtitle captured at start, so active/completed rows always show which
 * exposure source they came from. The ViewModel drives [tick]; Composables
 * never tick. Clock is injectable for deterministic tests.
 */
class TimerWorkspaceController(
    private val clock: () -> Instant = { Instant.now() },
) {
    private val runtime = TimerRuntime()
    private val calculator = ExposureCalculator()
    private val titles = LinkedHashMap<String, String>()
    private val subtitles = LinkedHashMap<String, String>()
    private val metadatas = LinkedHashMap<String, String>()
    private val sources = LinkedHashMap<String, ExposureTimerSource>()
    private var counter = 0L
    private val endsAtFormatter = DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZoneId.systemDefault())

    private val _state = MutableStateFlow(TimerWorkspaceUiState())
    val state: StateFlow<TimerWorkspaceUiState> = _state.asStateFlow()

    fun start(
        title: String,
        subtitle: String,
        metadata: String,
        source: ExposureTimerSource,
        durationSeconds: Double,
    ): String? {
        val id = "timer-${counter++}"
        val started = runtime.start(id, durationSeconds, clock()) ?: return null
        titles[started] = title; subtitles[started] = subtitle
        metadatas[started] = metadata; sources[started] = source
        refresh()
        return started
    }

    fun pause(id: String) { runtime.pause(id, clock()); refresh() }
    fun resume(id: String) { runtime.resume(id, clock()); refresh() }
    fun remove(id: String) { runtime.remove(id); forget(id); refresh() }
    fun clearCompleted() {
        val completedIds = runtime.timers.filter { it.status == TimerStatus.COMPLETED }.map { it.id }
        runtime.removeCompleted(); completedIds.forEach { forget(it) }; refresh()
    }

    /** "Start Again": clone a completed timer (identity preserved) into a fresh running one. */
    fun startAgain(completedId: String): String? = cloneToNew(completedId)

    /** "Start New": clone any timer (running/paused/completed) into a fresh running one. */
    fun cloneToNew(sourceId: String): String? {
        val src = runtime.timers.firstOrNull { it.id == sourceId } ?: return null
        val newId = "timer-${counter++}"
        val started = runtime.start(newId, src.durationSeconds, clock()) ?: return null
        titles[started] = titles[sourceId] ?: "Timer"
        subtitles[started] = subtitles[sourceId] ?: ""
        metadatas[started] = metadatas[sourceId] ?: ""
        sources[started] = sources[sourceId] ?: ExposureTimerSource.MANUAL
        refresh()
        return started
    }

    fun tick(): List<String> {
        val completed = runtime.tick(clock())
        refresh()
        return completed
    }

    fun hasRunning(): Boolean = runtime.hasRunningTimers(clock())

    /** Representative running timer for the ongoing notification, or null. */
    fun representative(): TimerItemUi? =
        RepresentativeTimerSelector.select(runtime.timers, clock())?.toUi(clock())

    fun titleOf(id: String): String? = titles[id]
    fun subtitleOf(id: String): String? = subtitles[id]

    fun snapshotJson(): String = TimerSnapshotCodec.encode(runtime.timers, titles, subtitles, metadatas, sources)

    fun restoreFromJson(json: String?) {
        if (json == null) return
        val restored = TimerSnapshotCodec.decode(json)
        runtime.restoreFrom(restored.snapshots, clock())
        titles.clear(); titles.putAll(restored.titles)
        subtitles.clear(); subtitles.putAll(restored.subtitles)
        metadatas.clear(); metadatas.putAll(restored.metadatas)
        sources.clear(); sources.putAll(restored.sources)
        refresh()
    }

    fun refresh() {
        val now = clock()
        val ordered = TimerWorkspaceOrdering.order(runtime.timers)
        _state.value = TimerWorkspaceUiState(
            active = ordered.active.map { it.toUi(now) },
            completed = ordered.completed.map { it.toUi(now) },
        )
    }

    private fun forget(id: String) {
        titles.remove(id); subtitles.remove(id); metadatas.remove(id); sources.remove(id)
    }

    private fun com.sangwook.ptimer.core.timer.TimerState.toUi(now: Instant): TimerItemUi {
        val remaining = remainingTime(now)
        val label = if (status == TimerStatus.COMPLETED) "Done" else calculator.formatExtendedClock(remaining)
        val statusLabel = when (status) {
            TimerStatus.RUNNING -> "Running"
            TimerStatus.PAUSED -> "Paused"
            TimerStatus.COMPLETED -> "Done"
        }
        val endsAt = if (status == TimerStatus.RUNNING) "Ends ${endsAtFormatter.format(endDate)}" else null
        return TimerItemUi(
            id = id,
            title = titles[id] ?: "Timer",
            subtitle = subtitles[id] ?: "",
            metadata = metadatas[id] ?: "",
            source = sources[id] ?: ExposureTimerSource.MANUAL,
            status = status,
            statusLabel = statusLabel,
            remainingSeconds = remaining,
            remainingLabel = label,
            endsAtLabel = endsAt,
        )
    }
}
