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
 * - [AlertStage.MAIN] posts the (silent) completion notification and plays the
 *   audible alarm directly on the alarm stream via [AndroidTimerAlarmPlayer] —
 *   loud in vibrate mode and past Do-Not-Disturb — so the photographer hears the
 *   timer finish even when backgrounded. It also advances the ongoing
 *   notification to the next representative (or clears it) right then.
 * - [AlertStage.PRE1] posts a haptic-first "Ns remaining" pre-alert on the
 *   silent channel and vibrates. [AlertStage.PRE2] is the stronger escalation:
 *   it plays the audible alarm and is suppressed while the app is in the
 *   foreground (see [StagedAlertPolicy.shouldDeliver]). pre-alerts never touch
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

        val foreground = isAppForeground()

        if (stage != AlertStage.MAIN) {
            if (!StagedAlertPolicy.shouldDeliver(stage, isAppForeground = foreground)) {
                return
            }
            val secondsRemaining = intent.getIntExtra(EXTRA_SECONDS_REMAINING, 0)
            TimerNotifications.notifyPreAlert(context, timerId, stage, secondsRemaining, title)
            if (StagedAlertPolicy.shouldPlayAlarm(stage, isAppForeground = foreground)) {
                // pre2 (not foreground): the stronger escalation is the audible
                // alarm itself.
                AndroidTimerAlarmPlayer.playAlarm(context)
            } else if (stage == AlertStage.PRE1) {
                // pre1 is haptic-first and silent.
                TimerVibration.vibrate(context, stage)
            }
            return
        }

        // notifyCompletion plays the audible alarm itself (de-duped), covering
        // both this receiver and the in-app foreground completion path.
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
