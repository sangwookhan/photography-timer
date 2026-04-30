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
              case .success(let result) = calculationResult else {
            return nil
        }

        return FilmModeExposureResultState(
            adjustedShutterSeconds: result.resultShutterSeconds,
            reciprocityState: reciprocityStateDisplayState(),
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
        makeFilmModeDetailsDisplayState()
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

    private func makeFilmModeDetailsDisplayState() -> FilmModeDetailsDisplayState? {
        guard let bindingState = filmReciprocityBindingState else {
            return nil
        }

        let sections = compactMapDetailsSections(for: bindingState)
        guard !sections.isEmpty else {
            return nil
        }

        return FilmModeDetailsDisplayState(
            title: "Reciprocity Details",
            summary: makeFilmModeDetailsSummaryState(for: bindingState),
            currentResult: makeFilmModeDetailsCurrentResultState(),
            sections: sections,
            graph: makeFilmModeDetailsGraphDisplayState(for: bindingState)
        )
    }

    private func makeFilmModeDetailsSummaryState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeDetailsSummaryState {
        let displayState = reciprocityStateDisplayState()
        return FilmModeDetailsSummaryState(
            badgeText: displayState.badgeText,
            tone: displayState.tone,
            summaryText: filmModeDetailsSummaryText(for: bindingState),
            detailText: filmModeDetailsSummaryDetailText(for: bindingState)
        )
    }

    private func makeFilmModeDetailsCurrentResultState() -> FilmModeDetailsCurrentResultState {
        guard let filmModeExposureResultState else {
            return FilmModeDetailsCurrentResultState(
                layout: .comparison,
                adjustedShutter: FilmModeDetailsCurrentResultValueState(
                    title: "Adjusted Shutter",
                    valueText: "Unavailable",
                    detailText: nil,
                    emphasizesValue: false
                ),
                correctedExposure: FilmModeDetailsCurrentResultValueState(
                    title: "Corrected Exposure",
                    valueText: "Unavailable",
                    detailText: nil,
                    emphasizesValue: false
                )
            )
        }

        let layout = detailsCurrentResultLayout()
        let correctedExposureNoteText: String?
        if layout == .compactValue {
            correctedExposureNoteText = "Adjusted shutter equals corrected exposure."
        } else {
            correctedExposureNoteText = correctedExposureDetailText(
                for: filmModeExposureResultState.correctedExposure
            )
        }

        return FilmModeDetailsCurrentResultState(
            layout: layout,
            adjustedShutter: FilmModeDetailsCurrentResultValueState(
                title: "Adjusted Shutter",
                valueText: formatReciprocityDurationCoarse(
                    filmModeExposureResultState.adjustedShutterSeconds
                ),
                detailText: nil,
                emphasizesValue: false
            ),
            correctedExposure: FilmModeDetailsCurrentResultValueState(
                title: "Corrected Exposure",
                valueText: filmModeExposureResultState.correctedExposure.correctedExposureSeconds
                    .map { formatReciprocityDurationCoarse($0) }
                    ?? filmModeExposureResultState.correctedExposure.primaryText,
                detailText: correctedExposureNoteText,
                emphasizesValue: filmModeExposureResultState.correctedExposure.usesNumericExposure
            )
        )
    }

    private func detailsCurrentResultLayout() -> FilmModeDetailsCurrentResultLayout {
        guard let bindingState = filmReciprocityBindingState else {
            return .comparison
        }

        switch bindingState.policyResult.metadata.basis {
        case .officialThresholdNoCorrection:
            return .compactValue
        case .advisoryOnlyBeyondOfficialRange:
            return .compactPair
        case .exactTablePoint,
             .interpolatedWithinTable,
             .extrapolatedBeyondTable,
             .formulaDerived,
             .unsupportedOutOfPolicyRange:
            return .comparison
        }
    }

    private func makeFilmModeDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeDetailsGraphDisplayState? {
        guard case .success(let result) = calculationResult,
              result.resultShutterSeconds > 0 else {
            return nil
        }

        let currentMeteredExposureSeconds = result.resultShutterSeconds
        let currentPoint = graphCurrentPoint(for: bindingState)

        if let formulaGraph = formulaDetailsGraphDisplayState(
            for: bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        ) {
            return formulaGraph
        }

        return tableDetailsGraphDisplayState(
            for: bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        )
    }

    private func formulaDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?
    ) -> FilmModeDetailsGraphDisplayState? {
        guard bindingState.policyResult.metadata.basis != .officialThresholdNoCorrection else {
            return nil
        }

        guard let formulaRule = bindingState.profile.rules.compactMap({ rule -> FormulaReciprocityRule? in
            guard case let .formula(formulaRule) = rule else {
                return nil
            }
            return formulaRule
        }).first else {
            return nil
        }

        let sourcePoints = formulaGraphSourcePoints(
            for: formulaRule,
            profile: bindingState.profile,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds
        )
        guard sourcePoints.count >= 2 else {
            return nil
        }

        let ranges = graphRanges(
            sourcePoints: sourcePoints,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint?.point
        )
        guard let ranges else {
            return nil
        }

        let supportedUpperBoundSeconds = formulaRule.meteredRange?.maximumSeconds

        return FilmModeDetailsGraphDisplayState(
            kind: .formula,
            title: "Reference Graph",
            sourcePoints: sourcePoints,
            currentPoint: currentPoint.map {
                FilmModeDetailsGraphCurrentPoint(
                    point: $0.point,
                    style: .formulaDerived
                )
            },
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            usesCurrentInputGuideOnly: bindingState.presentation.category == .unsupported,
            caption: "Adjusted shutter vs corrected exposure on the active formula curve",
            unsupportedExplanation: graphUnsupportedExplanation(for: bindingState),
            xAxisLabel: "Adjusted shutter",
            yAxisLabel: "Corrected exposure",
            xAxisTicks: graphAxisTicks(for: ranges.xRange),
            yAxisTicks: graphAxisTicks(for: ranges.yRange),
            supportedRangeUpperBoundSeconds: supportedUpperBoundSeconds,
            unsupportedRegionStartSeconds: unsupportedRegionStartSeconds(
                supportedUpperBoundSeconds: supportedUpperBoundSeconds,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                isUnsupported: bindingState.presentation.category == .unsupported
            ),
            xRange: ranges.xRange,
            yRange: ranges.yRange
        )
    }

    private func tableDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?
    ) -> FilmModeDetailsGraphDisplayState? {
        let sourcePoints = bindingState.profile.rules.flatMap { rule -> [FilmModeDetailsGraphPoint] in
            guard case let .table(tableRule) = rule else {
                return []
            }

            return tableRule.entries.compactMap(tableGraphSourcePoint(for:))
        }
        .sorted { $0.meteredExposureSeconds < $1.meteredExposureSeconds }

        guard sourcePoints.count >= 2 else {
            return nil
        }

        guard let ranges = graphRanges(
            sourcePoints: sourcePoints,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint?.point
        ) else {
            return nil
        }

        let supportedUpperBoundSeconds = sourcePoints.map(\.meteredExposureSeconds).max()

        return FilmModeDetailsGraphDisplayState(
            kind: .table,
            title: "Reference Graph",
            sourcePoints: sourcePoints,
            currentPoint: currentPoint,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            usesCurrentInputGuideOnly: bindingState.presentation.category == .unsupported,
            caption: "Adjusted shutter vs corrected exposure from reference anchors",
            unsupportedExplanation: graphUnsupportedExplanation(for: bindingState),
            xAxisLabel: "Adjusted shutter",
            yAxisLabel: "Corrected exposure",
            xAxisTicks: graphAxisTicks(for: ranges.xRange),
            yAxisTicks: graphAxisTicks(for: ranges.yRange),
            supportedRangeUpperBoundSeconds: supportedUpperBoundSeconds,
            unsupportedRegionStartSeconds: unsupportedRegionStartSeconds(
                supportedUpperBoundSeconds: supportedUpperBoundSeconds,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                isUnsupported: bindingState.presentation.category == .unsupported
            ),
            xRange: ranges.xRange,
            yRange: ranges.yRange
        )
    }

    private func graphCurrentPoint(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeDetailsGraphCurrentPoint? {
        guard case .success(let result) = calculationResult,
              let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds,
              result.resultShutterSeconds > 0,
              correctedExposureSeconds > 0 else {
            return nil
        }

        if bindingState.policyResult.metadata.basis == .officialThresholdNoCorrection {
            return nil
        }

        guard bindingState.presentation.returnsCalculatedExposureTime else {
            return nil
        }

        let style: FilmModeDetailsGraphCurrentPointStyle
        switch bindingState.presentation.category {
        case .exact:
            style = .exact
        case .estimated:
            style = .estimated
        case .extrapolated:
            style = .extrapolated
        case .advisoryOnly, .unsupported:
            return nil
        }

        return FilmModeDetailsGraphCurrentPoint(
            point: FilmModeDetailsGraphPoint(
                meteredExposureSeconds: result.resultShutterSeconds,
                correctedExposureSeconds: correctedExposureSeconds
            ),
            style: style
        )
    }

    private func formulaGraphSourcePoints(
        for rule: FormulaReciprocityRule,
        profile: ReciprocityProfile,
        currentMeteredExposureSeconds: Double
    ) -> [FilmModeDetailsGraphPoint] {
        let thresholdCandidates = profileThresholdUpperBounds(in: profile)
        let lowerBoundCandidates = [
            rule.meteredRange?.minimumSeconds,
            thresholdCandidates.min(),
            currentMeteredExposureSeconds / 4,
            1
        ]
        // When no explicit meteredRange is defined, use a canonical practical range
        // so the graph shows a stable reference viewport rather than auto-scaling
        // tightly around the current input.
        let canonicalUpperBoundSeconds: Double = 120
        let upperBoundCandidates = [
            rule.meteredRange?.maximumSeconds,
            canonicalUpperBoundSeconds,
            currentMeteredExposureSeconds
        ]

        let positiveLowerBound = lowerBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .min()
        let positiveUpperBound = upperBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()

        guard let lowerBound = positiveLowerBound,
              let upperBound = positiveUpperBound else {
            return []
        }

        let clampedLowerBound = min(lowerBound, upperBound)
        let clampedUpperBound = max(lowerBound, upperBound)
        let domain = expandedGraphDomain(
            minimum: clampedLowerBound,
            maximum: clampedUpperBound
        )
        let sampleCount = 24

        return (0..<sampleCount).compactMap { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let meteredExposureSeconds = logInterpolatedValue(
                minimum: domain.lowerBound,
                maximum: domain.upperBound,
                progress: progress
            )

            guard let correctedExposureSeconds = formulaCorrectedExposureSeconds(
                for: rule.formula,
                meteredExposureSeconds: meteredExposureSeconds
            ),
            correctedExposureSeconds.isFinite,
            correctedExposureSeconds > 0 else {
                return nil
            }

            return FilmModeDetailsGraphPoint(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds
            )
        }
    }

    private func tableGraphSourcePoint(
        for entry: ReciprocityTableEntry
    ) -> FilmModeDetailsGraphPoint? {
        guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure,
              meteredExposureSeconds > 0,
              let correctedExposureSeconds = correctedExposureSeconds(for: entry),
              correctedExposureSeconds > 0 else {
            return nil
        }

        return FilmModeDetailsGraphPoint(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds
        )
    }

    private func correctedExposureSeconds(for entry: ReciprocityTableEntry) -> Double? {
        for adjustment in entry.adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }

            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return mapping.correctedSeconds
            case .stopDelta(let adjustment):
                guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure else {
                    continue
                }
                return meteredExposureSeconds * pow(2, adjustment.stopDelta)
            case .multiplier(let adjustment):
                guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure else {
                    continue
                }
                return meteredExposureSeconds * adjustment.factor
            }
        }

        return nil
    }

    private func profileThresholdUpperBounds(in profile: ReciprocityProfile) -> [Double] {
        profile.rules.compactMap { rule -> Double? in
            guard case let .threshold(thresholdRule) = rule else {
                return nil
            }
            return thresholdRule.noCorrectionRange.maximumSeconds
        }
    }

    private func formulaCorrectedExposureSeconds(
        for formula: ReciprocityFormula,
        meteredExposureSeconds: Double
    ) -> Double? {
        guard meteredExposureSeconds.isFinite,
              meteredExposureSeconds > 0 else {
            return nil
        }

        switch formula.kind {
        case .exponentPower:
            let coefficient = formula.coefficient ?? 1
            let offsetSeconds = formula.offsetSeconds ?? 0
            return (coefficient * pow(meteredExposureSeconds, formula.exponent)) + offsetSeconds
        }
    }

    private func graphRanges(
        sourcePoints: [FilmModeDetailsGraphPoint],
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphPoint?
    ) -> (xRange: ClosedRange<Double>, yRange: ClosedRange<Double>)? {
        let allPlottedPoints = currentPoint.map { sourcePoints + [$0] } ?? sourcePoints
        let xValues = (allPlottedPoints.map(\.meteredExposureSeconds) + [currentMeteredExposureSeconds])
            .filter { $0 > 0 && $0.isFinite }
        let yValues = allPlottedPoints.map(\.correctedExposureSeconds).filter { $0 > 0 && $0.isFinite }

        guard let minimumX = xValues.min(),
              let maximumX = xValues.max(),
              let minimumY = yValues.min(),
              let maximumY = yValues.max() else {
            return nil
        }

        return (
            xRange: expandedGraphDomain(minimum: minimumX, maximum: maximumX),
            yRange: expandedGraphDomain(minimum: minimumY, maximum: maximumY)
        )
    }

    private func graphAxisTicks(
        for range: ClosedRange<Double>
    ) -> [FilmModeDetailsGraphAxisTick] {
        let lowerExponent = Int(floor(log10(range.lowerBound)))
        let upperExponent = Int(ceil(log10(range.upperBound)))

        let candidates = (lowerExponent...upperExponent).map { exponent in
            pow(10, Double(exponent))
        }
        .filter { range.contains($0) }

        let tickValues: [Double]
        if candidates.count <= 4 {
            tickValues = candidates
        } else {
            tickValues = [candidates.first, candidates[candidates.count / 2], candidates.last]
                .compactMap { $0 }
        }

        return tickValues.map {
            FilmModeDetailsGraphAxisTick(
                value: $0,
                label: formatReciprocityAxisDuration($0)
            )
        }
    }

    private func unsupportedRegionStartSeconds(
        supportedUpperBoundSeconds: Double?,
        currentMeteredExposureSeconds: Double,
        isUnsupported: Bool
    ) -> Double? {
        guard isUnsupported,
              let supportedUpperBoundSeconds,
              currentMeteredExposureSeconds > supportedUpperBoundSeconds else {
            return nil
        }

        return supportedUpperBoundSeconds
    }

    private func graphUnsupportedExplanation(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        guard bindingState.presentation.category == .unsupported else {
            return nil
        }

        return "Current input is outside the supported range. No quantified corrected point is available."
    }

    private func filmModeDetailsSummaryText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String {
        let metadata = bindingState.policyResult.metadata
        let references = metadata.referencedRows ?? []

        switch metadata.basis {
        case .exactTablePoint:
            if case .success(let result) = calculationResult {
                return "Exact at \(formatReciprocityDurationCoarse(result.resultShutterSeconds))"
            }
            return "Exact reference point"
        case .interpolatedWithinTable:
            let bounds = references
                .filter { $0.role == .lowerBound || $0.role == .upperBound }
                .map { meteredExposureReferenceText(for: $0) }
            if bounds.count == 2 {
                return "Estimated between \(bounds[0]) and \(bounds[1])"
            }
            return "Estimated within reference data"
        case .extrapolatedBeyondTable:
            if let anchor = references.first(where: { $0.role == .representativeAnchor }) {
                return "Extrapolated beyond \(meteredExposureReferenceText(for: anchor)) reference data"
            }
            return "Extrapolated beyond reference data"
        case .officialThresholdNoCorrection:
            if case .success(let result) = calculationResult {
                return "No correction at \(formatReciprocityDurationCoarse(result.resultShutterSeconds))"
            }
            return "No correction in the supported range"
        case .formulaDerived:
            return "Formula-based correction on the active curve"
        case .advisoryOnlyBeyondOfficialRange:
            return "Beyond published no-correction range"
        case .unsupportedOutOfPolicyRange:
            return "Outside supported reciprocity range"
        }
    }

    private func filmModeDetailsSummaryDetailText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        switch bindingState.presentation.category {
        case .unsupported:
            return "Current input is outside the supported range and no quantified corrected point is available."
        case .advisoryOnly:
            return "No published quantified correction is available beyond this range."
        case .exact, .estimated, .extrapolated:
            return nil
        }
    }

    private func correctedExposureDetailText(
        for correctedExposure: FilmModeCorrectedExposureDisplayState
    ) -> String? {
        guard !correctedExposure.usesNumericExposure else {
            return nil
        }

        switch correctedExposure.kind {
        case .noFilmSelected:
            return correctedExposure.secondaryText
        case .quantified:
            return correctedExposure.secondaryText
        case .advisory:
            return correctedExposure.secondaryText
        case .unsupported:
            return correctedExposure.secondaryText
        }
    }

    private func expandedGraphDomain(
        minimum: Double,
        maximum: Double
    ) -> ClosedRange<Double> {
        let safeMinimum = max(minimum, 0.000_001)
        let safeMaximum = max(maximum, safeMinimum)

        if safeMinimum == safeMaximum {
            return (safeMinimum / 2)...(safeMaximum * 2)
        }

        let minimumLog = log10(safeMinimum)
        let maximumLog = log10(safeMaximum)
        let padding = max((maximumLog - minimumLog) * 0.08, 0.12)

        return pow(10, minimumLog - padding)...pow(10, maximumLog + padding)
    }

    private func logInterpolatedValue(
        minimum: Double,
        maximum: Double,
        progress: Double
    ) -> Double {
        let minimumLog = log10(minimum)
        let maximumLog = log10(maximum)
        return pow(10, minimumLog + ((maximumLog - minimumLog) * progress))
    }

    private func compactMapDetailsSections(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsSectionState] {
        if profileUsesFormula(bindingState.profile) {
            return formulaDetailsSections(for: bindingState)
        }

        let profileRows = profileDetailsRows(for: bindingState)
        let referenceRows = referenceDetailsRows(for: bindingState)
        let sourceRows = sourceDetailsRows(for: bindingState.profile)

        return [
            !profileRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Profile", rows: profileRows)
                : nil,
            !referenceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Reference", rows: referenceRows)
                : nil,
            !sourceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Sources", rows: sourceRows)
                : nil
        ]
        .compactMap { $0 }
    }

    private func formulaDetailsSections(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsSectionState] {
        let profileRows = profileDetailsRows(for: bindingState)
        let formulaRows = formulaReferenceRows(for: bindingState) ?? []
        let sourceRows = sourceDetailsRows(for: bindingState.profile)

        return [
            !profileRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Profile", rows: profileRows)
                : nil,
            !formulaRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Formula", rows: formulaRows)
                : nil,
            !sourceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Sources", rows: sourceRows)
                : nil
        ]
        .compactMap { $0 }
    }

    private func profileDetailsRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState] {
        var rows: [FilmModeDetailsRowState] = []
        if let profileText = profileSummaryText(for: bindingState) {
            rows.append(FilmModeDetailsRowState(title: "Profile", value: profileText))
        }
        if let authorityText = profileAuthorityText(for: bindingState.profile) {
            rows.append(FilmModeDetailsRowState(title: "Authority", value: authorityText))
        }
        return rows
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

    private func profileAuthorityText(for profile: ReciprocityProfile) -> String? {
        switch profile.source.authority {
        case .official:
            return "Official manufacturer guidance"
        case .unofficial:
            return "Unofficial practical approximation"
        case .userDefined, .unknown:
            return nil
        }
    }

    private func referenceDetailsRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState] {
        if let formulaReference = formulaReferenceRows(for: bindingState), !formulaReference.isEmpty {
            return formulaReference
        }

        let tableReference = tableReferenceRows(for: bindingState)
        if !tableReference.isEmpty {
            return tableReference
        }

        return manufacturerNoDataReferenceRows(for: bindingState)
    }

    private func profileSummaryText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        if bindingState.profile.rules.contains(where: {
            if case .table = $0 { return true }
            return false
        }) {
            return "Reference table"
        }

        if bindingState.profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        }) {
            return "Formula-based guidance"
        }

        if bindingState.presentation.category == .advisoryOnly || bindingState.presentation.category == .unsupported {
            return "No quantified manufacturer data"
        }

        return nil
    }

    private func reciprocityStateDisplayState() -> FilmModeReciprocityStateDisplayState {
        guard let bindingState = filmReciprocityBindingState else {
            preconditionFailure("Reciprocity state display requires an active film binding.")
        }

        return FilmModeReciprocityStateDisplayState(
            badgeText: reciprocityStateBadgeText(for: bindingState),
            tone: reciprocityStateTone(for: bindingState.presentation.badgeStyle),
            infoText: reciprocityGuidanceExplanation(for: bindingState.presentation),
            showsInfoAffordance: true
        )
    }

    private func reciprocityStateBadgeText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String {
        let metadata = bindingState.policyResult.metadata
        let presentation = bindingState.presentation

        if metadata.basis == .officialThresholdNoCorrection {
            return "No correction"
        }

        if metadata.basis == .formulaDerived {
            return "Formula-based"
        }

        switch presentation.category {
        case .advisoryOnly:
            return "No quantified correction"
        case .unsupported:
            return "Unsupported"
        case .exact, .estimated, .extrapolated:
            return presentation.shortLabel
        }
    }

    private func reciprocityStateTone(
        for badgeStyle: ReciprocityConfidenceBadgeStyle
    ) -> FilmModeReciprocityStateTone {
        switch badgeStyle {
        case .trusted:
            return .trusted
        case .measured:
            return .measured
        case .caution:
            return .caution
        case .advisory:
            return .advisory
        case .unsupported:
            return .unsupported
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

    private func limitationNoteText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        let metadata = bindingState.policyResult.metadata

        switch bindingState.presentation.category {
        case .advisoryOnly, .unsupported:
            return normalizedDetailText(reciprocityGuidanceExplanation(for: bindingState.presentation))
        case .extrapolated:
            return normalizedDetailText(
                metadata.notes.first(where: shouldPreferLimitationNote(_:))?.text
                    ?? bindingState.presentation.defaultExplanation
            )
        case .exact, .estimated:
            if metadata.rangeStatus == .beyondLastRepresentativePoint
                || metadata.warningLevel == .caution
                || metadata.warningLevel == .strongWarning {
                return normalizedDetailText(
                    metadata.notes.first(where: shouldPreferLimitationNote(_:))?.text
                        ?? bindingState.presentation.defaultExplanation
                )
            }

            return nil
        }
    }

    private func profileNoteText(for profile: ReciprocityProfile) -> String? {
        if let note = normalizedDetailText(profile.notes.first) {
            return note
        }

        for rule in profile.rules {
            if let note = normalizedDetailText(firstNote(in: rule)) {
                return note
            }
        }

        return nil
    }

    private func shouldPreferLimitationNote(_ note: ReciprocityPolicyNote) -> Bool {
        switch note.token {
        case .advisoryContinuationOnly,
             .explicitManufacturerStopSignal,
             .beyondOfficialQuantifiedRange,
             .beyondRepresentativeTablePoint,
             .unsupportedByPolicy:
            return true
        case .none,
             .estimatedFromRepresentativeRows,
             .exactManufacturerTablePoint,
             .thresholdGuidanceOnly,
             .archivalOfficialSource,
             .unofficialSecondarySource,
             .userDefinedSource:
            return false
        }
    }

    private func meteredExposureReferenceText(
        for row: ReciprocityTableRowReference
    ) -> String {
        switch row.meteredExposure {
        case .exactSeconds(let seconds):
            return formatDuration(seconds)
        case .range(let range):
            let minimum = formatDuration(range.minimumSeconds)

            if let maximumSeconds = range.maximumSeconds {
                return "\(minimum)-\(formatDuration(maximumSeconds))"
            }

            return "\(minimum)+"
        }
    }

    private func normalizedDetailText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        })
    }

    private func tableReferenceRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState] {
        var lines: [[String]] = []

        for rule in bindingState.profile.rules {
            switch rule {
            case .threshold(let thresholdRule):
                lines.append(compactThresholdReferenceColumns(for: thresholdRule))
            case .table(let tableRule):
                lines.append(contentsOf: tableRule.entries.compactMap(compactTableEntryReferenceColumns(for:)))
            case .formula, .advisory:
                continue
            }
        }

        guard !lines.isEmpty else {
            return []
        }

        return [
            FilmModeDetailsRowState(
                title: "",
                value: formattedReferenceBlock(from: lines),
                style: .referenceBlock
            )
        ]
    }

    private func formulaReferenceRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState]? {
        guard let formulaRule = bindingState.profile.rules.first(where: {
            if case .formula = $0 { return true }
            return false
        }),
        case let .formula(rule) = formulaRule else {
            return nil
        }

        return [
            FilmModeDetailsRowState(
                title: "",
                value: userFacingFormulaReferenceText(for: rule.formula),
                style: .formulaExpression
            )
        ]
    }

    private func userFacingFormulaReferenceText(for formula: ReciprocityFormula) -> String {
        let formattedExponent = formatCompactNumber(formula.exponent)

        switch formula.kind {
        case .exponentPower:
            if let equation = normalizedDetailText(formula.equation),
               let substitutedEquation = substituteFormulaPlaceholder(
                in: equation,
                placeholder: "P",
                replacement: formattedExponent
               ) {
                return substitutedEquation
            }

            return "Tc = Tm^\(formattedExponent)"
        }
    }

    private func substituteFormulaPlaceholder(
        in equation: String,
        placeholder: String,
        replacement: String
    ) -> String? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: placeholder) + "\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(equation.startIndex..., in: equation)
        guard regex.firstMatch(in: equation, range: range) != nil else {
            return nil
        }

        return regex.stringByReplacingMatches(
            in: equation,
            range: range,
            withTemplate: replacement
        )
    }

    private func compactThresholdReferenceColumns(
        for rule: ThresholdReciprocityRule
    ) -> [String] {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return ["<= \(formatDuration(upperBound))", "No correction"]
        }

        if let upperBound {
            return ["\(formatDuration(lowerBound))-\(formatDuration(upperBound))", "No correction"]
        }

        return [">= \(formatDuration(lowerBound))", "No correction"]
    }

    private func compactTableEntryReferenceColumns(
        for entry: ReciprocityTableEntry
    ) -> [String]? {
        let meteredText = meteredExposureSelectorText(entry.meteredExposure)

        let exposureText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .exposure(exposureAdjustment) = adjustment else {
                return nil
            }

            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return formatDuration(mapping.correctedSeconds)
            case .stopDelta(let adjustment):
                return formattedStopDelta(adjustment.stopDelta)
            case .multiplier(let adjustment):
                return "\(formatCompactNumber(adjustment.factor))x"
            }
        }.first

        let developmentText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .development(development) = adjustment else {
                return nil
            }

            return compactDevelopmentReferenceText(from: development.instruction)
        }.first

        let detailColumns = [exposureText, developmentText].compactMap { $0 }
        guard !detailColumns.isEmpty else {
            return nil
        }

        return [meteredText] + detailColumns
    }

    private func compactDevelopmentReferenceText(from instruction: String) -> String {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([+-]?\d+%)\s+development$"#

        if let range = trimmedInstruction.range(of: pattern, options: .regularExpression) {
            let matched = String(trimmedInstruction[range])
            let percentage = matched.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: .regularExpression
            )
            return "Dev \(percentage)"
        }

        return trimmedInstruction
    }

    private func formattedReferenceBlock(from lines: [[String]]) -> String {
        let columnCount = lines.map(\.count).max() ?? 0
        let spacing = "    "
        let widths = (0..<max(columnCount - 1, 0)).map { columnIndex in
            lines
                .compactMap { $0.indices.contains(columnIndex) ? $0[columnIndex] : nil }
                .map(\.count)
                .max() ?? 0
        }

        return lines.map { columns in
            columns.enumerated().map { index, column in
                guard index < widths.count else {
                    return column
                }

                let paddingWidth = max(widths[index] - column.count, 0)
                return column + String(repeating: " ", count: paddingWidth) + spacing
            }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        }
        .joined(separator: "\n")
    }

    private func manufacturerNoDataReferenceRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState] {
        if bindingState.presentation.category == .advisoryOnly || bindingState.presentation.category == .unsupported {
            return [
                FilmModeDetailsRowState(
                    title: "",
                    value: "Manufacturer does not publish quantified reciprocity data",
                    style: .referenceBlock
                )
            ]
        }

        return []
    }

    private func sourceDetailsRows(for profile: ReciprocityProfile) -> [FilmModeDetailsRowState] {
        let source = profile.source

        let referenceComponents = [
            normalizedDetailText(source.publisher),
            normalizedDetailText(source.title),
            normalizedDetailText(source.sourceVersion).map { "Version \($0)" }
        ]
            .compactMap { $0 }

        let referenceRow = referenceComponents.isEmpty
            ? nil
            : FilmModeDetailsRowState(
                title: "Reference",
                value: referenceComponents.joined(separator: " · ")
            )

        let citationText = normalizedDetailText(source.citation)
        let citationURL = citationText.flatMap(parseUsableURL(_:))
        let citationRow: FilmModeDetailsRowState? = {
            guard let citationText else {
                return nil
            }

            return FilmModeDetailsRowState(
                title: "Citation",
                value: citationText,
                destinationURL: citationURL
            )
        }()

        return [referenceRow, citationRow].compactMap { $0 }
    }

    private func parseUsableURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }

    private func formatMultiplier(_ value: Double) -> String {
        formatCompactNumber(value)
    }

    private func thresholdReferenceText(for rule: ThresholdReciprocityRule) -> String {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return "No correction at \(formatDuration(upperBound)) or less"
        }

        if let upperBound {
            return "No correction from \(formatDuration(lowerBound)) to \(formatDuration(upperBound))"
        }

        return "No correction at \(formatDuration(lowerBound)) or more"
    }

    private func tableEntryReferenceText(for entry: ReciprocityTableEntry) -> String? {
        let meteredText = meteredExposureSelectorText(entry.meteredExposure)

        let exposureText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .exposure(exposureAdjustment) = adjustment else {
                return nil
            }

            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return formatDuration(mapping.correctedSeconds)
            case .stopDelta(let adjustment):
                return formattedStopDelta(adjustment.stopDelta)
            case .multiplier(let adjustment):
                return "\(formatCompactNumber(adjustment.factor))x"
            }
        }.first

        let developmentText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .development(development) = adjustment else {
                return nil
            }

            return development.instruction
        }.first

        if let exposureText {
            return developmentText.map { "\(meteredText) -> \(exposureText) (\($0))" }
                ?? "\(meteredText) -> \(exposureText)"
        }

        if let developmentText {
            return "\(meteredText) -> \(developmentText)"
        }

        return nil
    }

    private func meteredExposureSelectorText(_ selector: MeteredExposureSelector) -> String {
        switch selector {
        case .exactSeconds(let seconds):
            return formatDuration(seconds)
        case .range(let range):
            let lower = formatDuration(range.minimumSeconds)
            if let maximumSeconds = range.maximumSeconds {
                return "\(lower)-\(formatDuration(maximumSeconds))"
            }
            return "\(lower)+"
        }
    }

    private func formattedStopDelta(_ value: Double) -> String {
        let absolute = abs(value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let magnitude = formatter.string(from: NSNumber(value: absolute)) ?? String(absolute)
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(magnitude) stop" + (abs(absolute - 1) < ExposureCalculator.stabilityEpsilon ? "" : "s")
    }

    private func formatCompactNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 10 ? 1 : 2
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
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

    private func firstNote(in rule: ReciprocityRule) -> String? {
        switch rule {
        case .threshold(let threshold):
            return threshold.notes.first
        case .formula(let formula):
            return formula.notes.first
        case .table(let table):
            return table.notes.first ?? table.entries.lazy.compactMap(\.notes.first).first
        case .advisory(let advisory):
            return advisory.notes.first
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
