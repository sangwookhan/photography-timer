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
    fun notifyCompletion(context: Context, timerId: String, title: String, body: String) {
        val notification = NotificationCompat.Builder(context, COMPLETION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setSubText("Timer complete")
            .setContentTitle(title.ifBlank { "Timer complete" })
            .setContentText(body.ifBlank { null })
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setContentIntent(appContentIntent(context))
            .build()
        // POST_NOTIFICATIONS is requested at the UI layer; guard the post so a
        // denied permission cannot crash the receiver.
        try {
            NotificationManagerCompat.from(context).notify(timerId.hashCode(), notification)
        } catch (_: SecurityException) {
        }
    }

    private fun appContentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_SHOW_TIMERS, true)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
