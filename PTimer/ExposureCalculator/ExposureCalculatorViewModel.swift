import Combine
import Foundation

private let defaultFilmModeBaseShutter = 1.0 / 30.0
private let defaultFilmModeNDStop = 0

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
    @Published var baseShutter = defaultFilmModeBaseShutter {
        didSet {
            if liveBaseShutter == baseShutter {
                liveBaseShutter = nil
            }

            persistCalculatorContextIfNeeded()
        }
    }
    @Published var ndStop = defaultFilmModeNDStop {
        didSet {
            if liveNDStop == ndStop {
                liveNDStop = nil
            }

            persistCalculatorContextIfNeeded()
        }
    }
    @Published private(set) var timers: [RunningTimerItem] = []
    @Published private var liveBaseShutter: Double?
    @Published private var liveNDStop: Int?

    nonisolated static let shutterSpeeds = ExposureCalculator.fullStopShutterSpeeds

    private let calculator: ExposureCalculator
    private let presetFilms: [FilmIdentity]
    private let timerManager: TimerManager
    private let contextPersistenceStore: ExposureCalculatorContextPersistenceStoring
    private let metadataPersistenceStore: TimerMetadataPersistenceStoring
    private let lockScreenTargetCoordinator: LockScreenTimerTargetCoordinator
    private let reciprocityEvaluator = ReciprocityCalculationPolicyEvaluator()
    private let detailsPresenter = FilmModeDetailsPresenter()
    private let completedRelativeTimeFormatter = CompletedRelativeTimeFormatter()
    private var timerMetadata: [UUID: TimerMetadata] = [:]
    private var nextTimerOrder = 1
    private var cancellables: Set<AnyCancellable> = []
    private var completedTimeContextRefreshTimer: Timer?

    private enum TimerStartSource {
        case digitalResult
        case filmAdjustedShutter
        case filmCorrectedExposure
    }

    init(dependencies: ViewModelDependencies) {
        self.calculator = dependencies.calculator
        self.presetFilms = dependencies.presetFilms
        self.timerManager = dependencies.timerManager
        self.contextPersistenceStore = dependencies.contextPersistenceStore
        self.metadataPersistenceStore = dependencies.metadataPersistenceStore
        self.lockScreenTargetCoordinator = LockScreenTimerTargetCoordinator(
            exposer: dependencies.lockScreenTargetExposer
        )

        restorePersistedCalculatorContext()
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
        contextPersistenceStore: ExposureCalculatorContextPersistenceStoring = NoOpExposureCalculatorContextPersistenceStore(),
        metadataPersistenceStore: TimerMetadataPersistenceStoring = NoOpTimerMetadataPersistenceStore(),
        lockScreenTargetExposer: LockScreenTimerTargetExposing = NoOpLockScreenTimerTargetExposer()
    ) {
        self.calculator = calculator
        self.presetFilms = presetFilms
        self.timerManager = timerManager
        self.contextPersistenceStore = contextPersistenceStore
        self.metadataPersistenceStore = metadataPersistenceStore
        self.lockScreenTargetCoordinator = LockScreenTimerTargetCoordinator(
            exposer: lockScreenTargetExposer
        )

        restorePersistedCalculatorContext()
        restorePersistedTimerMetadata()
        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    var availablePresetFilms: [FilmIdentity] {
        presetFilms
    }

    var selectedPresetFilm: FilmIdentity? {
        activeCalculatorContext.selectedPresetFilm
    }

    var isFilmWorkflowActive: Bool {
        selectedPresetFilm != nil
    }

    var canResetFilmModeWorkingContext: Bool {
        selectedPresetFilm != nil
            || abs(baseShutter - defaultFilmModeBaseShutter) > ExposureCalculator.stabilityEpsilon
            || ndStop != defaultFilmModeNDStop
    }

    var filmSelectorEntries: [FilmSelectorEntry] {
        var entries: [FilmSelectorEntry] = [
            FilmSelectorEntry(id: "no-film", primaryText: "No film")
        ]

        for film in presetFilms {
            entries.append(FilmSelectorEntry(
                id: film.id,
                primaryText: film.canonicalStockName,
                secondaryText: inferredISOValue(for: film).map { "ISO \($0)" },
                film: film
            ))

            if let unofficialProfile = UnofficialPracticalProfiles.profile(forFilmID: film.id) {
                entries.append(FilmSelectorEntry(
                    id: unofficialProfile.id,
                    primaryText: film.canonicalStockName,
                    secondaryText: "Unofficial",
                    film: film,
                    profileOverride: unofficialProfile
                ))
            }
        }

        return entries
    }

    var selectedSelectorEntryID: String? {
        guard let film = selectedPresetFilm else { return nil }
        return activeCalculatorContext.selectedProfileOverride?.id ?? film.id
    }

    var filmSelectionDisplayState: FilmSelectionDisplayState {
        guard let selectedPresetFilm else {
            return FilmSelectionDisplayState(primaryText: "No film", secondaryText: nil)
        }

        let activeProfile = activeCalculatorContext.selectedProfileOverride
            ?? selectedPresetFilm.profiles.first
        return FilmSelectionDisplayState(
            primaryText: selectedPresetFilm.canonicalStockName,
            secondaryText: filmRowAuthorityLabel(for: activeProfile)
        )
    }

    var filmReciprocityBindingState: FilmModeReciprocityBindingState? {
        guard let selectedPresetFilm,
              let profile = activeCalculatorContext.selectedProfileOverride ?? selectedPresetFilm.profiles.first,
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

    var filmModeExposureResultState: FilmModeExposureResultState? {
        guard isFilmWorkflowActive,
              case .success(let result) = calculationResult,
              let bindingState = filmReciprocityBindingState else {
            return nil
        }

        return FilmModeExposureResultState(
            adjustedShutterSeconds: result.resultShutterSeconds,
            reciprocityState: detailsPresenter.reciprocityStateDisplayState(for: bindingState),
            adjustedShutterAction: FilmModeTimerActionState(
                targetSeconds: result.resultShutterSeconds,
                canStartTimer: result.resultShutterSeconds > 0,
                accessibilityLabel: "Start timer from adjusted shutter",
                accessibilityHint: "Starts a timer using the ND-adjusted shutter value"
            ),
            correctedExposure: correctedExposureDisplayState(
                adjustedShutterSeconds: result.resultShutterSeconds
            ),
            correctedExposureAction: correctedExposureActionState()
        )
    }

    var filmModeDetailsDisplayState: FilmModeDetailsDisplayState? {
        guard let bindingState = filmReciprocityBindingState else {
            return nil
        }

        return detailsPresenter.makeDetailsDisplayState(
            input: FilmModeDetailsPresenterInput(
                bindingState: bindingState,
                calculationResult: calculationResult,
                filmModeExposureResultState: filmModeExposureResultState,
                formatDuration: { [self] in formatDuration($0) },
                formatDurationCoarse: { [self] in formatReciprocityDurationCoarse($0) },
                formatAxisDuration: { [self] in formatReciprocityAxisDuration($0) }
            )
        )
    }

    var canShowFilmDetails: Bool {
        filmModeDetailsDisplayState != nil
    }

    var filmModePrimaryResultSeconds: TimeInterval? {
        guard let filmModeExposureResultState else {
            return nil
        }

        return filmModeExposureResultState.correctedExposureAction.targetSeconds
    }

    var canStartFilmAdjustedShutterTimer: Bool {
        filmModeExposureResultState?.adjustedShutterAction.canStartTimer == true
    }

    var canStartFilmCorrectedExposureTimer: Bool {
        filmModeExposureResultState?.correctedExposureAction.canStartTimer == true
    }

    func selectEntry(_ entry: FilmSelectorEntry) {
        activeCalculatorContext.selectedPresetFilm = entry.film
        activeCalculatorContext.selectedProfileOverride = entry.profileOverride
        persistCalculatorContext()
    }

    func selectPresetFilm(_ film: FilmIdentity) {
        activeCalculatorContext.selectedPresetFilm = film
        activeCalculatorContext.selectedProfileOverride = nil
        persistCalculatorContext()
    }

    func clearSelectedPresetFilm() {
        activeCalculatorContext.selectedPresetFilm = nil
        activeCalculatorContext.selectedProfileOverride = nil
        persistCalculatorContext()
    }

    func resetFilmModeWorkingContext() {
        activeCalculatorContext.selectedPresetFilm = nil
        activeCalculatorContext.selectedProfileOverride = nil
        liveBaseShutter = nil
        liveNDStop = nil
        baseShutter = defaultFilmModeBaseShutter
        ndStop = defaultFilmModeNDStop
        contextPersistenceStore.clearSnapshot()
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
        if isFilmWorkflowActive {
            guard let filmModePrimaryResultSeconds else {
                return false
            }

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

        let targetDuration: TimeInterval
        let startSource: TimerStartSource
        if isFilmWorkflowActive {
            guard let filmModePrimaryResultSeconds else {
                return
            }

            targetDuration = filmModePrimaryResultSeconds
            startSource = .filmCorrectedExposure
        } else {
            targetDuration = result.resultShutterSeconds
            startSource = .digitalResult
        }

        startTimer(
            from: targetDuration,
            result: result,
            filmModeResult: filmModeExposureResultState,
            startSource: startSource
        )
    }

    func startFilmAdjustedShutterTimer() {
        guard let filmModeResult = filmModeExposureResultState,
              let targetDuration = filmModeResult.adjustedShutterAction.targetSeconds,
              filmModeResult.adjustedShutterAction.canStartTimer,
              case .success(let result) = calculationResult else {
            return
        }

        startTimer(
            from: targetDuration,
            result: result,
            filmModeResult: filmModeResult,
            startSource: .filmAdjustedShutter
        )
    }

    func startFilmCorrectedExposureTimer() {
        guard let filmModeResult = filmModeExposureResultState,
              let targetDuration = filmModeResult.correctedExposureAction.targetSeconds,
              filmModeResult.correctedExposureAction.canStartTimer,
              case .success(let result) = calculationResult else {
            return
        }

        startTimer(
            from: targetDuration,
            result: result,
            filmModeResult: filmModeResult,
            startSource: .filmCorrectedExposure
        )
    }

    func startTimer(from resultShutter: TimeInterval) {
        startTimer(
            from: resultShutter,
            result: calculationPayload(for: resultShutter),
            filmModeResult: nil,
            startSource: .digitalResult
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
        filmModeResult: FilmModeExposureResultState?,
        startSource: TimerStartSource
    ) {
        let id = UUID()

        let timerName: String
        if let result {
            timerName = makeTimerName(
                for: result,
                targetDuration: resultShutter,
                filmModeResult: filmModeResult,
                startSource: startSource
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
                filmModeResult: filmModeResult,
                startSource: startSource
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

    func formatReciprocityTimeDisplay(_ seconds: TimeInterval) -> TimeDisplay {
        let safeSeconds = max(seconds, 0)
        let primary = formatReciprocityDuration(safeSeconds)
        return TimeDisplay(primary: primary, secondary: "")
    }

    func formatReciprocityDuration(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)

        if safeSeconds < 1 {
            return "\(trimmedReciprocitySubsecondText(safeSeconds))s"
        }

        if safeSeconds < 10 {
            return "\(formatReciprocityNumber(safeSeconds, maximumFractionDigits: 1))s"
        }

        let roundedSeconds = Int(safeSeconds.rounded())

        if roundedSeconds < 60 {
            return "\(roundedSeconds)s"
        }

        let secondsPerMinute = 60
        let secondsPerHour = 60 * secondsPerMinute
        let secondsPerDay = 24 * secondsPerHour

        let days = roundedSeconds / secondsPerDay
        let hours = (roundedSeconds % secondsPerDay) / secondsPerHour
        let minutes = (roundedSeconds % secondsPerHour) / secondsPerMinute
        let seconds = roundedSeconds % secondsPerMinute

        if days > 0 {
            return "\(days)d \(String(format: "%02d:%02d:%02d", hours, minutes, seconds))"
        }

        if roundedSeconds >= secondsPerHour {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    func formatReciprocityDurationCoarse(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)
        let roundedSeconds = Int(safeSeconds.rounded())
        let secondsPerDay = 86_400

        guard roundedSeconds >= secondsPerDay else {
            return formatReciprocityDuration(safeSeconds)
        }

        let days = roundedSeconds / secondsPerDay
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return (formatter.string(from: NSNumber(value: days)) ?? "\(days)") + "d"
    }

    func formatReciprocityAxisDuration(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)

        if safeSeconds < 1 {
            return "\(formatReciprocityNumber(safeSeconds, maximumFractionDigits: 1))s"
        }

        if safeSeconds < 120 {
            return "\(Int(safeSeconds.rounded()))s"
        }

        let roundedSeconds = Int(safeSeconds.rounded())
        let minutes = roundedSeconds / 60
        if roundedSeconds < 3600 {
            return "\(minutes)m"
        }

        let hours = roundedSeconds / 3600
        if roundedSeconds < 86_400 {
            return "\(hours)h"
        }

        let days = roundedSeconds / 86_400
        return "\(days)d"
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
        filmModeResult: FilmModeExposureResultState?,
        startSource: TimerStartSource
    ) -> String {
        let targetLabel = calculator.formatShutter(targetDuration)

        switch startSource {
        case .filmCorrectedExposure:
            guard filmModeResult?.hasQuantifiedCorrectedExposure == true,
                  let film = selectedPresetFilm else {
                return "\(ndStopLabel(for: result.stop)) - \(targetLabel)"
            }

            return "\(film.canonicalStockName) - \(targetLabel)"
        case .digitalResult, .filmAdjustedShutter:
            return "\(ndStopLabel(for: result.stop)) - \(targetLabel)"
        }
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
        filmModeResult: FilmModeExposureResultState?,
        startSource: TimerStartSource
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

        if startSource == .filmCorrectedExposure,
           let correctedExposureSeconds = filmModeResult.correctedExposure.correctedExposureSeconds {
            segments.append("Corrected \(calculator.formatShutter(correctedExposureSeconds))")
        }

        return segments.joined(separator: " · ")
    }

    private func ndStopLabel(for stop: Int) -> String {
        stop == 1 ? "1 stop" : "\(stop) stops"
    }

    private func filmSelectorTitle(for film: FilmIdentity) -> String {
        guard let isoValue = inferredISOValue(for: film) else {
            return film.canonicalStockName
        }

        return "\(film.canonicalStockName) (ISO \(isoValue))"
    }

    private func inferredISOValue(for film: FilmIdentity) -> String? {
        let candidateFields = [
            film.canonicalStockName,
            film.brandLabel,
            film.manufacturer
        ].compactMap { $0 } + film.aliases

        for field in candidateFields {
            if let isoValue = Self.firstISOValue(in: field) {
                return isoValue
            }
        }

        return nil
    }

    private static func firstISOValue(in text: String) -> String? {
        let pattern = #"\b(25|50|100|160|200|400|800|1600|3200)\b"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        return String(text[range])
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
                primaryText: formatReciprocityDurationCoarse(correctedExposureSeconds),
                secondaryText: "",
                usesNumericExposure: true
            )
        }

        switch bindingState.presentation.category {
        case .advisoryOnly:
            return FilmModeCorrectedExposureDisplayState(
                kind: .advisory,
                correctedExposureSeconds: nil,
                primaryText: "No corrected value",
                secondaryText: "No published quantified correction is available for this metered exposure.",
                usesNumericExposure: false
            )
        case .unsupported:
            return FilmModeCorrectedExposureDisplayState(
                kind: .unsupported,
                correctedExposureSeconds: nil,
                primaryText: "Unavailable",
                secondaryText: reciprocityGuidanceExplanation(for: bindingState.presentation),
                usesNumericExposure: false
            )
        case .exact, .estimated, .extrapolated:
            // A quantified path should have provided a corrected exposure.
            return FilmModeCorrectedExposureDisplayState(
                kind: .advisory,
                correctedExposureSeconds: nil,
                primaryText: "No quantified correction",
                secondaryText: reciprocityGuidanceExplanation(for: bindingState.presentation),
                usesNumericExposure: false
            )
        }
    }

    private func correctedExposureActionState() -> FilmModeTimerActionState {
        guard let bindingState = filmReciprocityBindingState else {
            return FilmModeTimerActionState(
                targetSeconds: nil,
                canStartTimer: false,
                accessibilityLabel: "Start timer from corrected exposure",
                accessibilityHint: "Timer unavailable because no film-specific corrected exposure is available"
            )
        }

        let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds

        if let correctedExposureSeconds, correctedExposureSeconds > 0 {
            return FilmModeTimerActionState(
                targetSeconds: correctedExposureSeconds,
                canStartTimer: true,
                accessibilityLabel: "Start timer from corrected exposure",
                accessibilityHint: "Starts a timer using the film-specific corrected exposure value"
            )
        }

        let disabledHint: String
        switch bindingState.presentation.category {
        case .advisoryOnly:
            disabledHint = "Timer unavailable because this corrected result is non-quantified"
        case .unsupported:
            disabledHint = "Timer unavailable because this corrected result is unsupported"
        default:
            disabledHint = "Timer unavailable because no quantified corrected exposure is available"
        }

        return FilmModeTimerActionState(
            targetSeconds: nil,
            canStartTimer: false,
            accessibilityLabel: "Start timer from corrected exposure",
            accessibilityHint: disabledHint
        )
    }

    /// Short authority label for the main Film row subtitle.
    /// Returns nil for userDefined/unknown so only official/unofficial films carry a visible qualifier.
    private func filmRowAuthorityLabel(for profile: ReciprocityProfile?) -> String? {
        switch profile?.source.authority {
        case .official: return "Official guidance"
        case .unofficial: return "Unofficial practical"
        case .userDefined, .unknown, nil: return nil
        }
    }

    private func reciprocityGuidanceExplanation(
        for presentation: ReciprocityConfidencePresentation
    ) -> String {
        let explanation = presentation.supportingNotes.first ?? presentation.defaultExplanation
        let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedExplanation.isEmpty else {
            return "See reciprocity guidance"
        }

        return trimmedExplanation
    }

    private func trimmedReciprocitySubsecondText(_ seconds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.minimumFractionDigits = seconds == 0 ? 0 : 1
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: seconds)) ?? "0"
    }

    private func formatReciprocityNumber(
        _ value: Double,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
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

    private func restorePersistedCalculatorContext() {
        guard let snapshot = contextPersistenceStore.loadSnapshot() else {
            return
        }

        if let selectedPresetFilmID = snapshot.selectedPresetFilmID {
            guard let restoredFilm = presetFilms.first(where: { $0.id == selectedPresetFilmID }) else {
                activeCalculatorContext.selectedPresetFilm = nil
                contextPersistenceStore.clearSnapshot()
                return
            }

            activeCalculatorContext.selectedPresetFilm = restoredFilm
        } else {
            activeCalculatorContext.selectedPresetFilm = nil
        }
        baseShutter = restoredBaseShutter(from: snapshot) ?? defaultFilmModeBaseShutter
        ndStop = restoredNDStop(from: snapshot) ?? defaultFilmModeNDStop
        persistCalculatorContext()
    }

    private func persistCalculatorContext() {
        contextPersistenceStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: activeCalculatorContext.selectedPresetFilm?.id,
                baseShutterSeconds: baseShutter,
                ndStop: ndStop
            )
        )
    }

    private func persistCalculatorContextIfNeeded() {
        persistCalculatorContext()
    }

    private func restoredBaseShutter(
        from snapshot: PersistentExposureCalculatorContextSnapshot
    ) -> Double? {
        guard let storedValue = snapshot.baseShutterSeconds else {
            return nil
        }

        return Self.shutterSpeeds.first {
            abs($0 - storedValue) <= ExposureCalculator.stabilityEpsilon
        }
    }

    private func restoredNDStop(
        from snapshot: PersistentExposureCalculatorContextSnapshot
    ) -> Int? {
        guard let storedValue = snapshot.ndStop, (0...30).contains(storedValue) else {
            return nil
        }

        return storedValue
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
