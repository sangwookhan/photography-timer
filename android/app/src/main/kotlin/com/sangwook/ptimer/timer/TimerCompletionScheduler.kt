package com.sangwook.ptimer.timer

import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot

/**
 * Schedules an OS-level completion notification for a running timer at its
 * expected completion time, so completion can still be delivered when the app
 * is backgrounded or its process is later reclaimed (the in-process tick loop
 * only fires while the app is alive). Note: an explicit force-stop (Settings →
 * Force stop, or some OEM task-killers) cancels the app's pending alarms, so
 * delivery then resumes only on the next launch — force-stop is not a supported
 * delivery guarantee.
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
