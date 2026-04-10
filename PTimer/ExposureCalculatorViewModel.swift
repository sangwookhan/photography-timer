import Combine
import Foundation

struct RunningTimerItem: Identifiable, Equatable {
    private static let stabilityEpsilon = ExposureCalculator.stabilityEpsilon

    let id: UUID
    let order: Int
    let name: String
    let basisSummary: String
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date?
    let pausedRemainingTime: TimeInterval?
    let pausedAt: Date?
    let status: TimerStatus
    let referenceDate: Date

    var remainingTime: TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return sanitizeRemainingTime(endDate.timeIntervalSince(referenceDate))
        case .stopped:
            return sanitizeRemainingTime(pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    var elapsedTime: TimeInterval {
        assert(!remainingTime.isNaN, "Remaining time must not be NaN.")
        return max(0, duration - remainingTime)
    }

    var completedAt: Date? {
        guard status == .completed, let endDate else {
            return nil
        }

        return endDate
    }

    private func sanitizeRemainingTime(_ value: TimeInterval) -> TimeInterval {
        assert(!value.isNaN, "Remaining time input must not be NaN.")
        let clamped = max(0, value)
        return clamped < Self.stabilityEpsilon ? 0 : clamped
    }
}

enum TimerWorkspaceOrdering {
    static func sort(_ timers: [RunningTimerItem]) -> [RunningTimerItem] {
        timers.sorted(by: areInPresentationOrder(lhs:rhs:))
    }

    static func areInPresentationOrder(lhs: RunningTimerItem, rhs: RunningTimerItem) -> Bool {
        let lhsGroup = presentationGroup(lhs.status)
        let rhsGroup = presentationGroup(rhs.status)

        if lhsGroup != rhsGroup {
            return lhsGroup < rhsGroup
        }

        switch lhsGroup {
        case 0:
            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
        case 1:
            if lhs.completedAt != rhs.completedAt {
                return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }

            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
        default:
            break
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func presentationGroup(_ status: TimerStatus) -> Int {
        switch status {
        case .running, .stopped:
            return 0
        case .completed:
            return 1
        }
    }
}

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published var baseShutter = 1.0 / 30.0 {
        didSet {
            if liveBaseShutter == baseShutter {
                liveBaseShutter = nil
            }
        }
    }
    @Published var ndStop = 0 {
        didSet {
            if liveNDStop == ndStop {
                liveNDStop = nil
            }
        }
    }
    @Published private(set) var timers: [RunningTimerItem] = []
    @Published private var liveBaseShutter: Double?
    @Published private var liveNDStop: Int?

    nonisolated static let shutterSpeeds = ExposureCalculator.fullStopShutterSpeeds

    private let calculator: ExposureCalculator
    private let timerManager: TimerManager
    private var timerMetadata: [UUID: TimerMetadata] = [:]
    private var nextTimerOrder = 1
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.calculator = ExposureCalculator()
        self.timerManager = TimerManager(
            completionAlertService: ForegroundTimerCompletionAlertService(
                feedbackPlayer: SystemTimerCompletionFeedbackPlayer()
            )
        )

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
                baseShutterSeconds: effectiveBaseShutter,
                stop: effectiveNDStop
            )

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: effectiveBaseShutter,
                    stop: effectiveNDStop,
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
    }

    func resumeTimer(id: UUID) {
        timerManager.resume(id: id)
    }

    func removeTimer(id: UUID) {
        timerManager.remove(id: id)
        timerMetadata.removeValue(forKey: id)
    }

    private func startTimer(
        from resultShutter: TimeInterval,
        result: ExposureCalculationResult?
    ) {
        let id = UUID()

        let timerName: String
        if let result {
            timerName = makeTimerName(for: result)
        } else {
            timerName = defaultName(for: resultShutter)
        }

        let order = nextTimerOrder
        timerMetadata[id] = TimerMetadata(
            order: order,
            name: timerName,
            basisSummary: makeBasisSummary(for: result)
        )

        guard timerManager.start(id: id, duration: resultShutter) != nil else {
            timerMetadata.removeValue(forKey: id)
            return
        }

        nextTimerOrder += 1
    }

    func clearCompletedTimers() {
        let completedIDs = Set(
            timers
                .filter { $0.status == .completed }
                .map(\.id)
        )
        timerManager.removeCompletedTimers()
        completedIDs.forEach { id in
            timerMetadata.removeValue(forKey: id)
        }
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
            let completionText = timer.completedAt.map(formatDateTime) ?? "--"
            return "Completed \(completionText)"
        case .stopped:
            let pausedText = timer.pausedAt.map(formatDateTime) ?? "--"
            return "Paused \(pausedText)"
        }
    }

    var runningTimerCount: Int {
        timers.filter { $0.status == .running }.count
    }

    func updateLiveBaseShutter(_ value: Double) {
        liveBaseShutter = value == baseShutter ? nil : value
    }

    func updateLiveNDStop(_ value: Int) {
        liveNDStop = value == ndStop ? nil : value
    }

    func clearLiveBaseShutterPreview() {
        liveBaseShutter = nil
    }

    func clearLiveNDStopPreview() {
        liveNDStop = nil
    }

    private var effectiveBaseShutter: Double {
        liveBaseShutter ?? baseShutter
    }

    private var effectiveNDStop: Int {
        liveNDStop ?? ndStop
    }

    private func makeTimerName(for result: ExposureCalculationResult) -> String {
        "\(ndStopLabel(for: result.stop)) - \(calculator.formatShutter(result.resultShutterSeconds))"
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
                    startDate: state.startDate,
                    endDate: state.endDate,
                    pausedRemainingTime: state.pausedRemainingTime,
                    pausedAt: state.pausedAt,
                    status: state.status,
                    referenceDate: referenceDate
                )
            }
            .sorted(by: TimerWorkspaceOrdering.areInPresentationOrder(lhs:rhs:))
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
