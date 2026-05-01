import Combine
import Foundation

private let defaultFilmModeBaseShutter = 1.0 / 30.0
private let defaultFilmModeNDStop = 0

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published private(set) var activeCalculatorContext = ActiveExposureCalculatorContext()
    @Published var baseShutter = defaultFilmModeBaseShutter {
        didSet {
            if calculatorModel.liveBaseShutter == baseShutter {
                calculatorModel.clearLiveBaseShutterPreview()
            }

            calculatorModel.baseShutterSeconds = baseShutter
            persistCalculatorContext()
        }
    }
    @Published var ndStop = defaultFilmModeNDStop {
        didSet {
            if calculatorModel.liveNDStop == ndStop {
                calculatorModel.clearLiveNDStopPreview()
            }

            calculatorModel.ndStop = ndStop
            persistCalculatorContext()
        }
    }
    @Published private(set) var timers: [RunningTimerItem] = []

    /// Calculation responsibility (calculator instance, inputs, result).
    /// The ViewModel mirrors `baseShutter` / `ndStop` here through the
    /// `didSet` observers above so views and tests can bind to either
    /// surface. The eventual ownership flip (model becomes the source
    /// of truth) is tracked by the B1 facade-trim follow-up.
    private let calculatorModel: CalculatorModel
    private var calculator: ExposureCalculator { calculatorModel.calculator }
    private let reciprocityModel: ReciprocityModel
    /// Timer collection, metadata persistence, and lifecycle ops. The
    /// ViewModel republishes `timerWorkspaceModel.$timers` into its own
    /// `@Published var timers` so existing view bindings, the lock-
    /// screen Combine subscription, and the record-replay smoke test
    /// continue to read the legacy surface unchanged.
    private let timerWorkspaceModel: TimerWorkspaceModel
    private var timerManager: TimerManager { timerWorkspaceModel.timerManager }
    /// Preset film catalog, active film identity slice, and the
    /// calculator-context persistence store. The ViewModel republishes
    /// `filmSelectionModel.$activeContext` into its own
    /// `@Published var activeCalculatorContext` so existing observers
    /// of the legacy surface continue to work unchanged.
    private let filmSelectionModel: FilmSelectionModel
    private var presetFilms: [FilmIdentity] { filmSelectionModel.presetFilms }
    private let lockScreenTargetCoordinator: LockScreenTimerCoordinator
    private var cancellables: Set<AnyCancellable> = []

    private enum TimerStartSource {
        case digitalResult
        case filmAdjustedShutter
        case filmCorrectedExposure
    }

    /// Convenience init that builds the four child models from the
    /// dependency bundle. Used by `RecordReplayBaselineSmokeTests` and
    /// any future caller that already has a `ViewModelDependencies`
    /// but does not need to share child models with a coordinator.
    convenience init(dependencies: ViewModelDependencies) {
        let calculatorModel = CalculatorModel(calculator: dependencies.calculator)
        let timerWorkspaceModel = TimerWorkspaceModel(
            timerManager: dependencies.timerManager,
            metadataPersistenceStore: dependencies.metadataPersistenceStore,
            defaultName: { duration in
                "Timer - \(calculatorModel.calculator.formatShutter(duration))"
            }
        )
        let filmSelectionModel = FilmSelectionModel(
            presetFilms: dependencies.presetFilms,
            contextPersistenceStore: dependencies.contextPersistenceStore,
            currentBaseShutterSeconds: { calculatorModel.baseShutterSeconds },
            currentNDStop: { calculatorModel.ndStop }
        )
        self.init(
            dependencies: dependencies,
            calculatorModel: calculatorModel,
            reciprocityModel: ReciprocityModel(),
            timerWorkspaceModel: timerWorkspaceModel,
            filmSelectionModel: filmSelectionModel
        )
    }

    /// Designated init used by `WorkspaceCoordinator`. The coordinator
    /// builds the four `@Observable` models from the dependency bundle
    /// and injects them so all surfaces share the same calc state,
    /// reciprocity collaborators, timer state, and film selection.
    init(
        dependencies: ViewModelDependencies,
        calculatorModel: CalculatorModel,
        reciprocityModel: ReciprocityModel,
        timerWorkspaceModel: TimerWorkspaceModel,
        filmSelectionModel: FilmSelectionModel
    ) {
        self.calculatorModel = calculatorModel
        self.reciprocityModel = reciprocityModel
        self.timerWorkspaceModel = timerWorkspaceModel
        self.filmSelectionModel = filmSelectionModel
        self.lockScreenTargetCoordinator = LockScreenTimerCoordinator(
            exposer: dependencies.lockScreenTargetExposer
        )

        // Bind republish before calling `restorePersistedCalculatorContext`
        // so the initial restore-time mutation of
        // `filmSelectionModel.activeContext` propagates into the
        // ViewModel's `@Published var activeCalculatorContext` —
        // mirrors the pre-decomposition behavior where the ViewModel
        // mutated its own published context inside the restore path.
        timerWorkspaceModel.$timers
            .assign(to: &$timers)
        filmSelectionModel.$activeContext
            .assign(to: &$activeCalculatorContext)
        restorePersistedCalculatorContext()
        bindLockScreenCoordinatorToTimerPublisher()
    }

    init(
        calculator: ExposureCalculator,
        timerManager: TimerManager,
        presetFilms: [FilmIdentity] = LaunchPresetFilmCatalog.films,
        contextPersistenceStore: ExposureCalculatorContextPersistenceStoring = NoOpExposureCalculatorContextPersistenceStore(),
        metadataPersistenceStore: TimerMetadataPersistenceStoring = NoOpTimerMetadataPersistenceStore(),
        lockScreenTargetExposer: LockScreenTimerTargetExposing = NoOpLockScreenTimerTargetExposer()
    ) {
        let calculatorModel = CalculatorModel(calculator: calculator)
        self.calculatorModel = calculatorModel
        self.reciprocityModel = ReciprocityModel()
        self.timerWorkspaceModel = TimerWorkspaceModel(
            timerManager: timerManager,
            metadataPersistenceStore: metadataPersistenceStore,
            defaultName: { duration in
                "Timer - \(calculator.formatShutter(duration))"
            }
        )
        self.filmSelectionModel = FilmSelectionModel(
            presetFilms: presetFilms,
            contextPersistenceStore: contextPersistenceStore,
            currentBaseShutterSeconds: { calculatorModel.baseShutterSeconds },
            currentNDStop: { calculatorModel.ndStop }
        )
        self.lockScreenTargetCoordinator = LockScreenTimerCoordinator(
            exposer: lockScreenTargetExposer
        )

        timerWorkspaceModel.$timers
            .assign(to: &$timers)
        filmSelectionModel.$activeContext
            .assign(to: &$activeCalculatorContext)
        restorePersistedCalculatorContext()
        bindLockScreenCoordinatorToTimerPublisher()
    }

    /// Wires the lock-screen coordinator to the ViewModel's `$timers`
    /// publisher so the coordinator drives the lock-screen surface
    /// directly off `RunningTimerItem` updates. The coordinator's
    /// subscription is owned by the ViewModel's `cancellables` and the
    /// ViewModel retains the coordinator for its lifetime, so the
    /// coordinator stays alive as long as the ViewModel does.
    private func bindLockScreenCoordinatorToTimerPublisher() {
        $timers
            .sink { [weak self] timers in
                self?.lockScreenTargetCoordinator.sync(with: timers)
            }
            .store(in: &cancellables)
    }

    var availablePresetFilms: [FilmIdentity] {
        filmSelectionModel.availablePresetFilms
    }

    var selectedPresetFilm: FilmIdentity? {
        filmSelectionModel.selectedPresetFilm
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
                secondaryText: FilmSelectionModel.inferredISOValue(for: film).map { "ISO \($0)" },
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
        return filmSelectionModel.selectedProfileOverride?.id ?? film.id
    }

    var filmSelectionDisplayState: FilmSelectionDisplayState {
        guard let selectedPresetFilm else {
            return FilmSelectionDisplayState(primaryText: "No film", secondaryText: nil)
        }

        let activeProfile = filmSelectionModel.selectedProfileOverride
            ?? selectedPresetFilm.profiles.first
        return FilmSelectionDisplayState(
            primaryText: selectedPresetFilm.canonicalStockName,
            secondaryText: FilmSelectionModel.filmRowAuthorityLabel(for: activeProfile)
        )
    }

    var filmReciprocityBindingState: FilmModeReciprocityBindingState? {
        guard let selectedPresetFilm,
              let profile = filmSelectionModel.selectedProfileOverride ?? selectedPresetFilm.profiles.first,
              case .success(let result) = calculationResult else {
            return nil
        }

        let policyResult = reciprocityModel.evaluate(
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
            reciprocityState: reciprocityModel.reciprocityStateDisplayState(for: bindingState),
            adjustedShutterAction: FilmModeTimerActionState(
                targetSeconds: result.resultShutterSeconds,
                canStartTimer: result.resultShutterSeconds > 0,
                accessibilityLabel: "Start timer from adjusted shutter",
                accessibilityHint: "Starts a timer using the ND-adjusted shutter value"
            ),
            correctedExposure: reciprocityModel.correctedExposureDisplayState(
                for: bindingState
            ),
            correctedExposureAction: reciprocityModel.correctedExposureActionState(
                for: bindingState
            )
        )
    }

    var filmModeDetailsDisplayState: FilmModeDetailsDisplayState? {
        guard let bindingState = filmReciprocityBindingState else {
            return nil
        }

        return reciprocityModel.makeDetailsDisplayState(
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
        filmSelectionModel.selectEntry(entry)
    }

    func selectPresetFilm(_ film: FilmIdentity) {
        filmSelectionModel.selectPresetFilm(film)
    }

    func clearSelectedPresetFilm() {
        filmSelectionModel.clearSelectedPresetFilm()
    }

    func resetFilmModeWorkingContext() {
        filmSelectionModel.dropActiveSelectionWithoutPersisting()
        calculatorModel.clearLiveBaseShutterPreview()
        calculatorModel.clearLiveNDStopPreview()
        baseShutter = defaultFilmModeBaseShutter
        ndStop = defaultFilmModeNDStop
        filmSelectionModel.clearPersistedContext()
    }

    var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        // Delegated to `CalculatorModel`. The model owns the live preview
        // overlay (`liveBaseShutter` / `liveNDStop`) and exposes
        // `effectiveBaseShutter` / `effectiveNDStop` so the calc engine
        // sees the value the user is currently dragging; once the gesture
        // commits, the `didSet` clear-preview path on `baseShutter` /
        // `ndStop` keeps the model's state consistent.
        calculatorModel.calculate(
            baseShutterSeconds: calculatorModel.effectiveBaseShutter,
            ndStop: calculatorModel.effectiveNDStop
        )
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
        timerWorkspaceModel.pauseTimer(id: id)
    }

    func resumeTimer(id: UUID) {
        timerWorkspaceModel.resumeTimer(id: id)
    }

    func removeTimer(id: UUID) {
        timerWorkspaceModel.removeTimer(id: id)
    }

    func reconcileTimersAfterAppBecomesActive() {
        timerWorkspaceModel.reconcileTimersAfterAppBecomesActive()
    }

    private func startTimer(
        from resultShutter: TimeInterval,
        result: ExposureCalculationResult?,
        filmModeResult: FilmModeExposureResultState?,
        startSource: TimerStartSource
    ) {
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

        let basisSummary = makeBasisSummary(
            for: result,
            filmModeResult: filmModeResult,
            startSource: startSource
        )

        timerWorkspaceModel.startTimer(
            duration: resultShutter,
            name: timerName,
            basisSummary: basisSummary
        )
    }

    func clearCompletedTimers() {
        timerWorkspaceModel.clearCompletedTimers()
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
        reciprocityModel.formatReciprocityDuration(seconds)
    }

    func formatReciprocityDurationCoarse(_ seconds: TimeInterval) -> String {
        reciprocityModel.formatReciprocityDurationCoarse(seconds)
    }

    func formatReciprocityAxisDuration(_ seconds: TimeInterval) -> String {
        reciprocityModel.formatReciprocityAxisDuration(seconds)
    }

    func formatShutter(_ seconds: TimeInterval) -> String {
        calculator.formatShutter(seconds)
    }

    func formatTimerClock(_ seconds: TimeInterval) -> String {
        calculator.formatExtendedClock(seconds)
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
        let relativeText = timerWorkspaceModel.relativeCompletedText(
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
        timerWorkspaceModel.compactCompletedRelativeTimeText(
            for: completionDate,
            relativeTo: referenceDate
        )
    }

    var runningTimerCount: Int {
        timerWorkspaceModel.runningTimerCount
    }

    func updateLiveBaseShutter(_ value: Double) {
        calculatorModel.updateLiveBaseShutter(value)
    }

    func updateLiveNDStop(_ value: Int) {
        calculatorModel.updateLiveNDStop(value)
    }

    func clearLiveBaseShutterPreview() {
        calculatorModel.clearLiveBaseShutterPreview()
    }

    func clearLiveNDStopPreview() {
        calculatorModel.clearLiveNDStopPreview()
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

    private func restorePersistedCalculatorContext() {
        // PR4 of B1 — `FilmSelectionModel` owns the persistence store
        // and the film identity slice; it returns the resolved film
        // selection plus the raw `baseShutterSeconds` / `ndStop`
        // values from the snapshot. The ViewModel applies those calc
        // inputs (which live on `CalculatorModel`) and writes back
        // a clean snapshot via `persistCalculatorContext()` —
        // preserving the legacy ordering byte-for-byte.
        guard let restored = filmSelectionModel.restoreContext() else {
            return
        }

        if restored.hadInvalidFilmReference {
            return
        }

        baseShutter = sanitizedRestoredBaseShutter(from: restored.baseShutterSeconds)
            ?? defaultFilmModeBaseShutter
        ndStop = sanitizedRestoredNDStop(from: restored.ndStop) ?? defaultFilmModeNDStop
        persistCalculatorContext()
    }

    private func persistCalculatorContext() {
        filmSelectionModel.persistContext()
    }

    private func sanitizedRestoredBaseShutter(from storedValue: Double?) -> Double? {
        guard let storedValue else {
            return nil
        }

        return CalculatorModel.shutterSpeeds.first {
            abs($0 - storedValue) <= ExposureCalculator.stabilityEpsilon
        }
    }

    private func sanitizedRestoredNDStop(from storedValue: Int?) -> Int? {
        guard let storedValue, (0...30).contains(storedValue) else {
            return nil
        }

        return storedValue
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
