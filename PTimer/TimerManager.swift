import Combine
import Foundation

private let timerStabilityEpsilon: TimeInterval = ExposureCalculator.stabilityEpsilon

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

        if let pausedAt,
           pausedAt.addingTimeInterval(remaining) <= now.addingTimeInterval(timerStabilityEpsilon) {
            return completed(at: pausedAt.addingTimeInterval(remaining))
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
    private var timer: Timer?
    init(
        tickInterval: TimeInterval = 0.1,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.tickInterval = tickInterval
        self.dateProvider = dateProvider
    }

    @discardableResult
    func start(duration: TimeInterval) -> UUID? {
        guard duration > 0 else {
            return nil
        }

        let now = dateProvider()
        let id = UUID()
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
        timers = timers.map { $0.updatingStatus(at: currentDate) }
        stopLoopIfNeeded(now: currentDate)
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
}
