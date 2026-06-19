package com.sangwook.ptimer.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * NotificationManager-backed notifier: a completion channel (one notification
 * per completed timer) and a low-importance ongoing channel for the
 * representative running timer. Posting is best-effort — if POST_NOTIFICATIONS
 * is not granted it silently no-ops (no crash). A foreground service for
 * guaranteed background countdown is a documented follow-up.
 */
class AndroidTimerNotifier(private val context: Context) : TimerNotifier {

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(
                NotificationChannel(COMPLETION_CHANNEL, "Timer completion", NotificationManager.IMPORTANCE_HIGH),
            )
            mgr.createNotificationChannel(
                NotificationChannel(ONGOING_CHANNEL, "Running timer", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    override fun postCompletion(id: String, name: String, subtitle: String?) {
        // Primary line is the timer identity; the source/subtitle line is shown
        // as the body when present (else a generic completion line on the
        // already-named "Timer completion" channel).
        val body = subtitle?.takeIf { it.isNotBlank() } ?: "Timer complete"
        notify(
            id.hashCode(),
            NotificationCompat.Builder(context, COMPLETION_CHANNEL)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(name)
                .setContentText(body)
                .setAutoCancel(true)
                .build(),
        )
    }

    override fun showOngoing(name: String, remainingLabel: String) {
        notify(
            ONGOING_ID,
            NotificationCompat.Builder(context, ONGOING_CHANNEL)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(name)
                .setContentText(remainingLabel)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build(),
        )
    }

    override fun clearOngoing() {
        NotificationManagerCompat.from(context).cancel(ONGOING_ID)
    }

    private fun notify(id: Int, notification: android.app.Notification) {
        val manager = NotificationManagerCompat.from(context)
        if (manager.areNotificationsEnabled()) {
            try {
                manager.notify(id, notification)
            } catch (_: SecurityException) {
                // POST_NOTIFICATIONS not granted — best-effort, ignore.
            }
        }
    }

    companion object {
        private const val COMPLETION_CHANNEL = "ptimer_completion"
        private const val ONGOING_CHANNEL = "ptimer_ongoing"
        private const val ONGOING_ID = 1
    }
}
