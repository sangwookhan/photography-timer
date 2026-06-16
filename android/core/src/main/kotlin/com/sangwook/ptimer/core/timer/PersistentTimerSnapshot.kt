package com.sangwook.ptimer.core.timer

import java.time.Instant

/**
 * Per-timer runtime snapshot. Restore reconciles running timers against
 * wall clock, keeps paused timers frozen, and surfaces a corrupt paused
 * snapshot (missing freeze metadata) as completed without fabricating a
 * timestamp. Mirrors iOS `PersistentTimerSnapshot`.
 *
 * Times are modeled as `Instant`; the app DataStore layer maps these to a
 * serializable form. The decoder accepts the legacy "stopped" token as
 * paused.
 */
data class PersistentTimerSnapshot(
    val id: String,
    val status: SnapshotStatus,
    val durationSeconds: Double,
    val startDate: Instant,
    val expectedCompletionAt: Instant?,
    val pausedRemainingDuration: Double?,
    val pausedAt: Instant?,
    val completedAt: Instant?,
) {
    enum class SnapshotStatus(val token: String) {
        RUNNING("running"),
        PAUSED("paused"),
        COMPLETED("completed");

        companion object {
            /** Backward-compatible: "stopped" decodes to PAUSED. */
            fun fromToken(token: String): SnapshotStatus = when (token) {
                "running" -> RUNNING
                "paused", "stopped" -> PAUSED
                "completed" -> COMPLETED
                else -> throw IllegalArgumentException("Unsupported snapshot status: $token")
            }
        }
    }

    fun restore(now: Instant): TimerState = when (status) {
        SnapshotStatus.RUNNING -> {
            val expected = expectedCompletionAt
            when {
                expected == null -> makeCompleted(now)
                secondsBetween(now, expected) <= TIMER_STABILITY_EPSILON -> makeCompleted(expected)
                else -> TimerState.Running(id, durationSeconds, startDate, expected)
            }
        }
        SnapshotStatus.PAUSED -> {
            val at = pausedAt
            val remaining = pausedRemainingDuration
            if (at == null || remaining == null) {
                makeCompleted(completedAt)
            } else {
                TimerState.Paused(id, durationSeconds, startDate, remaining, at)
            }
        }
        SnapshotStatus.COMPLETED -> makeCompleted(completedAt)
    }

    private fun makeCompleted(completionDate: Instant?): TimerState =
        TimerState.Completed(
            id = id,
            durationSeconds = durationSeconds,
            startDate = startDate,
            completedAt = completionDate
                ?: expectedCompletionAt
                ?: pausedAt
                ?: startDate.plusSeconds(durationSeconds),
        )

    companion object {
        fun fromTimer(timer: TimerState): PersistentTimerSnapshot = when (timer) {
            is TimerState.Running -> PersistentTimerSnapshot(
                id = timer.id, status = SnapshotStatus.RUNNING, durationSeconds = timer.durationSeconds,
                startDate = timer.startDate, expectedCompletionAt = timer.endDate,
                pausedRemainingDuration = null, pausedAt = null, completedAt = null,
            )
            is TimerState.Paused -> PersistentTimerSnapshot(
                id = timer.id, status = SnapshotStatus.PAUSED, durationSeconds = timer.durationSeconds,
                startDate = timer.startDate, expectedCompletionAt = null,
                pausedRemainingDuration = timer.pausedRemainingSeconds, pausedAt = timer.pausedAt,
                completedAt = null,
            )
            is TimerState.Completed -> PersistentTimerSnapshot(
                id = timer.id, status = SnapshotStatus.COMPLETED, durationSeconds = timer.durationSeconds,
                startDate = timer.startDate, expectedCompletionAt = null,
                pausedRemainingDuration = null, pausedAt = null, completedAt = timer.completedAt,
            )
        }
    }
}
