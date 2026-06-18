package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot

/**
 * Schedules an OS-level completion notification for a running timer at its
 * expected completion time, so completion can be delivered even if the app
 * process is backgrounded or force-stopped (the in-process tick loop only
 * fires while the app is alive).
 *
 * Abstracted so the app timer workflow is testable with a fake; the production
 * implementation lives in `:app` and uses AlarmManager + a BroadcastReceiver.
 * The snapshot's `expectedCompletionAt` is the alarm time and `id` is the
 * stable request key; `title`/`subtitle` are the immutable identity captured at
 * start, encoded into the alarm so the receiver does not depend on live state.
 */
interface TimerCompletionScheduler {
    fun schedule(snapshot: PersistentTimerSnapshot, title: String, subtitle: String)
    fun cancel(timerId: String)
    fun cancelAll(timerIds: Collection<String>)
}

/** No-op scheduler — safe default and used by JVM tests/previews. */
object NoOpTimerCompletionScheduler : TimerCompletionScheduler {
    override fun schedule(snapshot: PersistentTimerSnapshot, title: String, subtitle: String) {}
    override fun cancel(timerId: String) {}
    override fun cancelAll(timerIds: Collection<String>) {}
}
