import XCTest
@testable import PTimer

/// Direct unit tests for `CameraSlotSessionModel`. The session model
/// holds only the slot-switching state (active id + inactive
/// snapshots); slot-aware behavior end-to-end through the ViewModel
/// facade is covered separately by
/// `ExposureCalculatorViewModelCameraSlotsTests`.
final class CameraSlotSessionModelTests: XCTestCase {

    @MainActor
    func testDefaultStateExposesAllFourSlotsAndStartsOnCameraOne() {
        let model = CameraSlotSessionModel()

        XCTAssertEqual(model.availableSlots, CameraSlotID.allOrdered)
        XCTAssertEqual(model.activeSlotID, .camera1)
        XCTAssertEqual(model.activeSlot.displayName, "Camera 1")
    }

    @MainActor
    func testInactiveSnapshotReturnsInitialDefaultUntilSlotIsVisited() {
        let model = CameraSlotSessionModel()

        let snapshot = model.snapshot(forInactiveSlot: .camera2)

        XCTAssertEqual(snapshot, CameraSlotCalculatorSnapshot.initial)
    }

    @MainActor
    func testActiveSlotHasNoStoredSnapshotInTheInactiveMap() {
        let model = CameraSlotSessionModel()

        XCTAssertNil(model.snapshot(forInactiveSlot: .camera1))
    }

    @MainActor
    func testSwitchActiveSlotStoresOutgoingSnapshotAndReturnsIncomingDefault() {
        let model = CameraSlotSessionModel()
        let outgoing = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 1.0 / 60.0,
            ndStep: NDStep(stops: 6),
            scaleMode: .oneThirdStop,
            selectedPresetFilm: nil,
            selectedProfileOverride: nil
        )

        let incoming = model.switchActiveSlot(to: .camera2, capturing: outgoing)

        XCTAssertEqual(model.activeSlotID, .camera2)
        XCTAssertEqual(incoming, .initial)
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera1), outgoing)
        // The newly-active slot's snapshot is intentionally absent —
        // the calc/film models hold the live state for it.
        XCTAssertNil(model.snapshot(forInactiveSlot: .camera2))
    }

    @MainActor
    func testSwitchingBackRestoresStoredInactiveSnapshot() {
        let model = CameraSlotSessionModel()
        let cameraOneState = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 1.0 / 60.0,
            ndStep: NDStep(stops: 6),
            scaleMode: .oneThirdStop,
            selectedPresetFilm: nil,
            selectedProfileOverride: nil
        )
        let cameraTwoState = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 10),
            scaleMode: .fullStop,
            selectedPresetFilm: nil,
            selectedProfileOverride: nil
        )

        // Active=Camera 1, capture Camera 1 state, move to Camera 2
        _ = model.switchActiveSlot(to: .camera2, capturing: cameraOneState)
        // Active=Camera 2, capture Camera 2 state, move back to Camera 1
        let restored = model.switchActiveSlot(to: .camera1, capturing: cameraTwoState)

        XCTAssertEqual(model.activeSlotID, .camera1)
        XCTAssertEqual(restored, cameraOneState)
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera2), cameraTwoState)
    }

    @MainActor
    func testSwitchToActiveSlotIsNoOp() {
        let model = CameraSlotSessionModel()
        let snapshot = CameraSlotCalculatorSnapshot.initial

        let result = model.switchActiveSlot(to: .camera1, capturing: snapshot)

        XCTAssertNil(result)
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    @MainActor
    func testSwitchRejectsSlotsOutsideAvailableSet() {
        let model = CameraSlotSessionModel(
            availableSlots: [.camera1, .camera2],
            initialActiveSlotID: .camera1
        )

        let result = model.switchActiveSlot(to: .camera3, capturing: .initial)

        XCTAssertNil(result)
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
        // Lower bound of the invariant: a 2-slot session is the
        // smallest configuration the model accepts. Verifies the
        // precondition does not also reject the minimum.
        let model = CameraSlotSessionModel(
            availableSlots: [.camera1, .camera2],
            initialActiveSlotID: .camera1
        )
        XCTAssertEqual(model.availableSlots, [.camera1, .camera2])
    }

    @MainActor
    func testFourUniqueSlotConfigurationIsAccepted() {
        // Upper bound of the invariant: all four shipping slots,
        // unique. Sanity-checks that the precondition tightening did
        // not break the shipping configuration.
        let model = CameraSlotSessionModel()
        XCTAssertEqual(model.availableSlots.count, 4)
        XCTAssertEqual(Set(model.availableSlots).count, 4)
    }

    // Note: precondition() failures terminate the process and cannot
    // be reasonably caught from XCTest in-process. The invariant
    // doc-tests above stand in for the rejection cases (duplicate
    // slots / fewer than 2 / more than 4); those rejections trigger
    // a fatal precondition at runtime which is the intended
    // behavior.

    // MARK: - Restore helpers

    @MainActor
    func testRestoreActiveSlotMovesActiveAndDropsStaleInactiveEntry() {
        let model = CameraSlotSessionModel()
        let staleCamera2Snapshot = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 1.0 / 60.0,
            ndStep: NDStep(stops: 4),
            scaleMode: .oneThirdStop,
            selectedPresetFilm: nil,
            selectedProfileOverride: nil
        )
        // Seed Camera 2 as inactive with a stale snapshot.
        _ = model.switchActiveSlot(to: .camera2, capturing: .initial)
        _ = model.switchActiveSlot(to: .camera1, capturing: staleCamera2Snapshot)
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera2), staleCamera2Snapshot)

        // restoreActiveSlot is the launch-time restore path: setting
        // Camera 2 active means the live calc/film models now own
        // Camera 2's state, so any stale snapshot for Camera 2 in
        // the inactive map must be dropped.
        model.restoreActiveSlot(to: .camera2)

        XCTAssertEqual(model.activeSlotID, .camera2)
        XCTAssertNil(model.snapshot(forInactiveSlot: .camera2))
    }

    @MainActor
    func testRestoreInactiveSnapshotsLoadsBulkAndDropsActiveEntry() {
        let model = CameraSlotSessionModel(initialActiveSlotID: .camera2)
        let camera1Snapshot = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 6),
            scaleMode: .oneThirdStop,
            selectedPresetFilm: nil,
            selectedProfileOverride: nil
        )
        let camera3Snapshot = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 1.0,
            ndStep: NDStep(stops: 0),
            scaleMode: .oneThirdStop,
            selectedPresetFilm: nil,
            selectedProfileOverride: nil
        )
        // Active slot's entry must be dropped — its state is on the
        // live calc/film models, not in the inactive map.
        let activeShouldBeFiltered = CameraSlotCalculatorSnapshot.initial

        model.restoreInactiveSnapshots([
            .camera1: camera1Snapshot,
            .camera2: activeShouldBeFiltered,
            .camera3: camera3Snapshot
        ])

        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera1), camera1Snapshot)
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera3), camera3Snapshot)
        // Active slot returns nil — bulk-load did not store it.
        XCTAssertNil(model.snapshot(forInactiveSlot: .camera2))
    }
}
