package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot
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
        val id = nextId()
        val started = runtime.start(id, durationSeconds, clock()) ?: return null
        titles[started] = title; subtitles[started] = subtitle
        metadatas[started] = metadata; sources[started] = source
        refresh()
        return started
    }

    fun pause(id: String) { runtime.pause(id, clock()); refresh() }
    fun resume(id: String) { runtime.resume(id, clock()); refresh() }
    /** Cancel a running/paused timer, keeping it as a terminal canceled record (distinct from [remove]). */
    fun cancel(id: String) { runtime.cancel(id, clock()); refresh() }
    fun remove(id: String) { runtime.remove(id); forget(id); refresh() }
    /**
     * Clear completed records only. Canceled records survive in history (iOS
     * parity — `clearCompletedTimers` removes only `.completed`).
     */
    fun clearCompleted() {
        val completedIds = runtime.timers.filter { it.status == TimerStatus.COMPLETED }.map { it.id }
        runtime.removeCompleted(); completedIds.forEach { forget(it) }; refresh()
    }

    /**
     * "Start Again": clone a terminal (completed or canceled) record into a
     * fresh running timer, preserving identity. The source record is left
     * intact. Returns null when the source is not a terminal record.
     */
    fun startAgain(terminalId: String): String? {
        val src = runtime.timers.firstOrNull { it.id == terminalId } ?: return null
        if (src.status != TimerStatus.COMPLETED && src.status != TimerStatus.CANCELED) return null
        return cloneIdentityToNew(src)
    }

    /**
     * "Start New": cancel the active (running/paused) source — keeping it as a
     * terminal canceled record in history — and start a fresh timer from the
     * same identity and full duration, so no duplicate or ghost active timer
     * remains. Returns null when the source is not running or paused.
     */
    fun cloneToNew(sourceId: String): String? {
        val src = runtime.timers.firstOrNull { it.id == sourceId } ?: return null
        if (src.status != TimerStatus.RUNNING && src.status != TimerStatus.PAUSED) return null
        runtime.cancel(sourceId, clock())
        return cloneIdentityToNew(src)
    }

    /** Start a fresh running timer reusing [src]'s duration and captured identity. */
    private fun cloneIdentityToNew(src: com.sangwook.ptimer.core.timer.TimerState): String? {
        val newId = nextId()
        val started = runtime.start(newId, src.durationSeconds, clock()) ?: return null
        titles[started] = titles[src.id] ?: "Timer"
        subtitles[started] = subtitles[src.id] ?: ""
        metadatas[started] = metadatas[src.id] ?: ""
        sources[started] = sources[src.id] ?: ExposureTimerSource.MANUAL
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

    /** Identity + snapshot of the immutable expected-completion data per running timer. */
    data class CompletionTarget(val snapshot: PersistentTimerSnapshot, val title: String, val subtitle: String)

    /**
     * Running timers that still have a pending completion, with the immutable
     * identity captured at start. Used by the app layer to (re)schedule
     * OS-level completion alarms. Paused/completed timers are excluded.
     */
    fun runningCompletionTargets(): List<CompletionTarget> =
        runtime.timers.filter { it.status == TimerStatus.RUNNING }.map { timer ->
            CompletionTarget(
                snapshot = PersistentTimerSnapshot.fromTimer(timer),
                title = titles[timer.id] ?: "Timer",
                subtitle = subtitles[timer.id] ?: "",
            )
        }

    fun snapshotJson(): String = TimerSnapshotCodec.encode(runtime.timers, titles, subtitles, metadatas, sources)

    fun restoreFromJson(json: String?) {
        if (json == null) return
        val restored = TimerSnapshotCodec.decode(json)
        runtime.restoreFrom(restored.snapshots, clock())
        titles.clear(); titles.putAll(restored.titles)
        subtitles.clear(); subtitles.putAll(restored.subtitles)
        metadatas.clear(); metadatas.putAll(restored.metadatas)
        sources.clear(); sources.putAll(restored.sources)
        advanceCounterPast(restored.snapshots.map { it.id })
        refresh()
    }

    /**
     * Next generated id, guaranteed not to collide with an existing timer.
     * Generated ids follow `timer-<n>`; [advanceCounterPast] keeps [counter]
     * ahead of any restored generated id, and the loop is a final guard
     * against collisions with non-generated (custom/corrupt) restored ids.
     */
    private fun nextId(): String {
        var id = "timer-${counter++}"
        while (runtime.timers.any { it.id == id }) id = "timer-${counter++}"
        return id
    }

    /** Advance [counter] beyond every restored id matching the generated pattern. */
    private fun advanceCounterPast(ids: Collection<String>) {
        var maxN = -1L
        for (id in ids) {
            val n = GENERATED_ID.matchEntire(id)?.groupValues?.get(1)?.toLongOrNull() ?: continue
            if (n > maxN) maxN = n
        }
        if (maxN + 1 > counter) counter = maxN + 1
    }

    fun refresh() {
        val now = clock()
        val ordered = TimerWorkspaceOrdering.order(runtime.timers)
        _state.value = TimerWorkspaceUiState(
            active = ordered.active.map { it.toUi(now) },
            completed = ordered.completed.map { it.toUi(now) },
        )
    }

    /**
     * Large remaining label for a canceled record: combines the status with the
     * remaining-at-cancel ("Canceled · 51s left") when positive, else just
     * "Canceled". Mirrors iOS canceled large-remaining text.
     */
    private fun canceledLargeLabel(remainingAtCancel: Double): String =
        if (remainingAtCancel > 0) "Canceled · ${calculator.formatExtendedClock(remainingAtCancel)} left" else "Canceled"

    private fun forget(id: String) {
        titles.remove(id); subtitles.remove(id); metadatas.remove(id); sources.remove(id)
    }

    private companion object {
        val GENERATED_ID = Regex("""^timer-(\d+)$""")
    }

    private fun com.sangwook.ptimer.core.timer.TimerState.toUi(now: Instant): TimerItemUi {
        val remaining = remainingTime(now)
        val label = when (this) {
            is com.sangwook.ptimer.core.timer.TimerState.Completed -> "Done"
            is com.sangwook.ptimer.core.timer.TimerState.Canceled -> canceledLargeLabel(remainingAtCancelSeconds)
            else -> calculator.formatExtendedClock(remaining)
        }
        val statusLabel = when (status) {
            TimerStatus.RUNNING -> "Running"
            TimerStatus.PAUSED -> "Paused"
            TimerStatus.COMPLETED -> "Done"
            TimerStatus.CANCELED -> "Canceled"
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
