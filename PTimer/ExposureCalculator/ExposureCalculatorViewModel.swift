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
        case .paused:
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
        case .running, .paused:
            return 0
        case .completed:
            return 1
        }
    }
}

@MainActor
final class LockScreenTimerTargetCoordinator {
    private let exposer: LockScreenTimerTargetExposing
    private var activeTarget: LockScreenTimerTarget?

    init(exposer: LockScreenTimerTargetExposing) {
        self.exposer = exposer
    }

    func sync(with timers: [RunningTimerItem]) {
        let nextTarget = Self.selectRepresentativeTarget(from: timers)

        guard nextTarget != activeTarget else {
            return
        }

        activeTarget = nextTarget

        if let nextTarget {
            exposer.expose(nextTarget)
        } else {
            exposer.clear()
        }
    }

    // PTIMER-69 selection rule:
    // 1. Choose the running timer with the earliest endDate.
    // 2. If endDate is tied, prefer the existing workspace presentation order.
    // 3. If that is still tied, prefer the stable id order.
    static func selectRepresentativeTarget(from timers: [RunningTimerItem]) -> LockScreenTimerTarget? {
        let eligibleTargets = eligibleRunningTimers(from: timers)

        guard let timer = eligibleTargets.first else {
            return nil
        }

        return LockScreenTimerTarget(
            representativeTimerID: timer.timer.id,
            representativeTimerName: timer.timer.name,
            representativeEndDate: timer.endDate,
            scheduledTargets: eligibleTargets.map {
                LockScreenTimerScheduledTarget(
                    timerID: $0.timer.id,
                    timerName: $0.timer.name,
                    endDate: $0.endDate
                )
            }
        )
    }

    private static func eligibleRunningTimers(from timers: [RunningTimerItem]) -> [EligibleRunningTimer] {
        timers
            .compactMap { timer in
                guard timer.status == .running, let endDate = timer.endDate else {
                    return nil
                }

                return EligibleRunningTimer(timer: timer, endDate: endDate)
            }
            .sorted(by: areInRepresentativeOrder(lhs:rhs:))
    }

    private static func areInRepresentativeOrder(
        lhs: EligibleRunningTimer,
        rhs: EligibleRunningTimer
    ) -> Bool {
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        if TimerWorkspaceOrdering.areInPresentationOrder(lhs: lhs.timer, rhs: rhs.timer) {
            return true
        }

        if TimerWorkspaceOrdering.areInPresentationOrder(lhs: rhs.timer, rhs: lhs.timer) {
            return false
        }

        return lhs.timer.id.uuidString < rhs.timer.id.uuidString
    }
}

private struct EligibleRunningTimer {
    let timer: RunningTimerItem
    let endDate: Date

    init(timer: RunningTimerItem, endDate: Date) {
        self.timer = timer
        self.endDate = endDate
    }
}

struct PersistentTimerMetadataSnapshot: Codable, Equatable {
    let id: UUID
    let order: Int
    let name: String
    let basisSummary: String
}

struct PersistentTimerMetadataCollectionSnapshot: Codable, Equatable {
    let nextTimerOrder: Int
    let timers: [PersistentTimerMetadataSnapshot]
}

protocol TimerMetadataPersistenceStoring {
    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot?
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot)
    func clearSnapshot()
}

struct NoOpTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot) {}
    func clearSnapshot() {}
}

