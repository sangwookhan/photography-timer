package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.timer.TimerWorkspace
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.core.timer.WorkspaceTimer
import com.sangwook.ptimer.core.timer.endDate
import com.sangwook.ptimer.core.timer.remainingAtCancel
import com.sangwook.ptimer.core.timer.remainingTime
import com.sangwook.ptimer.core.timer.status
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.util.UUID

/** One-way intents the timer workspace UI emits. */
sealed interface ShootingIntent {
    data class StartTimer(val duration: Double, val identity: TimerIdentity) : ShootingIntent
    data class Pause(val id: UUID) : ShootingIntent
    data class Resume(val id: UUID) : ShootingIntent
    data class Cancel(val id: UUID) : ShootingIntent
    data class Remove(val id: UUID) : ShootingIntent
    data class Clone(val id: UUID) : ShootingIntent
    data object ClearCompleted : ShootingIntent
}

/** Read-only display card for one timer. */
data class TimerCardState(
    val id: UUID,
    val order: Int,
    val identity: TimerIdentity,
    val status: TimerStatus,
    val remainingSeconds: Double,
    val endDate: Instant,
    val remainingAtCancelSeconds: Double?,
)

/** Immutable state the timer workspace UI renders. */
data class ShootingUiState(
    val active: List<TimerCardState> = emptyList(),
    val history: List<TimerCardState> = emptyList(),
    val now: Instant = Instant.EPOCH,
)

/**
 * Owns the timer workspace: applies one-way [ShootingIntent]s, exposes an
 * immutable [ShootingUiState] via [StateFlow], reconciles on tick, and persists
 * on every change. A fresh-UUID supplier and clock are injected so the type is
 * deterministic and unit-testable without Android.
 *
 * Not an `androidx.lifecycle.ViewModel` subclass so it instantiates trivially
 * in JVM unit tests; the Compose wiring holds it across recompositions.
 */
class ShootingViewModel(
    private val store: WorkspacePersistenceStoring,
    private val clock: () -> Instant = { Instant.now() },
    private val idProvider: () -> UUID = { UUID.randomUUID() },
) {
    private val workspace = MutableStateFlow(TimerWorkspace())
    private val now = MutableStateFlow(clock())

    private val _uiState = MutableStateFlow(render(workspace.value, now.value))
    val uiState: StateFlow<ShootingUiState> = _uiState.asStateFlow()

    /** True while at least one timer is running (the coordinator ticks then). */
    val hasRunningTimers: Boolean get() = workspace.value.hasRunning

    /** Restores the persisted workspace, reconciling against the current time. */
    fun restore() {
        val snapshot = store.loadSnapshot() ?: return
        val n = clock()
        workspace.value = TimerWorkspace(snapshot.restore(n)).reconciled(n)
        now.value = n
        publish()
        persist()
    }

    fun onEvent(intent: ShootingIntent) {
        val n = clock()
        workspace.value = when (intent) {
            is ShootingIntent.StartTimer -> workspace.value.start(idProvider(), intent.duration, intent.identity, n)
            is ShootingIntent.Pause -> workspace.value.pause(intent.id, n)
            is ShootingIntent.Resume -> workspace.value.resume(intent.id, n)
            is ShootingIntent.Cancel -> workspace.value.cancel(intent.id, n)
            is ShootingIntent.Remove -> workspace.value.remove(intent.id)
            is ShootingIntent.Clone -> workspace.value.clone(intent.id, idProvider(), n)
            is ShootingIntent.ClearCompleted -> workspace.value.clearCompleted()
        }.reconciled(n)
        now.value = n
        publish()
        persist()
    }

    /** Wall-clock tick from the coordinator: re-render and auto-complete. */
    fun tick(n: Instant) {
        val reconciled = workspace.value.reconciled(n)
        val completionsChanged = reconciled != workspace.value
        workspace.value = reconciled
        now.value = n
        publish()
        if (completionsChanged) persist()
    }

    private fun publish() {
        _uiState.value = render(workspace.value, now.value)
    }

    private fun persist() {
        store.saveSnapshot(PersistentWorkspaceSnapshot.from(workspace.value.timers))
    }

    private fun render(ws: TimerWorkspace, n: Instant): ShootingUiState =
        ShootingUiState(
            active = ws.active().map { card(it, n) },
            history = ws.history().map { card(it, n) },
            now = n,
        )

    private fun card(wt: WorkspaceTimer, n: Instant): TimerCardState = TimerCardState(
        id = wt.id,
        order = wt.order,
        identity = wt.identity,
        status = wt.state.status,
        remainingSeconds = wt.state.remainingTime(n),
        endDate = wt.state.endDate,
        remainingAtCancelSeconds = wt.state.remainingAtCancel,
    )
}
