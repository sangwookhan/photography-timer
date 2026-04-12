import Combine
import Foundation
import AudioToolbox
import UIKit

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
// - expectedCompletionAt lets PTIMER-70 reconcile running timers to wall clock time.
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
            self.status = .paused
            self.expectedCompletionAt = timer.endDate
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
            // `paused` restores as the same frozen, resumable state. It must
            // not consume wall-clock time or auto-complete while the app was dead.
            return TimerState(
                id: id,
                duration: duration,
                startDate: startDate,
                endDate: expectedCompletionAt,
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

struct TimerState: Identifiable, Equatable {
    let id: UUID
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date?
    let pausedRemainingTime: TimeInterval?
    let pausedAt: Date?
    let status: TimerStatus

    var remainingTime: TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return sanitizeRemainingTime(endDate.timeIntervalSinceNow)
        case .paused:
            return sanitizeRemainingTime(pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    func remainingTime(at now: Date) -> TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return sanitizeRemainingTime(endDate.timeIntervalSince(now))
        case .paused:
            return sanitizeRemainingTime(pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    func status(at now: Date) -> TimerStatus {
        guard status == .running,
              let endDate,
              now.addingTimeInterval(timerStabilityEpsilon) >= endDate else {
            return status
        }

        return .completed
    }

    func updatingStatus(at now: Date) -> TimerState {
        guard status == .running,
              let endDate,
              now.addingTimeInterval(timerStabilityEpsilon) >= endDate else {
            return self
        }

        return completed(at: endDate)
    }

    func pausing(at now: Date) -> TimerState {
        let remaining = remainingTime(at: now)

        guard remaining > 0 else {
            return completed(at: endDate ?? now)
        }

        // Freeze the timer with its remaining duration intact so it can be
        // resumed later from the same logical point.
        return TimerState(
            id: id,
            duration: duration,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: remaining,
            pausedAt: now,
            status: .paused
        )
    }

    func resume(at now: Date) -> TimerState {
        let remaining = sanitizeRemainingTime(pausedRemainingTime ?? 0)
        guard remaining > 0 else {
            return completed(at: resolvedCompletionDate())
        }

        // Resume recalculates the end date from "now" because `paused`
        // preserves remaining time as a frozen resumable state.
        return TimerState(
            id: id,
            duration: duration,
            startDate: startDate,
            endDate: now.addingTimeInterval(remaining),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )
    }

    func completed(at completionDate: Date? = nil) -> TimerState {
        TimerState(
            id: id,
            duration: duration,
            startDate: startDate,
            endDate: completionDate ?? resolvedCompletionDate(),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed
        )
    }

    private func resolvedCompletionDate() -> Date {
        if let endDate {
            return endDate
        }

        if let pausedAt {
            return pausedAt.addingTimeInterval(sanitizeRemainingTime(pausedRemainingTime ?? 0))
        }

        return startDate.addingTimeInterval(duration)
    }

    private func sanitizeRemainingTime(_ value: TimeInterval) -> TimeInterval {
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
        guard duration > 0 else {
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
        // PTIMER-67 covers foreground reactivation while the same process is
        // still alive. PTIMER-70 restore happens only once in init and must
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

        // PTIMER-70 restore is deterministic and init-only: relaunch reads the
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
