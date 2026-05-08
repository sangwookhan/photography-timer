import Combine
import Foundation

private let defaultFilmModeBaseShutter = CalculatorDefaults.baseShutterSeconds
private let defaultFilmModeNDStop = CalculatorDefaults.ndStop

@MainActor
final class ExposureCalculatorViewModel: ObservableObject {
    @Published private(set) var activeCalculatorContext = ActiveExposureCalculatorContext()
    @Published var baseShutter = defaultFilmModeBaseShutter {
        didSet {
            guard oldValue != baseShutter else { return }
            if calculatorModel.liveBaseShutter == baseShutter {
                calculatorModel.clearLiveBaseShutterPreview()
            }

            calculatorModel.baseShutterSeconds = baseShutter
            persistCalculatorContext()
        }
    }
    @Published var ndStop = defaultFilmModeNDStop {
        didSet {
            guard oldValue != ndStop else { return }
            // Mirror writes through to the canonical `ndStep` so the
            // calc engine, the SwiftUI `NDStep` binding, and the
            // `@Published` observers stay in sync regardless of which
            // surface drove the write. The shipping ND picker writes
            // whole-stop values through this wrapper.
            let newStep = NDStep(stops: Double(ndStop))
            if ndStep != newStep {
                ndStep = newStep
            }
        }
    }
    /// Canonical fractional-aware ND value. Source of truth for the
    /// calc engine and the SwiftUI ND-picker binding. The shipping
    /// picker writes whole-stop values; the fractional path is
    /// reserved infrastructure (see `docs/specs/Calculator.md` §1.4).
    /// `@Published` so a fractional-only write — e.g. exercising the
    /// reserved path from a test or a future custom-ND workflow —
    /// still emits `objectWillChange` without going through the
    /// integer wrapper.
    @Published var ndStep: NDStep = NDStep(stops: Double(defaultFilmModeNDStop)) {
        didSet {
            guard oldValue != ndStep else { return }
            if calculatorModel.liveNDStep == ndStep {
                calculatorModel.clearLiveNDStopPreview()
            }
            // Mirror the integer wrapper for legacy callers; only when
            // the new value sits on a whole-stop boundary so a
            // fractional write does not silently round it through the
            // integer setter.
            if let whole = ndStep.wholeStops, whole != ndStop {
                ndStop = whole
            }
            calculatorModel.ndStep = ndStep
            persistCalculatorContext()
        }
    }
    /// Active exposure-scale mode. The shipping calculator runs on the
    /// one-third-stop scale (per `docs/specs/Calculator.md` §1.4); the
    /// full-stop scale is retained on the model for tests and the
    /// future Settings preference but is not exposed through the
    /// calculator UI. The property stays `@Published` so persistence
    /// restoration and any future preference path can mutate it and
    /// have SwiftUI redraw.
    @Published var scaleMode: ExposureScaleMode = .oneThirdStop {
        didSet {
            guard oldValue != scaleMode else { return }
            applyScaleModeChange()
        }
    }
    @Published private(set) var timers: [RunningTimerItem] = []
    /// Active camera-slot id mirrored from `cameraSlotSessionModel`.
    /// The slot picker UI binds to this so a slot switch driven by
    /// any path (UI tap, test action, future deep-link) flows through
    /// the same observed surface.
    @Published private(set) var activeCameraSlotID: CameraSlotID = .camera1
    /// Photographer-supplied display names keyed by slot id, mirrored
    /// from `cameraSlotSessionModel.$customDisplayNames`. Republishing
    /// here lets SwiftUI views observing the facade redraw the slot
    /// title and pager labels when the rename surface fires, without
    /// adding a second observed-model dependency in the screen.
    @Published private(set) var cameraSlotCustomDisplayNames: [CameraSlotID: String] = [:]

    /// Calculation responsibility (calculator instance, inputs, result).
    /// The ViewModel mirrors `baseShutter` / `ndStop` here through the
    /// `didSet` observers above so views and tests can bind to either
    /// surface.
    private let calculatorModel: CalculatorModel
    private var calculator: ExposureCalculator { calculatorModel.calculator }
    private let reciprocityModel: ReciprocityModel
    /// Timer collection, metadata persistence, and lifecycle ops. The
    /// facade republishes `timerWorkspaceModel.$timers` into its own
    /// `@Published var timers` so view bindings, the lock-screen
    /// Combine subscription, and the record-replay smoke test all
    /// observe the same published collection.
    private let timerWorkspaceModel: TimerWorkspaceModel
    private var timerManager: TimerManager { timerWorkspaceModel.timerManager }
    /// Preset film catalog, active film identity slice, and the
    /// calculator-context persistence store. The facade republishes
    /// `filmSelectionModel.$activeContext` into its own
    /// `@Published var activeCalculatorContext` so observers see a
    /// single source of truth.
    private let filmSelectionModel: FilmSelectionModel
    private var presetFilms: [FilmIdentity] { filmSelectionModel.presetFilms }
    /// Camera-slot session state: which slot is currently active, plus
    /// the calculator snapshot for every inactive slot. The facade
    /// orchestrates snapshot capture/load on slot switching.
    private let cameraSlotSessionModel: CameraSlotSessionModel
    /// Bridges the runtime session and the on-disk camera-slot
    /// snapshot. Owns save/load/migration so this facade does not
    /// have to know schema details. Optional because tests / the
    /// legacy convenience init can construct a ViewModel without
    /// session persistence.
    private let sessionPersistence: CameraSlotSessionPersistenceController?
    private let lockScreenTargetCoordinator: LockScreenTimerCoordinator
    private var cancellables: Set<AnyCancellable> = []
    /// Suppresses `persistCalculatorContext` calls during a camera-slot
    /// snapshot apply so the transition writes a single coherent
    /// snapshot at the end rather than four intermediate snapshots
    /// stamped with mismatched calc / film state.
    private var isApplyingSlotSnapshot = false

