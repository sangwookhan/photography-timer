// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Persistence, migration, and restore of the managed camera list
/// (CAMERA-PERSIST-001 through CAMERA-PERSIST-006, CAMERA-004).
@MainActor
final class ManagedCameraListPersistenceTests: XCTestCase {

    // MARK: - Fresh install

    func testFreshInstallSeedsTheFourCamerasInOrderShownWithCameraOneActive() {
        let viewModel = makeViewModel(InMemoryCameraListSessionStore())
        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(viewModel.cameraList.map(\.name), ["Camera 1", "Camera 2", "Camera 3", "Camera 4"])
        XCTAssertTrue(viewModel.cameraList.allSatisfy(\.isDisplayed))
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
    }

    // MARK: - Round trip

    func testListOrderPagerInclusionActiveCameraAndNamesSurviveRelaunch() throws {
        let store = InMemoryCameraListSessionStore()
        let viewModel = makeViewModel(store)
        viewModel.renameCamera(.camera2, to: "Mamiya 7")
        viewModel.moveCamera(.camera4, by: -3)
        viewModel.setCameraDisplayed(false, for: .camera3)
        let added = try XCTUnwrap(viewModel.addCamera())
        viewModel.selectCameraSlot(.camera2)

        let restored = makeViewModel(store)

        XCTAssertEqual(restored.cameraList.map(\.id), [.camera4, .camera1, .camera2, .camera3, added])
        XCTAssertEqual(restored.cameraList.map(\.name), ["Camera 4", "Camera 1", "Mamiya 7", "Camera 3", "Camera 5"])
        XCTAssertEqual(restored.availableCameraSlots, [.camera4, .camera1, .camera2, added])
        XCTAssertEqual(restored.activeCameraSlotID, .camera2)
    }

    func testEveryCamerasCalculatorStateSurvivesRelaunchIncludingHiddenCameras() throws {
        let store = InMemoryCameraListSessionStore()
        let viewModel = makeViewModel(store)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4
        viewModel.selectCameraSlot(.camera2)
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.ndStop = 7
        viewModel.setCameraDisplayed(false, for: .camera2)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)

        let restored = makeViewModel(store)

        XCTAssertEqual(restored.cameraSlotPageState(for: .camera1).baseShutter, 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(restored.cameraSlotPageState(for: .camera1).ndStep.stops, 4, accuracy: 1e-9)
        let hidden = restored.cameraSlotPageState(for: .camera2)
        XCTAssertEqual(hidden.baseShutter, 1.0 / 8.0, accuracy: 1e-12)
        XCTAssertEqual(hidden.ndStep.stops, 7, accuracy: 1e-9)
    }

    func testPersistedIdentitiesAreTheLegacyRawValuesAndAreNeverReissuedAfterRelaunch() throws {
        let store = InMemoryCameraListSessionStore()
        let viewModel = makeViewModel(store)
        viewModel.renameCamera(.camera1, to: "A")
        XCTAssertEqual(
            store.persistedManaged?.cameras.map(\.idRaw),
            ["camera1", "camera2", "camera3", "camera4"]
        )

        viewModel.deleteCameras([.camera2])
        let restored = makeViewModel(store)
        let added = try XCTUnwrap(restored.addCamera())
        XCTAssertFalse(CameraSlotID.legacyOrdered.contains(added))
        XCTAssertTrue(
            Set(try XCTUnwrap(store.persistedManaged).issuedIDRaws).isSuperset(of: ["camera1", "camera2", "camera3", "camera4"]),
            "Deleted identities stay issued."
        )
    }

    func testNoActiveCameraAndAnEmptyListSurviveRelaunchWithoutReseeding() throws {
        let store = InMemoryCameraListSessionStore()
        let viewModel = makeViewModel(store)
        viewModel.hideCameras(Set(CameraSlotID.legacyOrdered))
        XCTAssertNil(store.persistedManaged?.activeCameraIDRaw, "The absence of an active camera is explicit.")

        let allHidden = makeViewModel(store)
        XCTAssertTrue(allHidden.availableCameraSlots.isEmpty)
        XCTAssertNil(allHidden.activeCameraSlot)
        XCTAssertEqual(allHidden.cameraList.count, 4)
        allHidden.setCameraDisplayed(true, for: .camera3)
        XCTAssertEqual(allHidden.activeCameraSlotID, .camera3)

        let store2 = InMemoryCameraListSessionStore()
        let second = makeViewModel(store2)
        second.deleteCameras(Set(CameraSlotID.legacyOrdered))
        XCTAssertEqual(store2.persistedManaged?.cameras.count, 0)
        let emptyList = makeViewModel(store2)
        XCTAssertTrue(emptyList.cameraList.isEmpty, "An explicit empty list is never reseeded.")
        XCTAssertNil(emptyList.activeCameraSlot)
    }

