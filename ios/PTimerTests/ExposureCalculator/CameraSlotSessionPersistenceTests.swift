import XCTest
@testable import PTimer

/// End-to-end tests for the multi-slot persistence layer:
/// `CameraSlotSessionPersistenceController`, the
/// `PersistentCameraSlotSessionSnapshot` schema, and the ViewModel's
/// restore/save wiring. Covers the four scenarios called out in the
/// PTIMER-120 follow-up spec: 4-slot save+restore, active-slot
/// restore, inactive-slot restore, legacy-context migration, and
/// safe fallback for invalid stored film references.
@MainActor
final class CameraSlotSessionPersistenceTests: XCTestCase {

    // MARK: - 4-slot save and restore

    func testAllFourCameraSlotsSaveAndRestore() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)
        let triX = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        let portra = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName.contains("Portra 400") }
        )

        // Configure each slot with its own state.
        viewModel.selectPresetFilm(triX)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4

        viewModel.selectCameraSlot(.camera2)
        viewModel.selectPresetFilm(portra)
        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 6

        viewModel.selectCameraSlot(.camera3)
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.ndStop = 10

        viewModel.selectCameraSlot(.camera4)
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 0

        // Bring the persisted snapshot up by activating Camera 1
        // again so its state is captured into the inactive map and
        // the session save reflects all four slots.
        viewModel.selectCameraSlot(.camera1)

        // Simulate a relaunch: build a fresh ViewModel against the
        // same store. Each slot should restore its own values.
        let restored = makeViewModel(sessionStore: sessionStore)

        XCTAssertEqual(restored.activeCameraSlotID, .camera1)
        XCTAssertEqual(restored.selectedPresetFilm?.id, triX.id)
        XCTAssertEqual(restored.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(restored.ndStop, 4)

        let camera2Page = restored.cameraSlotPageState(for: .camera2)
        XCTAssertEqual(camera2Page.selectedFilm?.id, portra.id)
        XCTAssertEqual(camera2Page.baseShutter, 1.0 / 15.0, accuracy: 1e-9)
        XCTAssertEqual(camera2Page.ndStep.stops, 6, accuracy: 1e-9)

        let camera3Page = restored.cameraSlotPageState(for: .camera3)
        XCTAssertNil(camera3Page.selectedFilm)
        XCTAssertEqual(camera3Page.baseShutter, 1.0 / 8.0, accuracy: 1e-9)
        XCTAssertEqual(camera3Page.ndStep.stops, 10, accuracy: 1e-9)

        let camera4Page = restored.cameraSlotPageState(for: .camera4)
        XCTAssertNil(camera4Page.selectedFilm)
        XCTAssertEqual(camera4Page.baseShutter, 1.0, accuracy: 1e-9)
        XCTAssertEqual(camera4Page.ndStep.stops, 0, accuracy: 1e-9)
    }

    func testActiveSlotIDIsRestored() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)

        viewModel.selectCameraSlot(.camera3)
        viewModel.baseShutter = 1.0 / 15.0

        let restored = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(restored.activeCameraSlotID, .camera3)
    }

    /// Two-relaunch regression. The bug being fenced: on first
    /// relaunch, `applyRestoredSession` used to apply the active
    /// snapshot before loading the inactive map, and the trailing
    /// `persistCalculatorContext()` inside the snapshot apply read
    /// the (still empty) inactive map and overwrote the persisted
    /// session with active-only state. The result was that
    /// inactive slots disappeared on the second relaunch even
    /// though they were persisted before the first one.
    ///
    /// Verifies the fix by relaunching the ViewModel against the
    /// same store twice and checking that inactive slot state
    /// survives both transitions.
    func testInactiveSlotsSurviveTwoRelaunches() throws {
        let sessionStore = InMemorySessionStore()
        let setup = makeViewModel(sessionStore: sessionStore)
        let triX = try XCTUnwrap(
            setup.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

        // Configure all four slots with distinct state, then leave
        // Camera 4 active so the relaunches restore Camera 1-3 from
        // the inactive map.
        setup.selectPresetFilm(triX)
        setup.baseShutter = 1.0 / 60.0
        setup.ndStop = 4
        setup.selectCameraSlot(.camera2)
        setup.baseShutter = 1.0 / 15.0
        setup.ndStop = 6
        setup.selectCameraSlot(.camera3)
        setup.baseShutter = 1.0 / 8.0
        setup.ndStop = 10
        setup.selectCameraSlot(.camera4)

        // First relaunch.
        let firstRelaunch = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(firstRelaunch.activeCameraSlotID, .camera4)
        XCTAssertEqual(
            firstRelaunch.cameraSlotPageState(for: .camera1).selectedFilm?.id,
            triX.id,
            "Camera 1's film must survive the first relaunch."
        )
        XCTAssertEqual(
            firstRelaunch.cameraSlotPageState(for: .camera2).baseShutter,
            1.0 / 15.0,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            firstRelaunch.cameraSlotPageState(for: .camera3).ndStep.stops,
            10,
            accuracy: 1e-9
        )

        // Second relaunch — this is the regression. The first
        // relaunch's restore must not have wiped the inactive
        // slots out of the persistence store.
        let secondRelaunch = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(secondRelaunch.activeCameraSlotID, .camera4)
        XCTAssertEqual(
            secondRelaunch.cameraSlotPageState(for: .camera1).selectedFilm?.id,
            triX.id,
            "Camera 1's film must survive a second relaunch — the first relaunch's restore must not have overwritten the persisted session with active-only state."
        )
        XCTAssertEqual(
            secondRelaunch.cameraSlotPageState(for: .camera2).baseShutter,
            1.0 / 15.0,
            accuracy: 1e-9,
            "Camera 2's base shutter must survive a second relaunch."
        )
        XCTAssertEqual(
            secondRelaunch.cameraSlotPageState(for: .camera3).ndStep.stops,
            10,
            accuracy: 1e-9,
            "Camera 3's ND must survive a second relaunch."
        )
    }

    func testInactiveSlotStateRestoresIndependently() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.selectCameraSlot(.camera4)

        // Camera 1 is now inactive and should be persisted with its
        // film selection. Relaunch and verify the inactive slot's
        // state is reachable from the page-state derivation.
        let restored = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(restored.activeCameraSlotID, .camera4)

        let camera1Page = restored.cameraSlotPageState(for: .camera1)
        XCTAssertEqual(camera1Page.selectedFilm?.id, film.id)
        XCTAssertEqual(camera1Page.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
    }

    // MARK: - Target Shutter persistence

    /// PTIMER-25 follow-up: per-slot Target Shutter state must round-
    /// trip through the session snapshot. Configure distinct targets
    /// on three slots, leave a fourth without a target, then relaunch
    /// the ViewModel against the same store and confirm each slot
    /// restores its captured target (or absence of one).
    func testTargetShutterRoundTripsAcrossRelaunchPerSlot() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)

        viewModel.setTargetShutter(300) // Camera 1 → 5m
        viewModel.selectCameraSlot(.camera2)
        viewModel.setTargetShutter(3600) // Camera 2 → 1h
        viewModel.selectCameraSlot(.camera3)
        viewModel.setTargetShutter(8 * 3600) // Camera 3 → 8h
        viewModel.selectCameraSlot(.camera4)
        // Camera 4 deliberately left without a target.

        // Bring the persisted snapshot up to date by switching back
        // through Camera 1 so its (live) target is captured into the
        // inactive map at session save time.
        viewModel.selectCameraSlot(.camera1)

        let restored = makeViewModel(sessionStore: sessionStore)

        XCTAssertEqual(restored.activeCameraSlotID, .camera1)
        XCTAssertEqual(restored.targetShutterSeconds ?? 0, 300, accuracy: 0.0001,
                       "Camera 1's 5m target must survive the relaunch")

        XCTAssertEqual(
            restored.cameraSlotPageState(for: .camera2).targetShutterSeconds ?? 0,
            3600,
            accuracy: 0.0001,
            "Camera 2's 1h target must persist on its inactive snapshot"
        )
        XCTAssertEqual(
            restored.cameraSlotPageState(for: .camera3).targetShutterSeconds ?? 0,
            8 * 3600,
            accuracy: 0.0001,
            "Camera 3's 8h target must persist on its inactive snapshot"
        )
        XCTAssertNil(
            restored.cameraSlotPageState(for: .camera4).targetShutterSeconds,
            "Camera 4 had no target set — restore must surface nil, not a leaked value"
        )
    }

    /// Sanitises a corrupted target value at decode time. A negative
    /// or non-finite value must be treated as "no target" rather than
    /// resurfacing as an invalid timer duration.
    func testCorruptedPersistedTargetIsSanitisedAtDecodeTime() {
        let snapshot = PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: CameraSlotID.camera1.rawValue,
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1,
                    ndStop: 0,
                    targetShutterSeconds: -10
                ),
            ]
        )
        let sessionStore = InMemorySessionStore()
        sessionStore.saveSnapshot(snapshot)

        let restored = makeViewModel(sessionStore: sessionStore)

        XCTAssertNil(restored.targetShutterSeconds,
                     "Negative persisted target must decode as nil")
        XCTAssertFalse(restored.isTargetShutterActive)
    }

    // MARK: - Legacy migration

    func testLegacySingleContextMigratesToSessionOnFirstLaunch() throws {
        // First-launch state: legacy store has Camera 1 data, new
        // session store is empty. The ViewModel must apply the
        // legacy data to the active slot, then write a session
        // snapshot so the next launch reads the new schema.
        let legacyStore = InMemoryContextStore()
        let film = try XCTUnwrap(
            makeViewModel().availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        legacyStore.saveSnapshot(
            PersistentCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 60.0,
                ndStop: 6,
                ndStopThirds: nil,
                exposureScaleMode: nil,
                activeCameraSlotIDRaw: nil
            )
        )
        let sessionStore = InMemorySessionStore()

        let viewModel = makeViewModel(sessionStore: sessionStore, legacyStore: legacyStore)

        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndStop, 6)

        // The next launch should NOT touch the legacy store; the
        // session snapshot should be self-sufficient.
        let restored = makeViewModel(
            sessionStore: sessionStore,
            legacyStore: InMemoryContextStore() // empty legacy
        )
        XCTAssertEqual(restored.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(restored.baseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(restored.ndStop, 6)
    }

    // MARK: - Safe fallback for invalid stored film

    func testInvalidFilmReferenceInPersistedSlotRestoresAsNoFilm() throws {
        let sessionStore = InMemorySessionStore()
        sessionStore.saveSnapshot(
            PersistentCameraSlotSessionSnapshot(
                schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
                activeSlotIDRaw: "camera2",
                slots: [
                    PersistentCameraSlotCalculatorSnapshot(
                        slotIDRaw: "camera1",
                        selectedPresetFilmID: "definitely-not-a-real-film-id",
                        selectedProfileID: nil,
                        baseShutterSeconds: 1.0 / 30.0,
                        ndStop: 0,
                        ndStopThirds: nil,
                        exposureScaleMode: nil
                    ),
                    PersistentCameraSlotCalculatorSnapshot(
                        slotIDRaw: "camera2",
                        selectedPresetFilmID: nil,
                        selectedProfileID: nil,
                        baseShutterSeconds: 1.0 / 60.0,
                        ndStop: 4,
                        ndStopThirds: nil,
                        exposureScaleMode: nil
                    ),
                ]
            )
        )

        let viewModel = makeViewModel(sessionStore: sessionStore)

        // Active slot: camera2, intact.
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera2)
        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 60.0, accuracy: 1e-9)

        // Camera 1's invalid film id must NOT crash or mislabel —
        // it falls back to "No film".
        let camera1Page = viewModel.cameraSlotPageState(for: .camera1)
        XCTAssertNil(camera1Page.selectedFilm)
        XCTAssertEqual(camera1Page.filmSelectionDisplayState.primaryText, "No film")
    }

    func testSchemaVersionMismatchIsIgnoredOnLoad() {
        let sessionStore = InMemorySessionStore()
        // Persist a snapshot with a future schema version. The store
        // must reject it on load (returning nil) so the ViewModel
        // falls back to the legacy path / fresh defaults rather
        // than acting on misinterpreted data.
        sessionStore.saveSnapshot(
            PersistentCameraSlotSessionSnapshot(
                schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion + 100,
                activeSlotIDRaw: "camera3",
                slots: []
            )
        )

        let viewModel = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(viewModel.activeCameraSlotID, .camera1)
    }

    // MARK: - Custom display name persistence

    func testCustomDisplayNameRoundTripsAcrossRelaunch() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)

        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)
        viewModel.setCameraSlotCustomName("Mamiya 7", for: .camera3)

        // Simulate a relaunch.
        let restored = makeViewModel(sessionStore: sessionStore)

        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera1).displayName,
            "Hasselblad 500CM"
        )
        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera3).displayName,
            "Mamiya 7"
        )
        // Untouched slots still default to the canonical label.
        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera2).displayName,
            "Camera 2"
        )
        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera4).displayName,
            "Camera 4"
        )
    }

    func testResetClearsPersistedCustomDisplayName() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)
        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        viewModel.resetCameraSlotCustomName(.camera1)

        // Inspect the on-disk snapshot directly: the entry for
        // camera1 must persist no custom name (Optional `nil`) so
        // a relaunch falls back to the default label.
        let snapshot = try XCTUnwrap(sessionStore.loadSnapshot())
        let camera1Entry = snapshot.slots.first { $0.slotIDRaw == "camera1" }
        XCTAssertNil(camera1Entry?.customDisplayName)

        let restored = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera1).displayName,
            "Camera 1"
        )
    }

    /// Steady-state "no rename" snapshot must persist no custom
    /// name field (Optional stays `nil`) so a session that never
    /// used the rename surface stays byte-for-byte compatible
    /// with the pre-PTIMER-123 on-disk shape.
    func testSnapshotWithoutRenameOmitsCustomDisplayNameField() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)

        viewModel.baseShutter = 1.0 / 60.0
        viewModel.selectCameraSlot(.camera2)

        let snapshot = try XCTUnwrap(sessionStore.loadSnapshot())
        for slot in snapshot.slots {
            XCTAssertNil(
                slot.customDisplayName,
                "Slot \(slot.slotIDRaw) must persist no custom name when none has been set."
            )
        }
    }

    /// A session snapshot saved before PTIMER-123 (no
    /// `customDisplayName` field on disk) must decode into a
    /// session whose slots all show the default `Camera N` label.
    /// The Optional-additive field stays compatible.
    func testLegacySnapshotWithoutCustomDisplayNameDecodesAsDefault() throws {
        let sessionStore = InMemorySessionStore()
        sessionStore.saveSnapshot(
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
                        ndStopThirds: nil,
                        exposureScaleMode: nil
                        // Note: customDisplayName intentionally omitted
                        // so this exercises the pre-PTIMER-123 shape.
                    ),
                ]
            )
        )

        let viewModel = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(
            viewModel.cameraSlotIdentity(for: .camera1).displayName,
            "Camera 1"
        )
        XCTAssertNil(viewModel.cameraSlotIdentity(for: .camera1).customDisplayName)
    }

    /// Custom names persist alongside calculator state; the
    /// PTIMER-120 4-slot save/restore behaviour must continue to
    /// work even when a subset of slots has been renamed.
    func testFourSlotSaveAndRestoreKeepsRenamesWithCalculatorState() throws {
        let sessionStore = InMemorySessionStore()
        let viewModel = makeViewModel(sessionStore: sessionStore)
        let triX = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

        viewModel.selectPresetFilm(triX)
        viewModel.baseShutter = 1.0 / 60.0
        viewModel.ndStop = 4
        viewModel.setCameraSlotCustomName("Hasselblad 500CM", for: .camera1)

        viewModel.selectCameraSlot(.camera3)
        viewModel.baseShutter = 1.0 / 8.0
        viewModel.ndStop = 10
        viewModel.setCameraSlotCustomName("Mamiya 7", for: .camera3)

        viewModel.selectCameraSlot(.camera1)

        let restored = makeViewModel(sessionStore: sessionStore)
        XCTAssertEqual(restored.activeCameraSlotID, .camera1)
        XCTAssertEqual(restored.activeCameraSlot.displayName, "Hasselblad 500CM")
        XCTAssertEqual(restored.selectedPresetFilm?.id, triX.id)
        XCTAssertEqual(restored.baseShutter, 1.0 / 60.0, accuracy: 1e-9)

        let camera3Page = restored.cameraSlotPageState(for: .camera3)
        XCTAssertEqual(camera3Page.cameraDisplayName, "Mamiya 7")
        XCTAssertEqual(camera3Page.baseShutter, 1.0 / 8.0, accuracy: 1e-9)
        XCTAssertEqual(camera3Page.ndStep.stops, 10, accuracy: 1e-9)

        // Untouched slots round-trip with no custom name.
        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera2).displayName,
            "Camera 2"
        )
        XCTAssertEqual(
            restored.cameraSlotIdentity(for: .camera4).displayName,
            "Camera 4"
        )
    }

    // MARK: - Helpers

    private func makeViewModel(
        sessionStore: CameraSlotSessionPersistenceStoring = NoOpCameraSlotSessionPersistenceStore(),
        legacyStore: ExposureCalculatorContextStoring = NoOpCalculatorContextStore()
    ) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            contextPersistenceStore: legacyStore,
            cameraSlotSessionPersistenceStore: sessionStore
        )
    }
}

/// Schema-version-aware in-memory session store. Mirrors the
/// `UserDefaultsCameraSlotSessionStore` semantics so the
/// load path under test rejects unknown schema versions even in
/// tests.
private final class InMemorySessionStore: CameraSlotSessionPersistenceStoring {
    private var stored: PersistentCameraSlotSessionSnapshot?

    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? {
        guard let snapshot = stored,
              snapshot.schemaVersion == PersistentCameraSlotSessionSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) {
        stored = snapshot
    }

    func clearSnapshot() {
        stored = nil
    }
}

private final class InMemoryContextStore: ExposureCalculatorContextStoring {
    private var stored: PersistentCalculatorContextSnapshot?

    func loadSnapshot() -> PersistentCalculatorContextSnapshot? {
        stored
    }

    func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot) {
        stored = snapshot
    }

    func clearSnapshot() {
        stored = nil
    }
}
