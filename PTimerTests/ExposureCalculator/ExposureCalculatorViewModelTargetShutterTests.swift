import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelTargetShutterTests: XCTestCase {
    // MARK: - State and display

    @MainActor
    func testTargetShutterDefaultsToInactive() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.isTargetShutterActive)
        XCTAssertNil(viewModel.targetShutterSeconds)
        XCTAssertEqual(viewModel.targetShutterDisplayState, .unavailable(.inactive))
        XCTAssertFalse(viewModel.canStartTargetShutterTimer)
    }

    @MainActor
    func testSetTargetShutterActivatesAndSurfacesValue() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(120)

        XCTAssertTrue(viewModel.isTargetShutterActive)
        XCTAssertEqual(viewModel.targetShutterSeconds ?? 0, 120, accuracy: 0.0001)
        XCTAssertTrue(viewModel.canStartTargetShutterTimer)
    }

    @MainActor
    func testClearTargetShutterReturnsToInactive() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(60)

        viewModel.clearTargetShutter()

        XCTAssertFalse(viewModel.isTargetShutterActive)
        XCTAssertNil(viewModel.targetShutterSeconds)
    }

    @MainActor
    func testTargetShutterRemainsFixedWhileBaseShutterChanges() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(60)

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4

        XCTAssertEqual(viewModel.targetShutterSeconds ?? 0, 60, accuracy: 0.0001)
    }

    @MainActor
    func testInvalidTargetShutterValueIsRejected() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(-10)

        XCTAssertFalse(viewModel.isTargetShutterActive)
        XCTAssertFalse(viewModel.canStartTargetShutterTimer)
    }

    // MARK: - Comparison routing

    @MainActor
    func testDigitalWorkflowComparesAgainstAdjustedShutter() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1
        viewModel.ndStop = 6
        // Adjusted shutter = 1 * 2^6 = 64s.
        viewModel.setTargetShutter(128)

        guard case .available(let state) = viewModel.targetShutterDisplayState,
              let comparison = state.comparison,
              let stopDifference = state.stopDifference else {
            return XCTFail("Expected available state with quantified Adjusted Shutter comparison")
        }

        XCTAssertEqual(comparison.label, "Adjusted Shutter")
        XCTAssertEqual(comparison.seconds, 64, accuracy: 0.0001)
        XCTAssertEqual(stopDifference.stops, 1, accuracy: 0.001)
        XCTAssertEqual(stopDifference.kind, .longerThanComparison)
    }

    @MainActor
    func testFilmWorkflowComparesAgainstQuantifiedCorrectedExposure() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        // Tri-X 400 quantified corrected for 1s metered ≈ 2s. Set target = 4s ⇒ +1 stop.
        viewModel.setTargetShutter(4)

        guard case .available(let state) = viewModel.targetShutterDisplayState,
              let comparison = state.comparison,
              let stopDifference = state.stopDifference else {
            return XCTFail("Expected available state with quantified Corrected Exposure comparison")
        }

        XCTAssertEqual(comparison.label, "Corrected Exposure")
        XCTAssertEqual(comparison.seconds, 2, accuracy: 0.0001)
        XCTAssertEqual(stopDifference.stops, 1, accuracy: 0.001)
        XCTAssertEqual(stopDifference.kind, .longerThanComparison)
    }

    @MainActor
    func testFilmWorkflowAdvisoryDoesNotFabricateStopDifference() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        // Portra 400 at 15s metered exposure is advisory-only — no quantified
        // corrected exposure exists. The presenter must not silently fall
        // through to the Adjusted Shutter value.
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .advisory)

        viewModel.setTargetShutter(60)

        guard case .available(let state) = viewModel.targetShutterDisplayState else {
            return XCTFail("Expected available state with target preserved")
        }

        XCTAssertEqual(state.targetSeconds, 60)
        XCTAssertNil(state.comparison, "Advisory-only film result must not produce a fabricated comparison")
        XCTAssertNil(state.stopDifference)
    }

    @MainActor
    func testFilmWorkflowUnsupportedDoesNotFabricateStopDifference() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })
        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .unsupported)

        viewModel.setTargetShutter(60)

        guard case .available(let state) = viewModel.targetShutterDisplayState else {
            return XCTFail("Expected available state with target preserved")
        }

        XCTAssertNil(state.comparison)
        XCTAssertNil(state.stopDifference)
    }

    @MainActor
    func testTargetMatchProducesMatchKind() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        // Adjusted shutter = 1s; target == 1s ⇒ match.
        viewModel.setTargetShutter(1)

        guard case .available(let state) = viewModel.targetShutterDisplayState,
              let stopDifference = state.stopDifference else {
            return XCTFail("Expected available state with quantified comparison")
        }

        XCTAssertEqual(stopDifference.kind, .match)
        XCTAssertEqual(stopDifference.formattedText, "0 stops")
    }

    // MARK: - Timer integration

    @MainActor
    func testStartTargetShutterTimerUsesTargetDuration() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1
        viewModel.ndStop = 6
        viewModel.setTargetShutter(20 * 60)

        viewModel.startTargetShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 20 * 60, accuracy: 0.0001)
        XCTAssertEqual(timer.exposureSource, .targetShutter)
    }

    @MainActor
    func testStartTargetShutterTimerStampsCameraSlotIdentity() throws {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(60)

        viewModel.startTargetShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.cameraSlot?.id, viewModel.activeCameraSlotID)
    }

    @MainActor
    func testStartTargetShutterTimerWithoutTargetIsNoop() {
        let viewModel = makeViewModel()

        viewModel.startTargetShutterTimer()

        XCTAssertTrue(viewModel.timers.isEmpty)
    }

    @MainActor
    func testStartTargetShutterTimerNamePrefixesTarget() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.setTargetShutter(60)

        viewModel.startTargetShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.name, "Target - 60s")
    }

    @MainActor
    func testStartTargetShutterTimerNamePrefixesFilmAndTargetWhenFilmActive() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        viewModel.setTargetShutter(120)

        viewModel.startTargetShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.name, "Tri-X 400 · Target - 120s")
    }

    @MainActor
    func testTargetTimerCanCoexistWithAdjustedTimer() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1
        viewModel.ndStop = 6

        viewModel.startTimer()
        viewModel.setTargetShutter(180)
        viewModel.startTargetShutterTimer()

        XCTAssertEqual(viewModel.timers.count, 2)
        let sources = viewModel.timers.compactMap(\.exposureSource).sorted { $0.rawValue < $1.rawValue }
        XCTAssertEqual(sources, [.digitalResult, .targetShutter].sorted { $0.rawValue < $1.rawValue })
    }

    @MainActor
    func testTargetTimerBasisSummaryIncludesTargetSegment() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.setTargetShutter(120)

        viewModel.startTargetShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertTrue(timer.basisSummary.contains("Target 120s"),
                      "Basis summary should carry the target duration; got \(timer.basisSummary)")
    }

    // MARK: - Per-camera-slot target state

    @MainActor
    func testTargetShutterIsPerSlotAndDoesNotLeakWhenSwitching() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(300) // Camera 1 → 5m

        viewModel.selectCameraSlot(.camera2)

        XCTAssertNil(viewModel.targetShutterSeconds,
                     "Camera 2 must start with no target — Camera 1's value cannot leak")
        XCTAssertFalse(viewModel.isTargetShutterActive)
        XCTAssertEqual(viewModel.targetShutterDisplayState, .unavailable(.inactive))
    }

    /// Slot-isolation pin for the sheet seed path. Camera 1 sets and
    /// then clears a target; the global `lastUsedTargetSeconds`
    /// memory still holds Camera 1's value. Switching to Camera 2
    /// must report inactive display state — the sheet derives its
    /// seed from `displayState`, so `.unavailable(.inactive)` causes
    /// the section view's `initialSheetSeconds` to return `nil` and
    /// the sheet to seed to the default (1 minute). Camera 1's
    /// previously-used 8h 11m must not appear on Camera 2.
    @MainActor
    func testInactiveSlotDoesNotLeakLastUsedAsSheetSeed() {
        let viewModel = makeViewModel()
        let camera1Target: TimeInterval = TimeInterval(8 * 3600 + 11 * 60) // 8h 11m
        viewModel.setTargetShutter(camera1Target)
        viewModel.clearTargetShutter()

        // The global last-used memory still has the value — this is
        // intentional (the field is preserved for read-only callers),
        // but it must not drive the per-slot sheet seed.
        XCTAssertEqual(viewModel.lastUsedTargetShutterSeconds ?? 0, camera1Target, accuracy: 0.0001,
                       "Global last-used memory still holds the cleared value (this is the leak source the section view must ignore)")

        viewModel.selectCameraSlot(.camera2)

        // Camera 2 reports inactive — the section view's
        // `initialSheetSeconds` returns nil for inactive display
        // state, so the sheet falls back to the default seed.
        let camera2Page = viewModel.cameraSlotPageState(for: .camera2)
        XCTAssertEqual(
            viewModel.targetShutterDisplayState(forPage: camera2Page),
            .unavailable(.inactive),
            "Camera 2 with no committed target must report inactive — drives sheet to seed default, not Camera 1's 8h 11m"
        )

        // Camera 1 (now committed off) is also inactive after the
        // clear — same default-seed path applies. No same-slot draft
        // memory is added by this task.
        viewModel.selectCameraSlot(.camera1)
        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(
            viewModel.targetShutterDisplayState(forPage: camera1Page),
            .unavailable(.inactive),
            "Camera 1 after Clear+Confirm is inactive — sheet must also seed default, not the cleared 8h 11m"
        )
    }

    @MainActor
    func testTargetShutterRestoredOnSlotReturn() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(300) // Camera 1 → 5m
        viewModel.selectCameraSlot(.camera2)
        viewModel.setTargetShutter(3600) // Camera 2 → 1h

        viewModel.selectCameraSlot(.camera1)

        XCTAssertEqual(viewModel.targetShutterSeconds ?? 0, 300, accuracy: 0.0001,
                       "Camera 1 must restore its captured 5m target after a round trip through Camera 2")

        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.targetShutterSeconds ?? 0, 3600, accuracy: 0.0001,
                       "Camera 2 must restore its captured 1h target after a round trip through Camera 1")
    }

    @MainActor
    func testInactiveSlotPageStateExposesStoredTarget() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(900) // Camera 1 → 15m
        viewModel.selectCameraSlot(.camera2)
        viewModel.setTargetShutter(7200) // Camera 2 → 2h

        // While Camera 2 is active, peeking at Camera 1's page state
        // surfaces Camera 1's stored target (15m) — not the live
        // active target (2h).
        let inactivePageState = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(inactivePageState.targetShutterSeconds ?? 0, 900, accuracy: 0.0001)

        let inactiveDisplay = viewModel.targetShutterDisplayState(forPage: inactivePageState)
        guard case .available(let availableState) = inactiveDisplay else {
            return XCTFail("Inactive slot with stored target should produce an available display state")
        }
        XCTAssertEqual(availableState.targetSeconds, 900, accuracy: 0.0001)
    }

    @MainActor
    func testResetFilmModeWorkingContextClearsActiveSlotTarget() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(600)
        XCTAssertTrue(viewModel.isTargetShutterActive)

        viewModel.resetFilmModeWorkingContext()

        XCTAssertFalse(viewModel.isTargetShutterActive,
                       "Workspace reset must drop the active slot's target")
    }

    @MainActor
    func testActiveTargetCountsAsResettableContext() {
        // Use a default-scale ViewModel so the fixture starts with
        // `canResetFilmModeWorkingContext == false`. The shipping
        // default is `.oneThirdStop`; the suite's `makeViewModel`
        // helper pins `.fullStop`, which itself flips the reset flag.
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertFalse(viewModel.canResetFilmModeWorkingContext)

        viewModel.setTargetShutter(120)

        XCTAssertTrue(viewModel.canResetFilmModeWorkingContext,
                      "Setting a target should expose the Reset action so the photographer can clear it")
    }

    // MARK: - Long target durations

    @MainActor
    func testTargetShutterAcceptsOneHourDuration() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(3600)

        XCTAssertEqual(viewModel.targetShutterSeconds ?? 0, 3600, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isTargetShutterActive)
        XCTAssertTrue(viewModel.canStartTargetShutterTimer)
    }

    @MainActor
    func testTargetShutterAcceptsEightHourDuration() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1
        viewModel.ndStop = 6 // Adjusted = 64s

        viewModel.setTargetShutter(8 * 3600)

        guard case .available(let state) = viewModel.targetShutterDisplayState,
              let stopDifference = state.stopDifference else {
            return XCTFail("8h target with positive Adjusted Shutter should produce a quantified comparison")
        }
        // log2(28800 / 64) = log2(450) ≈ 8.81 stops
        XCTAssertEqual(stopDifference.stops, log2(28_800.0 / 64.0), accuracy: 0.001)
        XCTAssertEqual(stopDifference.kind, .longerThanComparison)
    }

    @MainActor
    func testTargetShutterAcceptsOneSecondDuration() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(1)

        XCTAssertEqual(viewModel.targetShutterSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(viewModel.canStartTargetShutterTimer)
    }

    // MARK: - Last-used target memory

    @MainActor
    func testLastUsedTargetMemoryStartsNil() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.lastUsedTargetShutterSeconds)
    }

    @MainActor
    func testLastUsedTargetMemoryUpdatesOnSet() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(120)
        XCTAssertEqual(viewModel.lastUsedTargetShutterSeconds ?? 0, 120, accuracy: 0.0001)

        viewModel.setTargetShutter(900)
        XCTAssertEqual(viewModel.lastUsedTargetShutterSeconds ?? 0, 900, accuracy: 0.0001)
    }

    @MainActor
    func testLastUsedTargetSurvivesClear() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(600)

        viewModel.clearTargetShutter()

        XCTAssertNil(viewModel.targetShutterSeconds, "Active target must clear")
        XCTAssertEqual(viewModel.lastUsedTargetShutterSeconds ?? 0, 600, accuracy: 0.0001,
                       "Last-used memory must survive a clear so the sheet can pre-fill it")
    }

    @MainActor
    func testLastUsedTargetSurvivesSlotSwitch() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(900) // Camera 1 → 15m
        viewModel.selectCameraSlot(.camera2)

        XCTAssertNil(viewModel.targetShutterSeconds, "Camera 2 must start without a target")
        XCTAssertEqual(viewModel.lastUsedTargetShutterSeconds ?? 0, 900, accuracy: 0.0001,
                       "Last-used memory should survive a slot switch")
    }

    @MainActor
    func testInvalidSetTargetDoesNotAffectLastUsedMemory() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(300)

        viewModel.setTargetShutter(-1)

        XCTAssertNil(viewModel.targetShutterSeconds)
        XCTAssertEqual(viewModel.lastUsedTargetShutterSeconds ?? 0, 300, accuracy: 0.0001,
                       "Invalid input must not overwrite the last positive value")
    }

    // MARK: - Per-slot target reinforcement

    @MainActor
    func testTargetSetOnCamera2DoesNotOverwriteCamera1Target() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(300) // Camera 1 → 5m
        viewModel.selectCameraSlot(.camera2)
        viewModel.setTargetShutter(3600) // Camera 2 → 1h

        // Camera 1's saved target must remain 5m on its inactive
        // snapshot — the active write only touches the active slot.
        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(camera1Page.targetShutterSeconds ?? 0, 300, accuracy: 0.0001,
                       "Camera 1's stored target must not change when Camera 2 sets a different target")
    }

    @MainActor
    func testTargetClearedOnCamera2DoesNotClearCamera1Target() {
        let viewModel = makeViewModel()

        viewModel.setTargetShutter(300)
        viewModel.selectCameraSlot(.camera2)
        viewModel.setTargetShutter(600)

        viewModel.clearTargetShutter() // Clears Camera 2 only

        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(camera1Page.targetShutterSeconds ?? 0, 300, accuracy: 0.0001,
                       "Clearing Camera 2's target must not clear Camera 1's stored target")
    }

    @MainActor
    func testInactivePageTargetDisplayStateMatchesStoredTarget() {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(7200) // Camera 1 → 2h
        viewModel.selectCameraSlot(.camera2)

        // While Camera 2 is active, peeking at Camera 1's page state
        // surfaces Camera 1's stored 2h target, not Camera 2's
        // (currently nil) live target.
        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        let camera1Display = viewModel.targetShutterDisplayState(forPage: camera1Page)

        guard case .available(let camera1State) = camera1Display else {
            return XCTFail("Inactive Camera 1 with stored 2h target should produce an available state")
        }
        XCTAssertEqual(camera1State.targetSeconds, 7200, accuracy: 0.0001)

        // Camera 2 is active and has no target — its display state
        // should be inactive even while Camera 1 has one stored.
        XCTAssertEqual(viewModel.targetShutterDisplayState, .unavailable(.inactive))
    }

    @MainActor
    func testStartTargetShutterTimerFromEightHourTargetUsesFullDuration() throws {
        let viewModel = makeViewModel()
        viewModel.setTargetShutter(8 * 3600)

        viewModel.startTargetShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 8 * 3600, accuracy: 0.0001)
        XCTAssertEqual(timer.exposureSource, .targetShutter)
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel() -> ExposureCalculatorViewModel {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        // Pin the legacy full-stop scale so the snap-style assertions in this
        // suite stay aligned with the Tri-X 400 / Portra 400 fixtures used
        // elsewhere; the shipping calculator defaults to the one-third-stop
        // scale per `docs/specs/Calculator.md` §1.4.
        viewModel.scaleMode = .fullStop
        return viewModel
    }
}
