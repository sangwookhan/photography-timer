package com.sangwook.ptimer.timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.sangwook.ptimer.notifications.AndroidTimerNotifier

/**
 * Fires when a scheduled completion alarm goes off (possibly with the app
 * process dead). It posts the completion notification straight from the
 * immutable identity carried in the intent — it never reads live ViewModel
 * state — so the notification is correct regardless of what the app is doing.
 */
class CompletionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Timer"
        AndroidTimerNotifier(context.applicationContext).postCompletion(id, title)
    }

    companion object {
        const val ACTION = "com.sangwook.ptimer.TIMER_COMPLETION"
        const val EXTRA_ID = "timer_id"
        const val EXTRA_TITLE = "timer_title"
        const val EXTRA_SUBTITLE = "timer_subtitle"
    }
}
