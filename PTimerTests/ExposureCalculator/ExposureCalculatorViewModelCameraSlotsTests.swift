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

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager()
        )
    }
}
