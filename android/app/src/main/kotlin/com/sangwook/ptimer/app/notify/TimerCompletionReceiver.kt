package com.sangwook.ptimer.app.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fired by AlarmManager at a timer's end instant. Posts the completion alert
 * (high-importance channel, default sound) so the photographer hears the timer
 * finish even when the app is backgrounded, and advances the ongoing
 * notification to the next representative (or clears it) right then — so the
 * live count-down swaps at the exact end instead of waiting for the background-
 * throttled in-app tick, and never shows a negative value. Verify on a device.
 */
class TimerCompletionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val timerId = intent.getStringExtra(EXTRA_TIMER_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val subtitle = intent.getStringExtra(EXTRA_SUBTITLE).orEmpty()
        TimerNotifications.ensureChannels(context)
        TimerNotifications.notifyCompletion(context, timerId, title, subtitle)

        // Swap the ongoing to the soonest timer still in the future (the new
        // representative), or stop the service when none remain. Exact alarms
        // grant a temporary allowance to (re)start the foreground service.
        val now = System.currentTimeMillis()
        val next = OngoingAlertRegistry.stages.firstOrNull { it.endMillis > now }
        if (next == null) {
            TimerForegroundService.stop(context)
        } else {
            TimerForegroundService.start(context, next.content)
        }
    }

    companion object {
        const val EXTRA_TIMER_ID = "timer_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
    }
}
