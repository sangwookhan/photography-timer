package com.sangwook.ptimer.app.notify

import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.timer.TimerStatus
import java.util.UUID

/** One exact completion alarm to fire at a running timer's end instant. */
data class CompletionAlarm(
    val timerId: UUID,
    val triggerAtEpochMillis: Long,
    val title: String,
)

/**
 * Content for the ongoing foreground-service notification — the Android
 * lock-screen analogue of the iOS Live Activity. [endAtEpochMillis] is the
 * representative (soonest) running timer's end instant, used to drive a live
 * count-down chronometer on the notification.
 */
data class OngoingContent(val title: String, val text: String, val endAtEpochMillis: Long)

/**
 * Desired notification side-effects derived purely from the workspace state:
 * one exact completion alarm per running timer (AlarmManager fires the
 * sound/alert at the end instant even if the app is backgrounded), plus the
 * ongoing foreground-service content while any timer is running (a persistent,
 * tappable way back into the app). `ongoing == null` means stop the service.
 */
data class TimerAlertPlan(
    val alarms: List<CompletionAlarm>,
    val ongoing: OngoingContent?,
)

/**
 * Pure mapping from active timers → [TimerAlertPlan]. Only running timers get
 * a completion alarm (a paused timer has no fixed end). The ongoing content
 * summarises how many timers are running and when the soonest one ends.
 */
object TimerAlertPlanner {
    fun plan(active: List<TimerCardState>, formatClock: (Long) -> String): TimerAlertPlan {
        val running = active.filter { it.status == TimerStatus.running }
        val alarms = running.map {
            CompletionAlarm(
                timerId = it.id,
                triggerAtEpochMillis = it.endDate.toEpochMilli(),
                title = it.identity.title,
            )
        }
        val ongoing = if (running.isEmpty()) {
            null
        } else {
            val soonest = running.minByOrNull { it.endDate }!!
            val endMillis = soonest.endDate.toEpochMilli()
            val count = running.size
            // iOS Live Activity wording: "Expected completion {time}", plus a
            // count suffix when more than one timer is running.
            val text = if (count == 1) {
                "Expected completion ${formatClock(endMillis)}"
            } else {
                "Expected completion ${formatClock(endMillis)} · $count timers"
            }
            OngoingContent(
                title = soonest.identity.title,
                text = text,
                endAtEpochMillis = endMillis,
            )
        }
        return TimerAlertPlan(alarms, ongoing)
    }
}
