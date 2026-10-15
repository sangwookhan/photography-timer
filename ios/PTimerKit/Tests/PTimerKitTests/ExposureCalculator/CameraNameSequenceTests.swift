// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// The durable automatic `Camera N` sequence (CAMERA-003, CAMERA-NAME-004,
/// CAMERA-PERSIST-001/002/007, PERSIST-CAMERA-SEQUENCE-001..003).
@MainActor
final class CameraNameSequenceTests: XCTestCase {

    // MARK: - Monotonic numbering

    func testTheFirstAddedCameraIsCameraFiveAndNumbersOnlyIncrease() throws {
        let viewModel = makeViewModel().viewModel
        let first = try XCTUnwrap(viewModel.addCamera())
        let second = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: first)?.displayName, "Camera 5")
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: second)?.displayName, "Camera 6")
    }

    func testRenameHideAndDeleteNeverReleaseANumber() throws {
        let viewModel = makeViewModel().viewModel
        let first = try XCTUnwrap(viewModel.addCamera())
        viewModel.renameCamera(first, to: "Leica")
        viewModel.setCameraDisplayed(false, for: first)
        viewModel.deleteCameras([first])
        viewModel.deleteCameras([.camera1])
        let next = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: next)?.displayName, "Camera 6")
    }

    func testEnteringACameraNNameByHandNeitherReleasesNorAdvancesTheSequence() throws {
        let viewModel = makeViewModel().viewModel
        viewModel.renameCamera(.camera1, to: "Camera 9")
        viewModel.renameCamera(.camera2, to: "Camera 5")
        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5", "Duplicates stay allowed.")
        let next = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: next)?.displayName, "Camera 6")
    }

    func testTheSequenceIsNeverReconstructedFromTheCamerasNamesOrCount() throws {
        let launch = makeViewModel()
        for _ in 0..<3 { launch.viewModel.addCamera() }
        launch.viewModel.deleteCameras(Set(launch.viewModel.cameraList.map(\.id)))
        XCTAssertTrue(launch.viewModel.cameraList.isEmpty)
        let relaunched = makeViewModel(stores: launch.stores).viewModel
        let added = try XCTUnwrap(relaunched.addCamera())
        XCTAssertEqual(relaunched.cameraSlotIdentity(for: added)?.displayName, "Camera 8")
    }

    func testTheSequenceSurvivesRelaunch() throws {
        let launch = makeViewModel()
        launch.viewModel.addCamera()
        let relaunched = makeViewModel(stores: launch.stores).viewModel
        let added = try XCTUnwrap(relaunched.addCamera())
        XCTAssertEqual(relaunched.cameraSlotIdentity(for: added)?.displayName, "Camera 6")
    }

    // MARK: - Write order and gaps

    func testFreshInstallWritesTheSequenceBeforeTheManagedList() {
        let events = EventLog()
        let stores = Stores(session: RecordingSessionStore(events), sequence: RecordingSequenceStore(events))
        let viewModel = makeViewModel(stores: stores).viewModel
        viewModel.renameCamera(.camera1, to: "First edit")
        let sequenceIndex = events.items.firstIndex(of: "sequence=5")
        let managedIndex = events.items.firstIndex(of: "managed")
        XCTAssertNotNil(sequenceIndex)
        XCTAssertNotNil(managedIndex)
        if let sequenceIndex, let managedIndex {
            XCTAssertLessThan(sequenceIndex, managedIndex, "Sequence value 5 is durable before the first payload.")
        }
        XCTAssertEqual(events.items.filter { $0 == "sequence=5" }.count, 1)
    }

    func testReservationIsDurableBeforeTheCameraIsCommitted() throws {
        let events = EventLog()
        let stores = Stores(session: RecordingSessionStore(events), sequence: RecordingSequenceStore(events))
        let viewModel = makeViewModel(stores: stores).viewModel
        events.items.removeAll()

        try XCTUnwrap(viewModel.addCamera())

        let reserved = events.items.firstIndex(of: "sequence=6")
        let committed = events.items.firstIndex(of: "managed")
        XCTAssertNotNil(reserved)
        XCTAssertNotNil(committed)
        if let reserved, let committed {
            XCTAssertLessThan(reserved, committed)
        }
    }

    func testACreationThatNeverCommitsLeavesAGapNotAReuse() throws {
        let sequence = InMemoryCameraNameSequenceStore()
        let lossy = LossySessionStore()
        let first = makeViewModel(stores: Stores(session: lossy, sequence: sequence)).viewModel
        let lost = try XCTUnwrap(first.addCamera())
        XCTAssertEqual(first.cameraSlotIdentity(for: lost)?.displayName, "Camera 5")
        XCTAssertEqual(sequence.result, .value(6), "The number was reserved before the commit was lost.")

        let relaunched = makeViewModel(stores: Stores(session: lossy, sequence: sequence)).viewModel
        XCTAssertNil(relaunched.cameraSlotIdentity(for: lost), "The camera record was never committed.")
        let added = try XCTUnwrap(relaunched.addCamera())
        XCTAssertEqual(relaunched.cameraSlotIdentity(for: added)?.displayName, "Camera 6")
    }

    func testAFailedReservationCreatesNoCamera() {
        let sequence = InMemoryCameraNameSequenceStore()
        let viewModel = makeViewModel(stores: Stores(sequence: sequence)).viewModel
        _ = viewModel.addCamera()
        sequence.failsWrites = true
        let before = viewModel.cameraList.count

        XCTAssertNil(viewModel.addCamera())

        XCTAssertEqual(viewModel.cameraList.count, before)
        sequence.failsWrites = false
        XCTAssertNotNil(viewModel.addCamera())
    }

    // MARK: - Migration

    func testMigrationWritesSequenceFiveFirstAndIgnoresCurrentNames() throws {
        let events = EventLog()
        let session = RecordingSessionStore(events)
        session.legacy = legacySnapshot(renaming: "Camera 9")
        let stores = Stores(session: session, sequence: RecordingSequenceStore(events))

        let viewModel = makeViewModel(stores: stores).viewModel

        XCTAssertEqual(viewModel.cameraList.first?.name, "Camera 9")
        let sequenceIndex = try XCTUnwrap(events.items.firstIndex(of: "sequence=5"))
        let managedIndex = try XCTUnwrap(events.items.firstIndex(of: "managed"))
        XCTAssertLessThan(sequenceIndex, managedIndex)
        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5", "Not derived from the highest existing N.")
    }

    func testARetriedMigrationNeverLowersAnExistingSequenceValue() throws {
        let session = InMemoryCameraListSessionStore()
        session.legacy = legacySnapshot(renaming: nil)
        let sequence = InMemoryCameraNameSequenceStore(.value(8))

        let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel

        XCTAssertEqual(sequence.result, .value(8))
        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 8")
    }

    // MARK: - Interrupted installation and migration (CAMERA-PERSIST-001/002)

    func testAKillBetweenTheFreshInstallSequenceAndListWritesRebuildsTheSeed() throws {
        let sequence = InMemoryCameraNameSequenceStore()
        let lossy = LossySessionStore()
        let first = makeViewModel(stores: Stores(session: lossy, sequence: sequence)).viewModel
        first.renameCamera(.camera1, to: "First edit")
        XCTAssertEqual(sequence.result, .value(5), "The sequence was written before the (lost) list payload.")

        let relaunched = makeViewModel(stores: Stores(session: lossy, sequence: sequence)).viewModel

        XCTAssertEqual(relaunched.cameraList.map(\.name), ["Camera 1", "Camera 2", "Camera 3", "Camera 4"], "The seed is rebuilt.")
        let added = try XCTUnwrap(relaunched.addCamera())
        XCTAssertEqual(relaunched.cameraSlotIdentity(for: added)?.displayName, "Camera 5")
        XCTAssertEqual(sequence.result, .value(6))
    }

    func testRetryingAPartialMigrationKeepsAHigherExistingSequenceValue() throws {
        let sequence = InMemoryCameraNameSequenceStore()
        let lossy = LossySessionStore(legacy: legacySnapshot(renaming: "Field"))
        let first = makeViewModel(stores: Stores(session: lossy, sequence: sequence)).viewModel
        XCTAssertEqual(first.cameraList.first?.name, "Field")
        XCTAssertNotNil(first.addCamera(), "Reserves number 5; the managed payload never reaches disk.")
        XCTAssertEqual(sequence.result, .value(6))

        let retried = makeViewModel(stores: Stores(session: lossy, sequence: sequence)).viewModel

        XCTAssertEqual(sequence.result, .value(6), "The retry never lowers the sequence back to 5.")
        XCTAssertEqual(retried.cameraList.first?.name, "Field", "The legacy source is still usable and migrates again.")
        let added = try XCTUnwrap(retried.addCamera())
        XCTAssertEqual(retried.cameraSlotIdentity(for: added)?.displayName, "Camera 6")
    }

    func testAFreshInstallOverAnExistingValidSequenceStoreKeepsItsValue() throws {
        let sequence = InMemoryCameraNameSequenceStore(.value(12))
        let viewModel = makeViewModel(stores: Stores(sequence: sequence)).viewModel
        viewModel.renameCamera(.camera1, to: "Edit")

        XCTAssertEqual(sequence.result, .value(12), "Seeding never replaces a valid stored value.")
        XCTAssertEqual(sequence.saveCount, 0)
        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 12")
    }

    // MARK: - Missing or unreadable sequence (CAMERA-PERSIST-007)

    func testAMissingSequenceUsesTheNormalAllocatorAtFiveAndPersistsSixFirst() throws {
        let events = EventLog()
        let session = RecordingSessionStore(events)
        session.managed = .loaded(try seededPayload(renaming: "Nikon Z7"))
        let sequence = RecordingSequenceStore(events)
        let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel
        events.items.removeAll()

        let added = try XCTUnwrap(viewModel.addCamera())

        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5")
        let reserved = try XCTUnwrap(events.items.firstIndex(of: "sequence=6"))
        let committed = try XCTUnwrap(events.items.firstIndex(of: "managed"))
        XCTAssertLessThan(reserved, committed, "6 is durable before Camera 5 is committed.")
        let next = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: next)?.displayName, "Camera 6", "Allocation then continues normally.")
        XCTAssertEqual(viewModel.cameraList.first?.name, "Nikon Z7", "Existing cameras are untouched.")
    }

    func testAnUnreadableSequenceFallsBackTheSameWay() throws {
        let session = InMemoryCameraListSessionStore()
        session.managed = .loaded(try seededPayload(renaming: "A"))
        let sequence = InMemoryCameraNameSequenceStore(.unusable)
        let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel

        let added = try XCTUnwrap(viewModel.addCamera())

        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5")
        XCTAssertEqual(sequence.result, .value(6))
    }

    func testStoredValuesBelowFiveOrAtTheIntegerLimitAreTreatedAsUnusable() throws {
        for stored in [1, 4, Int.max] {
            let session = InMemoryCameraListSessionStore()
            session.managed = .loaded(try seededPayload(renaming: "A"))
            let sequence = InMemoryCameraNameSequenceStore(.value(stored))
            let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel

            let added = try XCTUnwrap(viewModel.addCamera(), "Stored \(stored) allocates from 5.")

            XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5")
            XCTAssertEqual(sequence.result, .value(6))
        }
    }

    func testTheLargestAdvanceableValueStillAllocates() throws {
        let session = InMemoryCameraListSessionStore()
        session.managed = .loaded(try seededPayload(renaming: "A"))
        let sequence = InMemoryCameraNameSequenceStore(.value(Int.max - 1))
        let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel

        let added = try XCTUnwrap(viewModel.addCamera())

        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, CameraNaming.defaultName(number: Int.max - 1))
        XCTAssertEqual(sequence.result, .value(Int.max))
    }

    func testTheFallbackMayRepeatADisplayNumberButNeverACameraIdentity() throws {
        let session = InMemoryCameraListSessionStore()
        session.managed = .loaded(try seededPayload(renaming: "Camera 5"))
        let viewModel = makeViewModel(stores: Stores(session: session, sequence: InMemoryCameraNameSequenceStore(.absent))).viewModel
        let before = Set(viewModel.cameraList.map(\.id))

        let added = try XCTUnwrap(viewModel.addCamera())

        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5")
        XCTAssertEqual(viewModel.cameraList.filter { $0.name == "Camera 5" }.count, 2)
        XCTAssertFalse(before.contains(added))
    }

    func testAnUnreadableSequenceOnAFirstLaunchStillMigratesAndInitializesFive() throws {
        let session = InMemoryCameraListSessionStore()
        session.legacy = legacySnapshot(renaming: "Field")
        let sequence = InMemoryCameraNameSequenceStore(.unusable)

        let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel
        viewModel.renameCamera(.camera2, to: "Second")

        XCTAssertEqual(viewModel.cameraList.first?.name, "Field")
        XCTAssertEqual(sequence.result, .value(5), "Migration initializes the next number at 5.")
        XCTAssertNotNil(session.persistedManaged)
    }

    func testAnEditingFailureForTheSequenceNeverBlocksExistingCameras() throws {
        let session = InMemoryCameraListSessionStore()
        session.managed = .loaded(try seededPayload(renaming: "Kept"))
        let sequence = InMemoryCameraNameSequenceStore(.absent)
        sequence.failsWrites = true
        let viewModel = makeViewModel(stores: Stores(session: session, sequence: sequence)).viewModel

        XCTAssertNil(viewModel.addCamera(), "The reservation could not be written, so no camera is created.")
        XCTAssertTrue(viewModel.renameCamera(.camera2, to: "Still editable"))
        sequence.failsWrites = false
        XCTAssertNotNil(viewModel.addCamera(), "No blocked state remains.")
    }

    // MARK: - Helpers

    private struct Stores {
        var session: CameraSlotSessionPersistenceStoring = InMemoryCameraListSessionStore()
        var sequence: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore()
    }

    private func makeViewModel(
        stores: Stores = Stores()
    ) -> (viewModel: ExposureCalculatorViewModel, stores: Stores) {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: stores.session,
            cameraNameSequenceStore: stores.sequence
        )
        return (viewModel, stores)
    }

    /// A persisted managed payload whose first camera carries `name`.
    private func seededPayload(renaming name: String) throws -> PersistentManagedCameraListSnapshot {
        let seeded = InMemoryCameraListSessionStore()
        let viewModel = makeViewModel(stores: Stores(session: seeded, sequence: InMemoryCameraNameSequenceStore())).viewModel
        viewModel.renameCamera(.camera1, to: name)
        return try XCTUnwrap(seeded.persistedManaged)
    }

    private func legacySnapshot(renaming name: String?) -> PersistentCameraSlotSessionSnapshot {
        PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: "camera1",
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: "camera1",
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 0,
                    customDisplayName: name
                ),
            ]
        )
    }
}

