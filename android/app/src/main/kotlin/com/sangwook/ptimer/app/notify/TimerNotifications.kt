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
 * Notification channels + builders for the timer surfaces. Three channels:
 * a silent low-importance channel for the ongoing foreground-service
 * notification, a silent channel for the haptic-first pre1 pre-alert, and a
 * high-importance (visible/heads-up) but **silent** alert channel for the
 * completion and the stronger pre2 escalation.
 *
 * The alert channel is deliberately silent: its audio is produced directly by
 * [AndroidTimerAlarmPlayer] on the alarm stream (`USAGE_ALARM`), which is loud
 * in vibrate mode and bypasses Do-Not-Disturb — a notification-channel sound
 * cannot be relied on for that (PTIMER-73).
 */
object TimerNotifications {
    const val ONGOING_CHANNEL_ID = "timer_ongoing"
    // Visible-but-silent alert channel. A fresh id (the legacy sounding channels
    // are deleted in ensureChannels) because a channel's sound is immutable once
    // created — the silent definition only takes effect on a channel the OS has
    // not seen before.
    const val ALERT_CHANNEL_ID = "timer_alert"
    const val PRE_ALERT_CHANNEL_ID = "timer_pre_alert"
    const val ONGOING_NOTIFICATION_ID = 1

    private const val LEGACY_COMPLETION_CHANNEL_ID = "timer_completion"
    private const val LEGACY_ALARM_CHANNEL_ID = "timer_alarm"

    /** Intent extra: open the app straight into the (expanded) timer list. */
    const val EXTRA_SHOW_TIMERS = "com.sangwook.ptimer.SHOW_TIMERS"

    /** Intent extra: focus this timer id in the list (the completion that was tapped). */
    const val EXTRA_FOCUS_TIMER_ID = "com.sangwook.ptimer.FOCUS_TIMER_ID"

    /** Creates the channels; idempotent (safe to call on every launch). */
    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        // Drop the legacy sounding channels: completion sound on the
        // notification stream was silenced in vibrate mode, and the alarm-stream
        // channel double-sounded with the direct player. Audio now comes solely
        // from AndroidTimerAlarmPlayer.
        manager.deleteNotificationChannel(LEGACY_COMPLETION_CHANNEL_ID)
        manager.deleteNotificationChannel(LEGACY_ALARM_CHANNEL_ID)
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
        // Completion + the stronger pre2 escalation: a high-importance, visible
        // (heads-up) but SILENT channel. The audible alarm is played directly by
        // AndroidTimerAlarmPlayer on the alarm stream, so the channel itself must
        // not sound (it would double up).
        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "Timer alarm",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Shows a finished timer; the alarm sound plays on the alarm volume"
                setSound(null, null)
                enableVibration(false)
            },
        )
        // pre1 is haptic-first: a silent channel (we drive vibration ourselves in
        // TimerVibration) so "10s remaining" never competes with the alarm.
        manager.createNotificationChannel(
            NotificationChannel(
                PRE_ALERT_CHANNEL_ID,
                "Timer pre-alerts",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Vibrates as a timer is about to finish"
                setSound(null, null)
                enableVibration(false)
            },
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
        // Sound the audible alarm here — at the same de-duped point as the
        // notification — so completion is loud whether it fired from the
        // AlarmManager receiver (backgrounded) or the in-app detector
        // (foreground, where the receiver's alarm is cancelled by the
        // running-set sync). Exactly once per timer either way.
        AndroidTimerAlarmPlayer.playAlarm(context)
        val notification = NotificationCompat.Builder(context, ALERT_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setSubText("Timer complete")
            .setContentTitle(title.ifBlank { "Timer complete" })
            .setContentText(body.ifBlank { null })
            .setAutoCancel(true)
            // The channel is silent; the audible alarm is played directly by
            // AndroidTimerAlarmPlayer on the alarm stream (loud in vibrate mode,
            // bypasses Do-Not-Disturb).
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

    /**
     * Posts a "Ns remaining" pre-alert (PTIMER-73). pre1 goes on the silent
     * pre-alert channel (haptic-first; vibration driven by TimerVibration). pre2
     * is the stronger escalation and goes on the visible alert channel; its
     * audible alarm is played directly by AndroidTimerAlarmPlayer (it is only
     * ever delivered when the app is not in the foreground; see
     * StagedAlertPolicy.shouldDeliver). A distinct notification id per timer +
     * stage keeps pre1, pre2, and completion separate, and the notification
     * auto-dismisses shortly after the timer would complete so a stale
     * "Ns remaining" never lingers. The copy communicates remaining time only;
     * it never implies stopping exposure before completion.
     */
    fun notifyPreAlert(
        context: Context,
        timerId: String,
        stage: AlertStage,
        secondsRemaining: Int,
        title: String,
    ) {
        val channelId = if (StagedAlertPolicy.usesAlertChannel(stage)) ALERT_CHANNEL_ID else PRE_ALERT_CHANNEL_ID
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setSubText(title.ifBlank { "Timer" })
            .setContentTitle("${secondsRemaining}s remaining")
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setTimeoutAfter(secondsRemaining * 1_000L + 2_000L)
            .setContentIntent(appContentIntent(context, focusTimerId = timerId))
            .build()
        try {
            NotificationManagerCompat.from(context).notify(preAlertNotificationId(timerId, stage), notification)
        } catch (_: SecurityException) {
        }
    }

    private fun preAlertNotificationId(timerId: String, stage: AlertStage): Int =
        31 * timerId.hashCode() + stage.ordinal + 1

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
