import Combine
import Foundation

struct DockCompactTimeDisplay: Equatable {
    let primaryText: String
    let secondaryText: String
    let accessibilityText: String
}

enum DockCompactTimeFormatter {
    private static let daySeconds = 86_400
    private static let monthSeconds = daySeconds * 30
    private static let yearSeconds = daySeconds * 365

    static func format(_ seconds: TimeInterval) -> DockCompactTimeDisplay {
        let clamped = max(0, seconds)
        let wholeSeconds = Int(clamped.rounded(.down))

        if wholeSeconds >= yearSeconds {
            let years = wholeSeconds / yearSeconds
            return DockCompactTimeDisplay(
                primaryText: "\(years)y",
                secondaryText: "",
                accessibilityText: "\(years)y"
            )
        }

        if wholeSeconds >= monthSeconds {
            let months = wholeSeconds / monthSeconds
            let days = (wholeSeconds % monthSeconds) / daySeconds
            return DockCompactTimeDisplay(
                primaryText: "\(months)mo",
                secondaryText: "\(days)d",
                accessibilityText: "\(months)mo \(days)d"
            )
        }

        if wholeSeconds >= daySeconds {
            let days = wholeSeconds / daySeconds
            let hours = (wholeSeconds % daySeconds) / 3_600
            return DockCompactTimeDisplay(
                primaryText: "\(days)d",
                secondaryText: "\(hours)h",
                accessibilityText: "\(days)d \(hours)h"
            )
        }

        if wholeSeconds >= 3_600 {
            let hours = wholeSeconds / 3_600
            let minutes = (wholeSeconds % 3_600) / 60
            return DockCompactTimeDisplay(
                primaryText: "\(hours)h",
                secondaryText: String(format: "%02dm", minutes),
                accessibilityText: "\(hours)h \(minutes)m"
            )
        }

        if wholeSeconds >= 60 {
            let minutes = wholeSeconds / 60
            let secondsPart = wholeSeconds % 60
            return DockCompactTimeDisplay(
                primaryText: "\(minutes)m",
                secondaryText: String(format: "%02ds", secondsPart),
                accessibilityText: "\(minutes)m \(secondsPart)s"
            )
        }

        return DockCompactTimeDisplay(
            primaryText: "\(wholeSeconds)s",
            secondaryText: "",
            accessibilityText: "\(wholeSeconds)s"
        )
    }
}

struct TimerCreationRequest: Equatable {
    let duration: TimeInterval
    let name: String
    let basisSummary: String
}

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

@MainActor
final class TimerRuntimeStore: ObservableObject {
    @Published private(set) var timers: [RunningTimerItem] = []

    private let timerManager: TimerManager
    private let calculator = ExposureCalculator()
    private var timerMetadata: [UUID: TimerMetadata] = [:]
    private var nextTimerOrder = 1
    private var cancellables: Set<AnyCancellable> = []

    init(timerManager: TimerManager) {
        self.timerManager = timerManager

        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    convenience init() {
        self.init(timerManager: TimerManager())
    }

    var visibleTimers: [RunningTimerItem] {
        timers.sorted(by: compareVisibleTimers(_:_:))
    }

    var runningTimerCount: Int {
        timers.filter { $0.status == .running }.count
    }

    func startTimer(_ request: TimerCreationRequest) {
        guard let id = timerManager.start(duration: request.duration) else {
            return
        }

        let order = nextTimerOrder
        nextTimerOrder += 1
        timerMetadata[id] = TimerMetadata(
            order: order,
            name: request.name,
            basisSummary: request.basisSummary
        )
        syncTimers(with: timerManager.timers)
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

    func clearCompletedTimers() {
        timerManager.removeCompletedTimers()
        syncTimers(with: timerManager.timers)
    }

    func formatTimeDisplay(_ seconds: TimeInterval) -> TimeDisplay {
        calculator.formatTimeDisplay(seconds)
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

    private func syncTimers(with states: [TimerState]) {
        let validIDs = Set(states.map(\.id))
        timerMetadata = timerMetadata.filter { validIDs.contains($0.key) }
        let referenceDate = timerManager.currentDate

        timers = states.map { state in
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
    }

    private func compareVisibleTimers(_ lhs: RunningTimerItem, _ rhs: RunningTimerItem) -> Bool {
        let lhsPriority = priority(for: lhs.status)
        let rhsPriority = priority(for: rhs.status)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }

        return lhs.startDate > rhs.startDate
    }

    private func priority(for status: TimerStatus) -> Int {
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

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published var baseShutter = 1.0 / 30.0
    @Published var ndStop = 0

    nonisolated static let shutterSpeeds = ExposureCalculator.fullStopShutterSpeeds

    let timerRuntimeStore: TimerRuntimeStore

    private let calculator: ExposureCalculator
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let timerRuntimeStore = TimerRuntimeStore()
        self.calculator = ExposureCalculator()
        self.timerRuntimeStore = timerRuntimeStore
        bindTimerRuntimeStore()
    }

    init(
        calculator: ExposureCalculator,
        timerManager: TimerManager
    ) {
        self.calculator = calculator
        self.timerRuntimeStore = TimerRuntimeStore(timerManager: timerManager)
        bindTimerRuntimeStore()
    }

    init(
        calculator: ExposureCalculator,
        timerRuntimeStore: TimerRuntimeStore
    ) {
        self.calculator = calculator
        self.timerRuntimeStore = timerRuntimeStore
        bindTimerRuntimeStore()
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

    var timers: [RunningTimerItem] {
        timerRuntimeStore.timers
    }

    var runningTimerCount: Int {
        timerRuntimeStore.runningTimerCount
    }

    func startTimer() {
        guard let request = makeTimerCreationRequest() else {
            return
        }

        timerRuntimeStore.startTimer(request)
    }

    func startTimer(from resultShutter: TimeInterval) {
        timerRuntimeStore.startTimer(
            TimerCreationRequest(
                duration: resultShutter,
                name: defaultName(for: resultShutter),
                basisSummary: makeBasisSummary(for: calculationPayload(for: resultShutter))
            )
        )
    }

    func stopTimer(id: UUID) {
        timerRuntimeStore.stopTimer(id: id)
    }

    func resumeTimer(id: UUID) {
        timerRuntimeStore.resumeTimer(id: id)
    }

    func removeTimer(id: UUID) {
        timerRuntimeStore.removeTimer(id: id)
    }

    func clearCompletedTimers() {
        timerRuntimeStore.clearCompletedTimers()
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
        timerRuntimeStore.formatClockTime(date)
    }

    func formatDateTime(_ date: Date) -> String {
        timerRuntimeStore.formatDateTime(date)
    }

    func timerTargetContext(for timer: RunningTimerItem) -> String? {
        timerRuntimeStore.timerTargetContext(for: timer)
    }

    func timerTimeContext(for timer: RunningTimerItem) -> String? {
        timerRuntimeStore.timerTimeContext(for: timer)
    }

    func makeTimerCreationRequest() -> TimerCreationRequest? {
        guard case .success(let result) = calculationResult else {
            return nil
        }

        return TimerCreationRequest(
            duration: result.resultShutterSeconds,
            name: makeTimerName(for: result),
            basisSummary: makeBasisSummary(for: result)
        )
    }

    private func makeTimerName(for result: ExposureCalculationResult) -> String {
        "\(ndStopLabel(for: result.stop)) - \(calculator.formatShutter(result.resultShutterSeconds))"
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

    private func bindTimerRuntimeStore() {
        timerRuntimeStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

private struct TimerMetadata {
    let order: Int
    let name: String
    let basisSummary: String
}
