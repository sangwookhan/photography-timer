import Combine
import Foundation
import AudioToolbox
import UIKit
import PTimerKit

private let timerStabilityEpsilon: TimeInterval = ExposureCalculator.stabilityEpsilon

struct TimerCompletionEvent: Equatable {
    let timerID: UUID
    let completionDate: Date
}

protocol TimerCompletionAlerting {
    @MainActor
    func handleTimerCompletion(_ event: TimerCompletionEvent)
}

struct NoOpTimerCompletionAlertService: TimerCompletionAlerting {
    func handleTimerCompletion(_ event: TimerCompletionEvent) {}
}

protocol TimerCompletionFeedbackPlaying {
    @MainActor
    func playCompletionFeedback()
}

protocol TimerCompletionNotificationScheduling {
    @MainActor
    func requestAuthorizationIfNeeded()

    @MainActor
    func scheduleCompletionNotification(for timer: TimerState)

    @MainActor
    func cancelCompletionNotification(forTimerID timerID: UUID)
}

struct NoOpTimerCompletionScheduler: TimerCompletionNotificationScheduling {
    func requestAuthorizationIfNeeded() {}
    func scheduleCompletionNotification(for timer: TimerState) {}
    func cancelCompletionNotification(forTimerID timerID: UUID) {}
}

// Snapshot schema is intentionally minimal:
// - id keeps timer identity stable across relaunch.
// - status selects the restore rule for running/paused/completed.
//   In this model, `paused` means a frozen, later-resumable timer rather
//   than a terminal "done" state.
// - duration/startDate preserve the original timer semantics and UI context.
// - expectedCompletionAt lets relaunch restore reconcile running timers to wall-clock time.
// - pausedRemainingDuration/pausedAt keep paused timers frozen without drifting.
// - completedAt preserves the final timestamp for completed timers.
struct PersistentTimerSnapshot: Codable, Equatable {
    let id: UUID
    let status: SnapshotStatus
    let duration: TimeInterval
    let startDate: Date
    let expectedCompletionAt: Date?
    let pausedRemainingDuration: TimeInterval?
    let pausedAt: Date?
    let completedAt: Date?

    init(timer: TimerState) {
        self.id = timer.id
        self.duration = timer.duration
        self.startDate = timer.startDate
        self.pausedRemainingDuration = timer.pausedRemainingTime
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
        }
    }

    func restore(at now: Date) -> TimerState {
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

    enum SnapshotStatus: String, Codable, Equatable {
        case running
        case paused
        case completed

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "running":
                self = .running
            case "paused", "stopped":
                self = .paused
            case "completed":
                self = .completed
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported snapshot status: \(rawValue)"
                )
            }
        }
    }
}

struct PersistentTimerCollectionSnapshot: Codable, Equatable {
    let timers: [PersistentTimerSnapshot]

    init(timers: [TimerState]) {
        self.timers = timers.map(PersistentTimerSnapshot.init)
    }
}

protocol TimerPersistenceStoring {
    func loadSnapshot() -> PersistentTimerCollectionSnapshot?
    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot)
    func clearSnapshot()
}

struct NoOpTimerPersistenceStore: TimerPersistenceStoring {
    func loadSnapshot() -> PersistentTimerCollectionSnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {}
    func clearSnapshot() {}
}

struct UserDefaultsTimerPersistenceStore: TimerPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.timer-state.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentTimerCollectionSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}

struct SystemTimerCompletionFeedbackPlayer: TimerCompletionFeedbackPlaying {
    func playCompletionFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        AudioServicesPlaySystemSound(Self.completionSoundID)
    }

    private static let completionSoundID: SystemSoundID = 1005
}

@MainActor
final class ForegroundTimerCompletionAlertService: TimerCompletionAlerting {
    private let feedbackPlayer: TimerCompletionFeedbackPlaying
    private let applicationStateProvider: @MainActor () -> UIApplication.State

    init(
        feedbackPlayer: TimerCompletionFeedbackPlaying,
        applicationStateProvider: @escaping @MainActor () -> UIApplication.State = {
            UIApplication.shared.applicationState
        }
    ) {
        self.feedbackPlayer = feedbackPlayer
        self.applicationStateProvider = applicationStateProvider
    }

    func handleTimerCompletion(_ event: TimerCompletionEvent) {
        guard applicationStateProvider() == .active else {
            return
        }

        feedbackPlayer.playCompletionFeedback()
    }
}

enum TimerStatus: String, Equatable {
    case running
    // `paused` is a frozen, resumable state that preserves remaining time.
    case paused
    case completed
}

/// Payload of a `running` timer. Holds only the fields valid in the
/// `running` state: identity, duration, creation time, and the
/// expected end date.
struct RunningTimer: Equatable {
    let id: UUID
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date
}

