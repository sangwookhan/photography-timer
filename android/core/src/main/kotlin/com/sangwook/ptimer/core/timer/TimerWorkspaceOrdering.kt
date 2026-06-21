package com.sangwook.ptimer.core.timer

import java.time.Instant

/**
 * Ordering the runtime decides once; the UI consumes without re-sorting.
 * Active group (running + paused) is most-recent-first (LIFO by creation); the
 * terminal/history group (completed + canceled) is terminal-time descending,
 * presented behind active. Mirrors iOS `TimerWorkspaceOrdering` intent.
 */
object TimerWorkspaceOrdering {
    /** `completed` holds the terminal/history records — both completed and canceled. */
    data class Ordered(val active: List<TimerState>, val completed: List<TimerState>)

    fun order(timers: List<TimerState>): Ordered {
        val active = timers
            .filter { it.status == TimerStatus.RUNNING || it.status == TimerStatus.PAUSED }
            .sortedWith(compareByDescending<TimerState> { it.startDate }.thenBy { it.id })
        val terminal = timers
            .filter { it.status == TimerStatus.COMPLETED || it.status == TimerStatus.CANCELED }
            .sortedWith(compareByDescending<TimerState> { terminalAt(it) }.thenBy { it.id })
        return Ordered(active, terminal)
    }

    /** Terminal timestamp used to order history: completion time, else cancellation time. */
    private fun terminalAt(timer: TimerState): Instant = when (timer) {
        is TimerState.Completed -> timer.completedAt
        is TimerState.Canceled -> timer.canceledAt
        else -> timer.startDate // unreachable: only terminal records are sorted here
    }
}
