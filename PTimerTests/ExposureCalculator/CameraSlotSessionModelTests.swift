import XCTest
@testable import PTimer

/// Direct unit tests for `CameraSlotSessionModel`. The session model
/// holds only the active-slot id in this iteration — per-slot
/// snapshot capture/load lands in a follow-up commit and adds further
/// cases to this test class.
final class CameraSlotSessionModelTests: XCTestCase {

    @MainActor
    func testDefaultStateExposesAllFourSlotsAndStartsOnCameraOne() {
        let model = CameraSlotSessionModel()

        XCTAssertEqual(model.availableSlots, CameraSlotID.allOrdered)
        XCTAssertEqual(model.activeSlotID, .camera1)
        XCTAssertEqual(model.activeSlot.displayName, "Camera 1")
    }

    @MainActor
    func testSetActiveSlotChangesActiveID() {
        let model = CameraSlotSessionModel()

        model.setActiveSlot(.camera3)
        XCTAssertEqual(model.activeSlotID, .camera3)
    }

    @MainActor
    func testSetActiveSlotIsNoOpForActiveSlot() {
        let model = CameraSlotSessionModel()

        model.setActiveSlot(.camera1)
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    @MainActor
    func testSetActiveSlotRejectsSlotsOutsideAvailableSet() {
        let model = CameraSlotSessionModel(
            availableSlots: [.camera1, .camera2],
            initialActiveSlotID: .camera1
        )

        model.setActiveSlot(.camera3)
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    @MainActor
    func testIdentityProviderResolvesDisplayName() {
        let model = CameraSlotSessionModel(
            identityProvider: { CameraSlotIdentity(id: $0, displayName: "Cam \($0.rawValue)") }
        )

        XCTAssertEqual(model.identity(for: .camera2).displayName, "Cam camera2")
        XCTAssertEqual(model.activeSlot.displayName, "Cam camera1")
    }

    // MARK: - Invariants

    @MainActor
    func testTwoSlotConfigurationIsAccepted() {
        let model = CameraSlotSessionModel(
            availableSlots: [.camera1, .camera2],
            initialActiveSlotID: .camera1
        )
        XCTAssertEqual(model.availableSlots, [.camera1, .camera2])
    }

    @MainActor
    func testFourUniqueSlotConfigurationIsAccepted() {
        let model = CameraSlotSessionModel()
        XCTAssertEqual(model.availableSlots.count, 4)
        XCTAssertEqual(Set(model.availableSlots).count, 4)
    }

    // Note: precondition() failures terminate the process and cannot
    // be reasonably caught from XCTest in-process. The two
    // invariant doc-tests above stand in for the rejection cases
    // (duplicate slots / fewer than 2 / more than 4); those
    // rejections trigger a fatal precondition at runtime which is
    // the intended behavior.
}