    private enum TimerStartSource {
        case digitalResult
        case filmAdjustedShutter
        case filmCorrectedExposure
        /// Manual timer entry — a precomputed shutter passed in by an
        /// external caller (or tests) rather than the live calculator
        /// state. Manual timers must NOT inherit the active camera
        /// slot, film, or exposure-source identity: the photographer
        /// did not deliberately associate them with the active slot.
        case manual

        /// Maps the internal start-source enum to the public
        /// `ExposureTimerSource` recorded on `RunningTimerItem` and
        /// `PersistentTimerMetadataSnapshot`. `nil` for manual timers
        /// — they have no exposure source axis at all, which lets the
        /// timer card fall back to the order-based marker (`T1`, `T2`)
        /// and skip identity-first composition.
        var timerExposureSource: ExposureTimerSource? {
            switch self {
            case .digitalResult: return .digitalResult
            case .filmAdjustedShutter: return .filmAdjustedShutter
            case .filmCorrectedExposure: return .filmCorrectedExposure
            case .manual: return nil
            }
        }

        /// True when this start path should stamp the timer with the
        /// active camera slot + film + exposure-source identity.
        /// Manual timers explicitly skip identity capture — see the
        /// case doc above.
        var capturesCalculatorIdentity: Bool {
            switch self {
            case .digitalResult, .filmAdjustedShutter, .filmCorrectedExposure:
                return true
            case .manual:
                return false
            }
        }
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
        let cameraSlotSessionModel = CameraSlotSessionModel()
        let filmSelectionModel = FilmSelectionModel(
            presetFilms: dependencies.presetFilms,
            contextPersistenceStore: dependencies.contextPersistenceStore,
            currentBaseShutterSeconds: { calculatorModel.baseShutterSeconds },
            currentNDStep: { calculatorModel.ndStep },
            currentScaleMode: { calculatorModel.scaleMode },
            currentActiveCameraSlotID: { cameraSlotSessionModel.activeSlotID }
        )
        self.init(
            dependencies: dependencies,
            calculatorModel: calculatorModel,
            reciprocityModel: ReciprocityModel(),
            timerWorkspaceModel: timerWorkspaceModel,
            filmSelectionModel: filmSelectionModel,
            cameraSlotSessionModel: cameraSlotSessionModel
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
        filmSelectionModel: FilmSelectionModel,
        cameraSlotSessionModel: CameraSlotSessionModel? = nil
    ) {
        let resolvedSlotSession = cameraSlotSessionModel ?? CameraSlotSessionModel()
        self.calculatorModel = calculatorModel
        self.reciprocityModel = reciprocityModel
        self.timerWorkspaceModel = timerWorkspaceModel
        self.filmSelectionModel = filmSelectionModel
        self.cameraSlotSessionModel = resolvedSlotSession
        self.sessionPersistence = CameraSlotSessionPersistenceController(
            sessionStore: dependencies.cameraSlotSessionPersistenceStore,
            presetFilms: dependencies.presetFilms
        )
        self.activeCameraSlotID = resolvedSlotSession.activeSlotID
        self.cameraSlotCustomDisplayNames = resolvedSlotSession.customDisplayNames
        self.lockScreenTargetCoordinator = LockScreenTimerCoordinator(
            exposer: dependencies.lockScreenTargetExposer
        )

        // Bind republish before calling `restorePersistedCalculatorContext`
        // so the initial restore-time mutation of
        // `filmSelectionModel.activeContext` propagates into the
        // ViewModel's `@Published var activeCalculatorContext` so
        // restore-time context mutations are reflected on the published
        // surface used by views.
        timerWorkspaceModel.$timers
            .assign(to: &$timers)
        filmSelectionModel.$activeContext
            .assign(to: &$activeCalculatorContext)
        resolvedSlotSession.$activeSlotID
            .assign(to: &$activeCameraSlotID)
        resolvedSlotSession.$customDisplayNames
            .assign(to: &$cameraSlotCustomDisplayNames)
        restorePersistedCalculatorContext()
        bindLockScreenCoordinatorToTimerPublisher()
    }

    init(
        calculator: ExposureCalculator,
        timerManager: TimerManager,
        presetFilms: [FilmIdentity] = LaunchPresetFilmCatalog.films,
        contextPersistenceStore: ExposureCalculatorContextPersistenceStoring = NoOpExposureCalculatorContextPersistenceStore(),
        cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring = NoOpCameraSlotSessionPersistenceStore(),
        metadataPersistenceStore: TimerMetadataPersistenceStoring = NoOpTimerMetadataPersistenceStore(),
        lockScreenTargetExposer: LockScreenTimerTargetExposing = NoOpLockScreenTimerTargetExposer(),
        cameraSlotSessionModel: CameraSlotSessionModel? = nil
    ) {
        let calculatorModel = CalculatorModel(calculator: calculator)
        let resolvedSlotSession = cameraSlotSessionModel ?? CameraSlotSessionModel()
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
            currentNDStep: { calculatorModel.ndStep },
            currentScaleMode: { calculatorModel.scaleMode },
            currentActiveCameraSlotID: { resolvedSlotSession.activeSlotID }
        )
        self.cameraSlotSessionModel = resolvedSlotSession
        self.sessionPersistence = CameraSlotSessionPersistenceController(
            sessionStore: cameraSlotSessionPersistenceStore,
            presetFilms: presetFilms
        )
        self.activeCameraSlotID = resolvedSlotSession.activeSlotID
        self.cameraSlotCustomDisplayNames = resolvedSlotSession.customDisplayNames
        self.lockScreenTargetCoordinator = LockScreenTimerCoordinator(
            exposer: lockScreenTargetExposer
        )

