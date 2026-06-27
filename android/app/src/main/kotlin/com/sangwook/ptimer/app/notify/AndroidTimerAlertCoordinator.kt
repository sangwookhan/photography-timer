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
        val desired = plan.alarms.associateBy { it.timerId }

        // Cancel alarms for timers no longer running.
        (scheduled - desired.keys).forEach { cancelAlarm(it) }
        // Schedule / refresh the desired alarms.
        desired.values.forEach { scheduleAlarm(it) }
        scheduled.clear()
        scheduled.addAll(desired.keys)

        // Publish the stage sequence so the completion alarm can advance the
        // ongoing notification at the exact end instant (see OngoingAlertRegistry).
        OngoingAlertRegistry.stages = plan.stages

        // Ongoing foreground notification mirrors "any timer running".
        val ongoing = plan.ongoing
        if (ongoing != null) TimerForegroundService.start(context, ongoing) else TimerForegroundService.stop(context)
    }

    private fun scheduleAlarm(alarm: CompletionAlarm) {
        val pending = pendingIntent(alarm.timerId, alarm.title, alarm.subtitle, create = true) ?: return
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

    private fun cancelAlarm(timerId: UUID) {
        pendingIntent(timerId, title = "", subtitle = "", create = false)?.let { alarmManager.cancel(it) }
    }

    private fun pendingIntent(timerId: UUID, title: String, subtitle: String, create: Boolean): PendingIntent? {
        val intent = Intent(context, TimerCompletionReceiver::class.java)
            .putExtra(TimerCompletionReceiver.EXTRA_TIMER_ID, timerId.toString())
            .putExtra(TimerCompletionReceiver.EXTRA_TITLE, title)
            .putExtra(TimerCompletionReceiver.EXTRA_SUBTITLE, subtitle)
        val flags = (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE) or
            PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, timerId.hashCode(), intent, flags)
    }
}
