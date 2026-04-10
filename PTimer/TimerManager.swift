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
    case completed
    case stopped
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
        case .stopped:
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
        case .stopped:
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

    func stopping(at now: Date) -> TimerState {
        let remaining = remainingTime(at: now)

        guard remaining > 0 else {
            return completed(at: endDate ?? now)
        }

        return TimerState(
            id: id,
            duration: duration,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: remaining,
            pausedAt: now,
            status: .stopped
        )
    }

    func resume(at now: Date) -> TimerState {
        let remaining = sanitizeRemainingTime(pausedRemainingTime ?? 0)
        guard remaining > 0 else {
            return completed(at: resolvedCompletionDate())
        }

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
    private var timer: Timer?

    init(
        tickInterval: TimeInterval = 0.1,
        dateProvider: @escaping () -> Date = Date.init,
        completionAlertService: TimerCompletionAlerting = NoOpTimerCompletionAlertService()
    ) {
        self.tickInterval = tickInterval
        self.dateProvider = dateProvider
        self.completionAlertService = completionAlertService
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
        ensureTimerLoop()
        return id
    }

    func stop(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            stopLoopIfNeeded()
            return
        }

        let currentDate = dateProvider()
        timers[index] = timers[index].stopping(at: currentDate)
        stopLoopIfNeeded(now: currentDate)
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
            ensureTimerLoop()
        } else {
            stopLoopIfNeeded(now: currentDate)
        }
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
        // Reactivation reconciliation is state-only. It catches timers up to
        // wall clock time after inactive/background/lock without replaying
        // completion feedback that belongs to the foreground tick path.
        applyRunningStateReconciliation(
            now: currentDate,
            shouldEmitCompletionAlerts: false
        )
    }

    func removeCompletedTimers() {
        let currentDate = dateProvider()
        timers.removeAll { $0.status(at: currentDate) == .completed }

        stopLoopIfNeeded(now: currentDate)
    }

    func remove(id: UUID) {
        timers.removeAll { $0.id == id }
        stopLoopIfNeeded()
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
        // Only running timers can advance to completed here. Stopped timers keep
        // their preserved remaining time, and completed timers remain completed.
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

        let hasRunningTimers = timers.contains { $0.status(at: currentDate) == .running }
        if hasRunningTimers {
            ensureTimerLoop()
        } else {
            stopLoop()
        }
    }
}