        timerWorkspaceModel.$timers
            .assign(to: &$timers)
        filmSelectionModel.$activeContext
            .assign(to: &$activeCalculatorContext)
        resolvedSlotSession.$activeSlotID
            .assign(to: &$activeCameraSlotID)
        resolvedSlotSession.$customDisplayNames
            .assign(to: &$cameraSlotCustomDisplayNames)
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

    /// Active exposure scale exposed for UI consumption. Sourced from
    /// `CalculatorModel` so the picker reads the same scale the calc
    /// engine uses; the shipping default is `.oneThirdStop` per
    /// `docs/specs/Calculator.md` §1.4.
    var exposureScale: ExposureScale {
        calculatorModel.exposureScale
    }

    /// Mirrors the user's `scaleMode` write into `CalculatorModel` and
    /// pulls back any snapped committed values so the `@Published`
    /// wrappers stay consistent. Centralized so the `scaleMode` didSet
    /// stays declarative and the same flow is reachable from
    /// `restorePersistedCalculatorContext`.
    private func applyScaleModeChange() {
        calculatorModel.scaleMode = scaleMode
        if calculatorModel.baseShutterSeconds != baseShutter {
            baseShutter = calculatorModel.baseShutterSeconds
        }
        if calculatorModel.ndStep != ndStep {
            ndStep = calculatorModel.ndStep
        }
        persistCalculatorContext()
    }

    /// Shutter values the base-shutter picker should render. Equivalent
    /// to `exposureScale.shutterSteps.map(\.seconds)`; named for the
    /// caller's intent.
    var pickerShutterStepSeconds: [Double] {
        calculatorModel.pickerShutterStepSeconds
    }

    /// Whole-stop ND values the integer-binding ND picker should
    /// render. Filters the scale's ND ladder to the whole-stop
    /// subset so any legacy `Int`-bound caller keeps working
    /// alongside the canonical `NDStep` binding.
    var pickerWholeNDStops: [Int] {
        calculatorModel.pickerWholeNDStops
    }

    /// `NDStep` values the SwiftUI ND picker renders. Sourced from
    /// the active scale; the shipping ND ladder is whole-stop
    /// (`0…30`) per `docs/specs/Calculator.md` §2.2 in every shipping
    /// scale mode.
    var pickerNDSteps: [NDStep] {
        calculatorModel.exposureScale.ndSteps
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
            // Compare the canonical `NDStep.stops`, not the integer
            // wrapper — otherwise a reserved-path fractional ND
            // write away from the default zero state would not
            // register as "working" (the shipping ND picker emits
            // whole stops, but this guard must still cover the
            // reserved fractional path).
            || abs(ndStep.stops - Double(defaultFilmModeNDStop)) > ExposureCalculator.stabilityEpsilon
            || scaleMode != .oneThirdStop
    }

