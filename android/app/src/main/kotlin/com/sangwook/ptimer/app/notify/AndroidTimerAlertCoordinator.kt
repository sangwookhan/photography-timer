// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import java.util.UUID

/**
 * Reconciles a [TimerAlertPlan] with the OS: schedules one completion alarm
 * per running timer (exact when the permission allows it, inexact
 * allow-while-idle fallback otherwise) via [TimerAlarmScheduling] →
 * [TimerCompletionReceiver] posts the alert + sound at the end instant, even
 * backgrounded — and starts/updates/stops the ongoing foreground service via
 * [TimerForegroundServiceControlling]. Stateful only in the set of currently
 * scheduled timer ids so removed timers' alarms get cancelled. The OS
 * interaction and wall clock are injected (PTIMER-216) so this reconciliation
 * logic is unit-testable without a real AlarmManager; verify on a device too.
 */
class AndroidTimerAlertCoordinator(
    private val availability: ExactAlarmAvailability,
    private val scheduler: TimerAlarmScheduling,
    private val foregroundService: TimerForegroundServiceControlling,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val scheduled = mutableSetOf<UUID>()

    fun sync(plan: TimerAlertPlan) {
        val desiredIds = plan.alarms.map { it.timerId }.toSet()

        // Cancel every stage for timers no longer running.
        (scheduled - desiredIds).forEach { cancelTimerAlarms(it) }
        // Schedule / refresh the desired alarms (one per stage).
        plan.alarms.forEach { scheduleAlarm(it) }
        scheduled.clear()
        scheduled.addAll(desiredIds)

        // Publish the stage sequence so the completion alarm can advance the
        // ongoing notification at the exact end instant (see OngoingAlertRegistry).
        OngoingAlertRegistry.stages = plan.stages

        // Ongoing foreground notification mirrors "any timer running".
        val ongoing = plan.ongoing
        if (ongoing != null) foregroundService.start(ongoing) else foregroundService.stop()
    }

    private fun scheduleAlarm(alarm: CompletionAlarm) {
        // A pre-alert whose instant has already passed (e.g. resuming a long
        // timer with little time left) is dropped so it cannot fire immediately
        // as a stale "Ns remaining". The completion alarm is always scheduled.
        if (alarm.stage != AlertStage.MAIN && alarm.triggerAtEpochMillis <= clock()) {
            return
        }
        val exact = ExactAlarmPolicy.scheduling(availability) == AlarmScheduling.EXACT
        // Exact when the permission allows it; otherwise an inexact
        // allow-while-idle fallback. A permission revoked between the check and
        // the call (TOCTOU) degrades to inexact instead of crashing.
        val succeeded = scheduler.schedule(alarm, exact)
        if (!succeeded) {
            scheduler.schedule(alarm, exact = false)
        }
    }

    private fun cancelTimerAlarms(timerId: UUID) {
        AlertStage.entries.forEach { scheduler.cancel(timerId, it) }
    }

    companion object {
        /**
         * Distinct request code per (timer, stage) so each stage has its own
         * PendingIntent and one timer's pre1/pre2/completion never collide or
         * overwrite each other.
         */
        fun requestCode(timerId: UUID, stage: AlertStage): Int =
            31 * timerId.hashCode() + stage.ordinal
    }
}
