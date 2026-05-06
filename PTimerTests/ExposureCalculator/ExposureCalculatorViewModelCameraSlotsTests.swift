import XCTest
@testable import PTimer

/// Slot-navigation tests through the `ExposureCalculatorViewModel`
/// facade. This iteration covers slot pager API (active/index/page
/// text, prev/next, bounded behavior); per-slot calc state
/// independence and timer identity tests land in follow-up commits
/// as those features are wired in.
@MainActor
final class ExposureCalculatorViewModelCameraSlotsTests: XCTestCase {

    // MARK: - Slot pager navigation

    func testInitialActiveSlotIsCameraOne() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Camera 1")
        XCTAssertEqual(viewModel.activeCameraSlotIndex, 0)
    }

    func testSelectCameraSlotChangesActiveSlot() {
        let viewModel = makeViewModel()
        viewModel.selectCameraSlot(.camera3)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)
        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Camera 3")
        XCTAssertEqual(viewModel.activeCameraSlotIndex, 2)
    }

    func testSelectNextCameraSlotAdvancesAndStopsAtLast() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)

        viewModel.selectNextCameraSlot()
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2)

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

    // MARK: - Slot page state

    func testCameraSlotPageStateMarksActiveSlot() {
        let viewModel = makeViewModel()

        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(camera1Page.cameraDisplayName, "Camera 1")
        XCTAssertTrue(camera1Page.isActive)

        let camera2Page = viewModel.cameraSlotPageState(for: .camera2)
        XCTAssertEqual(camera2Page.cameraDisplayName, "Camera 2")
        XCTAssertFalse(camera2Page.isActive)
    }

    // MARK: - Slot independence

    func testTwoSlotsKeepDifferentFilmAndNonFilmWorkflowState() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6

        viewModel.selectCameraSlot(.camera2)
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)

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

    func testReciprocityResultSurvivesSlotSwitch() throws {
        let viewModel = makeViewModel()
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

    // MARK: - Per-slot page state derivation

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
        XCTAssertEqual(active.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(active.ndStep.stops, 6, accuracy: 1e-9)
        XCTAssertEqual(active.selectedFilm?.id, film.id)
        XCTAssertTrue(active.isFilmWorkflowActive)
    }

    func testInactivePageStateReadsStoredSnapshot() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6
        viewModel.selectCameraSlot(.camera2)

        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertFalse(camera1Page.isActive)
        XCTAssertEqual(camera1Page.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(camera1Page.ndStep.stops, 6, accuracy: 1e-9)
        XCTAssertEqual(camera1Page.selectedFilm?.id, film.id)
    }

    func testCalculationResultForInactivePageUsesItsOwnInputs() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4

        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 10

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
            accuracy: 1e-9
        )
    }

    func testInactivePageDisablesBothAdjustedAndCorrectedActions() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
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

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager()
        )
    }
}
