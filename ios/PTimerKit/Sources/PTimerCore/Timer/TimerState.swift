import Foundation

/// Numerical tolerance (1 microsecond) for the timer state machine's
/// wall-clock comparisons: deciding when a running timer has reached
/// its end date, and when a remaining-time value is effectively zero.
/// It absorbs floating-point drift at those boundaries so a timer
/// within 1 µs of its end is treated as completed rather than lingering
/// as `running`, and sub-microsecond remaining times snap to exactly 0.
///
/// This is the timer core's own constant. It is intentionally
/// independent of the exposure engine's `stabilityEpsilon`: the two
/// share the 1e-6 magnitude by coincidence but serve unrelated domains
/// (time vs. exposure-stop comparisons), so the timer core carries no
/// dependency on — and no sync obligation with — the exposure engine.
public let timerStabilityEpsilon: TimeInterval = 0.000_001

public enum TimerStatus: String, Equatable {
    case running
    // `paused` is a frozen, resumable state that preserves remaining time.
    case paused
    case completed
}

/// Payload of a `running` timer. Holds only the fields valid in the
/// `running` state: identity, duration, creation time, and the
/// expected end date.
public struct RunningTimer: Equatable {
    public let id: UUID
    public let duration: TimeInterval
    public let startDate: Date
    public let endDate: Date

    public init(id: UUID, duration: TimeInterval, startDate: Date, endDate: Date) {
        self.id = id
        self.duration = duration
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// Payload of a `paused` timer. Holds only the freeze metadata
/// (`pausedRemainingTime` + `pausedAt`); the hypothetical completion
/// date is derived from `pausedAt + pausedRemainingTime` rather than
/// stored, matching Timer Spec §3.1 ("expectedCompletionAt — running
/// status only"). Mathematically equivalent to the previous stored
/// `endDate` because `pausing(at:)` always set `pausedRemainingTime
/// = endDate - pausedAt`.
public struct PausedTimer: Equatable {
    public let id: UUID
    public let duration: TimeInterval
    public let startDate: Date
    public let pausedRemainingTime: TimeInterval
    public let pausedAt: Date

    public init(id: UUID, duration: TimeInterval, startDate: Date, pausedRemainingTime: TimeInterval, pausedAt: Date) {
        self.id = id
        self.duration = duration
        self.startDate = startDate
        self.pausedRemainingTime = pausedRemainingTime
        self.pausedAt = pausedAt
    }

    /// Hypothetical completion date for display purposes. Derived from
    /// the freeze metadata so the field disappears from the persisted
    /// schema (Timer Spec §3.1) while UI consumers can still read it.
    public var endDate: Date {
        pausedAt.addingTimeInterval(pausedRemainingTime)
    }
}

/// Payload of a `completed` timer. Holds the recorded completion
/// timestamp; surfaced via `endDate` for backward-compatible callers
/// that read the legacy field.
public struct CompletedTimer: Equatable {
    public let id: UUID
    public let duration: TimeInterval
    public let startDate: Date
    public let completedAt: Date

    public init(id: UUID, duration: TimeInterval, startDate: Date, completedAt: Date) {
        self.id = id
        self.duration = duration
        self.startDate = startDate
        self.completedAt = completedAt
    }
}

/// Sum-type representation of a timer's lifecycle state. Each case
/// carries only the fields valid for that state, so invalid
/// combinations (e.g. running with a `pausedAt`) cannot be
/// constructed.
///
/// Backward-compatible computed properties (`endDate`,
/// `pausedRemainingTime`, `pausedAt`, `status`) preserve the legacy
/// struct surface so existing call sites and the persisted snapshot
/// schema stay byte-identical.
public enum TimerState: Identifiable, Equatable {
    case running(RunningTimer)
    case paused(PausedTimer)
    case completed(CompletedTimer)

    /// Compatibility initializer that mirrors the historical struct
    /// `TimerState(id:duration:startDate:endDate:pausedRemainingTime:pausedAt:status:)`
    /// constructor used by tests and the `PersistentTimerSnapshot`
    /// restore path. The initializer dispatches on `status` and
    /// constructs the appropriate sum case from the supplied legacy
    /// fields.
    ///
    /// Trusted-callsite contract: callers shall supply the fields
    /// required by the chosen status:
    /// - `.running` ⇒ `endDate` non-nil
    /// - `.paused` ⇒ `pausedRemainingTime` and `pausedAt` non-nil
    /// - `.completed` ⇒ `endDate` non-nil (= completion timestamp)
    /// `endDate` is intentionally ignored for `.paused`; the sum-type
    /// representation derives it from `pausedAt + pausedRemainingTime`
    /// (Timer Spec §3.1 "expectedCompletionAt — running status only").
    /// Other missing fields debug-trap so corrupt inputs from a
    /// persisted snapshot are caught early; the production fallback
    /// constructs a degenerate but type-valid case so a debug crash
    /// does not become a release crash. `PersistentTimerSnapshot.restore`
    /// guards the `.paused` corrupt-input case at its caller boundary
    /// instead, surfacing such snapshots as completed.
    public init(
        id: UUID,
        duration: TimeInterval,
        startDate: Date,
        endDate: Date?,
        pausedRemainingTime: TimeInterval?,
        pausedAt: Date?,
        status: TimerStatus
    ) {
        switch status {
        case .running:
            assert(endDate != nil, "TimerState(.running) requires a non-nil endDate")
            self = .running(
                RunningTimer(
                    id: id,
                    duration: duration,
                    startDate: startDate,
                    endDate: endDate ?? startDate.addingTimeInterval(duration)
                )
            )
        case .paused:
            assert(
                pausedRemainingTime != nil && pausedAt != nil,
                "TimerState(.paused) requires non-nil pausedRemainingTime and pausedAt"
            )
            self = .paused(
                PausedTimer(
                    id: id,
                    duration: duration,
                    startDate: startDate,
                    pausedRemainingTime: pausedRemainingTime ?? 0,
                    pausedAt: pausedAt ?? startDate
                )
            )
        case .completed:
            assert(endDate != nil, "TimerState(.completed) requires a non-nil endDate (completion timestamp)")
            self = .completed(
                CompletedTimer(
                    id: id,
                    duration: duration,
                    startDate: startDate,
                    completedAt: endDate ?? startDate.addingTimeInterval(duration)
                )
            )
        }
    }

    public var id: UUID {
        switch self {
        case .running(let payload): return payload.id
        case .paused(let payload): return payload.id
        case .completed(let payload): return payload.id
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .running(let payload): return payload.duration
        case .paused(let payload): return payload.duration
        case .completed(let payload): return payload.duration
        }
    }

    public var startDate: Date {
        switch self {
        case .running(let payload): return payload.startDate
        case .paused(let payload): return payload.startDate
        case .completed(let payload): return payload.startDate
        }
    }

    /// Backward-compatible field surface. `endDate` is non-nil for
    /// every case in the sum-type representation; the optional return
    /// type is preserved so callers reading the legacy field continue
    /// to compile and behave identically.
    public var endDate: Date? {
        switch self {
        case .running(let payload): return payload.endDate
        case .paused(let payload): return payload.endDate
        case .completed(let payload): return payload.completedAt
        }
    }

    public var pausedRemainingTime: TimeInterval? {
        if case .paused(let payload) = self {
            return payload.pausedRemainingTime
        }
        return nil
    }

    public var pausedAt: Date? {
        if case .paused(let payload) = self {
            return payload.pausedAt
        }
        return nil
    }

    /// Derived status accessor preserving the legacy `status`
    /// property. External callers (display state mappers, lock-
    /// screen coordinator, view models) keep reading this without
    /// switching on case.
    public var status: TimerStatus {
        switch self {
        case .running: return .running
        case .paused: return .paused
        case .completed: return .completed
        }
    }

    public var remainingTime: TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch self {
        case .running(let payload):
            return Self.sanitizeRemainingTime(payload.endDate.timeIntervalSinceNow)
        case .paused(let payload):
            return Self.sanitizeRemainingTime(payload.pausedRemainingTime)
        case .completed:
            return 0
        }
    }

    public func remainingTime(at now: Date) -> TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch self {
        case .running(let payload):
            return Self.sanitizeRemainingTime(payload.endDate.timeIntervalSince(now))
        case .paused(let payload):
            return Self.sanitizeRemainingTime(payload.pausedRemainingTime)
        case .completed:
            return 0
        }
    }