struct UserDefaultsTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.timer-metadata.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentTimerMetadataCollectionSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published private(set) var activeCalculatorContext = ActiveExposureCalculatorContext()
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
    private let presetFilms: [FilmIdentity]
    private let timerManager: TimerManager
    private let metadataPersistenceStore: TimerMetadataPersistenceStoring
    private let lockScreenTargetCoordinator: LockScreenTimerTargetCoordinator
    private let reciprocityEvaluator = ReciprocityCalculationPolicyEvaluator()
    private let completedRelativeTimeFormatter = CompletedRelativeTimeFormatter()
    private var timerMetadata: [UUID: TimerMetadata] = [:]
    private var nextTimerOrder = 1
    private var cancellables: Set<AnyCancellable> = []
    private var completedTimeContextRefreshTimer: Timer?

    init() {
        self.calculator = ExposureCalculator()
        self.presetFilms = LaunchPresetFilmCatalog.films
        self.timerManager = TimerManager(
            completionAlertService: ForegroundTimerCompletionAlertService(
                feedbackPlayer: SystemTimerCompletionFeedbackPlayer()
            ),
            completionNotificationScheduler: UserNotificationTimerCompletionScheduler(),
            persistenceStore: UserDefaultsTimerPersistenceStore()
        )
        self.metadataPersistenceStore = UserDefaultsTimerMetadataPersistenceStore()
        self.lockScreenTargetCoordinator = LockScreenTimerTargetCoordinator(
            exposer: ActivityKitLockScreenTimerTargetExposer()
        )

        restorePersistedTimerMetadata()
        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    init(
        calculator: ExposureCalculator,
        timerManager: TimerManager,
        presetFilms: [FilmIdentity] = LaunchPresetFilmCatalog.films,
        metadataPersistenceStore: TimerMetadataPersistenceStoring = NoOpTimerMetadataPersistenceStore(),
        lockScreenTargetExposer: LockScreenTimerTargetExposing = NoOpLockScreenTimerTargetExposer()
    ) {
        self.calculator = calculator
        self.presetFilms = presetFilms
        self.timerManager = timerManager
        self.metadataPersistenceStore = metadataPersistenceStore
        self.lockScreenTargetCoordinator = LockScreenTimerTargetCoordinator(
            exposer: lockScreenTargetExposer
        )

        restorePersistedTimerMetadata()
        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    var calculatorMode: ExposureCalculatorMode {
        activeCalculatorContext.mode
    }

    var availablePresetFilms: [FilmIdentity] {
        presetFilms
    }

    var selectedPresetFilm: FilmIdentity? {
        activeCalculatorContext.selectedPresetFilm
    }

    var filmRowSelectionState: FilmModeSelectionState {
        guard calculatorMode == .film else {
            return .hidden
        }

        guard let selectedPresetFilm else {
            return .noFilmSelected
        }

        return .selectedPreset(selectedPresetFilm)
    }

    var shouldShowFilmRow: Bool {
        calculatorMode == .film
    }

    var selectedPresetFilmDisplayName: String? {
        selectedPresetFilm?.canonicalStockName
    }

    var filmReciprocityBindingState: FilmModeReciprocityBindingState? {
        guard calculatorMode == .film,
              let selectedPresetFilm,
              let profile = selectedPresetFilm.profiles.first,
              case .success(let result) = calculationResult else {
            return nil
        }

        let policyResult = reciprocityEvaluator.evaluate(
            profile: profile,
            meteredExposureSeconds: result.resultShutterSeconds
        )

        return FilmModeReciprocityBindingState(
            film: selectedPresetFilm,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    var filmReciprocityBindingSummaryText: String {
        if filmReciprocityBindingState != nil {
            return "Preset film bound"
        }

        return calculatorMode == .film ? "No film selected" : ""
    }

    var filmModeExposureResultState: FilmModeExposureResultState? {
        guard calculatorMode == .film,
              case .success(let result) = calculationResult else {
            return nil
        }

        return FilmModeExposureResultState(
            adjustedShutterSeconds: result.resultShutterSeconds,
            correctedExposure: correctedExposureDisplayState(
                adjustedShutterSeconds: result.resultShutterSeconds
            )
        )
    }

    var filmModePrimaryResultSeconds: TimeInterval? {
        guard let filmModeExposureResultState else {
            return nil
        }

        return filmModeExposureResultState.correctedExposure.correctedExposureSeconds
            ?? filmModeExposureResultState.adjustedShutterSeconds
    }

    func setCalculatorMode(_ mode: ExposureCalculatorMode) {
        activeCalculatorContext.mode = mode
    }

    func selectPresetFilm(_ film: FilmIdentity) {
        activeCalculatorContext.selectedPresetFilm = film
    }

    func clearSelectedPresetFilm() {
        activeCalculatorContext.selectedPresetFilm = nil
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
        if let filmModePrimaryResultSeconds {
            return filmModePrimaryResultSeconds > 0
        }

        guard case .success(let result) = calculationResult else {
            return false
        }

        return result.resultShutterSeconds > 0
    }

    func startTimer() {
        guard case .success(let result) = calculationResult else {
            return
        }

        let targetDuration = filmModePrimaryResultSeconds ?? result.resultShutterSeconds
        startTimer(
            from: targetDuration,
            result: result,
            filmModeResult: filmModeExposureResultState
        )
    }

    func startTimer(from resultShutter: TimeInterval) {
        startTimer(
            from: resultShutter,
            result: calculationPayload(for: resultShutter),
            filmModeResult: nil
        )
    }

    func pauseTimer(id: UUID) {
        timerManager.pause(id: id)
    }

    func resumeTimer(id: UUID) {
        timerManager.resume(id: id)
    }

    func removeTimer(id: UUID) {
        timerManager.remove(id: id)
        timerMetadata.removeValue(forKey: id)
        persistTimerMetadata()
    }

    func reconcileTimersAfterAppBecomesActive() {
        timerManager.reconcileAfterAppBecomesActive()
    }

    private func startTimer(
        from resultShutter: TimeInterval,
        result: ExposureCalculationResult?,
        filmModeResult: FilmModeExposureResultState?
    ) {
        let id = UUID()

        let timerName: String
        if let result {
            timerName = makeTimerName(
                for: result,
                targetDuration: resultShutter,
                filmModeResult: filmModeResult
            )
        } else {
            timerName = defaultName(for: resultShutter)
        }

        let order = nextTimerOrder
        timerMetadata[id] = TimerMetadata(
            order: order,
            name: timerName,
            basisSummary: makeBasisSummary(
                for: result,
                filmModeResult: filmModeResult
            )
        )

        guard timerManager.start(id: id, duration: resultShutter) != nil else {
            timerMetadata.removeValue(forKey: id)
            return
        }

        nextTimerOrder += 1
        persistTimerMetadata()
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
        persistTimerMetadata()
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
        case .running, .paused:
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
            return completedTimeContext(for: timer.completedAt, relativeTo: timer.referenceDate)
        case .paused:
            let pausedText = timer.pausedAt.map(formatDateTime) ?? "--"
            return "Paused \(pausedText)"
        }
    }

    func completedTimeContext(for completionDate: Date?, relativeTo referenceDate: Date) -> String {
        guard let completionDate else {
            return "Completed --"
        }

        let absoluteText = formatDateTime(completionDate)
        let relativeText = completedRelativeTimeFormatter.string(
            from: completionDate,
            relativeTo: referenceDate
        )
        return "Completed \(absoluteText) · \(relativeText)"
    }

    func compactCompletedSupplementaryText(for timer: RunningTimerItem) -> String? {
        guard timer.status == .completed else {
            return nil
        }

        return compactCompletedRelativeTimeText(for: timer.completedAt, relativeTo: timer.referenceDate)
    }

    func compactCompletedRelativeTimeText(for completionDate: Date?, relativeTo referenceDate: Date) -> String {
        guard let completionDate else {
            return "--"
        }

        return completedRelativeTimeFormatter.compactString(
            from: completionDate,
            relativeTo: referenceDate
        )
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

    private func makeTimerName(
        for result: ExposureCalculationResult,
        targetDuration: TimeInterval,
        filmModeResult: FilmModeExposureResultState?
    ) -> String {
        let targetLabel = calculator.formatShutter(targetDuration)

        guard filmModeResult?.hasQuantifiedCorrectedExposure == true,
              let film = selectedPresetFilm else {
            return "\(ndStopLabel(for: result.stop)) - \(targetLabel)"
        }

        return "\(film.canonicalStockName) - \(targetLabel)"
    }

    private func syncTimers(with states: [TimerState]) {
        let validIDs = Set(states.map(\.id))
        let originalCount = timerMetadata.count
        timerMetadata = timerMetadata.filter { validIDs.contains($0.key) }
        if timerMetadata.count != originalCount {
            persistTimerMetadata()
        }
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

        lockScreenTargetCoordinator.sync(with: timers)
        scheduleCompletedTimeContextRefreshIfNeeded()
    }

    private func defaultName(for duration: TimeInterval) -> String {
        "Timer - \(calculator.formatShutter(duration))"
    }

    private func makeBasisSummary(
        for result: ExposureCalculationResult?,
        filmModeResult: FilmModeExposureResultState?
    ) -> String {
        guard let result else {
            return "Manual timer"
        }

        let adjustedShutter = calculator.formatShutter(result.resultShutterSeconds)
        let baseSummary = "Base \(calculator.formatShutter(result.baseShutterSeconds)) · \(ndStopLabel(for: result.stop))"

        guard let filmModeResult else {
            return baseSummary
        }

        var segments = [
            baseSummary,
            "Adjusted \(adjustedShutter)"
        ]

        if let film = selectedPresetFilm {
            segments.append(film.canonicalStockName)
        }

        if let correctedExposureSeconds = filmModeResult.correctedExposure.correctedExposureSeconds {
            segments.append("Corrected \(calculator.formatShutter(correctedExposureSeconds))")
        }

        return segments.joined(separator: " · ")
    }

    private func ndStopLabel(for stop: Int) -> String {
        stop == 1 ? "1 stop" : "\(stop) stops"
    }

    private func correctedExposureDisplayState(
        adjustedShutterSeconds: TimeInterval
    ) -> FilmModeCorrectedExposureDisplayState {
        guard let bindingState = filmReciprocityBindingState else {
            return FilmModeCorrectedExposureDisplayState(
                kind: .noFilmSelected,
                correctedExposureSeconds: nil,
                primaryText: "No film selected",
                secondaryText: "Select a preset film",
                usesNumericExposure: false
            )
        }

        if let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds {
            return FilmModeCorrectedExposureDisplayState(
                kind: .quantified,
                correctedExposureSeconds: correctedExposureSeconds,
                primaryText: formatTimeDisplay(correctedExposureSeconds).primary,
                secondaryText: "Final shooting value",
                usesNumericExposure: true
            )
        }

        switch bindingState.presentation.category {
        case .advisoryOnly:
            return FilmModeCorrectedExposureDisplayState(
                kind: .advisory,
                correctedExposureSeconds: nil,
                primaryText: "Advisory only",
                secondaryText: "No corrected exposure provided",
                usesNumericExposure: false
            )
        case .unsupported:
            return FilmModeCorrectedExposureDisplayState(
                kind: .unsupported,
                correctedExposureSeconds: nil,
                primaryText: "Unsupported",
                secondaryText: "No corrected exposure available",
                usesNumericExposure: false
            )
        case .exact, .estimated, .extrapolated:
            // A quantified path should have provided a corrected exposure.
            return FilmModeCorrectedExposureDisplayState(
                kind: .advisory,
                correctedExposureSeconds: nil,
                primaryText: "Advisory only",
                secondaryText: "No corrected exposure provided",
                usesNumericExposure: false
            )
        }
    }

    private func restorePersistedTimerMetadata() {
        guard let snapshot = metadataPersistenceStore.loadSnapshot() else {
            return
        }

        nextTimerOrder = max(1, snapshot.nextTimerOrder)
        timerMetadata = Dictionary(
            uniqueKeysWithValues: snapshot.timers.map {
                (
                    $0.id,
                    TimerMetadata(
                        order: $0.order,
                        name: $0.name,
                        basisSummary: $0.basisSummary
                    )
                )
            }
        )
    }

    private func persistTimerMetadata() {
        guard !timerMetadata.isEmpty else {
            metadataPersistenceStore.clearSnapshot()
            return
        }

        let snapshot = PersistentTimerMetadataCollectionSnapshot(
            nextTimerOrder: nextTimerOrder,
            timers: timerMetadata
                .map { id, metadata in
                    PersistentTimerMetadataSnapshot(
                        id: id,
                        order: metadata.order,
                        name: metadata.name,
                        basisSummary: metadata.basisSummary
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }

                    return lhs.id.uuidString < rhs.id.uuidString
                }
        )

        metadataPersistenceStore.saveSnapshot(snapshot)
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

    private func scheduleCompletedTimeContextRefreshIfNeeded() {
        completedTimeContextRefreshTimer?.invalidate()
        completedTimeContextRefreshTimer = nil

        guard !timers.contains(where: { $0.status == .running }) else {
            return
        }

        let referenceDate = timerManager.currentDate
        let nextRefreshDate = timers
            .filter { $0.status == .completed }
            .compactMap(\.completedAt)
            .compactMap {
                completedRelativeTimeFormatter.nextRefreshDate(
                    from: $0,
                    relativeTo: referenceDate
                )
            }
            .min()

        guard let nextRefreshDate else {
            return
        }

        let refreshTimer = Timer(
            fire: nextRefreshDate,
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            guard let self else {
                return
            }

            self.syncTimers(with: self.timerManager.timers)
        }

        completedTimeContextRefreshTimer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
    }
}

private struct TimerMetadata {
    let order: Int
    let name: String
    let basisSummary: String
}
