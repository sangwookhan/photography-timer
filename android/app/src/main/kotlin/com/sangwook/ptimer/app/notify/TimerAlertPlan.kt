// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.timer.TimerStatus
import java.util.UUID

/**
 * The staged alert a scheduled alarm represents (PTIMER-73). [PRE1] and [PRE2]
 * are pre-alerts that fire before completion; [MAIN] is the completion alert at
 * the timer's end instant.
 */
enum class AlertStage { PRE1, PRE2, MAIN }

/**
 * One scheduled alert for a running timer. [triggerAtEpochMillis] is the
 * instant it fires (the end instant for [AlertStage.MAIN], earlier for
 * pre-alerts). [secondsBeforeCompletion] is how many seconds remain to
 * completion at that instant (0 for [AlertStage.MAIN]), driving pre-alert copy
 * such as "10s remaining". [title] is the camera/film identity ("Camera 2 · No
 * film") and [subtitle] the shooting source line ("Adjusted shutter · 8
 * stops"), so the notification can identify which timer and source it concerns.
 */
data class CompletionAlarm(
    val timerId: UUID,
    val triggerAtEpochMillis: Long,
    val title: String,
    val subtitle: String,
    val stage: AlertStage = AlertStage.MAIN,
    val secondsBeforeCompletion: Int = 0,
)

/** One pre-alert stage and its lead time, before any specific timer is bound. */
data class PreAlertSpec(val stage: AlertStage, val secondsBeforeCompletion: Int)

/**
 * Pure, platform-neutral staged-alert policy shared by the planner and the
 * receiver (PTIMER-73). Mirrors the iOS `TimerAlertSchedule` buckets:
 * - `duration <= 30s` — completion only.
 * - `30s < duration <= 60s` — pre1 at T−5s.
 * - `duration > 60s` — pre1 at T−10s, pre2 at T−5s.
 */
object StagedAlertPolicy {
    const val PRE_ALERT_MIN_DURATION_SECONDS = 30.0
    const val SECOND_PRE_ALERT_MIN_DURATION_SECONDS = 60.0

    fun preAlerts(durationSeconds: Double): List<PreAlertSpec> = when {
        durationSeconds > SECOND_PRE_ALERT_MIN_DURATION_SECONDS ->
            listOf(PreAlertSpec(AlertStage.PRE1, 10), PreAlertSpec(AlertStage.PRE2, 5))
        durationSeconds > PRE_ALERT_MIN_DURATION_SECONDS ->
            listOf(PreAlertSpec(AlertStage.PRE1, 5))
        else -> emptyList()
    }

    /**
     * pre2 is the not-foreground-only escalation: it must never surface while
     * the app is in the foreground. Every other stage delivers regardless.
     */
    fun shouldDeliver(stage: AlertStage, isAppForeground: Boolean): Boolean =
        !(stage == AlertStage.PRE2 && isAppForeground)

    /**
     * Whether a stage posts on the visible (heads-up) alert channel: the main
     * completion alert and the stronger pre2 escalation. pre1 stays on the
     * silent pre-alert channel.
     */
    fun usesAlertChannel(stage: AlertStage): Boolean =
        stage == AlertStage.MAIN || stage == AlertStage.PRE2

    /**
     * Whether a stage should play the direct, alarm-stream alarm sound (alarm
     * volume, so it stays audible in vibrate mode): the main completion always, and
     * pre2 only when the app is not in the foreground. pre1 is silent
     * (haptic-first), and a foreground pre2 is suppressed entirely.
     */
    fun shouldPlayAlarm(stage: AlertStage, isAppForeground: Boolean): Boolean =
        usesAlertChannel(stage) && shouldDeliver(stage, isAppForeground)
}

/**
 * Content for the ongoing foreground-service notification — the Android
 * lock-screen analogue of the iOS Live Activity. [endAtEpochMillis] is the
 * representative (soonest) running timer's end instant, used to drive a live
 * count-down chronometer on the notification.
 */
data class OngoingContent(val title: String, val text: String, val endAtEpochMillis: Long)

/**
 * The ongoing content to show once [endMillis] is the soonest still-running
 * timer's end (i.e. every earlier-ending timer has completed). The completion
 * alarm uses these to swap/clear the ongoing notification at the exact end
 * instant, so the live count-down never has to wait for the (background-
 * throttled) in-app tick and never shows a negative value.
 */
