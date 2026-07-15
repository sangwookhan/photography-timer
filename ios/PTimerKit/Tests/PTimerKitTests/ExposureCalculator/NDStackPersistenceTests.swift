// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199 M2: persistence tests for the ND filter wheel stack —
/// session round-trip, slot-switch survival, the legacy-scalar
/// maximum rule, Reset semantics, decode isolation for a malformed
/// `ndStack`, and the four corruption fallback cases from the task
/// spec (§7).
@MainActor
final class NDStackPersistenceTests: XCTestCase {

    // MARK: - Round-trip via the ViewModel

    func testStackSurvivesRelaunchRoundTrip() {
        let store = InMemoryStackSessionStore()
        let viewModel = makeViewModel(sessionStore: store)

        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        viewModel.setNDFilterStep(NDStep(stops: 6.6), at: 1)

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(
            restored.ndFilterSteps,
            [NDStep(stops: 10), NDStep(stops: 6.6), NDStep(stops: 0)]
        )
        XCTAssertEqual(restored.ndStep.stops, 16.6, accuracy: 1e-9)
    }

    func testAddOnlyChangeSurvivesRelaunch() {
        let store = InMemoryStackSessionStore()
        let viewModel = makeViewModel(sessionStore: store)

        // Add wheels WITHOUT committing any value: the layout change
        // alone must persist.
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(
            restored.ndFilterSteps,
            [NDStep(stops: 0), NDStep(stops: 0), NDStep(stops: 0)]
        )
    }

