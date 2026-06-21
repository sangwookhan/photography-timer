// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

// Snapshot schema is intentionally minimal:
// - id keeps timer identity stable across relaunch.
// - status selects the restore rule for running/paused/completed.
//   In this model, `paused` means a frozen, later-resumable timer rather
//   than a terminal "done" state.
// - duration/startDate preserve the original timer semantics and UI context.
// - expectedCompletionAt lets relaunch restore reconcile running timers to wall-clock time.
// - pausedRemainingDuration/pausedAt keep paused timers frozen without drifting.
// - completedAt preserves the final timestamp for completed timers.
public struct PersistentTimerSnapshot: Codable, Equatable {
    public let id: UUID
    public let status: SnapshotStatus
    public let duration: TimeInterval
    public let startDate: Date
    public let expectedCompletionAt: Date?
    public let pausedRemainingDuration: TimeInterval?
    public let pausedAt: Date?
    public let completedAt: Date?

    public init(
        id: UUID,
        status: SnapshotStatus,
        duration: TimeInterval,
        startDate: Date,
        expectedCompletionAt: Date?,
        pausedRemainingDuration: TimeInterval?,
        pausedAt: Date?,
        completedAt: Date?
    ) {
        self.id = id
        self.status = status
        self.duration = duration
        self.startDate = startDate
        self.expectedCompletionAt = expectedCompletionAt
        self.pausedRemainingDuration = pausedRemainingDuration
        self.pausedAt = pausedAt
        self.completedAt = completedAt
    }

    public init(timer: TimerState) {
        self.id = timer.id
        self.duration = timer.duration
        self.startDate = timer.startDate
        // For canceled records the `pausedRemainingDuration` slot carries
        // the remaining-at-cancel value (paused timers carry their frozen
        // remaining there); both mean "time left when the timer stopped".
        self.pausedRemainingDuration = timer.pausedRemainingTime ?? timer.remainingAtCancel
        self.pausedAt = timer.pausedAt

        switch timer.status {
        case .running:
            self.status = .running
            self.expectedCompletionAt = timer.endDate
            self.completedAt = nil
        case .paused:
            // Per Timer Spec §3.1, `expectedCompletionAt` is meaningful for
            // `running` status only. A paused snapshot carries the freeze
            // metadata (`pausedRemainingDuration` + `pausedAt`); the
            // hypothetical completion date is reconstructed on read by the
            // computed `PausedTimer.endDate` so it never needs to be
            // stored on disk.
            self.status = .paused
            self.expectedCompletionAt = nil
            self.completedAt = nil
        case .completed:
            self.status = .completed
            self.expectedCompletionAt = nil
            self.completedAt = timer.endDate
        case .canceled:
            // A canceled record stores its cancellation timestamp in
            // the same `completedAt` slot completed timers use; the
            // `canceled` status selects the canceled restore rule.
            self.status = .canceled
            self.expectedCompletionAt = nil
            self.completedAt = timer.endDate
        }
    }

    public func restore(at now: Date) -> TimerState {
        switch status {
        case .running:
            guard let expectedCompletionAt else {
                return makeCompletedTimer(completionDate: now)
            }

            if now.addingTimeInterval(timerStabilityEpsilon) >= expectedCompletionAt {
                return makeCompletedTimer(completionDate: expectedCompletionAt)
            }

            return TimerState(
                id: id,
                duration: duration,
                startDate: startDate,
                endDate: expectedCompletionAt,
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running
            )
        case .paused:
            // `paused` restores as the same frozen, resumable state. It
            // must not consume wall-clock time or auto-complete while
            // the app was dead. `expectedCompletionAt` is ignored on
            // this path: legacy snapshots may carry a non-nil value
            // while current snapshots write `nil`;
            // either way the sum-type init for `.paused` discards the
            // parameter and the computed `PausedTimer.endDate`
            // reconstructs the hypothetical completion date from
            // `pausedAt + pausedRemainingDuration`.
            //
            // A paused snapshot whose freeze metadata is missing is
            // structurally invalid (the back-compat init would otherwise
            // fabricate `pausedAt = startDate`, `pausedRemainingTime = 0`,
            // producing a fictitious "paused at startDate" timestamp).
            // Treat the corrupt input as completed instead, mirroring
            // the `.running` branch's missing-`expectedCompletionAt`
            // fallback above.
            guard let pausedAt, let pausedRemainingDuration else {
                return makeCompletedTimer(completionDate: completedAt)
            }
            return TimerState(
                id: id,
                duration: duration,
                startDate: startDate,
                endDate: nil,
                pausedRemainingTime: pausedRemainingDuration,
                pausedAt: pausedAt,
                status: .paused
            )
        case .completed:
            return makeCompletedTimer(completionDate: completedAt)
        case .canceled:
            return TimerState(
                id: id,
                duration: duration,
                startDate: startDate,
                endDate: completedAt ?? startDate.addingTimeInterval(duration),
                // Restores the remaining-at-cancel captured at stop time.
                pausedRemainingTime: pausedRemainingDuration,
                pausedAt: nil,
                status: .canceled
            )
        }
    }

    private func makeCompletedTimer(completionDate: Date?) -> TimerState {
        TimerState(
            id: id,
            duration: duration,
            startDate: startDate,
            endDate: completionDate ?? expectedCompletionAt ?? pausedAt ?? startDate.addingTimeInterval(duration),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed
        )
    }

    public enum SnapshotStatus: String, Codable, Equatable {
        case running
        case paused
        case completed
        case canceled

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "running":
                self = .running
            case "paused", "stopped":
                self = .paused
            case "completed":
                self = .completed
            case "canceled":
                self = .canceled
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported snapshot status: \(rawValue)"
                )
            }
        }
    }
}

public struct PersistentTimerCollectionSnapshot: Codable, Equatable {
    public let timers: [PersistentTimerSnapshot]

    public init(timers: [TimerState]) {
        self.timers = timers.map(PersistentTimerSnapshot.init)
    }
}

public protocol TimerPersistenceStoring {
    func loadSnapshot() -> PersistentTimerCollectionSnapshot?
    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot)
    func clearSnapshot()
}

public struct NoOpTimerPersistenceStore: TimerPersistenceStoring {
    public init() {}
    public func loadSnapshot() -> PersistentTimerCollectionSnapshot? { nil }
    public func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {}
    public func clearSnapshot() {}
}
