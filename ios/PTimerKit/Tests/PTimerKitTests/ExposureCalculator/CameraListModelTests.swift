// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Managed camera list rules at the session-model level
/// (CAMERA-001 through CAMERA-007, CAMERA-ORDER, CAMERA-PAGER-003).
@MainActor
final class CameraListModelTests: XCTestCase {

    // MARK: - Seed

    func testDefaultListIsTheFourSeededCamerasShownInOrderWithCameraOneActive() {
        let model = CameraSlotSessionModel()
        XCTAssertEqual(model.cameras.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(model.cameras.map(\.name), ["Camera 1", "Camera 2", "Camera 3", "Camera 4"])
        XCTAssertTrue(model.cameras.allSatisfy(\.isDisplayed))
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    // MARK: - Add

    func testAddAppendsAShownActiveCameraWithTheGivenName() {
        let model = CameraSlotSessionModel()
        let added = model.addCamera(named: "Camera 5")
        XCTAssertEqual(model.cameras.last?.id, added)
        XCTAssertEqual(model.cameras.last?.name, "Camera 5")
        XCTAssertEqual(model.cameras.last?.isDisplayed, true)
        XCTAssertEqual(model.activeSlotID, added)
    }

    func testAddNeverReusesAFreedIdentity() {
        let model = CameraSlotSessionModel()
        model.deleteCameras([.camera2])
        let added = model.addCamera(named: "Camera 5")
        XCTAssertNotEqual(added, .camera2, "The deleted camera's identity is never reissued.")
        XCTAssertTrue(model.issuedIDs.contains(.camera2))
    }

    func testAddRedrawsWhenAGeneratedIdentityWasAlreadyIssued() {
        var draws: [CameraSlotID] = [.camera2, .camera3, CameraSlotID(rawValue: "fresh")!]
        let model = CameraSlotSessionModel(generateID: { draws.removeFirst() })
        model.deleteCameras([.camera2])
        XCTAssertEqual(model.addCamera(named: "Camera 5").rawValue, "fresh")
    }

    func testTheModelNeverDerivesAnAddedCamerasNameFromTheList() {
        let model = CameraSlotSessionModel()
        let added = model.addCamera(named: "Camera 1")
        XCTAssertEqual(model.entry(for: added)?.name, "Camera 1", "The name is whatever the sequence issued.")
    }

    func testThereIsNoNumericLimitOnTheList() {
        let model = CameraSlotSessionModel()
        for number in 5..<45 { model.addCamera(named: "Camera \(number)") }
        XCTAssertEqual(model.cameras.count, 44)
        XCTAssertEqual(Set(model.cameras.map(\.id)).count, 44)
    }

    // MARK: - Rename

    func testRenameTrimsAndRejectsBlankNames() {
        let model = CameraSlotSessionModel()
        XCTAssertTrue(model.renameCamera(.camera1, to: "  Hasselblad \n"))
        XCTAssertEqual(model.entry(for: .camera1)?.name, "Hasselblad")
        XCTAssertFalse(model.renameCamera(.camera1, to: ""))
        XCTAssertFalse(model.renameCamera(.camera1, to: "   "))
        XCTAssertEqual(model.entry(for: .camera1)?.name, "Hasselblad")
    }

    func testDuplicateAndHistoricalNamesAreAllowedAndKeepDistinctIdentities() {
        let model = CameraSlotSessionModel()
        XCTAssertTrue(model.renameCamera(.camera1, to: "Leica"))
        XCTAssertTrue(model.renameCamera(.camera2, to: "Leica"))
        XCTAssertEqual(model.cameras.filter { $0.name == "Leica" }.map(\.id), [.camera1, .camera2])
        XCTAssertTrue(model.renameCamera(.camera1, to: "Camera 1"), "A former name can be reused.")
    }

    func testRenameDoesNotTouchInactiveCalculatorState() {
        let model = CameraSlotSessionModel()
        let stored = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 2, ndStep: NDStep(stops: 5), scaleMode: .oneThirdStop,
            selectedPresetFilm: nil, selectedProfileOverride: nil
        )
        model.storeSnapshot(stored, for: .camera2)
        model.renameCamera(.camera2, to: "Mamiya")
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera2), stored)
    }

    // MARK: - Hide and show

    func testHidingPreservesNamePositionAndStateAndShowingRestoresThePosition() {
        let model = CameraSlotSessionModel()
        let stored = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 4, ndStep: NDStep(stops: 3), scaleMode: .oneThirdStop,
            selectedPresetFilm: nil, selectedProfileOverride: nil
        )
        model.storeSnapshot(stored, for: .camera3)
        model.renameCamera(.camera3, to: "Pentax")

        model.setDisplayed(false, for: .camera3)
        XCTAssertEqual(model.cameras.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(model.displayedSlotIDs, [.camera1, .camera2, .camera4])
        XCTAssertEqual(model.entry(for: .camera3)?.name, "Pentax")
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera3), stored)

        model.setDisplayed(true, for: .camera3)
        XCTAssertEqual(model.displayedSlotIDs, [.camera1, .camera2, .camera3, .camera4])
    }

    func testHidingTheActiveCameraActivatesTheNextDisplayedCamera() {
        let model = CameraSlotSessionModel(activeSlotID: .camera2)
        model.setDisplayed(false, for: .camera2)
        XCTAssertEqual(model.activeSlotID, .camera3)
    }

    func testHidingTheActiveLastCameraActivatesTheFirstDisplayedCamera() {
        let model = CameraSlotSessionModel(activeSlotID: .camera4)
        model.setDisplayed(false, for: .camera4)
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    func testHidingAnInactiveCameraKeepsTheActiveCamera() {
        let model = CameraSlotSessionModel(activeSlotID: .camera2)
        model.setDisplayed(false, for: .camera3)
        XCTAssertEqual(model.activeSlotID, .camera2)
    }

    func testHidingTheLastDisplayedCameraLeavesNoActiveCamera() {
        let model = CameraSlotSessionModel()
        model.hideCameras([.camera1, .camera2, .camera3, .camera4])
        XCTAssertNil(model.activeSlotID)
        XCTAssertTrue(model.displayedSlotIDs.isEmpty)
        XCTAssertEqual(model.cameras.count, 4, "Hidden cameras stay in the list.")
    }

    func testShowingACameraWhileNoneIsActiveActivatesIt() {
        let model = CameraSlotSessionModel()
        model.hideCameras(Set(CameraSlotID.legacyOrdered))
        model.setDisplayed(true, for: .camera3)
        XCTAssertEqual(model.activeSlotID, .camera3)
    }

    func testShowingACameraKeepsAnExistingActiveCamera() {
        let model = CameraSlotSessionModel(activeSlotID: .camera1)
        model.setDisplayed(false, for: .camera3)
        model.setDisplayed(true, for: .camera3)
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    // MARK: - Delete

    func testDeleteRemovesTheEntryAndItsCalculatorState() {
        let model = CameraSlotSessionModel()
        model.storeSnapshot(.initial, for: .camera3)
        model.deleteCameras([.camera3])
        XCTAssertNil(model.entry(for: .camera3))
        XCTAssertNil(model.snapshot(forInactiveSlot: .camera3))
        XCTAssertNil(model.currentInactiveSnapshots()[.camera3])
        XCTAssertTrue(model.issuedIDs.contains(.camera3))
    }

    func testDeletingTheActiveCameraActivatesTheNextDisplayedCameraInTheResultingList() {
        let model = CameraSlotSessionModel(activeSlotID: .camera2)
        model.deleteCameras([.camera2])
        XCTAssertEqual(model.activeSlotID, .camera3)
        XCTAssertEqual(model.cameras.map(\.id), [.camera1, .camera3, .camera4])
    }

    func testDeletingTheActiveLastCameraActivatesTheFirstDisplayedCamera() {
        let model = CameraSlotSessionModel(activeSlotID: .camera4)
        model.deleteCameras([.camera4])
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    func testBulkNextActiveIsComputedAgainstTheResultingList() {
        // Active camera2 is removed together with the camera right after
        // it and a hidden camera; the next survivor is camera4.
        let model = CameraSlotSessionModel(activeSlotID: .camera2)
        model.setDisplayed(false, for: .camera4)
        model.setDisplayed(true, for: .camera4)
        model.deleteCameras([.camera2, .camera3])
        XCTAssertEqual(model.activeSlotID, .camera4)
    }

    func testBulkHideSkipsHiddenAndRemovedCamerasWhenPickingTheNextActiveCamera() {
        let model = CameraSlotSessionModel(activeSlotID: .camera2)
        model.hideCameras([.camera2, .camera3])
        XCTAssertEqual(model.activeSlotID, .camera4)
        model.hideCameras([.camera4])
        XCTAssertEqual(model.activeSlotID, .camera1, "No later displayed camera: the first displayed one.")
    }

    func testDeletingEveryCameraLeavesAnEmptyListAndNoActiveCamera() {
        let model = CameraSlotSessionModel()
        model.deleteCameras(Set(CameraSlotID.legacyOrdered))
        XCTAssertTrue(model.cameras.isEmpty)
        XCTAssertNil(model.activeSlotID)
    }

    func testBulkActionsIgnoreIdentitiesThatNoLongerExist() {
        let model = CameraSlotSessionModel()
        let gone = CameraSlotID(rawValue: "never-existed")!
        model.deleteCameras([.camera4, gone])
        model.hideCameras([.camera3, gone])
        XCTAssertEqual(model.cameras.map(\.id), [.camera1, .camera2, .camera3])
        XCTAssertEqual(model.displayedSlotIDs, [.camera1, .camera2])
    }

    // MARK: - Order

    func testMoveCamerasReordersTheGlobalListWithoutChangingState() {
        let model = CameraSlotSessionModel()
        model.moveCameras(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(model.cameras.map(\.id), [.camera4, .camera1, .camera2, .camera3])
        model.moveCameras(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(model.cameras.map(\.id), [.camera1, .camera2, .camera3, .camera4])
    }

    func testMoveByOnePositionIsClampedAtTheEnds() {
        let model = CameraSlotSessionModel()
        model.moveCamera(.camera2, by: -1)
        XCTAssertEqual(model.cameras.map(\.id), [.camera2, .camera1, .camera3, .camera4])
        model.moveCamera(.camera2, by: -1)
        XCTAssertEqual(model.cameras.map(\.id), [.camera2, .camera1, .camera3, .camera4])
        model.moveCamera(.camera2, by: 3)
        XCTAssertEqual(model.cameras.map(\.id), [.camera1, .camera3, .camera4, .camera2])
    }

    func testHidingKeepsTheGlobalOrderAndThePagerFollowsIt() {
        let model = CameraSlotSessionModel()
        model.moveCamera(.camera4, by: -3)
        model.setDisplayed(false, for: .camera2)
        XCTAssertEqual(model.cameras.map(\.id), [.camera4, .camera1, .camera2, .camera3])
        XCTAssertEqual(model.displayedSlotIDs, [.camera4, .camera1, .camera3])
    }

    func testReorderingKeepsTheActiveCameraAndItsState() {
        let model = CameraSlotSessionModel(activeSlotID: .camera3)
        model.moveCamera(.camera3, by: -2)
        XCTAssertEqual(model.activeSlotID, .camera3)
    }

    // MARK: - Switching and snapshots

    func testSwitchStoresTheOutgoingSnapshotAndReturnsTheIncomingOne() {
        let model = CameraSlotSessionModel()
        let outgoing = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 8, ndStep: NDStep(stops: 4), scaleMode: .oneThirdStop,
            selectedPresetFilm: nil, selectedProfileOverride: nil
        )
        XCTAssertEqual(model.switchActiveSlot(to: .camera2, capturing: outgoing), .initial)
        XCTAssertEqual(model.activeSlotID, .camera2)
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera1), outgoing)
        XCTAssertNil(model.snapshot(forInactiveSlot: .camera2), "The active camera has no stored snapshot.")
        XCTAssertEqual(model.switchActiveSlot(to: .camera1, capturing: .initial), outgoing)
    }

    func testSwitchToTheActiveHiddenOrUnknownCameraIsRejected() {
        let model = CameraSlotSessionModel()
        model.setDisplayed(false, for: .camera3)
        XCTAssertNil(model.switchActiveSlot(to: .camera1, capturing: .initial))
        XCTAssertNil(model.switchActiveSlot(to: .camera3, capturing: .initial))
        XCTAssertNil(model.switchActiveSlot(to: CameraSlotID(rawValue: "x")!, capturing: .initial))
        XCTAssertEqual(model.activeSlotID, .camera1)
    }

    // MARK: - Restore

    func testRestoreReplacesTheWholeSessionAndDropsStaleReferences() {
        let model = CameraSlotSessionModel()
        let custom = CameraSlotID(rawValue: "camera-custom")!
        let stored = CameraSlotCalculatorSnapshot(
            baseShutterSeconds: 2, ndStep: NDStep(stops: 5), scaleMode: .oneThirdStop,
            selectedPresetFilm: nil, selectedProfileOverride: nil
        )
        model.restore(
            cameras: [
                CameraListEntry(id: custom, name: "Field", isDisplayed: true),
                CameraListEntry(id: .camera2, name: "Camera 2", isDisplayed: false),
            ],
            activeSlotID: .camera2,
            issuedIDs: [.camera3],
            snapshots: [custom: stored, .camera2: stored, .camera4: stored]
        )
        XCTAssertEqual(model.cameras.map(\.id), [custom, .camera2])
        XCTAssertEqual(model.activeSlotID, custom, "A hidden or stale active id falls to the first displayed camera.")
        XCTAssertNil(model.snapshot(forInactiveSlot: .camera4))
        XCTAssertEqual(model.snapshot(forInactiveSlot: .camera2), stored)
        XCTAssertTrue(model.issuedIDs.isSuperset(of: [.camera3, custom, .camera2]))
    }

    func testRestoreWithNothingDisplayedHasNoActiveCamera() {
        let model = CameraSlotSessionModel()
        model.restore(
            cameras: [CameraListEntry(id: .camera1, name: "Camera 1", isDisplayed: false)],
            activeSlotID: .camera1, issuedIDs: [], snapshots: [:]
        )
        XCTAssertNil(model.activeSlotID)
    }
}
