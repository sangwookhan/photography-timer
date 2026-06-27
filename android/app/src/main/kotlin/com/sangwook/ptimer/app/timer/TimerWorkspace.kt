// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.timer

import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.core.timer.WorkspaceTimer
import com.sangwook.ptimer.core.timer.canceled
import com.sangwook.ptimer.core.timer.endDate
import com.sangwook.ptimer.core.timer.pausing
import com.sangwook.ptimer.core.timer.plusSecondsDouble
import com.sangwook.ptimer.core.timer.resume
import com.sangwook.ptimer.core.timer.status
import com.sangwook.ptimer.core.timer.updatingStatus
import java.time.Instant
import java.util.UUID

/**
 * Pure, immutable timer workspace: the single-owner collection of timers the
 * ViewModel mutates. Active timers (running/paused) sort by start ascending;
 * history (completed/canceled) sorts by terminal stamp descending so the most
 * recent finish leads — matching the iOS workspace ordering (PTIMER-50).
 *
 * Pure value type: every mutation returns a new workspace, and a fresh id is
 * supplied by the caller so this stays deterministic and testable.
 */
data class TimerWorkspace(val timers: List<WorkspaceTimer> = emptyList()) {

    val hasRunning: Boolean get() = timers.any { it.state.status == TimerStatus.running }

    fun start(id: UUID, duration: Double, identity: TimerIdentity, now: Instant): TimerWorkspace {
        val state = TimerState.Running(id, duration, startDate = now, endDate = now.plusSecondsDouble(duration))
        // Stable creation-order number (iOS RunningTimerItem.order): one past the
        // highest order in play, so new timers (incl. Clone) keep climbing
        // and the value survives deletion/sorting/restore.
        val order = (timers.maxOfOrNull { it.order } ?: 0) + 1
        return copy(timers = timers + WorkspaceTimer(state, identity, order))
    }

    fun pause(id: UUID, now: Instant) = transform(id) { it.pausing(now) }
    fun resume(id: UUID, now: Instant) = transform(id) { it.resume(now) }
    fun cancel(id: UUID, now: Instant) = transform(id) { it.canceled(now) }

    fun remove(id: UUID): TimerWorkspace = copy(timers = timers.filterNot { it.id == id })

    /**
     * Clone (iOS clone): starts a new running timer with the same duration +
     * identity as the source, from ANY state. The source is left untouched —
     * cancellation is never implicit; the user cancels a timer explicitly.
     */
    fun clone(id: UUID, newID: UUID, now: Instant): TimerWorkspace {
        val source = timers.firstOrNull { it.id == id } ?: return this
        return start(newID, source.state.duration, source.identity, now)
    }

    /**
     * Clear (iOS clearCompletedTimers): removes completed records only;
     * canceled history is preserved.
     */
    fun clearCompleted(): TimerWorkspace =
        copy(timers = timers.filterNot { it.state.status == TimerStatus.completed })

    /** Advances running timers to completed when their end has passed. */
    fun reconciled(now: Instant): TimerWorkspace =
        copy(timers = timers.map { wt -> wt.copy(state = wt.state.updatingStatus(now)) })

    fun active(): List<WorkspaceTimer> = timers
        .filter { it.state.status == TimerStatus.running || it.state.status == TimerStatus.paused }
        .sortedBy { it.state.startDate }

    fun history(): List<WorkspaceTimer> = timers
        .filter { it.state.status == TimerStatus.completed || it.state.status == TimerStatus.canceled }
        .sortedByDescending { it.state.endDate }

    private fun transform(id: UUID, change: (TimerState) -> TimerState): TimerWorkspace =
        copy(timers = timers.map { if (it.id == id) it.copy(state = change(it.state)) else it })
}