/// Orders store writes across the session and sequence stores.
private final class EventLog {
    var items: [String] = []
}

private final class RecordingSessionStore: CameraSlotSessionPersistenceStoring {
    private let events: EventLog
    var legacy: PersistentCameraSlotSessionSnapshot?
    var managed: ManagedCameraListLoadResult = .absent

    init(_ events: EventLog) { self.events = events }

    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { legacy }
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) { legacy = snapshot }
    func clearSnapshot() { legacy = nil }
    func loadManagedList() -> ManagedCameraListLoadResult { managed }
    func saveManagedList(_ snapshot: PersistentManagedCameraListSnapshot) {
        events.items.append("managed")
        managed = .loaded(snapshot)
    }
}

private final class RecordingSequenceStore: CameraNameSequenceStoring {
    private let events: EventLog
    private let inner = InMemoryCameraNameSequenceStore()

    init(_ events: EventLog) { self.events = events }

    func load() -> CameraNameSequenceLoadResult { inner.load() }
    func save(nextNumber: Int) -> Bool {
        events.items.append("sequence=\(nextNumber)")
        return inner.save(nextNumber: nextNumber)
    }
}

/// A session store whose managed writes are lost, as when the process is
/// killed after the sequence reservation and before the camera commit.
private final class LossySessionStore: CameraSlotSessionPersistenceStoring {
    private let legacy: PersistentCameraSlotSessionSnapshot?

    init(legacy: PersistentCameraSlotSessionSnapshot? = nil) { self.legacy = legacy }

    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { legacy }
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {}
    func clearSnapshot() {}
    func loadManagedList() -> ManagedCameraListLoadResult { .absent }
    func saveManagedList(_ snapshot: PersistentManagedCameraListSnapshot) {}
}
