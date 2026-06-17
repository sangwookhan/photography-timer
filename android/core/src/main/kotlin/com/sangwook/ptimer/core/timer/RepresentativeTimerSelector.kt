package com.sangwook.ptimer.core.timer

import java.time.Instant

/**
 * Selects the representative running timer for an ongoing notification (the
 * Android equivalent of the iOS lock-screen Live Activity): the running timer
 * with the earliest expected completion, with a stable id tiebreak. Returns
 * null when no timer is running. Mirrors iOS representative-selection intent.
 */
object RepresentativeTimerSelector {
    fun select(timers: List<TimerState>, now: Instant): TimerState? =
        timers
            .filter { it is TimerState.Running && it.statusAt(now) == TimerStatus.RUNNING }
            .minWithOrNull(compareBy({ it.endDate }, { it.id }))
}
