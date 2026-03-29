import Foundation

enum TimerStatus: String, Equatable {
    case idle
    case running
    case completed
}

struct TimerSnapshot: Equatable {
    let name: String
    let totalDuration: TimeInterval
    let baseShutterSeconds: Double
    let ndFactor: Double
    let resultShutterSeconds: Double
}

struct TimerState: Equatable {
    let duration: TimeInterval
    let remainingTime: TimeInterval
    let elapsedTime: TimeInterval
    let status: TimerStatus
    let snapshot: TimerSnapshot?

    static let idle = TimerState(
        duration: 0,
        remainingTime: 0,
        elapsedTime: 0,
        status: .idle,
        snapshot: nil
    )
}

@MainActor
final class TimerManager: ObservableObject {
    @Published private(set) var state: TimerState = .idle

    private let tickInterval: TimeInterval
    private let dateProvider: () -> Date
    private var timer: Timer?
    private var endDate: Date?

    init(
        tickInterval: TimeInterval = 0.1,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.tickInterval = tickInterval
        self.dateProvider = dateProvider
    }

    func start(snapshot: TimerSnapshot) {
        stopTimer()

        guard snapshot.totalDuration > 0 else {
            state = TimerState(
                duration: 0,
                remainingTime: 0,
                elapsedTime: 0,
                status: .completed,
                snapshot: snapshot
            )
            return
        }

        let now = dateProvider()
        let endDate = now.addingTimeInterval(snapshot.totalDuration)
        self.endDate = endDate

        state = TimerState(
            duration: snapshot.totalDuration,
            remainingTime: snapshot.totalDuration,
            elapsedTime: 0,
            status: .running,
            snapshot: snapshot
        )

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        stopTimer()
        state = .idle
    }

    func tick(now: Date? = nil) {
        guard state.status == .running, let endDate else {
            return
        }

        let currentDate = now ?? dateProvider()
        let remaining = max(0, endDate.timeIntervalSince(currentDate))

        if remaining <= 0 {
            stopTimer()
            state = TimerState(
                duration: state.duration,
                remainingTime: 0,
                elapsedTime: state.duration,
                status: .completed,
                snapshot: state.snapshot
            )
            return
        }

        state = TimerState(
            duration: state.duration,
            remainingTime: remaining,
            elapsedTime: state.duration - remaining,
            status: .running,
            snapshot: state.snapshot
        )
    }

    deinit {
        timer?.invalidate()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
    }
}
