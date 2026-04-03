import Combine
import Foundation

struct RunningTimerItem: Identifiable, Equatable {
    let id: UUID
    let order: Int
    let name: String
    let basisSummary: String
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date?
    let completionDate: Date?
    let pausedRemainingTime: TimeInterval?
    let pausedAt: Date?
    let timerState: TimerState
    let referenceDateProvider: () -> Date

    var status: TimerStatus {
        timerState.status(at: referenceDateProvider())
    }

    var remainingTime: TimeInterval {
        timerState.remainingTime(at: referenceDateProvider())
    }

    var elapsedTime: TimeInterval {
        assert(!remainingTime.isNaN, "Remaining time must not be NaN.")
        return max(0, duration - remainingTime)
    }

    static func == (lhs: RunningTimerItem, rhs: RunningTimerItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.order == rhs.order &&
        lhs.name == rhs.name &&
        lhs.basisSummary == rhs.basisSummary &&
        lhs.duration == rhs.duration &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.completionDate == rhs.completionDate &&
        lhs.pausedRemainingTime == rhs.pausedRemainingTime &&
        lhs.pausedAt == rhs.pausedAt &&
        lhs.timerState == rhs.timerState
    }
}

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published var baseShutter = 1.0 / 30.0
    @Published var ndStop = 0
    @Published private(set) var timers: [RunningTimerItem] = []

    nonisolated static let shutterSpeeds = ExposureCalculator.fullStopShutterSpeeds

    private let calculator: ExposureCalculator
    private let timerManager: TimerManager
    private var timerMetadata: [UUID: TimerMetadata] = [:]
    private var nextTimerOrder = 1
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.calculator = ExposureCalculator()
        self.timerManager = TimerManager()

        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    init(
        calculator: ExposureCalculator,
        timerManager: TimerManager
    ) {
        self.calculator = calculator
        self.timerManager = timerManager

        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        do {
            let resultShutter = try calculator.calculate(
                baseShutterSeconds: baseShutter,
                stop: ndStop
            )

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: baseShutter,
                    stop: ndStop,
                    resultShutterSeconds: resultShutter
                )
            )
        } catch let error as ExposureCalculatorError {
            return .failure(error)
        } catch {
            return .failure(.overflow)
        }
    }

    var canStartTimer: Bool {
        switch calculationResult {
        case .success(let result):
            return result.resultShutterSeconds > 0
        case .failure:
            return false
        }
    }

    func startTimer() {
        guard case .success(let result) = calculationResult else {
            return
        }

        startTimer(from: result.resultShutterSeconds, result: result)
    }

    func startTimer(from resultShutter: TimeInterval) {
        startTimer(
            from: resultShutter,
            result: calculationPayload(for: resultShutter)
        )
    }

    func stopTimer(id: UUID) {
        timerManager.stop(id: id)
        syncTimers(with: timerManager.timers)
    }

    func resumeTimer(id: UUID) {
        timerManager.resume(id: id)
        syncTimers(with: timerManager.timers)
    }

    func removeTimer(id: UUID) {
        timerManager.remove(id: id)
        timerMetadata.removeValue(forKey: id)
        syncTimers(with: timerManager.timers)
    }

    private func startTimer(
        from resultShutter: TimeInterval,
        result: ExposureCalculationResult?
    ) {
        guard let id = timerManager.start(duration: resultShutter) else {
            return
        }

        let timerName: String
        if let result {
            timerName = makeTimerName(for: result)
        } else {
            timerName = defaultName(for: resultShutter)
        }

        let order = nextTimerOrder
        nextTimerOrder += 1
        timerMetadata[id] = TimerMetadata(
            order: order,
            name: timerName,
            basisSummary: makeBasisSummary(for: result)
        )
        syncTimers(with: timerManager.timers)
    }

    func clearCompletedTimers() {
        timerManager.removeCompletedTimers()
        syncTimers(with: timerManager.timers)
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        calculator.formatShutter(seconds)
    }

    func formatTimeDisplay(_ seconds: TimeInterval) -> TimeDisplay {
        calculator.formatTimeDisplay(seconds)
    }

    func formatShutter(_ seconds: TimeInterval) -> String {
        calculator.formatShutter(seconds)
    }

    func formatTimerClock(_ seconds: TimeInterval) -> String {
        calculator.formatExtendedClock(seconds)
    }

    func formatClockTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }

    func formatDateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }

    func timerTargetContext(for timer: RunningTimerItem) -> String? {
        let targetDisplay = formatTimeDisplay(timer.duration)

        switch timer.status {
        case .running, .stopped:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        case .completed:
            return nil
        }
    }

    func timerTimeContext(for timer: RunningTimerItem) -> String? {
        switch timer.status {
        case .running:
            let completionText = timer.endDate.map(formatDateTime) ?? "--"
            return "Ends \(completionText)"
        case .completed:
            let completionText = timer.completionDate.map(formatDateTime) ?? "--"
            return "Completed \(completionText)"
        case .stopped:
            let pausedText = timer.pausedAt.map(formatDateTime) ?? "--"
            return "Paused \(pausedText)"
        }
    }

    var runningTimerCount: Int {
        timers.filter { $0.status == .running }.count
    }

    private func makeTimerName(for result: ExposureCalculationResult) -> String {
        "\(ndStopLabel(for: result.stop)) - \(calculator.formatShutter(result.resultShutterSeconds))"
    }

    private func syncTimers(with states: [TimerState]) {
        let validIDs = Set(states.map(\.id))
        timerMetadata = timerMetadata.filter { validIDs.contains($0.key) }
        timers = states
            .map { state in
                RunningTimerItem(
                    id: state.id,
                    order: timerMetadata[state.id]?.order ?? 0,
                    name: timerMetadata[state.id]?.name ?? defaultName(for: state.duration),
                    basisSummary: timerMetadata[state.id]?.basisSummary ?? "Manual timer",
                    duration: state.duration,
                    startDate: state.startDate,
                    endDate: state.endDate,
                    completionDate: state.completionDate,
                    pausedRemainingTime: state.pausedRemainingTime,
                    pausedAt: state.pausedAt,
                    timerState: state,
                    referenceDateProvider: { [weak timerManager = self.timerManager] in
                        timerManager?.currentDate ?? Date()
                    }
                )
            }
            .sorted(by: sortTimers)
    }

    private func sortTimers(lhs: RunningTimerItem, rhs: RunningTimerItem) -> Bool {
        let lhsRank = statusRank(lhs.status)
        let rhsRank = statusRank(rhs.status)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        return lhs.duration > rhs.duration
    }

    private func statusRank(_ status: TimerStatus) -> Int {
        switch status {
        case .running:
            return 0
        case .stopped:
            return 1
        case .completed:
            return 2
        }
    }

    private func defaultName(for duration: TimeInterval) -> String {
        "Timer - \(calculator.formatShutter(duration))"
    }

    private func makeBasisSummary(for result: ExposureCalculationResult?) -> String {
        guard let result else {
            return "Manual timer"
        }

        return "Base \(calculator.formatShutter(result.baseShutterSeconds)) · \(ndStopLabel(for: result.stop))"
    }

    private func ndStopLabel(for stop: Int) -> String {
        stop == 1 ? "1 stop" : "\(stop) stops"
    }

    private func calculationPayload(for resultShutter: TimeInterval) -> ExposureCalculationResult? {
        guard case .success(let result) = calculationResult else {
            return nil
        }

        guard abs(result.resultShutterSeconds - resultShutter) < 0.0001 else {
            return nil
        }

        return result
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct TimerMetadata {
    let order: Int
    let name: String
    let basisSummary: String
}
