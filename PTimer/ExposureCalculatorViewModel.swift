import Combine
import Foundation

struct RunningTimerItem: Identifiable, Equatable {
    let id: UUID
    let order: Int
    let name: String
    let basisSummary: String
    let duration: TimeInterval
    let endDate: Date?
    let pausedRemainingTime: TimeInterval?
    let status: TimerStatus
    let referenceDate: Date

    var remainingTime: TimeInterval {
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return max(0, endDate.timeIntervalSince(referenceDate))
        case .stopped:
            return max(0, pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    var elapsedTime: TimeInterval {
        max(0, duration - remainingTime)
    }
}

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published var baseShutterInput = "1/30"
    @Published var ndStop = 0
    @Published private(set) var timers: [RunningTimerItem] = []

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
            let baseShutter = try calculator.parseBaseShutter(baseShutterInput)
            let ndFactor = ndFactor(for: ndStop)
            let resultShutter = try calculator.calculate(
                baseShutterSeconds: baseShutter,
                ndFactor: ndFactor
            )

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: baseShutter,
                    ndFactor: ndFactor,
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

    func formatTimerClock(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    var runningTimerCount: Int {
        timers.filter { $0.status == .running }.count
    }

    private func makeTimerName(for result: ExposureCalculationResult) -> String {
        "\(ndStopLabel(for: result.ndFactor)) - \(calculator.formatShutter(result.resultShutterSeconds))"
    }

    private func syncTimers(with states: [TimerState]) {
        let validIDs = Set(states.map(\.id))
        timerMetadata = timerMetadata.filter { validIDs.contains($0.key) }
        let referenceDate = timerManager.currentDate

        timers = states
            .map { state in
                RunningTimerItem(
                    id: state.id,
                    order: timerMetadata[state.id]?.order ?? 0,
                    name: timerMetadata[state.id]?.name ?? defaultName(for: state.duration),
                    basisSummary: timerMetadata[state.id]?.basisSummary ?? "Manual timer",
                    duration: state.duration,
                    endDate: state.endDate,
                    pausedRemainingTime: state.pausedRemainingTime,
                    status: state.status,
                    referenceDate: referenceDate
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
        case .completed:
            return 1
        case .stopped:
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

        return "Base \(calculator.formatShutter(result.baseShutterSeconds)) · \(ndStopLabel(for: result.ndFactor))"
    }

    private func ndStopLabel(for factor: Double) -> String {
        let computedStop: Int

        do {
            computedStop = Int(try calculator.ndStops(for: factor).rounded())
        } catch {
            computedStop = 0
        }

        return "\(computedStop) stop"
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

    private func ndFactor(for stop: Int) -> Double {
        // TODO: remove ndFactor when PTIMER-22 is complete
        pow(2.0, Double(stop))
    }
}

private struct TimerMetadata {
    let order: Int
    let name: String
    let basisSummary: String
}