    var filmSelectorEntries: [FilmSelectorEntry] {
        var entries: [FilmSelectorEntry] = [
            FilmSelectorEntry(id: "no-film", primaryText: "No film")
        ]

        let sortedFilms = presetFilms.sorted { lhs, rhs in
            let lhsManufacturer = lhs.manufacturer ?? ""
            let rhsManufacturer = rhs.manufacturer ?? ""
            if lhsManufacturer != rhsManufacturer {
                return lhsManufacturer.localizedCaseInsensitiveCompare(rhsManufacturer) == .orderedAscending
            }
            return lhs.canonicalStockName.localizedCaseInsensitiveCompare(rhs.canonicalStockName) == .orderedAscending
        }

        for film in sortedFilms {
            entries.append(FilmSelectorEntry(
                id: film.id,
                primaryText: film.canonicalStockName,
                secondaryText: FilmSelectionModel.filmRowISOText(for: film),
                manufacturer: film.manufacturer,
                film: film
            ))

            if let unofficialProfile = UnofficialPracticalProfiles.profile(forFilmID: film.id) {
                // The "Unofficial" qualifier describes the profile, not the
                // ISO speed, so it lives on the left of the row alongside
                // the canonical stock name. The right column stays an ISO
                // value to match every other row's grid.
                entries.append(FilmSelectorEntry(
                    id: unofficialProfile.id,
                    primaryText: "\(film.canonicalStockName) · Unofficial",
                    secondaryText: FilmSelectionModel.filmRowISOText(for: film),
                    manufacturer: film.manufacturer,
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

    /// Manufacturer-grouped view of `filmSelectorEntries` for the
    /// grouped-card selector layout. Entries keep their flat-list order;
    /// the leading "No film" sentinel becomes its own headerless
    /// section, and contiguous entries sharing a manufacturer become a
    /// single grouped section. The flat `filmSelectorEntries` is still
    /// the source of truth so callers (collapsed-row accessibility lookup,
    /// existing tests) keep working unchanged.
    var filmSelectorSections: [FilmSelectorSection] {
        let entries = filmSelectorEntries
        guard !entries.isEmpty else { return [] }

        var sections: [FilmSelectorSection] = []

        // Leading entries with no manufacturer (the "No film" sentinel)
        // form a headerless section rendered as a plain row.
        let leading = Array(entries.prefix(while: { $0.manufacturer == nil }))
        if !leading.isEmpty {
            sections.append(
                FilmSelectorSection(id: "no-film", manufacturer: nil, entries: leading)
            )
        }

        // Group the remaining entries by manufacturer, preserving the
        // sort order that `filmSelectorEntries` already established.
        var currentManufacturer: String? = nil
        var currentEntries: [FilmSelectorEntry] = []
        for entry in entries.dropFirst(leading.count) {
            if entry.manufacturer != currentManufacturer {
                if let manufacturer = currentManufacturer, !currentEntries.isEmpty {
                    sections.append(
                        FilmSelectorSection(
                            id: manufacturer,
                            manufacturer: manufacturer,
                            entries: currentEntries
                        )
                    )
                }
                currentManufacturer = entry.manufacturer
                currentEntries = []
            }
            currentEntries.append(entry)
        }
        if let manufacturer = currentManufacturer, !currentEntries.isEmpty {
            sections.append(
                FilmSelectorSection(
                    id: manufacturer,
                    manufacturer: manufacturer,
                    entries: currentEntries
                )
            )
        }

        return sections
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
        // Reset scale mode first so the subsequent baseShutter / ndStep
        // writes land on the shipping one-third-stop default. The
        // `@Published` wrapper's didSet propagates the flip into the
        // calc model and refreshes SwiftUI observers.
        scaleMode = .oneThirdStop
        baseShutter = defaultFilmModeBaseShutter
        // Reset the canonical fractional `ndStep` directly. Routing
        // through `ndStop = defaultFilmModeNDStop` would no-op when
        // `ndStop` already equals `0` (e.g., after the user dragged
        // ND to a fractional value, leaving the integer wrapper
        // unchanged), so a fractional drift would survive the reset.
        ndStep = NDStep(stops: Double(defaultFilmModeNDStop))
        ndStop = defaultFilmModeNDStop
        filmSelectionModel.clearPersistedContext()
    }

    // MARK: - Camera slots

    /// Slots exposed to the slot picker in shipping order. The first
    /// implementation surfaces all four slots through this same array;
    /// a future configuration step can return a subset (still
    /// honoring the "minimum two" requirement enforced by the
    /// session model itself).
    var availableCameraSlots: [CameraSlotID] {
        cameraSlotSessionModel.availableSlots
    }

    /// Identity for the currently active slot. Includes the stable id
    /// and the user-facing display label.
    var activeCameraSlot: CameraSlotIdentity {
        cameraSlotSessionModel.activeSlot
    }

    /// Identity for an arbitrary slot id. Used by the slot picker to
    /// render the display label without reaching into the session
    /// model directly.
    func cameraSlotIdentity(for slotID: CameraSlotID) -> CameraSlotIdentity {
        cameraSlotSessionModel.identity(for: slotID)
    }

    /// Sets the photographer-supplied display name for `slotID`.
    /// Whitespace is trimmed; empty/whitespace-only/`nil` input
    /// clears the custom name (resetting back to the canonical
    /// `Camera N` label). Persists the session snapshot so the
    /// rename survives a relaunch.
    ///
    /// Renaming does not touch any calculator/film state and does
    /// not change `CameraSlotID` raw values; already-started timers
    /// keep the slot label captured at start time
    /// (`RunningTimerItem.cameraSlot.displayName`).
    func setCameraSlotCustomName(_ name: String?, for slotID: CameraSlotID) {
        cameraSlotSessionModel.setCustomDisplayName(name, for: slotID)
        persistCalculatorContext()
    }

    /// Clears any photographer-supplied display name for `slotID`,
    /// restoring the canonical `Camera N` label. Persists the change
    /// so the reset survives a relaunch. No calculator/film state is
    /// touched.
    func resetCameraSlotCustomName(_ slotID: CameraSlotID) {
        cameraSlotSessionModel.resetCustomDisplayName(for: slotID)
        persistCalculatorContext()
    }

    /// Switches the active camera slot, preserving the previous slot's
    /// calculator state and loading the target slot's preserved
    /// snapshot (or a fresh default if the slot has not been visited
    /// yet). The transition does not call any film/calc reset path,
    /// so inactive slots stay intact.
    func selectCameraSlot(_ targetSlotID: CameraSlotID) {
        guard targetSlotID != cameraSlotSessionModel.activeSlotID else {
            return
        }
        let outgoing = currentCameraSlotSnapshot()
        guard let incoming = cameraSlotSessionModel.switchActiveSlot(
            to: targetSlotID,
            capturing: outgoing
        ) else {
            return
        }
        applyCameraSlotSnapshot(incoming)
    }

    /// Zero-based index of the active slot inside `availableCameraSlots`.
    /// Drives the page indicator dot rendering and clamps the pager's
    /// horizontal offset.
    var activeCameraSlotIndex: Int {
        availableCameraSlots.firstIndex(of: activeCameraSlotID) ?? 0
    }

    /// VoiceOver value text for the slot pager. Format: `"Camera 2, 2 of 4"`
    /// — slot identity followed by position in the bounded set so a
    /// blind user can hear both at once.
    var activeCameraSlotPageText: String {
        let count = availableCameraSlots.count
        let position = activeCameraSlotIndex + 1
        return "\(activeCameraSlot.displayName), \(position) of \(count)"
    }

    /// Advances to the next slot in `availableCameraSlots`. No-op when
    /// the active slot is already the last available slot — the pager
    /// is bounded, not wrapping, so a swipe past the edge is rejected
    /// rather than silently looping back to the first slot.
    func selectNextCameraSlot() {
        let slots = availableCameraSlots
        let index = activeCameraSlotIndex
        guard index + 1 < slots.count else {
            return
        }
        selectCameraSlot(slots[index + 1])
    }

    /// Reverses to the previous slot in `availableCameraSlots`. No-op
    /// at the first slot for the same bounded-pager reason.
    func selectPreviousCameraSlot() {
        let slots = availableCameraSlots
        let index = activeCameraSlotIndex
        guard index - 1 >= 0 else {
            return
        }
        selectCameraSlot(slots[index - 1])
    }

    /// Builds the per-slot page state the workspace TabView consumes.
    /// Active slots read live calculator/film state directly so the
    /// page binds to whatever the user is currently dragging;
    /// inactive slots read their preserved snapshot so each TabView
    /// page shows that slot's own values during a swipe rather than
    /// the active slot's data leaking across pages.
    func cameraSlotPageState(for slotID: CameraSlotID) -> CameraSlotPageState {
        let isActive = slotID == cameraSlotSessionModel.activeSlotID
        let identity = cameraSlotSessionModel.identity(for: slotID)

        let baseShutter: Double
        let ndStep: NDStep
        let scaleMode: ExposureScaleMode
        let film: FilmIdentity?
        let profileOverride: ReciprocityProfile?

        if isActive {
            baseShutter = calculatorModel.baseShutterSeconds
            ndStep = calculatorModel.ndStep
            scaleMode = calculatorModel.scaleMode
            film = filmSelectionModel.selectedPresetFilm
            profileOverride = filmSelectionModel.selectedProfileOverride
        } else {
            let snapshot = cameraSlotSessionModel.snapshot(forInactiveSlot: slotID) ?? .initial
            baseShutter = snapshot.baseShutterSeconds
            ndStep = snapshot.ndStep
            scaleMode = snapshot.scaleMode
            film = snapshot.selectedPresetFilm
            profileOverride = snapshot.selectedProfileOverride
        }

        let filmDisplay: FilmSelectionDisplayState = {
            guard let film else {
                return FilmSelectionDisplayState(primaryText: "No film", secondaryText: nil)
            }
            let activeProfile = profileOverride ?? film.profiles.first
            return FilmSelectionDisplayState(
                primaryText: film.canonicalStockName,
                secondaryText: FilmSelectionModel.filmRowAuthorityLabel(for: activeProfile)
            )
        }()

        return CameraSlotPageState(
            slotID: slotID,
            cameraDisplayName: identity.displayName,
            baseShutter: baseShutter,
            ndStep: ndStep,
            scaleMode: scaleMode,
            selectedFilm: film,
            selectedProfileOverride: profileOverride,
            filmSelectionDisplayState: filmDisplay,
            isFilmWorkflowActive: film != nil,
            isActive: isActive
        )
    }

    /// Calculator result for a given page state. The active slot
    /// reuses the live `calculationResult` (which already accounts
    /// for live wheel-drag previews); inactive slots run the pure
    /// `CalculatorModel.calculate(...)` overload against the
    /// snapshot's inputs so each peek-during-drag TabView page shows
    /// the adjusted shutter the photographer would see if they paged
    /// over without changing anything.
    func calculationResult(
        forPage pageState: CameraSlotPageState
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        if pageState.isActive {
            return calculationResult
        }
        return calculatorModel.calculate(
            baseShutterSeconds: pageState.baseShutter,
            ndStep: pageState.ndStep
        )
    }

    /// Reciprocity binding state derived from a page's snapshot. The
    /// active page proxies through to the live binding state so any
    /// future change in derivation rules lands on every page; the
    /// inactive path mirrors the same composition without touching
    /// live state.
    func filmReciprocityBindingState(
        forPage pageState: CameraSlotPageState
    ) -> FilmModeReciprocityBindingState? {
        if pageState.isActive {
            return filmReciprocityBindingState
        }

        guard let film = pageState.selectedFilm,
              let profile = pageState.selectedProfileOverride ?? film.profiles.first,
              case .success(let result) = calculationResult(forPage: pageState) else {
            return nil
        }
        let policyResult = reciprocityModel.evaluate(
            profile: profile,
            meteredExposureSeconds: result.resultShutterSeconds
        )
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    /// Film-mode result state for a given page. Inactive pages disable
    /// **both** the adjusted-shutter and corrected-exposure timer
    /// actions in state, not just visually — the page presentation
    /// must completely express that an inactive slot cannot start a
    /// timer. View-level guards (`.allowsHitTesting(false)`) are a
    /// belt-and-suspenders measure, not the policy source.
    func filmModeExposureResultState(
        forPage pageState: CameraSlotPageState
    ) -> FilmModeExposureResultState? {
        if pageState.isActive {
            return filmModeExposureResultState
        }

        guard pageState.isFilmWorkflowActive,
              case .success(let result) = calculationResult(forPage: pageState),
              let bindingState = filmReciprocityBindingState(forPage: pageState) else {
            return nil
        }

        let liveCorrectedAction = reciprocityModel.correctedExposureActionState(
            for: bindingState
        )

        return FilmModeExposureResultState(
            adjustedShutterSeconds: result.resultShutterSeconds,
            reciprocityState: reciprocityModel.reciprocityStateDisplayState(for: bindingState),
            adjustedShutterAction: Self.inactiveTimerActionState(
                targetSeconds: result.resultShutterSeconds,
                accessibilityLabel: "Start timer from adjusted shutter"
            ),
            correctedExposure: reciprocityModel.correctedExposureDisplayState(
                for: bindingState
            ),
            correctedExposureAction: Self.inactiveTimerActionState(
                targetSeconds: liveCorrectedAction.targetSeconds,
                accessibilityLabel: liveCorrectedAction.accessibilityLabel
            )
        )
    }

    /// Builds a disabled action state for an inactive page. Centralised
    /// so both the adjusted and corrected actions emit the same
    /// "page to this slot first" hint and the same `canStartTimer`
    /// policy.
    private static func inactiveTimerActionState(
        targetSeconds: TimeInterval?,
        accessibilityLabel: String
    ) -> FilmModeTimerActionState {
        FilmModeTimerActionState(
            targetSeconds: targetSeconds,
            canStartTimer: false,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: "Inactive camera slot — page to this slot to start a timer"
        )
    }

    /// Picker shutter-step list for a given page's scale. Mirrors the
    /// active-slot `pickerShutterStepSeconds` but parametrized by
    /// the slot's stored scale mode so a future per-slot scale
    /// preference does not silently render the wrong ladder.
    func pickerShutterStepSeconds(forPage pageState: CameraSlotPageState) -> [Double] {
        ExposureScale.scale(for: pageState.scaleMode).shutterSteps.map(\.seconds)
    }

    /// Picker `NDStep` list for a given page's scale. Same reasoning
    /// as `pickerShutterStepSeconds(forPage:)`.
    func pickerNDSteps(forPage pageState: CameraSlotPageState) -> [NDStep] {
        ExposureScale.scale(for: pageState.scaleMode).ndSteps
    }

    /// Captures the active slot's current calculator/film state into a
    /// snapshot value. Sources of truth: `CalculatorModel` (base
    /// shutter, ND, scale) and `FilmSelectionModel` (selected film,
    /// profile override). The active slot's state is always read from
    /// the live models rather than from the session model.
    private func currentCameraSlotSnapshot() -> CameraSlotCalculatorSnapshot {
        CameraSlotCalculatorSnapshot(
            baseShutterSeconds: calculatorModel.baseShutterSeconds,
            ndStep: calculatorModel.ndStep,
            scaleMode: calculatorModel.scaleMode,
            selectedPresetFilm: filmSelectionModel.selectedPresetFilm,
            selectedProfileOverride: filmSelectionModel.selectedProfileOverride
        )
    }

    /// Loads `snapshot` into the calculator/film models without
    /// invoking any reset path or per-mutation persistence. A single
    /// `persistCalculatorContext` call writes a coherent snapshot at
    /// the end so the on-disk state always matches a single slot's
    /// view of the world.
    private func applyCameraSlotSnapshot(_ snapshot: CameraSlotCalculatorSnapshot) {
        isApplyingSlotSnapshot = true
        defer {
            isApplyingSlotSnapshot = false
            persistCalculatorContext()
        }

        calculatorModel.clearLiveBaseShutterPreview()
        calculatorModel.clearLiveNDStopPreview()

        // Write through the `@Published` wrappers so SwiftUI observers
        // see the flip. Order matters: `scaleMode` first so the calc
        // model's didSet snap pass operates before we overwrite
        // base shutter / ND with the snapshot's values, which already
        // sit on the new scale's ladder.
        if scaleMode != snapshot.scaleMode {
            scaleMode = snapshot.scaleMode
        }
        if baseShutter != snapshot.baseShutterSeconds {
            baseShutter = snapshot.baseShutterSeconds
        }
        if ndStep != snapshot.ndStep {
            ndStep = snapshot.ndStep
        }

        filmSelectionModel.replaceActiveSelection(
            film: snapshot.selectedPresetFilm,
            profileOverride: snapshot.selectedProfileOverride
        )
    }

    var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        // Delegated to `CalculatorModel`. The model owns the live
        // preview overlay (`liveBaseShutter` / `liveNDStep`) and
        // exposes `effectiveBaseShutter` / `effectiveNDStep` so the
        // calc engine sees the value the user is currently dragging;
        // once the gesture commits, the `didSet` clear-preview path
        // on `baseShutter` / `ndStop` keeps the model's state
        // consistent. The fractional-aware `ndStep` overload is
        // always taken so the reserved fractional path stays
        // identity-preserving even though the shipping picker only
        // emits whole-stop ND values.
        calculatorModel.calculate(
            baseShutterSeconds: calculatorModel.effectiveBaseShutter,
            ndStep: calculatorModel.effectiveNDStep
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
        // External / manual entry: the caller passed in a precomputed
        // shutter, not a calculation result derived from the active
        // slot. The timer must not inherit the active slot's
        // camera/film/source identity — see `.manual` doc.
        //
        // Pass `result: nil` so the basis summary always reads
        // `"Manual timer"` and the name falls through to the generic
        // `Timer - <duration>` shape. Reaching into
        // `calculationPayload(for:)` here would let a coincidental
        // match against the live calc result leak ND/film wording
        // into a manual timer's basis line — exactly the
        // contamination we just removed for identity capture.
        startTimer(
            from: resultShutter,
            result: nil,
            filmModeResult: nil,
            startSource: .manual
        )
    }

    /// Starts a new timer from a completed source timer in the
    /// workspace. The source timer is unchanged; the new timer
    /// reuses the source's duration and inherits its identity
    /// snapshot (camera slot, film display name, profile qualifier,
    /// exposure source) when present. No-op when `source` is not in
    /// the completed state, so view layers can route every row through
    /// this path safely.
    func startNewTimer(fromCompleted source: RunningTimerItem) {
        timerWorkspaceModel.startTimer(cloningCompleted: source)
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

        // Capture the film/profile snapshot at start time so a later
        // change to the active film does not retroactively rewrite the
        // started timer's identity. Digital (no-film) timers leave
        // `filmDisplayName` nil; UI surfaces render the digital cue
        // from the absent film + the exposure-source tag.
        //
        // Manual timers (external precomputed shutter) skip identity
        // capture entirely — they neither belong to the active slot
        // nor to any exposure source, so all four identity fields
        // stay nil and the dock falls back to the order-based marker.
        let captured = startSource.capturesCalculatorIdentity
        let activeFilm = captured ? filmSelectionModel.selectedPresetFilm : nil
        let activeProfile = captured ? filmSelectionModel.selectedProfileOverride : nil
        let filmProfileQualifier = activeProfile.flatMap { profile in
            switch profile.source.authority {
            case .unofficial: return "Unofficial"
            case .official, .userDefined, .unknown: return nil
            }
        }

        timerWorkspaceModel.startTimer(
            duration: resultShutter,
            name: timerName,
            basisSummary: basisSummary,
            cameraSlot: captured ? cameraSlotSessionModel.activeSlot : nil,
            filmDisplayName: activeFilm?.canonicalStockName,
            filmProfileQualifier: filmProfileQualifier,
            exposureSource: startSource.timerExposureSource
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

    /// Fractional-aware live preview hook used by the SwiftUI ND
    /// picker drag callback. Mirrors `updateLiveNDStop` but accepts
    /// the canonical `NDStep` so a fractional drag (exercised by
    /// tests covering the reserved fractional path) does not lose
    /// precision going through the integer wrapper.
    func updateLiveNDStep(_ value: NDStep) {
        calculatorModel.updateLiveNDStep(value)
    }

    func clearLiveBaseShutterPreview() {
        calculatorModel.clearLiveBaseShutterPreview()
    }

    func clearLiveNDStopPreview() {
        calculatorModel.clearLiveNDStopPreview()
    }

    /// Picker label for an `NDStep` value. The shipping ND picker
    /// advances in 1/3-stop increments (per `docs/specs/Calculator.md`
    /// §2.2), so this formatter renders whole stops as the integer
    /// alone (`"0"`, `"1"`, …) and fractional steps as mixed fractions
    /// (`"1/3"`, `"2/3"`, `"1 1/3"`, …).
    func formatNDStop(_ ndStep: NDStep) -> String {
        if let wholeStops = ndStep.wholeStops {
            return "\(wholeStops)"
        }

        let totalThirds = Int((ndStep.stops * 3).rounded())
        let wholePart = totalThirds / 3
        let fractionalThirds = totalThirds % 3
        let fractionLabel = fractionalThirds == 1 ? "1/3" : "2/3"

        if wholePart == 0 {
            return fractionLabel
        }
        return "\(wholePart) \(fractionLabel)"
    }

    /// Picker label for a shutter value in the active scale. In
    /// `.oneThirdStop` mode the canonical seconds (e.g.,
    /// `(1/30) · 2^(2/3) ≈ 0.0529`) are mapped to camera-facing labels
    /// (`"1/20"`) so the picker shows what the photographer can find
    /// on the camera dial. In `.fullStop` mode the existing
    /// `formatShutter` rendering is preserved byte-for-byte.
    func formatShutterStepLabel(_ seconds: TimeInterval) -> String {
        if scaleMode == .oneThirdStop,
           let cameraLabel = ExposureScale.oneThirdStopShutterCameraLabel(forSeconds: seconds) {
            return cameraLabel
        }
        return calculator.formatShutter(seconds)
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
                return "\(ndStopLabel(for: result.ndStep)) - \(targetLabel)"
            }

            return "\(film.canonicalStockName) - \(targetLabel)"
        case .digitalResult, .filmAdjustedShutter, .manual:
            // Manual timers reuse the same ND-prefixed name shape as
            // digital — without a deliberate calculator-origin tag we
            // still render the matched calc result if one exists.
            return "\(ndStopLabel(for: result.ndStep)) - \(targetLabel)"
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
        let baseSummary = "Base \(calculator.formatShutter(result.baseShutterSeconds)) · \(ndStopLabel(for: result.ndStep))"

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

    /// Human-readable label for an ND stop value, fractional-aware.
    /// Renders whole-stop values byte-for-byte as "N stops" /
    /// "1 stop" (the shipping ND picker only emits whole stops);
    /// reserved-path fractional values render as mixed fractions
    /// ("1/3 stop", "2/3 stop", "1 1/3 stops") so timer names and
    /// basis summaries do not lose the fractional component if a
    /// future custom-ND workflow ever drives this surface.
    private func ndStopLabel(for ndStep: NDStep) -> String {
        if let wholeStops = ndStep.wholeStops {
            return wholeStops == 1 ? "1 stop" : "\(wholeStops) stops"
        }

        let totalThirds = Int((ndStep.stops * 3).rounded())
        let wholePart = totalThirds / 3
        let fractionalThirds = totalThirds % 3
        let fractionLabel = fractionalThirds == 1 ? "1/3" : "2/3"

        let valueText: String
        if wholePart == 0 {
            valueText = fractionLabel
        } else {
            valueText = "\(wholePart) \(fractionLabel)"
        }

        // Singular only for an exact "1 stop" boundary (impossible here
        // because `wholeStops == nil` ⇒ fractional component present).
        return "\(valueText) stops"
    }

    private func restorePersistedCalculatorContext() {
        // Prefer the new multi-slot session snapshot when present.
        if let session = sessionPersistence?.loadSession() {
            applyRestoredSession(session)
            return
        }

        // No session snapshot — fall back to the legacy single-
        // context restore path. This covers (a) first launch after
        // upgrade from a session-unaware build and (b) test setups
        // that wire the legacy store directly. The legacy path
        // sanitises out-of-range stored values; the next persist
        // writes the new session snapshot so subsequent launches
        // skip this branch.
        guard let restored = filmSelectionModel.restoreContext() else {
            return
        }

        if let restoredSlotID = restored.activeCameraSlotID {
            cameraSlotSessionModel.restoreActiveSlot(to: restoredSlotID)
        }

        if restored.hadInvalidFilmReference {
            return
        }

        applyLegacyRestoredCalcInputs(
            baseShutterSeconds: restored.baseShutterSeconds,
            ndStep: restored.ndStep,
            scaleMode: restored.scaleMode
        )
        persistCalculatorContext()
    }

    /// Applies a session restored via the persistence controller.
    /// The active slot's snapshot becomes the live calc/film state;
    /// every other restored slot is loaded into the session model's
    /// inactive map so each TabView page comes back to the values
    /// the photographer left it with.
    ///
    /// **Order matters.** `applyCameraSlotSnapshot` runs a deferred
    /// `persistCalculatorContext()` at its end, which reads
    /// `cameraSlotSessionModel.currentInactiveSnapshots()` to write
    /// the full session. If we applied the active snapshot before
    /// loading the inactive map, the trailing persist would
    /// overwrite a valid 4-slot session with active-only state and
    /// silently destroy the photographer's other three slots on the
    /// first relaunch. Restore the inactive map first so the persist
    /// captures the full session.
    private func applyRestoredSession(
        _ session: CameraSlotSessionPersistenceController.RestoredSession
    ) {
        cameraSlotSessionModel.restoreActiveSlot(to: session.activeSlotID)

        var snapshotsBySlotID = session.snapshotsBySlotID
        let activeSnapshot = snapshotsBySlotID.removeValue(forKey: session.activeSlotID)
            ?? .initial

        // Bulk-load inactive snapshots BEFORE applying the active
        // snapshot — see method doc above for the persist-ordering
        // rationale.
        cameraSlotSessionModel.restoreInactiveSnapshots(snapshotsBySlotID)

        // Restore photographer-supplied custom names before the
        // trailing persist inside `applyCameraSlotSnapshot` so the
        // first re-write of the session snapshot captures both calc
        // state and labels.
        cameraSlotSessionModel.restoreCustomDisplayNames(session.customDisplayNames)

        // Apply the active slot's snapshot to the live models. Reuse
        // `applyCameraSlotSnapshot` so the same Combine wrapper rules
        // (live-preview clear, scale-then-inputs ordering, single
        // persist) cover both slot-switch and restore. The trailing
        // persist now captures active + inactive together.
        applyCameraSlotSnapshot(activeSnapshot)
    }

    /// Legacy fallback applier for the case where the session
    /// controller is absent (test setup that wires the legacy store
    /// directly). Mirrors the pre-session restore behavior.
    private func applyLegacyRestoredCalcInputs(
        baseShutterSeconds: Double?,
        ndStep restoredNDStep: NDStep?,
        scaleMode restoredScaleMode: ExposureScaleMode
    ) {
        scaleMode = restoredScaleMode
        baseShutter = sanitizedRestoredBaseShutter(from: baseShutterSeconds, mode: restoredScaleMode)
            ?? defaultFilmModeBaseShutter
        if let sanitized = sanitizedRestoredNDStep(from: restoredNDStep) {
            if let wholeStops = sanitized.wholeStops {
                ndStop = wholeStops
            } else {
                ndStep = sanitized
            }
        } else {
            ndStop = defaultFilmModeNDStop
        }
    }

    private func persistCalculatorContext() {
        // During a camera-slot snapshot apply we suppress per-mutation
        // persistence so the transition writes a single coherent
        // snapshot at the end (see `applyCameraSlotSnapshot`).
        guard !isApplyingSlotSnapshot else {
            return
        }

        // Legacy active-slot single-context store — kept writing for
        // forward compat with older app versions reading the legacy
        // key. The new session store is the source of truth on
        // restore; this write is idempotent with that.
        filmSelectionModel.persistContext()

        // Multi-slot session store: capture every slot's current
        // snapshot (active reads from live models, inactive from the
        // session model) and write the full session shape, including
        // photographer-supplied custom display names.
        sessionPersistence?.save(
            activeSlotID: cameraSlotSessionModel.activeSlotID,
            activeSlotSnapshot: currentCameraSlotSnapshot(),
            inactiveSnapshots: cameraSlotSessionModel.currentInactiveSnapshots(),
            customDisplayNames: cameraSlotSessionModel.customDisplayNames
        )
    }

    private func sanitizedRestoredBaseShutter(
        from storedValue: Double?,
        mode: ExposureScaleMode = .oneThirdStop
    ) -> Double? {
        guard let storedValue else {
            return nil
        }

        // Match the stored value against the active scale's shutter
        // ladder so a one-third-stop value (e.g., `(1/30) · 2^(1/3)`)
        // round-trips after a relaunch in 1/3-stop mode.
        return ExposureScale.scale(for: mode).shutterSteps.first {
            abs($0.seconds - storedValue) <= ExposureCalculator.stabilityEpsilon
        }?.seconds
    }

    private func sanitizedRestoredNDStep(from storedValue: NDStep?) -> NDStep? {
        guard let storedValue else {
            return nil
        }

        // Reject anything outside the 0…30 stop range supported by the
        // shipping picker; PTIMER-79 already documented this guardrail
        // for whole-stop values, and one-third-stop values inherit the
        // same envelope.
        guard storedValue.stops >= -ExposureCalculator.stabilityEpsilon,
              storedValue.stops <= Double(ExposureScale.maximumWholeNDStops) + ExposureCalculator.stabilityEpsilon else {
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
