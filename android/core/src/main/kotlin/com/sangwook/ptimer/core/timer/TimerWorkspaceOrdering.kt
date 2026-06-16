package com.sangwook.ptimer.core.timer

/**
 * Ordering the runtime decides once; the UI consumes without re-sorting.
 * Active group (running + paused) is most-recent-first (LIFO by creation);
 * completed group is completion-time descending, presented behind active.
 * Mirrors iOS `TimerWorkspaceOrdering` intent.
 */
object TimerWorkspaceOrdering {
    data class Ordered(val active: List<TimerState>, val completed: List<TimerState>)

    fun order(timers: List<TimerState>): Ordered {
        val active = timers
            .filter { it.status != TimerStatus.COMPLETED }
            .sortedWith(compareByDescending<TimerState> { it.startDate }.thenBy { it.id })
        val completed = timers
            .filterIsInstance<TimerState.Completed>()
            .sortedWith(compareByDescending<TimerState.Completed> { it.completedAt }.thenBy { it.id })
        return Ordered(active, completed)
    }
}
