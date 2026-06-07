import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

@MainActor
final class CalculatorViewModelCameraSlotRenameTests: XCTestCase {
    /// Renaming a slot should change its identity surface (active
    /// title and per-slot page state) without touching the rest of
    /// the slot's calculator state. This is the acceptance test the
    /// product spec calls out: rename is a label change, nothing
    /// else.
    func testRenameUpdatesActiveTitleAndPreservesCalculatorState() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 6

        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Hasselblad 500CM")
        XCTAssertEqual(viewModel.activeCameraSlot.id, .camera1)
        XCTAssertEqual(viewModel.cameraSlotPageState(for: .camera1).cameraDisplayName, "Hasselblad 500CM")

        // The renamed slot's calc state is untouched.
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 6)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)
    }

    func testRenamingOneSlotDoesNotAffectAnotherSlotsLabelOrState() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 10

        viewModel.setCameraSlotCustomName("Mamiya 7", for: .camera2)

        // Camera 2 (active) is renamed.
        XCTAssertEqual(viewModel.cameraSlotPageState(for: .camera2).cameraDisplayName, "Mamiya 7")
        // Camera 1 (inactive) keeps its default label and its
        // parked calculator inputs.
        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(camera1Page.cameraDisplayName, "Camera 1")
        XCTAssertEqual(camera1Page.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(camera1Page.ndStep.stops, 4, accuracy: 1e-9)
    }

    func testRenameSurvivesSlotSwitch() {
        let viewModel = makeViewModel()

        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)
        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: .camera1).displayName, "Hasselblad 500CM")
        viewModel.selectCameraSlot(.camera1)

        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Hasselblad 500CM")
    }

    func testResetRestoresDefaultSlotLabel() {
        let viewModel = makeViewModel()
        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)
        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Hasselblad 500CM")

        viewModel.resetCameraSlotCustomName(.camera1)

        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Camera 1")
        XCTAssertNil(viewModel.activeCameraSlot.customDisplayName)
    }

    func testRenameWithWhitespaceOnlyClearsCustomName() {
        let viewModel = makeViewModel()
        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        viewModel.setCameraSlotCustomName("   ", for: .camera1)

        XCTAssertEqual(viewModel.activeCameraSlot.displayName, "Camera 1")
        XCTAssertNil(viewModel.activeCameraSlot.customDisplayName)
    }

    func testRenamingDoesNotChangeCameraSlotIDRawValues() {
        let viewModel = makeViewModel()
        // Sanity: stable id raw values must never shift through a
        // rename — they are persisted identifiers consumed by
        // timer metadata and the slot session schema.
        let originalOrdering = viewModel.availableCameraSlots.map(\.rawValue)

        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)
        viewModel.setCameraSlotCustomName("Mamiya 7", for: .camera3)

        XCTAssertEqual(viewModel.availableCameraSlots.map(\.rawValue), originalOrdering)
        XCTAssertEqual(viewModel.activeCameraSlot.id.rawValue, "camera1")
    }

    /// Existing started timers must keep their captured slot label
    /// even after a later rename. The identity snapshot is frozen
    /// at start time and lives on the timer's metadata, separate
    /// from the live session model.
    func testStartedTimerSlotLabelIsImmutableAfterRename() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let captured = try XCTUnwrap(viewModel.timers.first)

        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        let after = try XCTUnwrap(viewModel.timers.first { $0.id == captured.id })
        XCTAssertEqual(after.cameraSlot?.id, .camera1)
        XCTAssertEqual(
            after.cameraSlot?.displayName,
            "Camera 1",
            "Renaming the slot must not retroactively rewrite a previously-started timer's identity snapshot."
        )
    }

    /// A timer started after a rename must stamp the renamed
    /// label, since identity capture happens at start time.
    func testNewTimerAfterRenameUsesUpdatedLabel() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.cameraSlot?.id, .camera1)
        XCTAssertEqual(timer.cameraSlot?.displayName, "Hasselblad 500CM")
    }

    /// Renaming must publish a change so SwiftUI views observing
    /// the ViewModel facade redraw without forcing a slot switch.
    /// The mirrored `cameraSlotCustomDisplayNames` is the contract
    /// SwiftUI binds to.
    func testRenamePublishesCustomDisplayNamesOnFacade() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.cameraSlotCustomDisplayNames[.camera1])

        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        XCTAssertEqual(
            viewModel.cameraSlotCustomDisplayNames[.camera1],
            "Hasselblad 500CM"
        )
    }

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            contextPersistenceStore: NoOpCalculatorContextStore()
        )
    }
}
