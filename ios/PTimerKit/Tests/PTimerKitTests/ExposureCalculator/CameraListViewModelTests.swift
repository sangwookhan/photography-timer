// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Managed camera list behavior through the `ExposureCalculatorViewModel`
/// facade: list edits with per-camera calculator state, the active
/// camera and empty-pager rules, and timer identity independence.
@MainActor
final class CameraListViewModelTests: XCTestCase {

    // MARK: - Add

    func testAddedCameraBecomesActiveWithFreshCalculatorDefaults() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 250.0
        viewModel.ndStop = 9
        let fresh = makeViewModel()

        let added = try XCTUnwrap(viewModel.addCamera())

        XCTAssertEqual(viewModel.activeCameraSlotID, added)
        XCTAssertEqual(viewModel.activeCameraSlot?.displayName, "Camera 5")
        XCTAssertEqual(viewModel.baseShutter, fresh.baseShutter, accuracy: 1e-12)
        XCTAssertEqual(viewModel.ndStop, fresh.ndStop)
        XCTAssertEqual(viewModel.availableCameraSlots.last, added)
        // The camera that was active keeps its own state.
        let camera1 = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(camera1.baseShutter, 1.0 / 250.0, accuracy: 1e-12)
        XCTAssertEqual(camera1.ndStep.stops, 9, accuracy: 1e-9)
    }

    // MARK: - Rename

    func testRenameKeepsStateAndRejectsBlankNames() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4

        XCTAssertTrue(viewModel.renameCamera(.camera1, to: "  Hasselblad  "))
        XCTAssertEqual(viewModel.activeCameraSlot?.displayName, "Hasselblad")
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.ndStop, 4)

        XCTAssertFalse(viewModel.renameCamera(.camera1, to: "   "))
        XCTAssertEqual(viewModel.activeCameraSlot?.displayName, "Hasselblad")
        XCTAssertEqual(viewModel.cameraList.first?.name, "Hasselblad", "The facade list republishes the rename.")
    }

    // MARK: - Hide and show

    func testHidingTheActiveCameraLoadsTheNextCamerasOwnState() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.selectCameraSlot(.camera3)
        viewModel.baseShutter = 2.0
        viewModel.selectCameraSlot(.camera2)

        viewModel.setCameraDisplayed(false, for: .camera2)

        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)
        XCTAssertEqual(viewModel.baseShutter, 2.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.availableCameraSlots, [.camera1, .camera3, .camera4])
    }

    func testHiddenCameraKeepsItsStateWhileHiddenAndAfterShowing() {
        let viewModel = makeViewModel()
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.ndStop = 7
        viewModel.setCameraDisplayed(false, for: .camera2)

        XCTAssertEqual(viewModel.cameraSlotPageState(for: .camera2).baseShutter, 1.0 / 8.0, accuracy: 1e-12)

        viewModel.setCameraDisplayed(true, for: .camera2)
        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 8.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.ndStop, 7)
    }

    func testSelectingAHiddenCameraIsIgnored() {
        let viewModel = makeViewModel()
        viewModel.setCameraDisplayed(false, for: .camera3)
        viewModel.selectCameraSlot(.camera3)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
    }

    // MARK: - Reorder

    func testReorderChangesThePagerOrderAndKeepsEveryCamerasState() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 8.0

        viewModel.moveCamera(.camera4, by: -3)
        XCTAssertEqual(viewModel.availableCameraSlots, [.camera4, .camera1, .camera2, .camera3])
        viewModel.moveCameras(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(viewModel.availableCameraSlots, [.camera3, .camera4, .camera1, .camera2])

        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 8.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.cameraSlotPageState(for: .camera1).baseShutter, 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.activeCameraSlotIndex, 3)
    }

    // MARK: - Delete

    func testDeletingTheActiveCameraLoadsTheNextCameraAndDropsItsState() throws {
        let viewModel = makeViewModel()
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.selectCameraSlot(.camera3)
        viewModel.baseShutter = 2.0
        viewModel.selectCameraSlot(.camera2)

        viewModel.deleteCameras([.camera2])

        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)
        XCTAssertEqual(viewModel.baseShutter, 2.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1, .camera3, .camera4])

        // A new camera never inherits the deleted camera's state or identity.
        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertNotEqual(added, .camera2)
        XCTAssertEqual(viewModel.activeCameraSlot?.displayName, "Camera 5", "The automatic sequence issues 5 first, not a freed number.")
        XCTAssertEqual(viewModel.baseShutter, makeViewModel().baseShutter, accuracy: 1e-12)
    }

    func testBulkHideAndBulkDeleteApplyTogether() {
        let viewModel = makeViewModel()
        viewModel.hideCameras([.camera1, .camera2])
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)
        XCTAssertEqual(viewModel.availableCameraSlots, [.camera3, .camera4])

        viewModel.deleteCameras([.camera3, .camera4])
        XCTAssertNil(viewModel.activeCameraSlotID, "Only hidden cameras remain.")
        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1, .camera2])
        XCTAssertTrue(viewModel.availableCameraSlots.isEmpty)
    }

    // MARK: - Empty pager

    func testHidingTheLastDisplayedCameraYieldsAnEmptyPager() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4
        viewModel.hideCameras(Set(CameraSlotID.legacyOrdered))

        XCTAssertTrue(viewModel.availableCameraSlots.isEmpty)
        XCTAssertNil(viewModel.activeCameraSlotID)
        XCTAssertNil(viewModel.activeCameraSlot)
        XCTAssertEqual(viewModel.activeCameraSlotPageText, "")
        XCTAssertEqual(viewModel.cameraList.count, 4, "The managed list is not empty.")

        // Showing a camera again activates it with its preserved state.
        viewModel.setCameraDisplayed(true, for: .camera1)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.ndStop, 4)
    }

    func testEmptyPagerRefusesCalculatorBoundTimersButAllowsManualTimers() {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.hideCameras(Set(CameraSlotID.legacyOrdered))

        viewModel.startTimer()
        XCTAssertTrue(viewModel.timers.isEmpty, "A calculator-bound timer needs a displayed active camera.")

        viewModel.startTimer(from: 12.5)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertNil(viewModel.timers.first?.cameraSlot)
    }

    func testDeletingEveryCameraYieldsAnEmptyListThatAddingRecovers() throws {
        let viewModel = makeViewModel()
        viewModel.deleteCameras(Set(CameraSlotID.legacyOrdered))
        XCTAssertTrue(viewModel.cameraList.isEmpty)
        XCTAssertNil(viewModel.activeCameraSlot)

        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.activeCameraSlotID, added)
        XCTAssertEqual(viewModel.activeCameraSlot?.displayName, "Camera 5")
        viewModel.startTimer()
        XCTAssertEqual(viewModel.timers.count, 1)
    }

    func testEmptyPagerDoesNotAffectRunningTimers() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let started = try XCTUnwrap(viewModel.timers.first)

        viewModel.hideCameras(Set(CameraSlotID.legacyOrdered))

        let after = try XCTUnwrap(viewModel.timers.first { $0.id == started.id })
        XCTAssertEqual(after.cameraSlot, started.cameraSlot)
    }

    // MARK: - Timer identity

    func testTimersKeepTheCapturedCameraAfterEveryListEdit() throws {
        let viewModel = makeViewModel()
        viewModel.renameCamera(.camera2, to: "Mamiya 7")
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let captured = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(captured.cameraSlot?.displayName, "Mamiya 7")

        viewModel.renameCamera(.camera2, to: "Renamed")
        viewModel.moveCamera(.camera2, by: 2)
        viewModel.setCameraDisplayed(false, for: .camera2)
        viewModel.setCameraDisplayed(true, for: .camera2)
        viewModel.deleteCameras([.camera2])

        let after = try XCTUnwrap(viewModel.timers.first { $0.id == captured.id })
        XCTAssertEqual(after.cameraSlot?.id, .camera2)
        XCTAssertEqual(after.cameraSlot?.displayName, "Mamiya 7")
        XCTAssertEqual(after.status, captured.status, "The running timer is not interrupted.")
        XCTAssertNotNil(after.identitySnapshot, "The entry stays renderable without the camera.")
    }

    func testNewTimerAfterRenameCapturesTheNewNameWhileTheOldTimerKeepsItsName() throws {
        let viewModel = makeViewModel()
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        viewModel.renameCamera(.camera1, to: "Hasselblad")
        viewModel.startTimer()

        let names = viewModel.timers.compactMap { $0.cameraSlot?.displayName }
        XCTAssertEqual(Set(names), ["Camera 1", "Hasselblad"])
    }

    func testGeneratedCameraTimersGetABadgeFromTheCapturedName() throws {
        let viewModel = makeViewModel()
        viewModel.addCamera()
        viewModel.renameCamera(try XCTUnwrap(viewModel.activeCameraSlotID), to: "Leica M6")
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        let snapshot = try XCTUnwrap(timer.identitySnapshot)
        XCTAssertEqual(TimerCardIdentityPresenter.compactCameraLabel(for: snapshot), "L6", "First letter plus the trailing number.")
        XCTAssertEqual(TimerCardIdentityPresenter.fullCameraLabel(for: snapshot), "Leica M6")

        viewModel.renameCamera(try XCTUnwrap(viewModel.activeCameraSlotID), to: "Rolleiflex")
        viewModel.startTimer()
        let unnumbered = try XCTUnwrap(viewModel.timers.last { $0.id != timer.id }?.identitySnapshot)
        XCTAssertEqual(TimerCardIdentityPresenter.compactCameraLabel(for: unnumbered), "RO")
    }

    func testCompactBadgeCoversNumericAndLongTrailingNumberNames() throws {
        let cases: [(name: String, badge: String)] = [
            ("Leica M6", "L6"),
            ("Camera 123", "C23"),
            ("Camera 7", "C7"),
            ("35", "35"),
            ("7", "7"),
            ("2024", "24"),
            ("35mm Leica 2", "32"),
            ("Rolleiflex", "RO"),
        ]
        for (name, badge) in cases {
            let viewModel = makeViewModel()
            viewModel.addCamera()
            viewModel.renameCamera(try XCTUnwrap(viewModel.activeCameraSlotID), to: name)
            viewModel.baseShutter = 1.0
            viewModel.ndStop = 6
            viewModel.startTimer()
            let snapshot = try XCTUnwrap(viewModel.timers.first?.identitySnapshot)
            XCTAssertEqual(TimerCardIdentityPresenter.compactCameraLabel(for: snapshot), badge, name)
        }
    }

    func testEveryListEditBumpsTheRevisionThePagerReseedsFrom() throws {
        let viewModel = makeViewModel()
        var revision = viewModel.cameraListRevision
        func assertBumped(_ edit: () -> Void, _ label: String) {
            edit()
            XCTAssertGreaterThan(viewModel.cameraListRevision, revision, label)
            revision = viewModel.cameraListRevision
        }
        assertBumped({ viewModel.addCamera() }, "add")
        assertBumped({ viewModel.renameCamera(.camera1, to: "A") }, "rename")
        assertBumped({ viewModel.moveCamera(.camera1, by: 1) }, "move")
        assertBumped({ viewModel.setCameraDisplayed(false, for: .camera2) }, "hide")
        assertBumped({ viewModel.deleteCameras([.camera3]) }, "delete")
        viewModel.selectCameraSlot(.camera4)
        XCTAssertEqual(viewModel.cameraListRevision, revision, "Paging between cameras is not a list edit.")
    }

    // MARK: - Rename result

    func testRenameReportsFailureForAnUnknownCameraAndChangesNothing() {
        let viewModel = makeViewModel()
        let revision = viewModel.cameraListRevision
        let unknown = CameraSlotID(rawValue: "never-existed")!

        XCTAssertFalse(viewModel.renameCamera(unknown, to: "Leica"))
        XCTAssertEqual(viewModel.cameraList.map(\.name), ["Camera 1", "Camera 2", "Camera 3", "Camera 4"])
        XCTAssertEqual(viewModel.cameraListRevision, revision, "A failed rename is not a list edit.")
        XCTAssertFalse(viewModel.renameCamera(.camera1, to: "  "), "Blank names still fail.")
        XCTAssertTrue(viewModel.renameCamera(.camera1, to: "Leica"))
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: InMemoryCameraListSessionStore()
        )
    }
}