    public func status(at now: Date) -> TimerStatus {
        guard case .running(let payload) = self,
              now.addingTimeInterval(timerStabilityEpsilon) >= payload.endDate else {
            return status
        }

        return .completed
    }

    public func updatingStatus(at now: Date) -> TimerState {
        guard case .running(let payload) = self,
              now.addingTimeInterval(timerStabilityEpsilon) >= payload.endDate else {
            return self
        }

        return completed(at: payload.endDate)
    }

    public func pausing(at now: Date) -> TimerState {
        let remaining = remainingTime(at: now)

        guard remaining > 0 else {
            // Preserve the legacy short-circuit: pausing while remaining
            // time has reached zero immediately completes using the
            // existing endDate (or `now` as the fallback only if endDate
            // is somehow absent — unreachable in the sum-type
            // representation but kept for shape parity).
            return completed(at: endDate ?? now)
        }

        // Freeze the timer with its remaining duration intact so it can be
        // resumed later from the same logical point. The hypothetical
        // completion date stays accessible via the computed
        // `PausedTimer.endDate` (= `pausedAt + pausedRemainingTime`),
        // matching the legacy stored value exactly.
        return .paused(
            PausedTimer(
                id: id,
                duration: duration,
                startDate: startDate,
                pausedRemainingTime: remaining,
                pausedAt: now
            )
        )
    }

    public func resume(at now: Date) -> TimerState {
        let remaining = Self.sanitizeRemainingTime(pausedRemainingTime ?? 0)
        guard remaining > 0 else {
            return completed(at: resolvedCompletionDate())
        }

        // Resume recalculates the end date from "now" because `paused`
        // preserves remaining time as a frozen resumable state.
        return .running(
            RunningTimer(
                id: id,
                duration: duration,
                startDate: startDate,
                endDate: now.addingTimeInterval(remaining)
            )
        )
    }

    public func completed(at completionDate: Date? = nil) -> TimerState {
        .completed(
            CompletedTimer(
                id: id,
                duration: duration,
                startDate: startDate,
                completedAt: completionDate ?? resolvedCompletionDate()
            )
        )
    }

    private func resolvedCompletionDate() -> Date {
        // Mirrors the legacy `endDate ?? pausedAt + remaining ??
        // startDate + duration` resolution exactly. In the sum-type
        // representation `endDate` is non-nil for running and paused
        // and `completedAt` is the recorded completion timestamp,
        // so the legacy fallback chain collapses to a direct case
        // dispatch without changing observable behavior.
        switch self {
        case .running(let payload):
            return payload.endDate
        case .paused(let payload):
            return payload.endDate
        case .completed(let payload):
            return payload.completedAt
        }
    }

    private static func sanitizeRemainingTime(_ value: TimeInterval) -> TimeInterval {
        let clamped = max(0, value)
        return clamped < timerStabilityEpsilon ? 0 : clamped
    }
}
