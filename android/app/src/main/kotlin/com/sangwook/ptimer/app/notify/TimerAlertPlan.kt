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
 * The ongoing content to show once [endMillis] is the soonest still-running
 * timer's end (i.e. every earlier-ending timer has completed). The completion
 * alarm uses these to swap/clear the ongoing notification at the exact end
 * instant, so the live count-down never has to wait for the (background-
 * throttled) in-app tick and never shows a negative value.
 */
data class OngoingStage(val endMillis: Long, val content: OngoingContent)

/**
 * Desired notification side-effects derived purely from the workspace state:
 * one exact completion alarm per running timer (AlarmManager fires the
 * sound/alert at the end instant even if the app is backgrounded), plus the
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
        val alarms = running.map {
            CompletionAlarm(
                timerId = it.id,
                triggerAtEpochMillis = it.endDate.toEpochMilli(),
                title = it.identity.title,
            )
        }
        // One stage per timer, ordered by end. Stage i is the ongoing content
        // while timer i is representative — every earlier-ending timer has gone,
        // so the still-running set is the suffix from i onward.
        val sorted = alarms.sortedBy { it.triggerAtEpochMillis }
        val stages = sorted.indices.map { i ->
            OngoingStage(sorted[i].triggerAtEpochMillis, ongoingFor(sorted.subList(i, sorted.size), formatClock)!!)
        }
        return TimerAlertPlan(alarms, ongoingFor(alarms, formatClock), stages)
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