    func testRemoveOnlyChangeSurvivesRelaunch() {
        let store = InMemoryStackSessionStore()
        let viewModel = makeViewModel(sessionStore: store)

        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        // [10, 0] persisted; now clean up the empty wheel and nothing
        // else — the removal alone must persist.
        viewModel.cleanupEmptyFilterWheels()

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 10)])
    }

    func testStackSurvivesSlotSwitchAndReturn() {
        let store = InMemoryStackSessionStore()
        let viewModel = makeViewModel(sessionStore: store)

        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 7.6), at: 0)
        viewModel.setNDFilterStep(NDStep(stops: 3), at: 1)

        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 0)],
            "A fresh slot starts with the single default wheel."
        )

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 7.6), NDStep(stops: 3)]
        )
    }

    // MARK: - Delayed auto-removal persists

    func testAutoRemovalResultPersistsAcrossRelaunch() async {
        let store = InMemoryStackSessionStore()
        let viewModel = makeViewModel(sessionStore: store)
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.ndWheelReshapeDuration = 0.02

        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 8), at: 0)
        // Zero out the previously non-zero wheel: [0, 0] with one
        // pending auto-removal.
        viewModel.setNDFilterStep(NDStep(stops: 0), at: 0)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 0)])

        // The auto-removal itself persisted — a relaunch shows one
        // wheel, not the pre-removal pair.
        let restored = makeViewModel(sessionStore: store)
        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 0)])
    }

    // MARK: - Legacy scalar carries the maximum wheel

    func testLegacyScalarFieldsCarryTheExplicitMaximumEntry() throws {
        let store = InMemoryStackSessionStore()
        let viewModel = makeViewModel(sessionStore: store)

        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        // Committed values sort to [6.6, 3, 0]; the maximum is the
        // preset 6.6 → persisted through `ndStopsExact`, not `ndStop`.
        viewModel.setNDFilterStep(NDStep(stops: 3), at: 0)
        viewModel.setNDFilterStep(NDStep(stops: 6.6), at: 1)

        let slot = try XCTUnwrap(
            store.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue }
        )
        XCTAssertEqual(slot.ndStopsExact ?? 0, 6.6, accuracy: 1e-9)
        XCTAssertNil(slot.ndStop, "The preset maximum persists exactly, not as a whole stop.")
        XCTAssertEqual(slot.ndStack?.count, 3)
    }

    // MARK: - Reset semantics

    func testResetReturnsToSingleZeroWheel() {
        let viewModel = makeViewModel()

        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 12), at: 0)

        viewModel.resetFilmModeWorkingContext()

        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 0)])
    }

    // MARK: - Absent stack: legacy scalar restore

    func testAbsentStackRestoresThroughLegacyScalar() throws {
        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [
            persistentSlot(ndStop: 7, ndStack: nil)
        ])

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 7)])
    }

    // MARK: - Corruption case 1/2: decode isolation, end-to-end restore

    func testMalformedStackArrayFallsBackToLegacyScalarEndToEnd() throws {
        // Case 1: the array itself has the wrong type. The whole slot
        // — base shutter included — must still restore, with ND
        // falling back through the legacy scalar.
        let entry = try decodedSlotEntry(json: """
        {"slotIDRaw": "camera1", "baseShutterSeconds": 0.125,
         "ndStop": 5, "ndStack": "corrupted"}
        """)
        XCTAssertNil(entry.ndStack, "A malformed array decodes as absent.")

        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [entry])
        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 5)])
        XCTAssertEqual(restored.baseShutter, 0.125, accuracy: 1e-9)
    }

    func testMalformedStackEntryFallsBackToLegacyScalarEndToEnd() throws {
        // Case 2: one wheel entry has the wrong shape.
        let entry = try decodedSlotEntry(json: """
        {"slotIDRaw": "camera1", "baseShutterSeconds": 0.5,
         "ndStop": 4, "ndStack": [{"ndStop": 4}, {"ndStop": "four"}]}
        """)
        XCTAssertNil(entry.ndStack)

        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [entry])
        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 4)])
        XCTAssertEqual(restored.baseShutter, 0.5, accuracy: 1e-9)
    }

    // MARK: - Conflicting triple: structurally corrupted wheel entries

    func testConflictingExactAndWholeTripleRejectsWholeStack() {
        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [
            persistentSlot(
                ndStop: 8,
                ndStack: [
                    PersistentNDFilterWheelSnapshot(ndStop: 2),
                    // Structurally corrupted: two fields populated.
                    PersistentNDFilterWheelSnapshot(ndStop: 3, ndStopsExact: 6.6),
                ]
            )
        ])

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(
            restored.ndFilterSteps,
            [NDStep(stops: 8)],
            "A conflicting triple invalidates the whole stack, not just the wheel."
        )
    }

    func testConflictingExactAndThirdsTripleRejectsWholeStack() {
        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [
            persistentSlot(
                ndStop: 8,
                ndStack: [
                    PersistentNDFilterWheelSnapshot(ndStop: nil, ndStopThirds: 20, ndStopsExact: 6.6)
                ]
            )
        ])

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 8)])
    }

    // MARK: - Corruption case 3: off-ladder wheel value

    func testOffLadderStackValueRejectsWholeStackAndFallsBackToScalar() {
        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [
            persistentSlot(
                ndStop: 9,
                ndStack: [
                    PersistentNDFilterWheelSnapshot(ndStop: 3),
                    // 5.5 is not a supported commercial preset.
                    PersistentNDFilterWheelSnapshot(ndStop: nil, ndStopsExact: 5.5),
                ]
            )
        ])

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(
            restored.ndFilterSteps,
            [NDStep(stops: 9)],
            "No partial recovery: the whole stack drops to the legacy scalar."
        )
    }

    // MARK: - Corruption case 4: individually valid, sum over 30

    func testOverBudgetStackSumRejectsWholeStackAndFallsBackToScalar() {
        let store = InMemoryStackSessionStore()
        store.stored = sessionSnapshot(slots: [
            persistentSlot(
                ndStop: 12,
                ndStack: [
                    PersistentNDFilterWheelSnapshot(ndStop: nil, ndStopsExact: 16.6),
                    PersistentNDFilterWheelSnapshot(ndStop: nil, ndStopsExact: 16.6),
                ]
            )
        ])

        let restored = makeViewModel(sessionStore: store)

        XCTAssertEqual(restored.ndFilterSteps, [NDStep(stops: 12)])
    }

    // MARK: - Helpers

    private func decodedSlotEntry(json: String) throws -> PersistentCameraSlotCalculatorSnapshot {
        try JSONDecoder().decode(
            PersistentCameraSlotCalculatorSnapshot.self,
            from: Data(json.utf8)
        )
    }

    private func sessionSnapshot(
        slots: [PersistentCameraSlotCalculatorSnapshot]
    ) -> PersistentCameraSlotSessionSnapshot {
        PersistentCameraSlotSessionSnapshot(
            schemaVersion: PersistentCameraSlotSessionSnapshot.currentSchemaVersion,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: slots
        )
    }

    private func persistentSlot(
        ndStop: Int?,
        ndStack: [PersistentNDFilterWheelSnapshot]?
    ) -> PersistentCameraSlotCalculatorSnapshot {
        PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: CameraSlotID.camera1.rawValue,
            selectedPresetFilmID: nil,
            selectedProfileID: nil,
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: ndStop,
            ndStack: ndStack
        )
    }

    private func makeViewModel(
        sessionStore: CameraSlotSessionPersistenceStoring = NoOpCameraSlotSessionPersistenceStore()
    ) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore
        )
    }
}

/// In-memory session store that exposes the stored snapshot so tests
/// can assert on the persisted (on-disk-shaped) fields directly.
private final class InMemoryStackSessionStore: CameraSlotSessionPersistenceStoring {
    var stored: PersistentCameraSlotSessionSnapshot?

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