    func testABulkEditPersistsAsOneWriteWithListActiveCameraAndStateTogether() throws {
        let store = InMemoryCameraListSessionStore()
        let viewModel = makeViewModel(store)
        viewModel.renameCamera(.camera1, to: "A")
        let before = store.managedSaveCount

        viewModel.deleteCameras([.camera1, .camera2])

        XCTAssertEqual(store.managedSaveCount, before + 1)
        let payload = try XCTUnwrap(store.persistedManaged)
        XCTAssertEqual(payload.cameras.map(\.idRaw), ["camera3", "camera4"])
        XCTAssertEqual(payload.activeCameraIDRaw, "camera3")
        XCTAssertTrue(payload.cameras.allSatisfy { $0.calculator != nil })
    }

    // MARK: - Migration from the four fixed cameras

    func testLegacySessionMigratesNamesStatesOrderAndVisibility() throws {
        let store = InMemoryCameraListSessionStore()
        store.legacy = PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: "camera3",
            slots: [
                legacySlot("camera1", name: "Hasselblad", baseShutter: 1.0 / 60.0, ndStop: 4),
                legacySlot("camera3", name: nil, baseShutter: 1.0 / 8.0, ndStop: 10),
                legacySlot("camera4", name: "  Mamiya 7 ", baseShutter: 2.0, ndStop: 0),
            ]
        )

