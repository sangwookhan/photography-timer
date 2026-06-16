package com.sangwook.ptimer.core.timer

import java.time.Duration
import java.time.Instant

/**
 * Numerical tolerance (1 microsecond) for the timer state machine's
 * wall-clock comparisons. The timer core's own constant, independent of
 * the exposure engine's epsilon. Mirrors iOS `timerStabilityEpsilon`.
 */
const val TIMER_STABILITY_EPSILON: Double = 0.000_001

enum class TimerStatus { RUNNING, PAUSED, COMPLETED }

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

    val status: TimerStatus
        get() = when (this) {
            is Running -> TimerStatus.RUNNING
            is Paused -> TimerStatus.PAUSED
            is Completed -> TimerStatus.COMPLETED
        }

    val pausedRemainingOrNull: Double? get() = (this as? Paused)?.pausedRemainingSeconds
    val pausedAtOrNull: Instant? get() = (this as? Paused)?.pausedAt

    fun remainingTime(now: Instant): Double = when (this) {
        is Running -> sanitizeRemainingTime(secondsBetween(now, endDate))
        is Paused -> sanitizeRemainingTime(pausedRemainingSeconds)
        is Completed -> 0.0
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

    /** Pause; a pause whose remaining already reached zero short-circuits to completed. */
    fun pausing(now: Instant): TimerState {
        val remaining = remainingTime(now)
        if (remaining <= 0) return completed(endDate)
        return Paused(id, durationSeconds, startDate, remaining, now)
    }

    /** Resume from a frozen paused state; resuming at/after zero remaining completes. */
    fun resume(now: Instant): TimerState {
        val remaining = sanitizeRemainingTime(pausedRemainingOrNull ?: 0.0)
        if (remaining <= 0) return completed(resolvedCompletionDate())
        return Running(id, durationSeconds, startDate, now.plusSeconds(remaining))
    }

    fun completed(completionDate: Instant? = null): TimerState =
        Completed(id, durationSeconds, startDate, completionDate ?: resolvedCompletionDate())

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
