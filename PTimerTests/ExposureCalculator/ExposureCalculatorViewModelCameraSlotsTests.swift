import XCTest
@testable import PTimer

/// Integration tests for camera-slot behavior through the
/// `ExposureCalculatorViewModel` facade. Exercises slot independence
/// (films, exposure inputs, reciprocity result) and the camera-slot
/// metadata that flows through `TimerWorkspaceModel.startTimer`.
@MainActor
final class ExposureCalculatorViewModelCameraSlotsTests: XCTestCase {

    // MARK: - Slot independence: workflow + film

    func testTwoSlotsKeepDifferentFilmAndNonFilmWorkflowState() throws {
        let viewModel = makeViewModel()
        // Camera 1 stays in non-film workflow with custom inputs.
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6

        // Switch to Camera 2 and pick a film.
        viewModel.selectCameraSlot(.camera2)
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)

        // Switch back to Camera 1 — non-film workflow is restored with the
        // exposure inputs the user left there.
        viewModel.selectCameraSlot(.camera1)

        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 6)
    }

    func testFilmSelectionPreservedAcrossSlotSwitchAndReturn() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.selectPresetFilm(film)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)

        viewModel.selectCameraSlot(.camera2)
        XCTAssertNil(viewModel.selectedPresetFilm)
        viewModel.selectCameraSlot(.camera1)

        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)
    }

    func testTwoFilmSlotsCanHoldDifferentFilms() throws {
        let viewModel = makeViewModel()
        let triX = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        let portra = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName.contains("Portra 400") }
        )

        viewModel.selectPresetFilm(triX)
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectPresetFilm(portra)

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, triX.id)
        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, portra.id)
    }

    // MARK: - Slot independence: exposure inputs

    func testBaseShutterAndNDStaySlotSpecific() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4

        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 10

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 4)

        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 15.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 10)
    }

    func testMutationOnActiveSlotDoesNotMutateInactiveSlot() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 10

        // Mutate Camera 2 (currently active). Camera 1 must remain
        // unchanged.
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.ndStop = 12

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 4)
    }

    // MARK: - Adjusted shutter / corrected exposure independence

    /// The calculated (adjusted) shutter is a pure function of base
    /// shutter + ND, so per-slot input independence implies per-slot
    /// adjusted shutter independence. The spec calls this out as an
    /// explicit acceptance criterion, so verify the read-side matches.
    func testAdjustedShutterResultStaysSlotSpecific() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4
        let camera1Adjusted = try unwrappedAdjustedShutter(viewModel)

        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 10
        let camera2Adjusted = try unwrappedAdjustedShutter(viewModel)

        XCTAssertNotEqual(
            camera1Adjusted,
            camera2Adjusted,
            accuracy: 1e-9,
            "Slot-specific inputs must produce slot-specific adjusted shutter results."
        )

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(
            try unwrappedAdjustedShutter(viewModel),
            camera1Adjusted,
            accuracy: 1e-9
        )
        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(
            try unwrappedAdjustedShutter(viewModel),
            camera2Adjusted,
            accuracy: 1e-9
        )
    }

    /// Two film slots with the same film but different exposure inputs
    /// must produce different corrected exposure results. Guards
    /// against a regression where slot switching restored film state
    /// but accidentally clobbered the corrected exposure result.
    func testCorrectedExposureStaysSlotSpecific() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        let camera1Corrected = try XCTUnwrap(
            viewModel.filmModeExposureResultState?.correctedExposure.correctedExposureSeconds
        )

        viewModel.selectCameraSlot(.camera2)
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 10
        let camera2Corrected = try XCTUnwrap(
            viewModel.filmModeExposureResultState?.correctedExposure.correctedExposureSeconds
        )

        XCTAssertNotEqual(
            camera1Corrected,
            camera2Corrected,
            accuracy: 1e-9
        )

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(
            viewModel.filmModeExposureResultState?.correctedExposure.correctedExposureSeconds,
            camera1Corrected
        )
    }

    // MARK: - Reciprocity result preservation

    func testReciprocityResultSurvivesSlotSwitch() throws {
        let viewModel = makeViewModel()
        // Pick a film with quantified reciprocity guidance and inputs
        // that produce a reciprocity-corrected result.
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6

        let beforeSwitch = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertNotNil(beforeSwitch.correctedExposure.correctedExposureSeconds)

        viewModel.selectCameraSlot(.camera2)
        viewModel.selectCameraSlot(.camera1)

        let afterSwitch = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(
            afterSwitch.correctedExposure.correctedExposureSeconds,
            beforeSwitch.correctedExposure.correctedExposureSeconds
        )
    }

    // MARK: - Active slot publication

    func testActiveCameraSlotIDPublishesOnSwitch() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)

        viewModel.selectCameraSlot(.camera3)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
    }

    // MARK: - Timer metadata

    func testStartedTimerCarriesActiveCameraSlotIdentity() throws {
        let viewModel = makeViewModel()
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6

        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.cameraSlot?.id, .camera2)
        XCTAssertEqual(timer.cameraSlot?.displayName, "Camera 2")
    }

    func testFilmAdjustedAndCorrectedTimersBothCarrySlotIdentity() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectCameraSlot(.camera3)
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6

        viewModel.startFilmAdjustedShutterTimer()
        viewModel.startFilmCorrectedExposureTimer()

        XCTAssertGreaterThanOrEqual(viewModel.timers.count, 2)
        for timer in viewModel.timers {
            XCTAssertEqual(timer.cameraSlot?.id, .camera3)
            XCTAssertEqual(timer.cameraSlot?.displayName, "Camera 3")
        }
    }

    // MARK: - Slot page state (TabView pages)

    func testActivePageStateMatchesLiveCalculatorState() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6

        let active = viewModel.cameraSlotPageState(for: .camera1)

        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.cameraDisplayName, "Camera 1")
        XCTAssertEqual(active.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(active.ndStep.stops, 6, accuracy: 1e-9)
        XCTAssertEqual(active.selectedFilm?.id, film.id)
        XCTAssertTrue(active.isFilmWorkflowActive)
        XCTAssertEqual(active.filmSelectionDisplayState.primaryText, "Tri-X 400")
    }

    func testInactivePageStateReadsStoredSnapshot() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

        // Configure Camera 1 then switch away — Camera 1's snapshot
        // is now the source of truth for its page state.
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6
        viewModel.selectCameraSlot(.camera2)

        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertFalse(camera1Page.isActive)
        XCTAssertEqual(camera1Page.cameraDisplayName, "Camera 1")
        XCTAssertEqual(camera1Page.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(camera1Page.ndStep.stops, 6, accuracy: 1e-9)
        XCTAssertEqual(camera1Page.selectedFilm?.id, film.id)
        XCTAssertTrue(camera1Page.isFilmWorkflowActive)
    }

    func testInactivePageDigitalSlotShowsNoFilmDisplay() {
        let viewModel = makeViewModel()
        // Camera 2 has not been visited, so its snapshot is the
        // initial defaults — no film, baseShutter 1/30, ND 0.
        let page = viewModel.cameraSlotPageState(for: .camera2)

        XCTAssertFalse(page.isActive)
        XCTAssertNil(page.selectedFilm)
        XCTAssertFalse(page.isFilmWorkflowActive)
        XCTAssertEqual(page.filmSelectionDisplayState.primaryText, "No film")
    }

    func testCalculationResultForInactivePageUsesItsOwnInputs() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4

        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 10

        // Page calc result must come from each slot's own inputs even
        // when the live state holds Camera 2's values.
        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        let camera2Page = viewModel.cameraSlotPageState(for: .camera2)

        guard case .success(let camera1Result) = viewModel.calculationResult(forPage: camera1Page),
              case .success(let camera2Result) = viewModel.calculationResult(forPage: camera2Page) else {
            XCTFail("Expected calculation results for both pages")
            return
        }

        XCTAssertNotEqual(
            camera1Result.resultShutterSeconds,
            camera2Result.resultShutterSeconds,
            accuracy: 1e-9,
            "Each page's calc result must reflect its own slot inputs."
        )
    }

    func testInactivePageFilmModeResultDisablesTimerStart() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.selectCameraSlot(.camera2)

        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        let camera1Result = try XCTUnwrap(
            viewModel.filmModeExposureResultState(forPage: camera1Page)
        )

        // Inactive pages render the same layout but disable the
        // start-timer affordances — the user has to swipe to the
        // page first, which makes it active.
        XCTAssertFalse(camera1Result.adjustedShutterAction.canStartTimer)
        XCTAssertFalse(camera1Page.isActive)
    }

    // MARK: - Slot pager navigation

    func testSelectNextCameraSlotAdvancesAndStopsAtLast() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
        XCTAssertEqual(viewModel.activeCameraSlotIndex, 0)

        viewModel.selectNextCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2)
        XCTAssertEqual(viewModel.activeCameraSlotIndex, 1)

        viewModel.selectNextCameraSlot()
        viewModel.selectNextCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera4)

        // Bounded pager: another next at the last slot is a no-op.
        viewModel.selectNextCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera4)
    }

    func testSelectPreviousCameraSlotReversesAndStopsAtFirst() {
        let viewModel = makeViewModel()
        viewModel.selectCameraSlot(.camera3)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)

        viewModel.selectPreviousCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2)

        viewModel.selectPreviousCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)

        // Bounded pager: another previous at the first slot is a no-op.
        viewModel.selectPreviousCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
    }

    func testActiveCameraSlotPageTextFollowsCurrentSlot() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.activeCameraSlotPageText, "Camera 1, 1 of 4")

        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.activeCameraSlotPageText, "Camera 2, 2 of 4")

        viewModel.selectCameraSlot(.camera4)
        XCTAssertEqual(viewModel.activeCameraSlotPageText, "Camera 4, 4 of 4")
    }

    // MARK: - Identity snapshot semantics

    func testStartedTimerCarriesFilmDisplayNameAndExposureSource() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.filmDisplayName, "Tri-X 400")
        XCTAssertEqual(timer.exposureSource, .filmAdjustedShutter)
        XCTAssertEqual(timer.cameraSlot?.id, .camera2)
    }

    func testDigitalTimerIdentityHasNilFilmAndDigitalSource() throws {
        let viewModel = makeViewModel()
        viewModel.selectCameraSlot(.camera1)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6

        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertNil(timer.filmDisplayName)
        XCTAssertEqual(timer.exposureSource, .digitalResult)
    }

    func testTimerIdentityIsImmutableAfterSlotAndFilmChanges() throws {
        let viewModel = makeViewModel()
        let triX = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectPresetFilm(triX)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6

        viewModel.startFilmAdjustedShutterTimer()
        let captured = try XCTUnwrap(viewModel.timers.first)

        // Now mutate the active slot and the active film. The
        // already-started timer's identity must NOT rewrite.
        viewModel.selectCameraSlot(.camera1)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 0
        if let portra = viewModel.availablePresetFilms.first(where: { $0.canonicalStockName.contains("Portra 400") }) {
            viewModel.selectCameraSlot(.camera2)
            viewModel.selectPresetFilm(portra)
        }

        let after = try XCTUnwrap(viewModel.timers.first { $0.id == captured.id })
        XCTAssertEqual(after.cameraSlot?.id, .camera2)
        XCTAssertEqual(after.cameraSlot?.displayName, "Camera 2")
        XCTAssertEqual(after.filmDisplayName, "Tri-X 400")
        XCTAssertEqual(after.exposureSource, .filmAdjustedShutter)
    }

    // MARK: - Manual timer origin (no slot/film/source contamination)

    /// Manual entry — `viewModel.startTimer(from:)` — must NOT
    /// inherit the active camera slot, film, or exposure source.
    /// The photographer's external precomputed shutter is decoupled
    /// from whichever slot happens to be active.
    func testManualTimerDoesNotCaptureCameraSlotOrFilmIdentity() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

        // Set up a "rich" active context so any contamination would
        // be visible: Camera 2, Tri-X selected, custom inputs.
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6

        // Manual timer entry: external shutter that has nothing to do
        // with the active slot.
        viewModel.startTimer(from: 12.5)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertNil(timer.cameraSlot)
        XCTAssertNil(timer.filmDisplayName)
        XCTAssertNil(timer.filmProfileQualifier)
        XCTAssertNil(timer.exposureSource)
        // Identity snapshot must be nil so the dock falls back to
        // the order-based marker rather than rendering Camera 2's
        // identity onto a manual timer.
        XCTAssertNil(timer.identitySnapshot)
    }

    // MARK: - Inactive page action policy (state-level, not view-level)

    /// Inactive pages must disable BOTH adjusted and corrected
    /// timer-start actions in their state. Relying on
    /// `.allowsHitTesting(false)` on the view alone leaves the
    /// page's presentation lying about what it allows.
    func testInactivePageDisablesBothAdjustedAndCorrectedActions() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        // Move to camera2 so camera1 becomes the inactive page.
        viewModel.selectCameraSlot(.camera2)

        let inactivePage = viewModel.cameraSlotPageState(for: .camera1)
        let inactiveResult = try XCTUnwrap(
            viewModel.filmModeExposureResultState(forPage: inactivePage)
        )

        XCTAssertFalse(inactivePage.isActive)
        XCTAssertFalse(inactiveResult.adjustedShutterAction.canStartTimer)
        XCTAssertFalse(
            inactiveResult.correctedExposureAction.canStartTimer,
            "Inactive page must disable corrected-exposure timer start in state, not just at the view layer."
        )
    }

    // MARK: - Active slot persistence

    /// The persisted calculator context must capture the active slot
    /// id so a relaunch grafts the values back onto the same slot.
    /// Without this, Camera 3 context would silently restore as
    /// Camera 1 state.
    func testCalculatorContextPersistsActiveSlotIDForNonDefaultSlots() throws {
        let store = InMemoryContextStore()
        let viewModel = makeViewModel(contextStore: store)

        viewModel.selectCameraSlot(.camera3)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4

        let snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(snapshot.activeCameraSlotIDRaw, "camera3")
    }

    /// Default Camera 1 emits `nil` for the slot id field so legacy
    /// (pre-slot-aware) snapshots round-trip byte-for-byte.
    func testCalculatorContextOmitsActiveSlotIDForDefaultSlot() throws {
        let store = InMemoryContextStore()
        let viewModel = makeViewModel(contextStore: store)

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        let snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertNil(snapshot.activeCameraSlotIDRaw)
    }

    /// On launch, a persisted snapshot whose `activeCameraSlotIDRaw`
    /// names a non-default slot must restore that slot as active —
    /// not Camera 1 — so the values land on the page they came from.
    func testRelaunchRestoresPersistedActiveSlot() throws {
        let store = InMemoryContextStore()
        store.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: nil,
                baseShutterSeconds: 1.0 / 60.0,
                ndStop: 4,
                ndStopThirds: nil,
                exposureScaleMode: nil,
                activeCameraSlotIDRaw: "camera3"
            )
        )

        let viewModel = makeViewModel(contextStore: store)

        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)
        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Camera 3")
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 4)
    }

    // MARK: - Single-slot regression

    /// When the user never switches slots, the calculator must behave
    /// the same as the single-slot baseline: input mutations land on
    /// Camera 1, the calculated shutter reflects the inputs, and the
    /// started timer carries the Camera 1 identity (not nil — Camera 1
    /// is always the active slot, even when the picker hasn't been
    /// touched).
    func testSingleSlotBehaviorMatchesSingleSlotBaseline() throws {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Camera 1")

        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6
        let adjusted = try unwrappedAdjustedShutter(viewModel)
        XCTAssertGreaterThan(adjusted, 0)

        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.cameraSlot?.id, .camera1)
        XCTAssertEqual(timer.cameraSlot?.displayName, "Camera 1")
        XCTAssertEqual(timer.duration, adjusted, accuracy: 1e-9)
    }

    // MARK: - Helpers

    private func makeViewModel(
        contextStore: ExposureCalculatorContextPersistenceStoring = NoOpExposureCalculatorContextPersistenceStore()
    ) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            contextPersistenceStore: contextStore
        )
    }

    private func unwrappedAdjustedShutter(
        _ viewModel: ExposureCalculatorViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TimeInterval {
        guard case .success(let result) = viewModel.calculationResult else {
            XCTFail("Expected a successful calculation result", file: file, line: line)
            throw NSError(domain: "ExposureCalculatorViewModelCameraSlotsTests", code: 0)
        }
        return result.resultShutterSeconds
    }
}

/// Test double that mirrors the production persistence store but
/// keeps the snapshot in memory so tests can preload (`saveSnapshot`)
/// and inspect (`snapshot`) without touching `UserDefaults`.
private final class InMemoryContextStore: ExposureCalculatorContextPersistenceStoring {
    private(set) var snapshot: PersistentExposureCalculatorContextSnapshot?

    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}
