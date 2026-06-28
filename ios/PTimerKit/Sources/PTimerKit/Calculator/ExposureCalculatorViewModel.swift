// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

private let defaultFilmModeBaseShutter = CalculatorDefaults.baseShutterSeconds
private let defaultFilmModeNDStop = CalculatorDefaults.ndStop

@MainActor
public final class ExposureCalculatorViewModel: ObservableObject {
    @Published public private(set) var activeCalculatorContext = ActiveExposureCalculatorContext()
    @Published public var baseShutter = defaultFilmModeBaseShutter {
        didSet {
            guard oldValue != baseShutter else { return }
            if calculatorModel.liveBaseShutter == baseShutter {
                calculatorModel.clearLiveBaseShutterPreview()
            }

            calculatorModel.baseShutterSeconds = baseShutter
            persistCalculatorContext()
        }
    }
    @Published public var ndStop = defaultFilmModeNDStop {
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
    @Published public var ndStep: NDStep = NDStep(stops: Double(defaultFilmModeNDStop)) {
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
    @Published public var scaleMode: ExposureScaleMode = .oneThirdStop {
        didSet {
            guard oldValue != scaleMode else { return }
            applyScaleModeChange()
        }
    }
    /// How ND strength is *displayed* across the picker, result/basis
    /// summaries, and timer cards. Display-only — never feeds the calc
    /// engine; the canonical ND value stays `ndStep.stops`. Persisted
    /// to its own app-global settings store (PTIMER-187).
    @Published public var ndNotationMode: NDNotationMode = .stops {
        didSet {
            guard oldValue != ndNotationMode else { return }
            persistDisplaySettings()
        }
    }
    @Published public private(set) var timers: [RunningTimerItem] = []
    /// Active camera-slot id mirrored from `cameraSlotSessionModel`.
    /// The slot picker UI binds to this so a slot switch driven by
    /// any path (UI tap, test action, future deep-link) flows through
    /// the same observed surface.
    @Published public private(set) var activeCameraSlotID: CameraSlotID = .camera1
    /// Photographer-supplied display names keyed by slot id, mirrored
    /// from `cameraSlotSessionModel.$customDisplayNames`. Republishing
    /// here lets SwiftUI views observing the facade redraw the slot
    /// title and pager labels when the rename surface fires, without
    /// adding a second observed-model dependency in the screen.
    @Published public private(set) var cameraSlotCustomDisplayNames: [CameraSlotID: String] = [:]
    /// Custom films, mirrored from `customFilmLibrary`.
    @Published public private(set) var customFilms: [FilmIdentity] = []

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
    /// Optional Target Shutter slice — owns the photographer-supplied
    /// final exposure duration that the calculator compares its
    /// current result against. The facade reads the model's
    /// `targetSeconds` to compose `targetShutterDisplayState` and
    /// delegates user actions through `setTargetShutter` / `clearTargetShutter`.
    private let targetShutterModel: TargetShutterModel
    /// Bridges the runtime session and the on-disk camera-slot
    /// snapshot. Owns save/load/migration so this facade does not
    /// have to know schema details. Optional because tests / the
    /// legacy convenience init can construct a ViewModel without
    /// session persistence.
    private let sessionPersistence: CameraSlotSessionPersistenceController?
    /// Source of truth for photographer-authored custom
    /// films. Internal so the +CustomFilm extension can write.
    public let customFilmLibrary: CustomFilmLibrary
    /// App-global display-settings store (ND notation mode). Display
    /// preferences only; never participates in calculation.
    private let displaySettingStore: DisplaySettingStoring
    private let lockScreenTargetCoordinator: LockScreenTimerCoordinator
    private var cancellables: Set<AnyCancellable> = []
    /// Suppresses `persistCalculatorContext` calls during a camera-slot
    /// snapshot apply so the transition writes a single coherent
    /// snapshot at the end rather than four intermediate snapshots
    /// stamped with mismatched calc / film state.
    private var isApplyingSlotSnapshot = false

    /// Pure value composer for timer-start display strings and
    /// captured-identity metadata. Re-instantiated per call so the
    /// shutter formatter always reflects the live `calculator`.
    private var timerStartComposer: TimerStartComposer {
        TimerStartComposer(formatShutter: calculator.formatShutter)
    }

    /// Stateless projection helper for per-camera-slot page state.
    /// Holds no model references; the ViewModel feeds it pre-computed
    /// values from live models or stored snapshots.
    private let cameraSlotPageStateBuilder = CameraSlotPageStateBuilder()

    /// Convenience init that builds the four child models from the
    /// dependency bundle. Used by `RecordReplayBaselineSmokeTests` and
    /// any future caller that already has a `ViewModelDependencies`
    /// but does not need to share child models with a coordinator.
    public convenience init(dependencies: ViewModelDependencies) {
        let calculatorModel = CalculatorModel(calculator: dependencies.calculator)
        let timerWorkspaceModel = TimerWorkspaceModel(
            timerManager: dependencies.timerManager,
            metadataPersistenceStore: dependencies.metadataPersistenceStore,
            defaultName: { duration in
                "Timer - \(calculatorModel.calculator.formatShutter(duration))"
            }
        )
        let cameraSlotSessionModel = CameraSlotSessionModel()
        let customLibrary = dependencies.customFilmLibrary
        let filmSelectionModel = FilmSelectionModel(
            presetFilms: dependencies.presetFilms,
            contextPersistenceStore: dependencies.contextPersistenceStore,
            currentBaseShutterSeconds: { calculatorModel.baseShutterSeconds },
            currentNDStep: { calculatorModel.ndStep },
            currentScaleMode: { calculatorModel.scaleMode },
            currentActiveCameraSlotID: { cameraSlotSessionModel.activeSlotID },
            currentCustomFilms: { customLibrary.customFilms }
        )
        self.init(
            dependencies: dependencies,
            calculatorModel: calculatorModel,
            reciprocityModel: ReciprocityModel(),
            timerWorkspaceModel: timerWorkspaceModel,
            filmSelectionModel: filmSelectionModel,
            cameraSlotSessionModel: cameraSlotSessionModel,
            targetShutterModel: TargetShutterModel(),
            customFilmLibrary: dependencies.customFilmLibrary
        )
    }

    /// Designated init used by `WorkspaceCoordinator`. The coordinator
    /// builds the four `@Observable` models from the dependency bundle
    /// and injects them so all surfaces share the same calc state,
    /// reciprocity collaborators, timer state, and film selection.
    public init(
        dependencies: ViewModelDependencies,
        calculatorModel: CalculatorModel,
        reciprocityModel: ReciprocityModel,
        timerWorkspaceModel: TimerWorkspaceModel,
        filmSelectionModel: FilmSelectionModel,
        cameraSlotSessionModel: CameraSlotSessionModel? = nil,
        targetShutterModel: TargetShutterModel? = nil,
        customFilmLibrary: CustomFilmLibrary? = nil
    ) {
        let resolvedSlotSession = cameraSlotSessionModel ?? CameraSlotSessionModel()
        let resolvedCustomLibrary = customFilmLibrary ?? dependencies.customFilmLibrary
        self.calculatorModel = calculatorModel
        self.reciprocityModel = reciprocityModel
        self.timerWorkspaceModel = timerWorkspaceModel
        self.filmSelectionModel = filmSelectionModel
        self.cameraSlotSessionModel = resolvedSlotSession
        self.targetShutterModel = targetShutterModel ?? TargetShutterModel()
        self.sessionPersistence = CameraSlotSessionPersistenceController(
            sessionStore: dependencies.cameraSlotSessionPersistenceStore,
            presetFilms: dependencies.presetFilms,
            currentCustomFilms: { resolvedCustomLibrary.customFilms }
        )
        self.customFilmLibrary = resolvedCustomLibrary
        self.displaySettingStore = dependencies.displaySettingStore
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
        resolvedCustomLibrary.$customFilms
            .assign(to: &$customFilms)
        restoreDisplaySettings()
        restorePersistedCalculatorContext()
        bindLockScreenCoordinatorToTimerPublisher()
    }

    public init(
        calculator: ExposureCalculator,
        timerManager: any TimerManaging,
        presetFilms: [FilmIdentity] = LaunchPresetFilmCatalog.films,
        contextPersistenceStore: ExposureCalculatorContextStoring = NoOpCalculatorContextStore(),
        cameraSlotSessionPersistenceStore: CameraSlotSessionPersistenceStoring = NoOpCameraSlotSessionPersistenceStore(),
        metadataPersistenceStore: TimerMetadataPersistenceStoring = NoOpTimerMetadataPersistenceStore(),
        displaySettingStore: DisplaySettingStoring = NoOpDisplaySettingStore(),
        lockScreenTargetExposer: LockScreenTimerTargetExposing = NoOpLockScreenTimerTargetExposer(),
        cameraSlotSessionModel: CameraSlotSessionModel? = nil,
        targetShutterModel: TargetShutterModel? = nil,
        customFilmLibrary: CustomFilmLibrary? = nil
    ) {
        let calculatorModel = CalculatorModel(calculator: calculator)
        let resolvedSlotSession = cameraSlotSessionModel ?? CameraSlotSessionModel()
        let resolvedCustomLibrary = customFilmLibrary ?? CustomFilmLibrary()
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
            currentActiveCameraSlotID: { resolvedSlotSession.activeSlotID },
            currentCustomFilms: { resolvedCustomLibrary.customFilms }
        )
        self.cameraSlotSessionModel = resolvedSlotSession
        self.targetShutterModel = targetShutterModel ?? TargetShutterModel()
        self.sessionPersistence = CameraSlotSessionPersistenceController(
            sessionStore: cameraSlotSessionPersistenceStore,
            presetFilms: presetFilms,
            currentCustomFilms: { resolvedCustomLibrary.customFilms }
        )
        self.customFilmLibrary = resolvedCustomLibrary
        self.displaySettingStore = displaySettingStore
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
        resolvedCustomLibrary.$customFilms
            .assign(to: &$customFilms)
        restoreDisplaySettings()
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
    public var exposureScale: ExposureScale {
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
    public var pickerShutterStepSeconds: [Double] {
        calculatorModel.pickerShutterStepSeconds
    }

    /// Whole-stop ND values the integer-binding ND picker should
    /// render. Filters the scale's ND ladder to the whole-stop
    /// subset so any legacy `Int`-bound caller keeps working
    /// alongside the canonical `NDStep` binding.
    public var pickerWholeNDStops: [Int] {
        calculatorModel.pickerWholeNDStops
    }

    /// `NDStep` values the SwiftUI ND picker renders. Sourced from
    /// the active scale; the shipping ND ladder is whole-stop
    /// (`0…30`) per `docs/specs/Calculator.md` §2.2 in every shipping
    /// scale mode.
    public var pickerNDSteps: [NDStep] {
        calculatorModel.exposureScale.ndSteps
    }

    public var availablePresetFilms: [FilmIdentity] {
        filmSelectionModel.availablePresetFilms
    }

    public var selectedPresetFilm: FilmIdentity? {
        filmSelectionModel.selectedPresetFilm
    }

    public var isFilmWorkflowActive: Bool {
        selectedPresetFilm != nil
    }

    public var canResetFilmModeWorkingContext: Bool {
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
            || targetShutterModel.isActive
    }

    public var filmSelectorEntries: [FilmSelectorEntry] {
        // One stable list: "No film" sentinel, the explicit
        // "New custom film" action row, then the user's Custom
        // Films section (above the preset catalog), then every
        // built-in film grouped by manufacturer.
        var entries: [FilmSelectorEntry] = [
            FilmSelectorEntry(id: "no-film", primaryText: "No film"),
            createCustomFilmSelectorEntry(),
        ]
        entries.append(contentsOf: customFilmSelectorEntries())

        let sortedFilms = presetFilms.sorted { lhs, rhs in
            let lhsManufacturer = lhs.manufacturer ?? ""
            let rhsManufacturer = rhs.manufacturer ?? ""
            if lhsManufacturer != rhsManufacturer {
                return lhsManufacturer.localizedCaseInsensitiveCompare(rhsManufacturer) == .orderedAscending
            }
            return lhs.canonicalStockName.localizedCaseInsensitiveCompare(rhs.canonicalStockName) == .orderedAscending
        }

        for film in sortedFilms {
            // PTIMER-159: the main selector stays film-stock focused —
            // one entry per stock. Films with more than one reciprocity
            // profile/model (e.g. Portra 400 official + unofficial
            // practical) expose that choice through the model selector
            // (the main-screen segmented control, mirrored in Details),
            // not as duplicate top-level rows.
            entries.append(FilmSelectorEntry(
                id: film.id,
                primaryText: film.canonicalStockName,
                secondaryText: FilmSelectionModel.filmRowISOText(for: film),
                manufacturer: film.manufacturer,
                film: film,
                supportState: FilmSelectorSupportPresenter.makeSupportState(
                    for: film,
                    profileOverride: nil
                )
            ))
        }

        return entries
    }

    public var selectedSelectorEntryID: String? {
        // One row per film stock (PTIMER-159): an active profile/model
        // override still highlights the single film-stock row, so the
        // selector identity is the film id regardless of the override.
        selectedPresetFilm?.id
    }

    /// Manufacturer-grouped view of `filmSelectorEntries` for the
    /// grouped-card selector layout. Entries keep their flat-list order;
    /// the leading "No film" sentinel becomes its own headerless
    /// section, and contiguous entries sharing a manufacturer become a
    /// single grouped section. The flat `filmSelectorEntries` is still
    /// the source of truth so callers (collapsed-row accessibility lookup,
    /// existing tests) keep working unchanged.
    public var filmSelectorSections: [FilmSelectorSection] {
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
        var currentManufacturer: String?
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

    public var filmSelectionDisplayState: FilmSelectionDisplayState {
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

    public var filmReciprocityBindingState: FilmModeReciprocityBindingState? {
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

    public var filmModeExposureResultState: FilmModeExposureResultState? {
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

    public var filmModeDetailsDisplayState: FilmModeDetailsDisplayState? {
        guard let bindingState = filmReciprocityBindingState else {
            return nil
        }

        return reciprocityModel.makeDetailsDisplayState(
            input: FilmModeDetailsPresenterInput(
                bindingState: bindingState,
                calculationResult: calculationResult,
                filmModeExposureResultState: filmModeExposureResultState,
                modelSelection: filmDetailsModelSelection,
                formatDuration: { [self] in formatDuration($0) },
                formatDurationCoarse: { [self] in formatReciprocityDurationCoarse($0) },
                formatAxisDuration: { [self] in formatReciprocityAxisDuration($0) },
                formatSecondsComparison: { [self] in
                    // The Detail current-result card renders the coarse
                    // duration without the Main card's outside-guidance
                    // "≈" prefix, so the seconds comparison matches that
                    // (non-approximate) treatment (PTIMER-172).
                    reciprocityModel.formatReciprocitySecondsComparison($0, approximate: false)
                }
            )
        )
    }

    public var canShowFilmDetails: Bool {
        filmModeDetailsDisplayState != nil
    }

    public var filmModePrimaryResultSeconds: TimeInterval? {
        guard let filmModeExposureResultState else {
            return nil
        }

        return filmModeExposureResultState.correctedExposureAction.targetSeconds
    }

    public var canStartFilmAdjustedShutterTimer: Bool {
        filmModeExposureResultState?.adjustedShutterAction.canStartTimer == true
    }

    public var canStartFilmCorrectedExposureTimer: Bool {
        filmModeExposureResultState?.correctedExposureAction.canStartTimer == true
    }

    public func selectEntry(_ entry: FilmSelectorEntry) {
        filmSelectionModel.selectEntry(entry)
        // The multi-slot session store is the restore source of truth;
        // `FilmSelectionModel` only writes the legacy single-context
        // snapshot (which carries no profile id). Persist here so the
        // chosen film AND profile/model variant reach the session store
        // immediately, instead of surviving only when a later
        // calc-input change happens to rewrite it (PTIMER-168 relaunch
        // persistence fix).
        persistCalculatorContext()
    }

    /// Switches the active reciprocity profile/model within the
    /// currently selected film (PTIMER-159). The Details model picker
    /// calls this; the film stays selected while the profile override
    /// flips.
    ///
    /// Persists through `persistCalculatorContext()` so the multi-slot
    /// session store — the restore source of truth — captures the
    /// chosen model immediately. `FilmSelectionModel.selectProfileOverride`
    /// only writes the legacy single-context snapshot, which has no
    /// profile id; relying on it alone dropped the model selection on
    /// relaunch (e.g. Tri-X "Table"/"App formula" or Portra
    /// "Official" reverting to a stale session value) (PTIMER-168).
    public func selectProfileVariant(profileID: String) {
        guard let film = selectedPresetFilm else { return }
        if let alternate = AlternateReciprocityModels
            .alternates(forFilmID: film.id)
            .first(where: { $0.id == profileID }) {
            filmSelectionModel.selectProfileOverride(alternate)
        } else {
            // Any other id resolves to the film's primary (catalog)
            // profile, cleared back to the no-override default.
            filmSelectionModel.selectProfileOverride(nil)
        }
        persistCalculatorContext()
    }

    /// Profile/model picker state for Reciprocity Details. `nil` for a
    /// film stock that exposes a single profile/model so single-profile
    /// films stay frictionless (no picker). The active option follows
    /// the current override, defaulting to the primary profile.
    public var filmDetailsModelSelection: FilmModeDetailsModelSelectionState? {
        guard let film = selectedPresetFilm else { return nil }

        // Display order comes from the registry (Tri-X 400 leads with
        // the published-rows-only Official table); the ACTIVE model is
        // resolved by id below, so the catalog primary stays the
        // default selection regardless of its display position.
        var profiles: [ReciprocityProfile] = []
        if let primary = film.profiles.first {
            profiles = AlternateReciprocityModels.modelPickerOrder(
                primary: primary,
                forFilmID: film.id
            )
        }

        guard profiles.count > 1 else { return nil }

        let options = profiles.map {
            FilmModeDetailsModelOption(
                id: $0.id,
                name: $0.name,
                selectorLabel: Self.modelSelectorLabel(for: $0)
            )
        }
        let activeID = (filmSelectionModel.selectedProfileOverride ?? film.profiles.first)?.id ?? ""
        return FilmModeDetailsModelSelectionState(options: options, activeOptionID: activeID)
    }

    /// Short, non-misleading label for the segmented model selectors,
    /// where full catalog names ("Official threshold guidance",
    /// "Unofficial practical approximation") would truncate (PTIMER-159).
    /// An explicit `profile.selectorLabel` wins when present (so a future
    /// source-named model like "Ohzart" reads its own name); otherwise a
    /// heuristic label is derived from authority / calculation.
    /// `internal` (not `private`) so the fallback/preference is unit-testable.
    public static func modelSelectorLabel(for profile: ReciprocityProfile) -> String {
        if let explicit = profile.selectorLabel, !explicit.isEmpty {
            return explicit
        }
        if AlternateReciprocityModels.isAppDerivedModel(id: profile.id) {
            return "App formula"
        }
        switch profile.source.authority {
        case .unofficial:
            return "Unofficial"
        case .userDefined:
            return "Custom"
        case .unknown:
            return "Model"
        case .official:
            return profile.effectiveModelBasis.calculationModel == .tableLogLogInterpolation
                ? "Official table"
                : "Official"
        }
    }

    /// Compact two-line active-model summary for the main calculation
    /// screen (PTIMER-159): model name + calculation method. Present
    /// whenever a film is selected, independent of the current result.
    public var activeFilmModelSummary: FilmModeActiveModelSummary? {
        guard let film = selectedPresetFilm,
              let profile = filmSelectionModel.selectedProfileOverride ?? film.profiles.first else {
            return nil
        }
        return FilmModeActiveModelSummary(
            name: profile.name,
            calculation: Self.calculationMethodShortLabel(
                for: profile.effectiveModelBasis.calculationModel
            )
        )
    }

    private static func calculationMethodShortLabel(
        for model: ReciprocityCalculationModel
    ) -> String {
        switch model {
        case .tableLogLogInterpolation:
            return "Log-log interpolation"
        case .guardedFormula:
            return "Guarded formula"
        case .limitedGuidance:
            return "Limited guidance"
        case .unsupported:
            return "Unsupported"
        case .tableLookup:
            return "Table lookup"
        }
    }

    public func selectPresetFilm(_ film: FilmIdentity) {
        filmSelectionModel.selectPresetFilm(film)
        // Capture the selection in the session store (see `selectEntry`).
        persistCalculatorContext()
    }

    public func clearSelectedPresetFilm() {
        filmSelectionModel.clearSelectedPresetFilm()
        // Capture the cleared selection in the session store too, so a
        // deselect survives relaunch instead of resurfacing a stale film.
        persistCalculatorContext()
    }

    public func resetFilmModeWorkingContext() {
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
        // Target Shutter is part of the slot's shooting context, so
        // the workspace reset also drops it. Tap-to-reset returns the
        // entire slot to a clean shooting setup, not just the
        // calculator inputs.
        targetShutterModel.clear()
        filmSelectionModel.clearPersistedContext()
    }

    // MARK: - Camera slots

    /// Slots exposed to the slot picker in shipping order. The first
    /// implementation surfaces all four slots through this same array;
    /// a future configuration step can return a subset (still
    /// honoring the "minimum two" requirement enforced by the
    /// session model itself).
    public var availableCameraSlots: [CameraSlotID] {
        cameraSlotSessionModel.availableSlots
    }

    /// Identity for the currently active slot. Includes the stable id
    /// and the user-facing display label.
    public var activeCameraSlot: CameraSlotIdentity {
        cameraSlotSessionModel.activeSlot
    }

    /// Identity for an arbitrary slot id. Used by the slot picker to
    /// render the display label without reaching into the session
    /// model directly.
    public func cameraSlotIdentity(for slotID: CameraSlotID) -> CameraSlotIdentity {
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
    public func setCameraSlotCustomName(_ name: String?, for slotID: CameraSlotID) {
        cameraSlotSessionModel.setCustomDisplayName(name, for: slotID)
        persistCalculatorContext()
    }

    /// Clears any photographer-supplied display name for `slotID`,
    /// restoring the canonical `Camera N` label. Persists the change
    /// so the reset survives a relaunch. No calculator/film state is
    /// touched.
    public func resetCameraSlotCustomName(_ slotID: CameraSlotID) {
        cameraSlotSessionModel.resetCustomDisplayName(for: slotID)
        persistCalculatorContext()
    }

    /// Switches the active camera slot, preserving the previous slot's
    /// calculator state and loading the target slot's preserved
    /// snapshot (or a fresh default if the slot has not been visited
    /// yet). The transition does not call any film/calc reset path,
    /// so inactive slots stay intact.
    public func selectCameraSlot(_ targetSlotID: CameraSlotID) {
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
    public var activeCameraSlotIndex: Int {
        availableCameraSlots.firstIndex(of: activeCameraSlotID) ?? 0
    }

    /// VoiceOver value text for the slot pager. Format: `"Camera 2, 2 of 4"`
    /// — slot identity followed by position in the bounded set so a
    /// blind user can hear both at once.
    public var activeCameraSlotPageText: String {
        let count = availableCameraSlots.count
        let position = activeCameraSlotIndex + 1
        return "\(activeCameraSlot.displayName), \(position) of \(count)"
    }

    /// Advances to the next slot in `availableCameraSlots`. No-op when
    /// the active slot is already the last available slot — the pager
    /// is bounded, not wrapping, so a swipe past the edge is rejected
    /// rather than silently looping back to the first slot.
    public func selectNextCameraSlot() {
        let slots = availableCameraSlots
        let index = activeCameraSlotIndex
        guard index + 1 < slots.count else {
            return
        }
        selectCameraSlot(slots[index + 1])
    }

    /// Reverses to the previous slot in `availableCameraSlots`. No-op
    /// at the first slot for the same bounded-pager reason.
    public func selectPreviousCameraSlot() {
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
    public func cameraSlotPageState(for slotID: CameraSlotID) -> CameraSlotPageState {
        let isActive = slotID == cameraSlotSessionModel.activeSlotID
        let identity = cameraSlotSessionModel.identity(for: slotID)

        let inputs: CameraSlotPageStateBuilder.PageStateInputs
        if isActive {
            inputs = CameraSlotPageStateBuilder.PageStateInputs(
                slotID: slotID,
                cameraDisplayName: identity.displayName,
                isActive: true,
                baseShutter: calculatorModel.baseShutterSeconds,
                ndStep: calculatorModel.ndStep,
                scaleMode: calculatorModel.scaleMode,
                selectedFilm: filmSelectionModel.selectedPresetFilm,
                selectedProfileOverride: filmSelectionModel.selectedProfileOverride,
                targetShutterSeconds: targetShutterModel.targetSeconds
            )
        } else {
            let snapshot = cameraSlotSessionModel.snapshot(forInactiveSlot: slotID) ?? .initial
            inputs = CameraSlotPageStateBuilder.PageStateInputs(
                slotID: slotID,
                cameraDisplayName: identity.displayName,
                isActive: false,
                baseShutter: snapshot.baseShutterSeconds,
                ndStep: snapshot.ndStep,
                scaleMode: snapshot.scaleMode,
                selectedFilm: snapshot.selectedPresetFilm,
                selectedProfileOverride: snapshot.selectedProfileOverride,
                targetShutterSeconds: snapshot.targetShutterSeconds
            )
        }

        return cameraSlotPageStateBuilder.pageState(inputs)
    }

    /// Calculator result for a given page state. The active slot
    /// reuses the live `calculationResult` (which already accounts
    /// for live wheel-drag previews); inactive slots run the pure
    /// `CalculatorModel.calculate(...)` overload against the
    /// snapshot's inputs so each peek-during-drag TabView page shows
    /// the adjusted shutter the photographer would see if they paged
    /// over without changing anything.
    public func calculationResult(
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
    public func filmReciprocityBindingState(
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
    public func filmModeExposureResultState(
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

        return cameraSlotPageStateBuilder.inactiveFilmModeResult(
            CameraSlotPageStateBuilder.InactiveFilmModeInputs(
                adjustedShutterSeconds: result.resultShutterSeconds,
                reciprocityState: reciprocityModel.reciprocityStateDisplayState(for: bindingState),
                correctedExposure: reciprocityModel.correctedExposureDisplayState(for: bindingState),
                liveCorrectedActionState: liveCorrectedAction
            )
        )
    }

    /// Picker shutter-step list for a given page's scale.
    public func pickerShutterStepSeconds(forPage pageState: CameraSlotPageState) -> [Double] {
        cameraSlotPageStateBuilder.pickerShutterStepSeconds(forPage: pageState)
    }

    /// Picker `NDStep` list for a given page's scale.
    public func pickerNDSteps(forPage pageState: CameraSlotPageState) -> [NDStep] {
        cameraSlotPageStateBuilder.pickerNDSteps(forPage: pageState)
    }

    /// Captures the active slot's current calculator/film state into a
    /// snapshot value. Sources of truth: `CalculatorModel` (base
    /// shutter, ND, scale), `FilmSelectionModel` (selected film,
    /// profile override), and `TargetShutterModel` (per-slot target
    /// duration). The active slot's state is always read from the live
    /// models rather than from the session model.
    private func currentCameraSlotSnapshot() -> CameraSlotCalculatorSnapshot {
        CameraSlotCalculatorSnapshot(
            baseShutterSeconds: calculatorModel.baseShutterSeconds,
            ndStep: calculatorModel.ndStep,
            scaleMode: calculatorModel.scaleMode,
            selectedPresetFilm: filmSelectionModel.selectedPresetFilm,
            selectedProfileOverride: filmSelectionModel.selectedProfileOverride,
            targetShutterSeconds: targetShutterModel.targetSeconds
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

        // Restore the per-slot target. `setTarget` re-sanitises the
        // value, so a corrupted snapshot can never resurface as an
        // invalid target — same rule the persistence controller
        // applies at decode time.
        targetShutterModel.setTarget(snapshot.targetShutterSeconds)
    }

    public var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
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

    public var canStartTimer: Bool {
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

    public func startTimer() {
        guard case .success(let result) = calculationResult else {
            return
        }

        let targetDuration: TimeInterval
        let startSource: TimerStartComposer.Source
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

    public func startFilmAdjustedShutterTimer() {
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

    public func startFilmCorrectedExposureTimer() {
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

    // MARK: - Target Shutter

    /// Currently set Target Shutter duration in seconds. `nil` when
    /// the photographer has not set a target. Read-through to
    /// `TargetShutterModel` so the source-of-truth contract stays
    /// single-rooted on the model.
    public var targetShutterSeconds: TimeInterval? {
        targetShutterModel.targetSeconds
    }

    /// True when Target Shutter is set to a finite positive value.
    public var isTargetShutterActive: Bool {
        targetShutterModel.isActive
    }

    /// Last positive target the photographer set in the current
    /// session — surfaces from `TargetShutterModel.lastUsedTargetSeconds`.
    ///
    /// **Not** used as the input sheet's fallback seed for a slot with
    /// no committed target. Doing so would leak Camera 1's last value
    /// onto Camera 2's sheet because the `TargetShutterModel` instance
    /// is shared across slots and this memory is global. The sheet's
    /// seed comes only from the active slot's committed target; a
    /// slot with no committed target seeds to the default (1 minute).
    /// This accessor remains for read-only callers (tests, future
    /// surfaces that explicitly want session-global memory) but must
    /// never be wired back into per-slot sheet seeding.
    public var lastUsedTargetShutterSeconds: TimeInterval? {
        targetShutterModel.lastUsedTargetSeconds
    }

    /// Composed display state for the Target Shutter card. Routes the
    /// presenter through the active workflow's comparison source so
    /// the stop-difference text reflects the same value the
    /// photographer reads in the result section.
    public var targetShutterDisplayState: TargetShutterDisplayState {
        TargetShutterPresenter.makeDisplayState(
            targetSeconds: targetShutterModel.targetSeconds,
            comparisonSource: targetShutterComparisonSource
        )
    }

    /// True when the photographer can start a timer from the current
    /// Target Shutter value. The target itself is the timer duration —
    /// no comparison is needed for the timer to start, so this only
    /// guards against unset / non-finite / zero values that the
    /// model would already reject.
    public var canStartTargetShutterTimer: Bool {
        guard let target = targetShutterModel.targetSeconds else {
            return false
        }
        return target.isFinite && target > 0
    }

    /// Sets the Target Shutter duration. Non-finite, zero, and
    /// negative inputs are rejected and clear the target back to
    /// inactive — see `TargetShutterModel.setTarget(_:)`. Persists the
    /// active slot's snapshot so the new target survives a relaunch on
    /// the same slot.
    public func setTargetShutter(_ seconds: TimeInterval?) {
        targetShutterModel.setTarget(seconds)
        persistCalculatorContext()
    }

    /// Clears the Target Shutter back to inactive. The result section
    /// stops rendering the comparison and the start-target-timer
    /// affordance. Persists so the cleared state survives a relaunch.
    public func clearTargetShutter() {
        targetShutterModel.clear()
        persistCalculatorContext()
    }

    /// Starts a timer using the current Target Shutter value. The
    /// timer carries `.targetShutter` as its exposure source plus the
    /// active camera-slot identity so the dock can label it
    /// distinctly from Adjusted Shutter / Corrected Exposure timers.
    public func startTargetShutterTimer() {
        guard let target = targetShutterModel.targetSeconds,
              target.isFinite,
              target > 0 else {
            return
        }

        // Pull the current calc result so the basis summary still
        // reflects the active calculator inputs (Base / ND), giving
        // the row a useful subtitle alongside the Target Shutter
        // source label. A calc failure path falls through to the
        // generic "Manual timer" basis — keeping the start path
        // tolerant of edge cases (e.g. a zero base shutter typed
        // by the user) while still stamping the target source.
        let liveResult: ExposureCalculationResult? = {
            if case .success(let result) = calculationResult {
                return result
            }
            return nil
        }()

        startTimer(
            from: target,
            result: liveResult,
            filmModeResult: filmModeExposureResultState,
            startSource: .targetShutter
        )
    }

    /// Builds the Target Shutter display state for an arbitrary
    /// camera-slot page. Active pages reuse the live
    /// `targetShutterDisplayState` (so the comparison reflects the
    /// drag-in-flight calculator state); inactive pages compose the
    /// presenter against the slot's stored snapshot so each TabView
    /// page surfaces its slot's own target without leaking the
    /// active slot's value during a peek.
    public func targetShutterDisplayState(forPage pageState: CameraSlotPageState) -> TargetShutterDisplayState {
        if pageState.isActive {
            return targetShutterDisplayState
        }
        return TargetShutterPresenter.makeDisplayState(
            targetSeconds: pageState.targetShutterSeconds,
            comparisonSource: cameraSlotPageStateBuilder.targetShutterComparisonSource(
                forPage: pageState,
                filmModeResult: filmModeExposureResultState(forPage: pageState),
                calculationResult: calculationResult(forPage: pageState)
            )
        )
    }

    /// Comparison source the presenter uses when composing the Target
    /// Shutter display state. Digital workflow compares against the
    /// Adjusted Shutter; film workflow compares against the
    /// quantified Corrected Exposure when present, otherwise reports
    /// `unavailable` so the UI surfaces the calm `noComparisonAvailable`
    /// state rather than fabricating a number.
    private var targetShutterComparisonSource: TargetShutterPresenter.ComparisonSource {
        if isFilmWorkflowActive {
            // Film mode: compare against the quantified corrected
            // exposure when present. Limited-guidance / unsupported /
            // calc failure paths return `unavailable` so the UI never
            // silently compares against the intermediate Adjusted
            // Shutter value.
            if let filmModeExposureResultState,
               filmModeExposureResultState.hasQuantifiedCorrectedExposure,
               let correctedSeconds = filmModeExposureResultState.correctedExposure.correctedExposureSeconds,
               correctedSeconds.isFinite,
               correctedSeconds > 0 {
                return .correctedExposure(correctedSeconds)
            }
            return .unavailable
        }

        // Digital workflow: compare against the calculated Adjusted
        // Shutter. A calc failure falls through to `unavailable` so
        // the UI keeps the target visible without a fabricated value.
        guard case .success(let result) = calculationResult,
              result.resultShutterSeconds.isFinite,
              result.resultShutterSeconds > 0 else {
            return .unavailable
        }
        return .adjustedShutter(result.resultShutterSeconds)
    }

    public func startTimer(from resultShutter: TimeInterval) {
        // External / manual entry: the caller passed in a precomputed
        // shutter, not a calculation result derived from the active
        // slot. The timer must not inherit the active slot's
        // camera/film/source identity — see `.manual` doc.
        //
        // Pass `result: nil` so the basis summary always reads
        // `"Manual timer"` and the name falls through to the generic
        // `Timer - <duration>` shape. Threading the live calc result
        // into the composer here would let a coincidental match leak
        // ND/film wording into a manual timer's basis line — exactly
        // the contamination removed for identity capture.
        startTimer(
            from: resultShutter,
            result: nil,
            filmModeResult: nil,
            startSource: .manual
        )
    }

    /// Starts a fresh timer cloned from `source`'s setup and full
    /// duration, from any state, leaving the source timer untouched. A
    /// timer is canceled only by an explicit Cancel, never implicitly by
    /// Clone. Returns the new timer's id so the caller can move focus to it.
    @discardableResult
    public func cloneTimer(from source: RunningTimerItem) -> UUID? {
        timerWorkspaceModel.startTimer(cloning: source)
    }

    /// Cancels a running or paused timer, keeping it as a terminal
    /// canceled record (distinct from `removeTimer`, which deletes it).
    public func cancelTimer(id: UUID) {
        timerWorkspaceModel.cancelTimer(id: id)
    }

    public func pauseTimer(id: UUID) {
        timerWorkspaceModel.pauseTimer(id: id)
    }

    public func resumeTimer(id: UUID) {
        timerWorkspaceModel.resumeTimer(id: id)
    }

    public func removeTimer(id: UUID) {
        timerWorkspaceModel.removeTimer(id: id)
    }

    public func reconcileTimersAfterAppBecomesActive() {
        timerWorkspaceModel.reconcileTimersAfterAppBecomesActive()
    }

    private func startTimer(
        from resultShutter: TimeInterval,
        result: ExposureCalculationResult?,
        filmModeResult: FilmModeExposureResultState?,
        startSource: TimerStartComposer.Source
    ) {
        let payload = timerStartComposer.compose(
            TimerStartComposer.Input(
                targetDuration: resultShutter,
                result: result,
                filmModeResult: filmModeResult,
                source: startSource,
                selectedPresetFilm: filmSelectionModel.selectedPresetFilm,
                selectedProfileOverride: filmSelectionModel.selectedProfileOverride,
                activeCameraSlot: cameraSlotSessionModel.activeSlot,
                targetShutterSeconds: targetShutterModel.targetSeconds
            )
        )

        timerWorkspaceModel.startTimer(
            duration: resultShutter,
            name: payload.name,
            basisSummary: payload.basisSummary,
            cameraSlot: payload.cameraSlot,
            filmDisplayName: payload.filmDisplayName,
            filmProfileQualifier: payload.filmProfileQualifier,
            exposureSource: payload.exposureSource,
            isOutsideManufacturerGuidance: payload.isOutsideManufacturerGuidance,
            customProfileSummary: payload.customProfileSummary,
            selectedModelLabel: payload.selectedModelLabel,
            ndStops: payload.ndStops,
            baseShutterSeconds: payload.baseShutterSeconds,
            adjustedShutterSeconds: payload.adjustedShutterSeconds
        )
    }

    public func clearCompletedTimers() {
        timerWorkspaceModel.clearCompletedTimers()
    }

    public func formatDuration(_ seconds: TimeInterval) -> String {
        calculator.formatShutter(seconds)
    }

    public func formatTimeDisplay(_ seconds: TimeInterval) -> TimeDisplay {
        calculator.formatTimeDisplay(seconds)
    }

    /// Shared result-row duration policy for BOTH No Film and Film
    /// (PTIMER-172). One policy so the two modes never differ:
    /// - `< 60 s` → concise seconds primary, no secondary
    /// - `60 s ≤ t < 1 d` → clock primary + whole-seconds secondary
    /// - `≥ 1 d` → coarse ("Nd" / "≈Nmo" / "≈Ny") primary, no secondary
    /// The coarse formatter also keeps Main and Detail rendering the same
    /// primary string. This deliberately uses whole seconds for the
    /// secondary in both modes (the timer panel keeps its own decimal
    /// `formatTimeDisplay`).
    public func resultDurationDisplay(_ seconds: TimeInterval) -> TimeDisplay {
        let safeSeconds = max(seconds, 0)
        let primary = formatReciprocityDurationCoarse(safeSeconds)
        let secondary = reciprocityModel.formatReciprocitySecondsComparison(
            safeSeconds,
            approximate: primary.hasPrefix("≈")
        ) ?? ""
        return TimeDisplay(primary: primary, secondary: secondary)
    }

    public func formatReciprocityDuration(_ seconds: TimeInterval) -> String {
        reciprocityModel.formatReciprocityDuration(seconds)
    }

    public func formatReciprocityDurationCoarse(_ seconds: TimeInterval) -> String {
        reciprocityModel.formatReciprocityDurationCoarse(seconds)
    }

    public func formatReciprocityAxisDuration(_ seconds: TimeInterval) -> String {
        reciprocityModel.formatReciprocityAxisDuration(seconds)
    }

    public func formatShutter(_ seconds: TimeInterval) -> String {
        calculator.formatShutter(seconds)
    }

    public func formatTimerClock(_ seconds: TimeInterval) -> String {
        calculator.formatExtendedClock(seconds)
    }

    public func formatDateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }

    public func timerTargetContext(for timer: RunningTimerItem) -> String? {
        let targetDisplay = formatTimeDisplay(timer.duration)

        switch timer.status {
        case .running, .paused:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        case .completed, .canceled:
            return nil
        }
    }

    public func timerTimeContext(for timer: RunningTimerItem) -> String? {
        switch timer.status {
        case .running:
            let completionText = timer.endDate.map(formatDateTime) ?? "--"
            return "Ends \(completionText)"
        case .completed:
            return completedTimeContext(for: timer.completedAt, relativeTo: timer.referenceDate)
        case .canceled:
            // Same timestamp + relative-age style as completed, just a
            // different verb, so canceled rows read e.g.
            // "Canceled 2026-06-16 23:59:31 · just now".
            return terminalTimeContext(verb: "Canceled", for: timer.endDate, relativeTo: timer.referenceDate)
        case .paused:
            let pausedText = timer.pausedAt.map(formatDateTime) ?? "--"
            return "Paused \(pausedText)"
        }
    }

    public func completedTimeContext(for completionDate: Date?, relativeTo referenceDate: Date) -> String {
        terminalTimeContext(verb: "Completed", for: completionDate, relativeTo: referenceDate)
    }

    /// Shared "<verb> <absolute timestamp> · <relative age>" formatter
    /// for terminal records (completed and canceled), so both surfaces
    /// share one absolute+relative presentation path.
    private func terminalTimeContext(verb: String, for date: Date?, relativeTo referenceDate: Date) -> String {
        guard let date else {
            return "\(verb) --"
        }

        let absoluteText = formatDateTime(date)
        let relativeText = timerWorkspaceModel.relativeCompletedText(
            from: date,
            relativeTo: referenceDate
        )
        return "\(verb) \(absoluteText) · \(relativeText)"
    }

    public func compactCompletedSupplementaryText(for timer: RunningTimerItem) -> String? {
        guard timer.status == .completed else {
            return nil
        }

        return compactCompletedRelativeTimeText(for: timer.completedAt, relativeTo: timer.referenceDate)
    }

    public func compactCompletedRelativeTimeText(for completionDate: Date?, relativeTo referenceDate: Date) -> String {
        timerWorkspaceModel.compactCompletedRelativeTimeText(
            for: completionDate,
            relativeTo: referenceDate
        )
    }

    public var runningTimerCount: Int {
        timerWorkspaceModel.runningTimerCount
    }

    public func updateLiveBaseShutter(_ value: Double) {
        calculatorModel.updateLiveBaseShutter(value)
    }

    public func updateLiveNDStop(_ value: Int) {
        calculatorModel.updateLiveNDStop(value)
    }

    /// Fractional-aware live preview hook used by the SwiftUI ND
    /// picker drag callback. Mirrors `updateLiveNDStop` but accepts
    /// the canonical `NDStep` so a fractional drag (exercised by
    /// tests covering the reserved fractional path) does not lose
    /// precision going through the integer wrapper.
    public func updateLiveNDStep(_ value: NDStep) {
        calculatorModel.updateLiveNDStep(value)
    }

    public func clearLiveBaseShutterPreview() {
        calculatorModel.clearLiveBaseShutterPreview()
    }

    public func clearLiveNDStopPreview() {
        calculatorModel.clearLiveNDStopPreview()
    }

    /// Picker label for an `NDStep` value. The shipping ND picker
    /// advances in 1/3-stop increments (per `docs/specs/Calculator.md`
    /// §2.2), so this formatter renders whole stops as the integer
    /// alone (`"0"`, `"1"`, …) and fractional steps as mixed fractions
    /// (`"1/3"`, `"2/3"`, `"1 1/3"`, …).
    public func formatNDStop(_ ndStep: NDStep) -> String {
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
    public func formatShutterStepLabel(_ seconds: TimeInterval) -> String {
        if scaleMode == .oneThirdStop,
           let cameraLabel = ExposureScale.oneThirdStopShutterCameraLabel(forSeconds: seconds) {
            return cameraLabel
        }
        return calculator.formatShutter(seconds)
    }

    private func restorePersistedCalculatorContext() {
        let planBuilder = CalculatorContextRestorePlanBuilder()
        let plan: CalculatorContextRestorePlanBuilder.RestorePlan

        // Prefer the new multi-slot session snapshot when present.
        // No session snapshot falls back to the legacy single-
        // context restore path — covers (a) first launch after
        // upgrade from a session-unaware build and (b) test setups
        // that wire the legacy store directly.
        if let session = sessionPersistence?.loadSession() {
            plan = planBuilder.plan(from: session)
        } else if let restored = filmSelectionModel.restoreContext() {
            plan = planBuilder.plan(fromLegacy: restored)
        } else {
            return
        }

        applyRestorePlan(plan)
    }

    /// Applies a planned restore. **Side-effect order matters** on
    /// the session branch: `applyCameraSlotSnapshot` runs a deferred
    /// `persistCalculatorContext()` at its end, which reads
    /// `cameraSlotSessionModel.currentInactiveSnapshots()` to write
    /// the full session. If the active snapshot is applied before
    /// the inactive map is loaded, the trailing persist would
    /// overwrite a valid 4-slot session with active-only state and
    /// silently destroy the photographer's other three slots on the
    /// first relaunch. Restore the inactive map first so the persist
    /// captures the full session.
    private func applyRestorePlan(
        _ plan: CalculatorContextRestorePlanBuilder.RestorePlan
    ) {
        switch plan.source {
        case let .session(sessionPlan):
            cameraSlotSessionModel.restoreActiveSlot(to: sessionPlan.activeSlotID)
            cameraSlotSessionModel.restoreInactiveSnapshots(sessionPlan.inactiveSnapshots)
            cameraSlotSessionModel.restoreCustomDisplayNames(sessionPlan.customDisplayNames)
            applyCameraSlotSnapshot(sessionPlan.activeSlotSnapshot)

        case let .legacy(legacy):
            if let restoredSlotID = legacy.activeCameraSlotID {
                cameraSlotSessionModel.restoreActiveSlot(to: restoredSlotID)
            }
            guard !legacy.hadInvalidFilmReference else {
                return
            }
            scaleMode = legacy.scaleMode
            baseShutter = legacy.baseShutterSeconds ?? defaultFilmModeBaseShutter
            if let sanitized = legacy.ndStep {
                if let wholeStops = sanitized.wholeStops {
                    ndStop = wholeStops
                } else {
                    ndStep = sanitized
                }
            } else {
                ndStop = defaultFilmModeNDStop
            }
            persistCalculatorContext()
        }
    }

    /// Helper exposed for the +CustomFilm extension. Scrubs
    /// every inactive camera-slot snapshot's film reference matching
    /// `id` so a custom-film deletion cannot resurface a deleted
    /// reference on slot switch. Returns the touched slot ids so the
    /// caller can decide whether to flush persistence.
    @discardableResult
    public func clearCustomFilmFromInactiveSlots(id: String) -> Set<CameraSlotID> {
        cameraSlotSessionModel.clearFilmReference(filmID: id)
    }

    /// Helper that pipes a custom-film delete through the
    /// same persistence path a regular state mutation uses, so the
    /// inactive-slot scrub survives a relaunch.
    public func persistInactiveSlotCleanup() {
        persistCalculatorContext()
    }

    /// Loads the persisted ND notation mode on launch. Display-only;
    /// independent of the calculator-context restore so a missing or
    /// corrupt settings blob leaves the shipping `.stops` default in
    /// place without affecting calc state.
    private func restoreDisplaySettings() {
        guard let settings = displaySettingStore.loadSettings() else {
            return
        }
        let restored = settings.restoredNDNotationMode
        if ndNotationMode != restored {
            ndNotationMode = restored
        }
    }

    private func persistDisplaySettings() {
        displaySettingStore.saveSettings(
            PersistentDisplaySettings(ndNotationMode: ndNotationMode)
        )
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

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Absolute event timestamps (completed / canceled / paused / ends)
        // render in the device's local time zone, not UTC, so each event reads
        // in the local time where it occurred.
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

}
