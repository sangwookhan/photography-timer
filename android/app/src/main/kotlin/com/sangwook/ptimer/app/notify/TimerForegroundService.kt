package com.sangwook.ptimer.app.notify

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/**
 * Foreground service that holds the ongoing "timer running" notification while
 * at least one timer is counting down. Started/updated with the latest
 * [OngoingContent] and stopped when no timer is running. The persistent
 * notification gives the photographer a tappable way back into the app from
 * anywhere. Verify on a device (see the unit-12 device-test checklist).
 */
class TimerForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
        val endAt = intent?.getLongExtra(EXTRA_END, 0L) ?: 0L
        TimerNotifications.ensureChannels(this)
        // ServiceCompat with an explicit FGS type is required on API 34+;
        // passing the type also avoids the silent startForeground failures some
        // OEMs exhibit when the type is left implicit.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(
            this,
            TimerNotifications.ONGOING_NOTIFICATION_ID,
            TimerNotifications.buildOngoing(this, OngoingContent(title, text, endAt)),
            type,
        )
        return START_STICKY
    }

    companion object {
        private const val ACTION_STOP = "com.sangwook.ptimer.action.STOP_TIMER_SERVICE"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_END = "endAtEpochMillis"

        fun start(context: Context, content: OngoingContent) {
            val intent = Intent(context, TimerForegroundService::class.java)
                .putExtra(EXTRA_TITLE, content.title)
                .putExtra(EXTRA_TEXT, content.text)
                .putExtra(EXTRA_END, content.endAtEpochMillis)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, TimerForegroundService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