data class OngoingStage(val endMillis: Long, val content: OngoingContent)

/**
 * Desired notification side-effects derived purely from the workspace state:
 * one completion alarm per running timer, exact when permitted and inexact
 * as fallback (AlarmManager fires the sound/alert at the end instant even
 * if the app is backgrounded), plus the
 * ongoing foreground-service content while any timer is running (a persistent,
 * tappable way back into the app). `ongoing == null` means stop the service.
 * [stages] is the ordered sequence the ongoing should pass through as timers
 * complete, so the completion alarm can advance it without re-reading state.
 */
data class TimerAlertPlan(
    val alarms: List<CompletionAlarm>,
    val ongoing: OngoingContent?,
    val stages: List<OngoingStage> = emptyList(),
)

/**
 * Pure mapping from active timers → [TimerAlertPlan]. Only running timers get
 * a completion alarm (a paused timer has no fixed end). The ongoing content
 * summarises how many timers are running and when the soonest one ends.
 */
object TimerAlertPlanner {
    fun plan(active: List<TimerCardState>, formatClock: (Long) -> String): TimerAlertPlan {
        val running = active.filter { it.status == TimerStatus.running }
        val mainAlarms = running.map {
            CompletionAlarm(
                timerId = it.id,
                triggerAtEpochMillis = it.endDate.toEpochMilli(),
                title = it.identity.title,
                subtitle = it.identity.subtitle,
                stage = AlertStage.MAIN,
                secondsBeforeCompletion = 0,
            )
        }
        // Pre-alerts (PTIMER-73) fire before the end instant per the duration
        // bucket. They are scheduled but do not participate in the ongoing /
        // stage sequence, which tracks completions only.
        val preAlarms = running.flatMap { card ->
            val endMillis = card.endDate.toEpochMilli()
            StagedAlertPolicy.preAlerts(card.durationSeconds).map { spec ->
                CompletionAlarm(
                    timerId = card.id,
                    triggerAtEpochMillis = endMillis - spec.secondsBeforeCompletion * 1_000L,
                    title = card.identity.title,
                    subtitle = card.identity.subtitle,
                    stage = spec.stage,
                    secondsBeforeCompletion = spec.secondsBeforeCompletion,
                )
            }
        }
        // One stage per timer, ordered by end. Stage i is the ongoing content
        // while timer i is representative — every earlier-ending timer has gone,
        // so the still-running set is the suffix from i onward.
        val sorted = mainAlarms.sortedBy { it.triggerAtEpochMillis }
        val stages = sorted.indices.map { i ->
            OngoingStage(sorted[i].triggerAtEpochMillis, ongoingFor(sorted.subList(i, sorted.size), formatClock)!!)
        }
        return TimerAlertPlan(mainAlarms + preAlarms, ongoingFor(mainAlarms, formatClock), stages)
    }

    /** The ongoing content for a given set of still-running timers, or null when empty. */
    private fun ongoingFor(running: List<CompletionAlarm>, formatClock: (Long) -> String): OngoingContent? {
        if (running.isEmpty()) return null
        val soonest = running.minByOrNull { it.triggerAtEpochMillis }!!
        val endMillis = soonest.triggerAtEpochMillis
        val count = running.size
        // iOS Live Activity wording: "Expected completion {time}", plus a
        // count suffix when more than one timer is running.
        val text = if (count == 1) {
            "Expected completion ${formatClock(endMillis)}"
        } else {
            "Expected completion ${formatClock(endMillis)} · $count timers"
        }
        return OngoingContent(title = soonest.title, text = text, endAtEpochMillis = endMillis)
    }
}

/**
 * Process-wide latest ongoing [OngoingStage] sequence, written by the alert
 * coordinator on every sync and read by [TimerCompletionReceiver] when a
 * completion alarm fires. Lets the receiver advance the ongoing notification
 * to the next representative (or clear it) at the exact end instant without
 * re-deriving workspace state. Empty after a cold start (process killed); the
 * receiver then just clears, and the next app launch re-syncs.
 */
object OngoingAlertRegistry {
    @Volatile
    var stages: List<OngoingStage> = emptyList()
}
