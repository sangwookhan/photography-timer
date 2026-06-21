package com.sangwook.ptimer.core.timer

import java.time.Duration
import java.time.Instant

/**
 * Numerical tolerance (1 microsecond) for the timer state machine's
 * wall-clock comparisons. The timer core's own constant, independent of
 * the exposure engine's epsilon. Mirrors iOS `timerStabilityEpsilon`.
 */
const val TIMER_STABILITY_EPSILON: Double = 0.000_001

enum class TimerStatus { RUNNING, PAUSED, COMPLETED, CANCELED }

/** Seconds from [from] to [to] (positive when [to] is later). */
internal fun secondsBetween(from: Instant, to: Instant): Double {
    val d = Duration.between(from, to)
    return d.seconds.toDouble() + d.nano / 1_000_000_000.0
}

internal fun Instant.plusSeconds(seconds: Double): Instant =
    this.plusNanos(Math.round(seconds * 1_000_000_000.0))

/**
 * Sum-type timer lifecycle state. Each case carries only the fields valid
 * for that state, so invalid combinations cannot be constructed. Protected
 * behavior — exact parity with iOS `TimerState`.
 */
sealed interface TimerState {
    val id: String
    val durationSeconds: Double
    val startDate: Instant

    /** Non-null for every case (running/paused expected end, completed timestamp). */
    val endDate: Instant

    data class Running(
        override val id: String,
        override val durationSeconds: Double,
        override val startDate: Instant,
        override val endDate: Instant,
    ) : TimerState

    data class Paused(
        override val id: String,
        override val durationSeconds: Double,
        override val startDate: Instant,
        val pausedRemainingSeconds: Double,
        val pausedAt: Instant,
    ) : TimerState {
        override val endDate: Instant get() = pausedAt.plusSeconds(pausedRemainingSeconds)
    }

    data class Completed(
        override val id: String,
        override val durationSeconds: Double,
        override val startDate: Instant,
        val completedAt: Instant,
    ) : TimerState {
        override val endDate: Instant get() = completedAt
    }

    /**
     * Terminal record for a timer the user stopped before it finished. Like
     * [Completed] it no longer runs and is surfaced in the history area, but it
     * is labeled Canceled rather than Done. [remainingAtCancelSeconds] is the
     * remaining time captured at the cancellation moment (distinct from
     * [durationSeconds]) so the history surface can show how much was left.
     * Mirrors iOS `CanceledTimer`.
     */
    data class Canceled(
        override val id: String,
        override val durationSeconds: Double,
        override val startDate: Instant,
        val canceledAt: Instant,
        val remainingAtCancelSeconds: Double,
    ) : TimerState {
        override val endDate: Instant get() = canceledAt
    }

    val status: TimerStatus
        get() = when (this) {
            is Running -> TimerStatus.RUNNING
            is Paused -> TimerStatus.PAUSED
            is Completed -> TimerStatus.COMPLETED
            is Canceled -> TimerStatus.CANCELED
        }

    val pausedRemainingOrNull: Double? get() = (this as? Paused)?.pausedRemainingSeconds
    val pausedAtOrNull: Instant? get() = (this as? Paused)?.pausedAt

    /** Remaining time recorded at cancellation; null for every non-canceled state. */
    val remainingAtCancelOrNull: Double? get() = (this as? Canceled)?.remainingAtCancelSeconds

    fun remainingTime(now: Instant): Double = when (this) {
        is Running -> sanitizeRemainingTime(secondsBetween(now, endDate))
        is Paused -> sanitizeRemainingTime(pausedRemainingSeconds)
        is Completed, is Canceled -> 0.0
    }

    fun statusAt(now: Instant): TimerStatus {
        if (this is Running && secondsBetween(now, endDate) <= TIMER_STABILITY_EPSILON) {
            return TimerStatus.COMPLETED
        }
        return status
    }

    fun updatingStatus(now: Instant): TimerState {
        if (this is Running && secondsBetween(now, endDate) <= TIMER_STABILITY_EPSILON) {
            return completed(endDate)
        }
        return this
    }

    /**
     * Pause; a pause whose remaining already reached zero short-circuits to
     * completed. Terminal states (completed, canceled) cannot pause and are
     * returned unchanged.
     */
    fun pausing(now: Instant): TimerState {
        if (this is Completed || this is Canceled) return this
        val remaining = remainingTime(now)
        if (remaining <= 0) return completed(endDate)
        return Paused(id, durationSeconds, startDate, remaining, now)
    }

    /**
     * Resume from a frozen paused state; resuming at/after zero remaining
     * completes. Only a paused timer can resume; any other state (running or
     * terminal) is returned unchanged.
     */
    fun resume(now: Instant): TimerState {
        if (this !is Paused) return this
        val remaining = sanitizeRemainingTime(pausedRemainingSeconds)
        if (remaining <= 0) return completed(resolvedCompletionDate())
        return Running(id, durationSeconds, startDate, now.plusSeconds(remaining))
    }

    fun completed(completionDate: Instant? = null): TimerState =
        Completed(id, durationSeconds, startDate, completionDate ?: resolvedCompletionDate())

    /**
     * Transition a running or paused timer to the terminal [Canceled] record,
     * stamping [cancellationDate] and capturing the remaining time at that
     * instant. Already-terminal states (completed, canceled) are returned
     * unchanged so a stray cancel cannot rewrite a finished record. Mirrors iOS
     * `TimerState.canceled(at:)`.
     */
    fun canceled(cancellationDate: Instant): TimerState = when (this) {
        is Running, is Paused -> Canceled(
            id = id,
            durationSeconds = durationSeconds,
            startDate = startDate,
            canceledAt = cancellationDate,
            remainingAtCancelSeconds = remainingTime(cancellationDate),
        )
        is Completed, is Canceled -> this
    }

    private fun resolvedCompletionDate(): Instant = endDate

    companion object {
        internal fun sanitizeRemainingTime(value: Double): Double {
            val clamped = maxOf(0.0, value)
            return if (clamped < TIMER_STABILITY_EPSILON) 0.0 else clamped
        }

        /** Construct a running timer beginning at [start] with the given duration. */
        fun running(id: String, durationSeconds: Double, start: Instant): TimerState =
            Running(id, durationSeconds, start, start.plusSeconds(durationSeconds))
    }
}
