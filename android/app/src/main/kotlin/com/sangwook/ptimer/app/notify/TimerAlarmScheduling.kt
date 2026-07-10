// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.UUID

/**
 * OS alarm-scheduling seam for [AndroidTimerAlertCoordinator] (PTIMER-216):
 * wraps the AlarmManager + PendingIntent calls the coordinator needs, so its
 * reconciliation logic (which stages to schedule/cancel, exact-vs-inexact
 * fallback) is unit-testable through a fake without touching AlarmManager.
 */
interface TimerAlarmScheduling {
    /**
     * Schedules [alarm] exact-and-allow-while-idle when [exact], else
     * inexact-allow-while-idle. Returns false if the OS call throws (e.g. the
     * exact-alarm permission was revoked between the check and the call), so
     * the caller can retry as inexact.
     */
    fun schedule(alarm: CompletionAlarm, exact: Boolean): Boolean

    /** Cancels the given timer's alarm for [stage], if one is currently scheduled. */
    fun cancel(timerId: UUID, stage: AlertStage)
}

/** Production [TimerAlarmScheduling] backed by [AlarmManager] + [PendingIntent]. */
class AndroidTimerAlarmScheduling(private val context: Context) : TimerAlarmScheduling {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    override fun schedule(alarm: CompletionAlarm, exact: Boolean): Boolean {
        val pending = pendingIntent(alarm, create = true) ?: return true
        return runCatching {
            if (exact) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.triggerAtEpochMillis, pending)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.triggerAtEpochMillis, pending)
            }
        }.isSuccess
    }

    override fun cancel(timerId: UUID, stage: AlertStage) {
        pendingIntent(timerId, stage, create = false)?.let { alarmManager.cancel(it) }
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
        return PendingIntent.getBroadcast(
            context,
            AndroidTimerAlertCoordinator.requestCode(timerId, stage),
            intent,
            flags,
        )
    }
}