        let viewModel = makeViewModel(store)

        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(viewModel.cameraList.map(\.name), ["Hasselblad", "Camera 2", "Camera 3", "Mamiya 7"])
        XCTAssertTrue(viewModel.cameraList.allSatisfy(\.isDisplayed))
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera3)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 8.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.ndStop, 10)
        XCTAssertEqual(viewModel.cameraSlotPageState(for: .camera1).baseShutter, 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.cameraSlotPageState(for: .camera1).ndStep.stops, 4, accuracy: 1e-9)
        let unvisited = viewModel.cameraSlotPageState(for: .camera2)
        XCTAssertEqual(unvisited.baseShutter, makeViewModel(InMemoryCameraListSessionStore()).baseShutter, accuracy: 1e-12)

        // The migrated list is persisted, and the legacy source is kept.
        XCTAssertEqual(store.persistedManaged?.cameras.map(\.name), ["Hasselblad", "Camera 2", "Camera 3", "Mamiya 7"])
        XCTAssertNotNil(store.legacy)
        XCTAssertEqual(store.legacyWriteCount, 0, "Migration never modifies the legacy source.")
    }

    func testMigrationIsIdempotentAndSurvivesAnInterruptedFirstSave() throws {
        let store = InMemoryCameraListSessionStore()
        store.legacy = PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: "camera2",
            slots: [legacySlot("camera2", name: "Field", baseShutter: 0.5, ndStop: 3)]
        )
        let first = makeViewModel(store)
        XCTAssertEqual(first.cameraList.count, 4)

        // Interrupted: the managed payload never reached disk.
        store.managed = .absent
        let retry = makeViewModel(store)
        XCTAssertEqual(retry.cameraList.map(\.id), [.camera1, .camera2, .camera3, .camera4], "No duplicate cameras.")
        XCTAssertEqual(retry.cameraList.map(\.name), first.cameraList.map(\.name))
        XCTAssertEqual(retry.activeCameraSlotID, .camera2)
        XCTAssertEqual(retry.baseShutter, 0.5, accuracy: 1e-12)

        // A further launch with the managed payload present changes nothing.
        let again = makeViewModel(store)
        XCTAssertEqual(again.cameraList.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(again.cameraList.map(\.name), first.cameraList.map(\.name))
    }

    func testAValidManagedPayloadWinsOverARemainingLegacyPayload() throws {
        let store = InMemoryCameraListSessionStore()
        store.legacy = PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: "camera4",
            slots: [legacySlot("camera1", name: "Legacy name", baseShutter: 4, ndStop: 9)]
        )
        let managed = try managedPayload { $0.renameCamera(.camera1, to: "Managed name") }
        store.managed = .loaded(managed)

        let restored = makeViewModel(store)

        XCTAssertEqual(restored.cameraList.first?.name, "Managed name")
        XCTAssertEqual(restored.activeCameraSlotID, .camera1)
    }

    func testLegacySingleContextStillMigratesWhenNoSessionExists() throws {
        let legacyContext = InMemoryContextStore()
        legacyContext.saveSnapshot(
            PersistentCalculatorContextSnapshot(
                selectedPresetFilmID: nil,
                baseShutterSeconds: 1.0 / 60.0,
                ndStop: 6,
                ndStopThirds: nil,
                exposureScaleMode: nil,
                activeCameraSlotIDRaw: "camera2"
            )
        )
        let store = InMemoryCameraListSessionStore()

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: legacyContext,
            cameraSlotSessionPersistenceStore: store
        )

        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.ndStop, 6)
        viewModel.renameCamera(.camera2, to: "Field")
        XCTAssertEqual(store.persistedManaged?.activeCameraIDRaw, "camera2")
    }

    // MARK: - Undecodable content and failed reads (CAMERA-PERSIST-004)

    func testUndecodableContentIsAtomicallyReplacedWithFreshCamerasAndNoLegacyFallback() throws {
        let store = InMemoryCameraListSessionStore()
        store.legacy = PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: "camera1",
            slots: [legacySlot("camera1", name: "Stale legacy", baseShutter: 4, ndStop: 9)]
        )
        store.managed = .undecodable
        let sequence = InMemoryCameraNameSequenceStore(.value(9))
        sequenceStores[ObjectIdentifier(store)] = sequence

        let viewModel = makeViewModel(store)

        XCTAssertEqual(viewModel.cameraList.map(\.name), ["Camera 1", "Camera 2", "Camera 3", "Camera 4"], "Stale legacy data is never used.")
        XCTAssertTrue(viewModel.cameraList.allSatisfy(\.isDisplayed))
        XCTAssertEqual(viewModel.activeCameraSlotID, viewModel.cameraList.first?.id, "The first camera is active.")
        let legacyIDs: Set<CameraSlotID> = [.camera1, .camera2, .camera3, .camera4]
        XCTAssertTrue(Set(viewModel.cameraList.map(\.id)).isDisjoint(with: legacyIDs), "Recovery issues new opaque identities.")
        XCTAssertEqual(Set(viewModel.cameraList.map(\.id)).count, 4)
        XCTAssertGreaterThanOrEqual(store.managedSaveCount, 1, "A write replaces the unreadable content.")
        XCTAssertNotEqual(store.managed, .absent, "The payload is replaced, never left absent.")
        let persisted = try XCTUnwrap(store.persistedManaged)
        XCTAssertEqual(persisted.cameras.map(\.idRaw), viewModel.cameraList.map(\.id.rawValue))
        XCTAssertEqual(sequence.result, .value(9), "A readable sequence is never lowered.")
    }

    func testReplacementUsesAtLeastFiveForTheSequence() {
        for stored in [CameraNameSequenceLoadResult.absent, .unusable, .value(3)] {
            let store = InMemoryCameraListSessionStore()
            store.managed = .undecodable
            let sequence = InMemoryCameraNameSequenceStore(stored)
            sequenceStores[ObjectIdentifier(store)] = sequence

            _ = makeViewModel(store)

            XCTAssertEqual(sequence.result, .value(5), "Stored \(stored) becomes 5.")
        }
    }

    func testReplacementKeepsAReadableSequenceOfTwelve() throws {
        let store = InMemoryCameraListSessionStore()
        store.managed = .undecodable
        let sequence = InMemoryCameraNameSequenceStore(.value(12))
        sequenceStores[ObjectIdentifier(store)] = sequence

        let viewModel = makeViewModel(store)

        XCTAssertEqual(sequence.result, .value(12), "A readable 12 is preserved, not reset to 5.")
        let added = try XCTUnwrap(viewModel.addCamera())
        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 12")
        XCTAssertEqual(sequence.result, .value(13))
    }

    func testTimersStayUsableWhileCameraDataCouldNotBeLoaded() {
        let store = InMemoryCameraListSessionStore()
        store.managed = .readFailed
        let viewModel = makeViewModel(store)
        XCTAssertFalse(viewModel.isCameraListEditable)

        viewModel.startTimer(from: 30)

        XCTAssertEqual(viewModel.timers.count, 1, "A timer that needs no camera still starts.")
        XCTAssertEqual(store.managedSaveCount, 0)
    }

    func testAStorageReadFailurePerformsNoWriteAndLeavesNoEditableCameraState() {
        let store = InMemoryCameraListSessionStore()
        store.legacy = PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: "camera1",
            slots: [legacySlot("camera1", name: "Stale legacy", baseShutter: 4, ndStop: 9)]
        )
        store.managed = .readFailed
        let sequence = InMemoryCameraNameSequenceStore(.value(7))
        sequenceStores[ObjectIdentifier(store)] = sequence

        let viewModel = makeViewModel(store)

        XCTAssertTrue(viewModel.cameraList.isEmpty, "No legacy fallback and no seeding.")
        XCTAssertFalse(viewModel.isCameraListEditable)
        XCTAssertNil(viewModel.addCamera())
        XCTAssertFalse(viewModel.renameCamera(.camera1, to: "Edit"))
        viewModel.setCameraDisplayed(false, for: .camera1)
        viewModel.deleteCameras([.camera1])
        viewModel.baseShutter = 2.0
        XCTAssertEqual(store.managedSaveCount, 0, "Nothing is written for the whole session.")
        XCTAssertEqual(store.managed, .readFailed)
        XCTAssertEqual(store.legacyWriteCount, 0)
        XCTAssertEqual(sequence.saveCount, 0)
        XCTAssertEqual(sequence.result, .value(7))
    }

    func testTheNextLaunchRetriesInitializationAfterAFailedRead() {
        let store = InMemoryCameraListSessionStore()
        store.managed = .readFailed
        _ = makeViewModel(store)

        store.managed = .absent
        let retried = makeViewModel(store)

        XCTAssertTrue(retried.isCameraListEditable)
        XCTAssertEqual(retried.cameraList.map(\.id), [.camera1, .camera2, .camera3, .camera4])
    }

    // MARK: - Per-record defaults (CAMERA-PERSIST-004)

    func testRecordsWithMissingFieldsTakeTheDocumentedDefaults() throws {
        let json = """
        {"schemaVersion":1,"issuedIDRaws":["camera1","camera2"],"activeCameraIDRaw":"camera3",
         "cameras":[
          {"idRaw":"camera1","name":"Kept","isDisplayed":false},
          {"idRaw":"camera2"},
          {"name":"No identity","isDisplayed":true,"calculator":"not a calculator"}
         ]}
        """
        let payload = try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(json.utf8))
        let store = InMemoryCameraListSessionStore()
        store.managed = .loaded(payload)

        let viewModel = makeViewModel(store)

        XCTAssertEqual(viewModel.cameraList.count, 3)
        XCTAssertEqual(viewModel.cameraList.map(\.name), ["Kept", "Camera", "No identity"], "A missing name is the localized Camera.")
        XCTAssertEqual(viewModel.cameraList.map(\.isDisplayed), [false, true, true], "Missing pager inclusion is shown.")
        XCTAssertEqual(viewModel.cameraList[0].id, .camera1)
        XCTAssertEqual(viewModel.cameraList[1].id, .camera2)
        let generated = viewModel.cameraList[2].id
        XCTAssertFalse([.camera1, .camera2, .camera3, .camera4].contains(generated), "A missing identity gets a new opaque identity.")
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2, "An unusable active identity selects the first shown camera.")
        let fresh = makeViewModel(InMemoryCameraListSessionStore())
        XCTAssertEqual(viewModel.cameraSlotPageState(for: generated).baseShutter, fresh.baseShutter, accuracy: 1e-12, "Fresh calculator defaults.")
        XCTAssertGreaterThanOrEqual(store.managedSaveCount, 1, "The normalized list is persisted.")
        XCTAssertEqual(store.persistedManaged?.cameras.map(\.idRaw), viewModel.cameraList.map(\.id.rawValue))
        let relaunched = makeViewModel(store)
        XCTAssertEqual(relaunched.cameraList.map(\.id), viewModel.cameraList.map(\.id), "The generated identity is stable.")
    }

    func testNoShownCameraMeansNoActiveCamera() throws {
        let json = """
        {"schemaVersion":1,"issuedIDRaws":["camera1"],"activeCameraIDRaw":"camera1",
         "cameras":[{"idRaw":"camera1","name":"Hidden","isDisplayed":false}]}
        """
        let payload = try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(json.utf8))
        let store = InMemoryCameraListSessionStore()
        store.managed = .loaded(payload)

        let viewModel = makeViewModel(store)

        XCTAssertNil(viewModel.activeCameraSlotID)
        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1])
    }

    func testValuesThatAreNotKeyedCameraRecordsAreSkipped() throws {
        let json = """
        {"schemaVersion":1,"issuedIDRaws":["camera1","camera3"],"activeCameraIDRaw":"camera1",
         "cameras":[
          {"idRaw":"camera1","name":"Kept","isDisplayed":true},
          7, "text", null,
          {"idRaw":"camera3","name":"Also kept","isDisplayed":false}
         ]}
        """
        let payload = try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(json.utf8))
        let store = InMemoryCameraListSessionStore()
        store.managed = .loaded(payload)

        let viewModel = makeViewModel(store)

        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1, .camera3], "Surviving entries keep their stored order.")
        XCTAssertEqual(viewModel.availableCameraSlots, [.camera1])
        XCTAssertEqual(store.persistedManaged?.cameras.map(\.idRaw), ["camera1", "camera3"], "The normalized list is persisted.")
    }

    func testTheFirstDuplicateIdentityIsKeptAndLaterOnesGetNewIdentities() throws {
        let json = """
        {"schemaVersion":1,"issuedIDRaws":["camera1"],"activeCameraIDRaw":"camera1",
         "cameras":[
          {"idRaw":"camera1","name":"First","isDisplayed":true},
          {"idRaw":"camera1","name":"Second","isDisplayed":true},
          {"idRaw":"camera1","name":"Third","isDisplayed":true}
         ]}
        """
        let payload = try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(json.utf8))
        let store = InMemoryCameraListSessionStore()
        store.managed = .loaded(payload)

        let viewModel = makeViewModel(store)

        XCTAssertEqual(viewModel.cameraList.map(\.name), ["First", "Second", "Third"])
        XCTAssertEqual(viewModel.cameraList.first?.id, .camera1)
        XCTAssertEqual(Set(viewModel.cameraList.map(\.id)).count, 3, "Every camera has its own identity.")
    }

    func testAPayloadWithNoRestorableCameraRestoresAnEmptyListAndPersistsIt() throws {
        let json = """
        {"schemaVersion":1,"issuedIDRaws":[],"activeCameraIDRaw":null,"cameras":[1, "x"]}
        """
        let payload = try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(json.utf8))
        let store = InMemoryCameraListSessionStore()
        store.managed = .loaded(payload)

        let viewModel = makeViewModel(store)

        XCTAssertTrue(viewModel.cameraList.isEmpty)
        XCTAssertNil(viewModel.activeCameraSlotID)
        XCTAssertEqual(store.persistedManaged?.cameras.count, 0)
    }

    func testACollectionThatCannotBeDecodedIsUndecodableContent() {
        let json = #"{"schemaVersion":1,"issuedIDRaws":[],"activeCameraIDRaw":null,"cameras":"nope"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(json.utf8)))
        let noVersion = #"{"issuedIDRaws":[],"cameras":[]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(PersistentManagedCameraListSnapshot.self, from: Data(noVersion.utf8)))
    }

    func testAnOrphanedCalculatorStateIsIgnoredAndACameraWithoutStateGetsDefaults() throws {
        let store = InMemoryCameraListSessionStore()
        let full = try managedPayload { $0.baseShutter = 4 }
        let trimmed = PersistentManagedCameraListSnapshot(
            issuedIDRaws: full.issuedIDRaws,
            activeCameraIDRaw: "camera1",
            cameras: [
                PersistentManagedCamera(idRaw: "camera1", name: "Only", isDisplayed: true, calculator: nil),
            ]
        )
        store.managed = .loaded(trimmed)

        let viewModel = makeViewModel(store)

        XCTAssertEqual(viewModel.cameraList.map(\.id), [.camera1])
        XCTAssertEqual(viewModel.baseShutter, makeViewModel(InMemoryCameraListSessionStore()).baseShutter, accuracy: 1e-12)
    }

    // MARK: - Running timers

    func testTimerCaptureSurvivesRenameDeleteAndRelaunch() throws {
        let store = InMemoryCameraListSessionStore()
        let timerStore = InMemoryCameraListTimerStore()
        let metadataStore = InMemoryCameraListMetadataStore()
        func launch() -> ExposureCalculatorViewModel {
            ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerManager: RuntimeBackedTimerManaging(persistenceStore: timerStore),
                cameraSlotSessionPersistenceStore: store,
                metadataPersistenceStore: metadataStore
            )
        }
        let viewModel = launch()
        viewModel.renameCamera(.camera1, to: "Hasselblad")
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let started = try XCTUnwrap(viewModel.timers.first)

        viewModel.renameCamera(.camera1, to: "Renamed")
        viewModel.deleteCameras([.camera1])

        let restored = launch()
        let timer = try XCTUnwrap(restored.timers.first { $0.id == started.id })
        XCTAssertEqual(timer.cameraSlot?.id, .camera1)
        XCTAssertEqual(timer.cameraSlot?.displayName, "Hasselblad")
        XCTAssertFalse(restored.cameraList.contains { $0.id == .camera1 })
    }

    func testTimerSnapshotsSurviveReplacementOfUndecodableCameraContent() throws {
        let store = InMemoryCameraListSessionStore()
        let timerStore = InMemoryCameraListTimerStore()
        let metadataStore = InMemoryCameraListMetadataStore()
        func launch() -> ExposureCalculatorViewModel {
            ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerManager: RuntimeBackedTimerManaging(persistenceStore: timerStore),
                cameraSlotSessionPersistenceStore: store,
                metadataPersistenceStore: metadataStore
            )
        }
        let viewModel = launch()
        viewModel.renameCamera(.camera1, to: "Hasselblad")
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let started = try XCTUnwrap(viewModel.timers.first)

        store.managed = .undecodable
        let restored = launch()

        let timer = try XCTUnwrap(restored.timers.first { $0.id == started.id })
        XCTAssertEqual(timer.cameraSlot?.id, .camera1, "The captured identity is unchanged.")
        XCTAssertEqual(timer.cameraSlot?.displayName, "Hasselblad", "The captured name is unchanged.")
        XCTAssertFalse(restored.cameraList.contains { $0.id == .camera1 }, "Recovery never reassigns a captured identity.")
    }

    // MARK: - Helpers

    /// Launches share one sequence store per session store, as a device
    /// keeps one sequence store across launches.
    private var sequenceStores: [ObjectIdentifier: InMemoryCameraNameSequenceStore] = [:]

    private func sequenceStore(for store: InMemoryCameraListSessionStore) -> InMemoryCameraNameSequenceStore {
        if let existing = sequenceStores[ObjectIdentifier(store)] { return existing }
        // A managed payload that is already on "disk" belongs to a build
        // that also wrote the sequence, so seed the value for a stored payload.
        let created = InMemoryCameraNameSequenceStore(store.persistedManaged == nil ? .absent : .value(5))
        sequenceStores[ObjectIdentifier(store)] = created
        return created
    }

    private func makeViewModel(_ store: InMemoryCameraListSessionStore) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: store,
            cameraNameSequenceStore: sequenceStore(for: store)
        )
    }

    /// The managed payload a launch writes after `configure` ran.
    private func managedPayload(
        _ configure: (ExposureCalculatorViewModel) -> Void
    ) throws -> PersistentManagedCameraListSnapshot {
        let store = InMemoryCameraListSessionStore()
        configure(makeViewModel(store))
        return try XCTUnwrap(store.persistedManaged)
    }

    private func legacySlot(
        _ id: String,
        name: String?,
        baseShutter: Double,
        ndStop: Int
    ) -> PersistentCameraSlotCalculatorSnapshot {
        PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: id,
            selectedPresetFilmID: nil,
            selectedProfileID: nil,
            baseShutterSeconds: baseShutter,
            ndStop: ndStop,
            customDisplayName: name
        )
    }
}

private final class InMemoryContextStore: ExposureCalculatorContextStoring {
    private var stored: PersistentCalculatorContextSnapshot?
    func loadSnapshot() -> PersistentCalculatorContextSnapshot? { stored }
    func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot) { stored = snapshot }
    func clearSnapshot() { stored = nil }
}
