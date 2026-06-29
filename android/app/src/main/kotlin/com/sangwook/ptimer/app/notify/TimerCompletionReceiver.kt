// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner

/**
 * Fired by AlarmManager at a timer's staged-alert instant (PTIMER-73).
 *
 * - [AlertStage.MAIN] posts the completion alert (high-importance channel,
 *   default sound) so the photographer hears the timer finish even when
 *   backgrounded, and advances the ongoing notification to the next
 *   representative (or clears it) right then — so the live count-down swaps at
 *   the exact end instead of waiting for the background-throttled in-app tick.
 * - [AlertStage.PRE1] / [AlertStage.PRE2] post a haptic-first "Ns remaining"
 *   pre-alert and vibrate. pre2 is suppressed while the app is in the
 *   foreground (see [StagedAlertPolicy.shouldDeliver]); pre-alerts never touch
 *   the ongoing service. Verify on a device.
 */
class TimerCompletionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val timerId = intent.getStringExtra(EXTRA_TIMER_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val subtitle = intent.getStringExtra(EXTRA_SUBTITLE).orEmpty()
        val stage = runCatching {
            AlertStage.valueOf(intent.getStringExtra(EXTRA_STAGE) ?: AlertStage.MAIN.name)
        }.getOrDefault(AlertStage.MAIN)

        TimerNotifications.ensureChannels(context)

        if (stage != AlertStage.MAIN) {
            if (!StagedAlertPolicy.shouldDeliver(stage, isAppForeground = isAppForeground())) {
                return
            }
            val secondsRemaining = intent.getIntExtra(EXTRA_SECONDS_REMAINING, 0)
            TimerNotifications.notifyPreAlert(context, timerId, stage, secondsRemaining, title)
            TimerVibration.vibrate(context, stage)
            return
        }

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

    private fun isAppForeground(): Boolean =
        ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)

    companion object {
        const val EXTRA_TIMER_ID = "timer_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_STAGE = "stage"
        const val EXTRA_SECONDS_REMAINING = "seconds_remaining"
    }
}
