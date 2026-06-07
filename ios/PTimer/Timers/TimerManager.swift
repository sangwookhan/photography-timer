import Combine
import PTimerCore
import Foundation
import AudioToolbox
import UIKit

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

