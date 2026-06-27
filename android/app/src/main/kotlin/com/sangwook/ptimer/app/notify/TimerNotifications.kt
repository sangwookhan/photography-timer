// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sangwook.ptimer.MainActivity
import com.sangwook.ptimer.R

/**
 * Notification channels + builders for the timer surfaces. Two channels:
 * a silent low-importance channel for the ongoing foreground-service
 * notification (a persistent, tappable way back into the app), and a
 * high-importance channel with the default sound for the completion alert
 * the AlarmManager fires at a timer's end.
 */
object TimerNotifications {
    const val ONGOING_CHANNEL_ID = "timer_ongoing"
    const val COMPLETION_CHANNEL_ID = "timer_completion"
    const val ONGOING_NOTIFICATION_ID = 1

    /** Intent extra: open the app straight into the (expanded) timer list. */
    const val EXTRA_SHOW_TIMERS = "com.sangwook.ptimer.SHOW_TIMERS"

    /** Intent extra: focus this timer id in the list (the completion that was tapped). */
    const val EXTRA_FOCUS_TIMER_ID = "com.sangwook.ptimer.FOCUS_TIMER_ID"

    /** Creates both channels; idempotent (safe to call on every launch). */
    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                ONGOING_CHANNEL_ID,
                "Running timers",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows while a timer is counting down"
                setSound(null, null)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                COMPLETION_CHANNEL_ID,
                "Timer complete",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Alerts when a timer finishes" },
        )
    }

    /**
     * The ongoing foreground-service notification — the Android lock-screen
     * analogue of the iOS Live Activity. Shows the representative timer name,
     * the "Expected completion {time}" line, and a live count-down chronometer
     * to the representative end (the ticking element). Tapping it opens the
     * timer list.
     */
    fun buildOngoing(context: Context, content: OngoingContent): Notification =
        NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(content.title)
            .setContentText(content.text)
            // Live count-down to the representative timer's end (API 24+).
            .setWhen(content.endAtEpochMillis)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(appContentIntent(context))
            .build()

    /**
     * Posts the completion alert for a finished timer (default sound channel).
     * Identifies the timer so multi-camera completions are distinguishable: a
     * "Timer complete" sub-label, the camera/film [title] ("Camera 2 · No
     * film"), and the shooting source line [body] ("Adjusted shutter · 8
     * stops"). Falls back to "Timer complete" when the identity is missing.
     */
    // Completion can be driven from two paths in the same process: the
    // AlarmManager receiver and the in-app completion detector (for timers that
    // finish while the app is alive, whose alarm the running-set sync may cancel
    // before it fires). Whichever calls first posts; the other is de-duped here,
    // so a short backgrounded timer always rings exactly once.
    private val notifiedTimerIds = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    fun notifyCompletion(context: Context, timerId: String, title: String, body: String) {
        if (!notifiedTimerIds.add(timerId)) return
        val notification = NotificationCompat.Builder(context, COMPLETION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setSubText("Timer complete")
            .setContentTitle(title.ifBlank { "Timer complete" })
            .setContentText(body.ifBlank { null })
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            // Carry the timer id so tapping focuses this finished timer in the list.
            .setContentIntent(appContentIntent(context, focusTimerId = timerId))
            .build()
        // POST_NOTIFICATIONS is requested at the UI layer; guard the post so a
        // denied permission cannot crash the receiver.
        try {
            NotificationManagerCompat.from(context).notify(timerId.hashCode(), notification)
        } catch (_: SecurityException) {
        }
    }

    private fun appContentIntent(context: Context, focusTimerId: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_SHOW_TIMERS, true)
        if (focusTimerId != null) intent.putExtra(EXTRA_FOCUS_TIMER_ID, focusTimerId)
        // A distinct request code per focus target so each completion notification
        // keeps its own intent; a shared code with FLAG_UPDATE_CURRENT would
        // collapse them all onto the last-posted timer.
        val requestCode = focusTimerId?.hashCode() ?: 0
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
