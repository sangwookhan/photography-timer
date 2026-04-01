import Combine
import Foundation

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
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return max(0, endDate.timeIntervalSinceNow)
        case .stopped:
            return max(0, pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    func remainingTime(at now: Date) -> TimeInterval {
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return max(0, endDate.timeIntervalSince(now))
        case .stopped:
            return max(0, pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    func status(at now: Date) -> TimerStatus {
        if status == .running,
           let endDate,
           now >= endDate {
            return .completed
        }

        return status
    }

    func stopping(at now: Date) -> TimerState {
        let remaining = remainingTime(at: now)

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

    func resuming(at now: Date) -> TimerState? {
        let remaining = max(0, pausedRemainingTime ?? 0)
        guard remaining > 0 else {
            return nil
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

    func completed() -> TimerState {
        TimerState(
            id: id,
            duration: duration,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: pausedAt,
            status: .completed
        )
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
        guard let resumedState = timers[index].resuming(at: currentDate) else {
            timers.remove(at: index)
            stopLoopIfNeeded(now: currentDate)
            return
        }

        timers[index] = resumedState
        ensureTimerLoop()
    }

    func tick(now: Date? = nil) {
        guard !timers.isEmpty else {
            stopLoop()
            return
        }

        let currentDate = now ?? dateProvider()
        timers = timers.map { timerState in
            guard timerState.status == .running,
                  let endDate = timerState.endDate,
                  currentDate >= endDate else {
                return timerState
            }

            return timerState.completed()
        }
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
