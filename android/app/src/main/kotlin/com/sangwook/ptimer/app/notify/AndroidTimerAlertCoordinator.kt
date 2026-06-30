// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.UUID

/**
 * Reconciles a [TimerAlertPlan] with the OS: schedules one completion
 * AlarmManager alarm per running timer (exact when the permission allows it,
 * inexact allow-while-idle fallback otherwise) → [TimerCompletionReceiver]
 * posts the alert + sound at the end instant, even backgrounded — and
 * starts/updates/stops the ongoing [TimerForegroundService]. Stateful only in
 * the set of currently scheduled timer ids so removed timers' alarms get
 * cancelled. Verify on a device.
 */
class AndroidTimerAlertCoordinator(
    private val context: Context,
    private val availability: ExactAlarmAvailability = AndroidExactAlarmAvailability(context),
) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
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
        if (ongoing != null) TimerForegroundService.start(context, ongoing) else TimerForegroundService.stop(context)
    }

    private fun scheduleAlarm(alarm: CompletionAlarm) {
        // A pre-alert whose instant has already passed (e.g. resuming a long
        // timer with little time left) is dropped so it cannot fire immediately
        // as a stale "Ns remaining". The completion alarm is always scheduled.
        if (alarm.stage != AlertStage.MAIN && alarm.triggerAtEpochMillis <= System.currentTimeMillis()) {
            return
        }
        val pending = pendingIntent(alarm, create = true) ?: return
        val exact = ExactAlarmPolicy.scheduling(availability) == AlarmScheduling.EXACT
        // Exact when the permission allows it; otherwise an inexact
        // allow-while-idle fallback. Wrapped so a permission revoked between the
        // check and the call (TOCTOU) degrades to inexact instead of crashing.
        val scheduled = runCatching {
            if (exact) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.triggerAtEpochMillis, pending)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.triggerAtEpochMillis, pending)
            }
        }
        if (scheduled.isFailure) {
            runCatching { alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.triggerAtEpochMillis, pending) }
        }
    }

    private fun cancelTimerAlarms(timerId: UUID) {
        AlertStage.entries.forEach { stage ->
            pendingIntent(timerId, stage, create = false)?.let { alarmManager.cancel(it) }
        }
    }

    private fun pendingIntent(alarm: CompletionAlarm, create: Boolean): PendingIntent? =
        pendingIntent(
            timerId = alarm.timerId,
            stage = alarm.stage,
            create = create,
            title = alarm.title,
            subtitle = alarm.subtitle,
            secondsBeforeCompletion = alarm.secondsBeforeCompletion,
        )

    private fun pendingIntent(
        timerId: UUID,
        stage: AlertStage,
        create: Boolean,
        title: String = "",
        subtitle: String = "",
        secondsBeforeCompletion: Int = 0,
    ): PendingIntent? {
        val intent = Intent(context, TimerCompletionReceiver::class.java)
            .putExtra(TimerCompletionReceiver.EXTRA_TIMER_ID, timerId.toString())
            .putExtra(TimerCompletionReceiver.EXTRA_TITLE, title)
            .putExtra(TimerCompletionReceiver.EXTRA_SUBTITLE, subtitle)
            .putExtra(TimerCompletionReceiver.EXTRA_STAGE, stage.name)
            .putExtra(TimerCompletionReceiver.EXTRA_SECONDS_REMAINING, secondsBeforeCompletion)
        val flags = (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE) or
            PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, requestCode(timerId, stage), intent, flags)
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
