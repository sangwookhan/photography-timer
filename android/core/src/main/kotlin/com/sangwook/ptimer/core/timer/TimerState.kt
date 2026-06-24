package com.sangwook.ptimer.core.timer

import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToLong

// Faithful port of iOS PTimerCore TimerState (PROTECTED AREA — the pause/
// resume/complete/cancel state machine). Dates map to java.time.Instant and
// TimeInterval to Double seconds; comparisons use nanosecond precision so the
// 1 µs stability epsilon behaves as on iOS.

/** 1 microsecond tolerance for the timer state machine's wall-clock comparisons. */
const val TIMER_STABILITY_EPSILON: Double = 0.000_001

internal fun secondsBetween(from: Instant, to: Instant): Double =
    Duration.between(from, to).toNanos() / 1_000_000_000.0

internal fun Instant.plusSecondsDouble(seconds: Double): Instant =
    this.plusNanos((seconds * 1_000_000_000.0).roundToLong())

enum class TimerStatus { running, paused, completed, canceled }

/**
 * Sum-type representation of a timer's lifecycle. Each case carries only the
 * fields valid for that state, so invalid combinations cannot be constructed.
 */
sealed interface TimerState {
    val id: UUID
    val duration: Double
    val startDate: Instant

    data class Running(
        override val id: UUID,
        override val duration: Double,
        override val startDate: Instant,
        val endDate: Instant,
    ) : TimerState

    data class Paused(
        override val id: UUID,
        override val duration: Double,
        override val startDate: Instant,
        val pausedRemainingTime: Double,
        val pausedAt: Instant,
    ) : TimerState {
        /** Hypothetical completion date, derived (not stored). */
        val endDate: Instant get() = pausedAt.plusSecondsDouble(pausedRemainingTime)
    }

    data class Completed(
        override val id: UUID,
        override val duration: Double,
        override val startDate: Instant,
        val completedAt: Instant,
    ) : TimerState

    data class Canceled(
        override val id: UUID,
        override val duration: Double,
        override val startDate: Instant,
        val canceledAt: Instant,
        /** Remaining time captured at cancellation (e.g. "Canceled · 51s left"). */
        val remainingAtCancel: Double,
    ) : TimerState

    companion object {
        /**
         * Compatibility factory mirroring the legacy field-based constructor
         * used by the persisted-snapshot restore path. Trusted-callsite
         * contract: supply the fields required by [status]. `endDate` is
         * ignored for `.paused` (derived from `pausedAt + pausedRemainingTime`).
         */
        fun fromLegacy(
            id: UUID,
            duration: Double,
            startDate: Instant,
            endDate: Instant?,
            pausedRemainingTime: Double?,
            pausedAt: Instant?,
            status: TimerStatus,
        ): TimerState = when (status) {
            TimerStatus.running -> Running(
                id, duration, startDate,
                endDate = endDate ?: startDate.plusSecondsDouble(duration),
            )
            TimerStatus.paused -> Paused(
                id, duration, startDate,
                pausedRemainingTime = pausedRemainingTime ?: 0.0,
                pausedAt = pausedAt ?: startDate,
            )
            TimerStatus.completed -> Completed(
                id, duration, startDate,
                completedAt = endDate ?: startDate.plusSecondsDouble(duration),
            )
            TimerStatus.canceled -> Canceled(
                id, duration, startDate,
                canceledAt = endDate ?: startDate.plusSecondsDouble(duration),
                remainingAtCancel = pausedRemainingTime ?: 0.0,
            )
        }
    }
}

val TimerState.status: TimerStatus
    get() = when (this) {
        is TimerState.Running -> TimerStatus.running
        is TimerState.Paused -> TimerStatus.paused
        is TimerState.Completed -> TimerStatus.completed
        is TimerState.Canceled -> TimerStatus.canceled
    }

/** Non-null in every case (running/paused expected completion; terminal stamp). */
val TimerState.endDate: Instant
    get() = when (this) {
        is TimerState.Running -> endDate
        is TimerState.Paused -> endDate
        is TimerState.Completed -> completedAt
        is TimerState.Canceled -> canceledAt
    }

val TimerState.pausedRemainingTime: Double?
    get() = (this as? TimerState.Paused)?.pausedRemainingTime

val TimerState.pausedAt: Instant?
    get() = (this as? TimerState.Paused)?.pausedAt

val TimerState.remainingAtCancel: Double?
    get() = (this as? TimerState.Canceled)?.remainingAtCancel

fun TimerState.remainingTime(at: Instant): Double = when (this) {
    is TimerState.Running -> sanitizeRemainingTime(secondsBetween(at, endDate))
    is TimerState.Paused -> sanitizeRemainingTime(pausedRemainingTime)
    is TimerState.Completed, is TimerState.Canceled -> 0.0
}

fun TimerState.status(at: Instant): TimerStatus {
    if (this is TimerState.Running && secondsBetween(at, endDate) <= TIMER_STABILITY_EPSILON) {
        return TimerStatus.completed
    }
    return status
}

fun TimerState.updatingStatus(at: Instant): TimerState {
    if (this is TimerState.Running && secondsBetween(at, endDate) <= TIMER_STABILITY_EPSILON) {
        return completed(at = endDate)
    }
    return this
}

fun TimerState.pausing(at: Instant): TimerState {
    val remaining = remainingTime(at)
    if (remaining <= 0) {
        return completed(at = endDate)
    }
    return TimerState.Paused(
        id = id,
        duration = duration,
        startDate = startDate,
        pausedRemainingTime = remaining,
        pausedAt = at,
    )
}

fun TimerState.resume(at: Instant): TimerState {
    val remaining = sanitizeRemainingTime(pausedRemainingTime ?: 0.0)
    if (remaining <= 0) {
        return completed(at = resolvedCompletionDate())
    }
    return TimerState.Running(
        id = id,
        duration = duration,
        startDate = startDate,
        endDate = at.plusSecondsDouble(remaining),
    )
}

fun TimerState.completed(at: Instant? = null): TimerState = TimerState.Completed(
    id = id,
    duration = duration,
    startDate = startDate,
    completedAt = at ?: resolvedCompletionDate(),
)

/**
 * Transitions a running or paused timer to the terminal canceled record.
 * Already-terminal states are returned unchanged.
 */
fun TimerState.canceled(at: Instant): TimerState = when (this) {
    is TimerState.Running, is TimerState.Paused -> TimerState.Canceled(
        id = id,
        duration = duration,
        startDate = startDate,
        canceledAt = at,
        remainingAtCancel = remainingTime(at),
    )
    is TimerState.Completed, is TimerState.Canceled -> this
}

private fun TimerState.resolvedCompletionDate(): Instant = when (this) {
    is TimerState.Running -> endDate
    is TimerState.Paused -> endDate
    is TimerState.Completed -> completedAt
    is TimerState.Canceled -> canceledAt
}

private fun sanitizeRemainingTime(value: Double): Double {
    val clamped = max(0.0, value)
    return if (clamped < TIMER_STABILITY_EPSILON) 0.0 else clamped
}