/// Payload of a `paused` timer. Holds only the freeze metadata
/// (`pausedRemainingTime` + `pausedAt`); the hypothetical completion
/// date is derived from `pausedAt + pausedRemainingTime` rather than
/// stored, matching Timer Spec §3.1 ("expectedCompletionAt — running
/// status only"). Mathematically equivalent to the previous stored
/// `endDate` because `pausing(at:)` always set `pausedRemainingTime
/// = endDate - pausedAt`.
struct PausedTimer: Equatable {
    let id: UUID
    let duration: TimeInterval
    let startDate: Date
    let pausedRemainingTime: TimeInterval
    let pausedAt: Date

    /// Hypothetical completion date for display purposes. Derived from
    /// the freeze metadata so the field disappears from the persisted
    /// schema (Timer Spec §3.1) while UI consumers can still read it.
    var endDate: Date {
        pausedAt.addingTimeInterval(pausedRemainingTime)
    }
}

/// Payload of a `completed` timer. Holds the recorded completion
/// timestamp; surfaced via `endDate` for backward-compatible callers
/// that read the legacy field.
struct CompletedTimer: Equatable {
    let id: UUID
    let duration: TimeInterval
    let startDate: Date
    let completedAt: Date
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
enum TimerState: Identifiable, Equatable {
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
    init(
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

    var id: UUID {
        switch self {
        case .running(let payload): return payload.id
        case .paused(let payload): return payload.id
        case .completed(let payload): return payload.id
        }
    }

    var duration: TimeInterval {
        switch self {
        case .running(let payload): return payload.duration
        case .paused(let payload): return payload.duration
        case .completed(let payload): return payload.duration
        }
    }

    var startDate: Date {
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
    var endDate: Date? {
        switch self {
        case .running(let payload): return payload.endDate
        case .paused(let payload): return payload.endDate
        case .completed(let payload): return payload.completedAt
        }
    }

    var pausedRemainingTime: TimeInterval? {
        if case .paused(let payload) = self {
            return payload.pausedRemainingTime
        }
        return nil
    }

    var pausedAt: Date? {
        if case .paused(let payload) = self {
            return payload.pausedAt
        }
        return nil
    }

    /// Derived status accessor preserving the legacy `status`
    /// property. External callers (display state mappers, lock-
    /// screen coordinator, view models) keep reading this without
    /// switching on case.
    var status: TimerStatus {
        switch self {
        case .running: return .running
        case .paused: return .paused
        case .completed: return .completed
        }
    }

    var remainingTime: TimeInterval {
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

    func remainingTime(at now: Date) -> TimeInterval {
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

    func status(at now: Date) -> TimerStatus {
        guard case .running(let payload) = self,
              now.addingTimeInterval(timerStabilityEpsilon) >= payload.endDate else {
            return status
        }

        return .completed
    }

    func updatingStatus(at now: Date) -> TimerState {
        guard case .running(let payload) = self,
              now.addingTimeInterval(timerStabilityEpsilon) >= payload.endDate else {
            return self
        }

        return completed(at: payload.endDate)
    }

    func pausing(at now: Date) -> TimerState {
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

    func resume(at now: Date) -> TimerState {
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

    func completed(at completionDate: Date? = nil) -> TimerState {
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

@MainActor
final class TimerManager: ObservableObject {
    @Published private(set) var timers: [TimerState] = []

    var currentDate: Date {
        dateProvider()
    }

    private let tickInterval: TimeInterval
    private let dateProvider: () -> Date
    private let completionAlertService: TimerCompletionAlerting
    private let completionNotificationScheduler: TimerCompletionNotificationScheduling
    private let persistenceStore: TimerPersistenceStoring
    private var hasRestoredPersistedTimers = false
    private var timer: Timer?

    init(
        tickInterval: TimeInterval = 0.1,
        dateProvider: @escaping () -> Date = Date.init,
        completionAlertService: TimerCompletionAlerting = NoOpTimerCompletionAlertService(),
        completionNotificationScheduler: TimerCompletionNotificationScheduling = NoOpTimerCompletionScheduler(),
        persistenceStore: TimerPersistenceStoring = NoOpTimerPersistenceStore()
    ) {
        self.tickInterval = tickInterval
        self.dateProvider = dateProvider
        self.completionAlertService = completionAlertService
        self.completionNotificationScheduler = completionNotificationScheduler
        self.persistenceStore = persistenceStore

        restorePersistedTimersIfNeeded()
    }

    @discardableResult
    func start(id: UUID = UUID(), duration: TimeInterval) -> UUID? {
        // Per Timer Spec §1.2, the system rejects creation with non-positive,
        // non-finite, or NaN duration values. `> 0` admits `+Infinity`
        // (`.infinity > 0` is true) so `isFinite` must be checked explicitly.
        // NaN comparisons return false in both directions, so the `> 0` guard
        // already rejects NaN.
        guard duration.isFinite, duration > 0 else {
            return nil
        }

        let now = dateProvider()
        let endDate = now.addingTimeInterval(duration)
        timers.append(
            TimerState(
                id: id,
                duration: duration,
                startDate: now,
                endDate: endDate,
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running
            )
        )
        completionNotificationScheduler.requestAuthorizationIfNeeded()
        if let timer = timers.last {
            completionNotificationScheduler.scheduleCompletionNotification(for: timer)
        }
        ensureTimerLoop()
        persistTimers()
        return id
    }

    func pause(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            stopLoopIfNeeded()
            return
        }

        let currentDate = dateProvider()
        timers[index] = timers[index].pausing(at: currentDate)
        completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        stopLoopIfNeeded(now: currentDate)
        persistTimers()
    }

    func resume(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            stopLoopIfNeeded()
            return
        }

        let currentDate = dateProvider()
        let newState = timers[index].resume(at: currentDate)
        timers[index] = newState

        if newState.status == .running {
            completionNotificationScheduler.requestAuthorizationIfNeeded()
            completionNotificationScheduler.scheduleCompletionNotification(for: newState)
            ensureTimerLoop()
        } else {
            completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
            stopLoopIfNeeded(now: currentDate)
        }

        persistTimers()
    }

    func tick(now: Date? = nil) {
        guard !timers.isEmpty else {
            stopLoop()
            return
        }

        let currentDate = now ?? dateProvider()
        // Regular foreground ticking keeps timer state fresh and is allowed to
        // emit foreground completion alerts when a running timer finishes now.
        applyRunningStateReconciliation(
            now: currentDate,
            shouldEmitCompletionAlerts: true
        )
    }

    func reconcileAfterAppBecomesActive(now: Date? = nil) {
        guard !timers.isEmpty else {
            stopLoop()
            return
        }

        let currentDate = now ?? dateProvider()
        // Foreground reactivation runs while the same process is still alive.
        // Relaunch restore happens only once in init and must
        // not be re-entered from lifecycle hooks like this.
        applyRunningStateReconciliation(
            now: currentDate,
            shouldEmitCompletionAlerts: false
        )
    }

    func removeCompletedTimers() {
        let currentDate = dateProvider()
        let completedIDs = timers
            .filter { $0.status(at: currentDate) == .completed }
            .map(\.id)
        completedIDs.forEach { id in
            completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        }
        timers.removeAll { $0.status(at: currentDate) == .completed }

        stopLoopIfNeeded(now: currentDate)
        persistTimers()
    }

    func remove(id: UUID) {
        completionNotificationScheduler.cancelCompletionNotification(forTimerID: id)
        timers.removeAll { $0.id == id }
        stopLoopIfNeeded()
        persistTimers()
    }

    deinit {
        timer?.invalidate()
    }

    private func ensureTimerLoop() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopLoopIfNeeded(now: Date? = nil) {
        let currentDate = now ?? dateProvider()

        if !timers.contains(where: { $0.status(at: currentDate) == .running }) {
            stopLoop()
        }
    }

    private func stopLoop() {
        timer?.invalidate()
        timer = nil
    }

    private func completionEvent(
        from previous: TimerState,
        to updated: TimerState
    ) -> TimerCompletionEvent? {
        guard previous.status == .running,
              updated.status == .completed,
              let completionDate = updated.endDate else {
            return nil
        }

        return TimerCompletionEvent(
            timerID: updated.id,
            completionDate: completionDate
        )
    }

    private func applyRunningStateReconciliation(
        now currentDate: Date,
        shouldEmitCompletionAlerts: Bool
    ) {
        // Only running timers can advance to completed here. Paused timers are
        // frozen/resumable and keep their preserved remaining time regardless of
        // wall-clock passage, and completed timers remain completed.
        let transitionResult = timers.map { state in
            let updated = state.updatingStatus(at: currentDate)
            return (updated, completionEvent(from: state, to: updated))
        }

        timers = transitionResult.map(\.0)

        if shouldEmitCompletionAlerts {
            transitionResult
                .compactMap(\.1)
                .forEach(completionAlertService.handleTimerCompletion)
        }

        transitionResult
            .filter { $0.1 != nil }
            .forEach { updated, _ in
                completionNotificationScheduler.cancelCompletionNotification(
                    forTimerID: updated.id
                )
            }

        let hasRunningTimers = timers.contains { $0.status(at: currentDate) == .running }
        if hasRunningTimers {
            ensureTimerLoop()
        } else {
            stopLoop()
        }

        persistTimers()
    }

    private func restorePersistedTimersIfNeeded() {
        guard !hasRestoredPersistedTimers else {
            return
        }

        hasRestoredPersistedTimers = true

        guard let snapshot = persistenceStore.loadSnapshot() else {
            return
        }

        let currentDate = dateProvider()
        timers = snapshot.timers.map { $0.restore(at: currentDate) }

        if timers.contains(where: { $0.status(at: currentDate) == .running }) {
            ensureTimerLoop()
        } else {
            stopLoop()
        }

        // Relaunch restore is deterministic and init-only: it reads the
        // saved snapshot once, reconciles only running timers against wall
        // clock time, preserves paused timers as frozen resumable state, and
        // writes the normalized result back as the new source.
        persistTimers()
    }

    private func persistTimers() {
        guard !timers.isEmpty else {
            persistenceStore.clearSnapshot()
            return
        }

        persistenceStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(timers: timers)
        )
    }
}
