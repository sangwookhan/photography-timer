package com.sangwook.ptimer.timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.sangwook.ptimer.core.timer.PersistentTimerSnapshot

/**
 * AlarmManager-backed completion scheduler. The stable timer id is the
 * PendingIntent request key, and only immutable identity (id/title/subtitle) is
 * encoded into the intent, so the [CompletionAlarmReceiver] is independent of
 * live app state.
 *
 * Reliability is best-effort and honestly bounded:
 * - On API < 31 (Android 11 and below) it uses `setExactAndAllowWhileIdle`
 *   (exact, Doze-aware, no special permission).
 * - On API 31+ it uses exact scheduling only when `canScheduleExactAlarms()` is
 *   already true; this pass does NOT request `SCHEDULE_EXACT_ALARM`, so by
 *   default it falls back to `setAndAllowWhileIdle` (inexact but Doze-aware).
 * - OEM background restrictions / aggressive task-killers can still suppress or
 *   delay delivery. A foreground service and/or an exact-alarm permission flow
 *   remain a documented follow-up.
 * All scheduling is wrapped so it can never crash the timer workflow.
 */
class AndroidTimerCompletionScheduler(context: Context) : TimerCompletionScheduler {

    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)

    override fun schedule(snapshot: PersistentTimerSnapshot, title: String, subtitle: String) {
        val triggerAtMs = snapshot.expectedCompletionAt?.toEpochMilli() ?: return
        val manager = alarmManager ?: return
        val pendingIntent = PendingIntent.getBroadcast(
            appContext,
            snapshot.id.hashCode(),
            intentFor(snapshot.id, title, subtitle),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val exactAllowed =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        runCatching {
            if (exactAllowed) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            }
        }.onFailure {
            // e.g. SecurityException if exact is revoked between check and call.
            runCatching { manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent) }
        }
    }

    override fun cancel(timerId: String) {
        val manager = alarmManager ?: return
        val existing = PendingIntent.getBroadcast(
            appContext,
            timerId.hashCode(),
            intentFor(timerId, "", ""),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        runCatching { manager.cancel(existing); existing.cancel() }
    }

    override fun cancelAll(timerIds: Collection<String>) = timerIds.forEach { cancel(it) }

    private fun intentFor(id: String, title: String, subtitle: String) =
        Intent(appContext, CompletionAlarmReceiver::class.java).apply {
            action = CompletionAlarmReceiver.ACTION
            putExtra(CompletionAlarmReceiver.EXTRA_ID, id)
            putExtra(CompletionAlarmReceiver.EXTRA_TITLE, title)
            putExtra(CompletionAlarmReceiver.EXTRA_SUBTITLE, subtitle)
        }
}
