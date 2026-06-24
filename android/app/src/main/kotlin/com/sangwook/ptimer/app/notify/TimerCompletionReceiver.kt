package com.sangwook.ptimer.app.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fired by AlarmManager at a timer's end instant. Posts the completion alert
 * (high-importance channel, default sound) so the photographer hears the timer
 * finish even when the app is backgrounded. Verify on a device.
 */
class TimerCompletionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val timerId = intent.getStringExtra(EXTRA_TIMER_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        TimerNotifications.ensureChannels(context)
        TimerNotifications.notifyCompletion(context, timerId, title)
    }

    companion object {
        const val EXTRA_TIMER_ID = "timer_id"
        const val EXTRA_TITLE = "title"
    }
}
