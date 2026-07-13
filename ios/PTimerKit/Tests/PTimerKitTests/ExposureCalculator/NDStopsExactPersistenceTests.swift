// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit
import PTimerCore

/// PTIMER-209 schema-level guarantees for the additive `ndStopsExact`
/// field: it round-trips the commercial ND presets losslessly through
/// JSON, is omitted for whole/third-stop values (so pre-PTIMER-209
/// records stay backward-compatible and gain no key), takes precedence
/// on restore, and is honored only for the supported preset values.
final class NDStopsExactPersistenceTests: XCTestCase {
    private func json(_ snapshot: PersistentCameraSlotCalculatorSnapshot) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private func roundTrip(
        _ snapshot: PersistentCameraSlotCalculatorSnapshot
    ) throws -> PersistentCameraSlotCalculatorSnapshot {
        let data = try JSONEncoder().encode(snapshot)
        return try JSONDecoder().decode(PersistentCameraSlotCalculatorSnapshot.self, from: data)
    }

    func testPresetRoundTripsThroughJSONExactly() throws {
        let snapshot = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1",
            selectedPresetFilmID: nil,
            selectedProfileID: nil,
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: nil,
            ndStopThirds: nil,
            ndStopsExact: 16.6
        )
        let restored = try roundTrip(snapshot)
        XCTAssertEqual(try XCTUnwrap(restored.ndStopsExact), 16.6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(restored.restoredNDStep).stops, 16.6, accuracy: 1e-9)
    }

    /// Whole-stop and third-stop snapshots must not emit the new key, so
    /// the existing payload shape remains backward-compatible and simply
    /// omits `ndStopsExact`.
    func testNonPresetSnapshotsOmitTheExactKey() throws {
        let whole = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1", selectedPresetFilmID: nil, selectedProfileID: nil,
            baseShutterSeconds: 1.0, ndStop: 4
        )
        XCTAssertFalse(try json(whole).contains("ndStopsExact"))

        let thirdStop = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1", selectedPresetFilmID: nil, selectedProfileID: nil,
            baseShutterSeconds: 1.0, ndStop: nil, ndStopThirds: 4
        )
        XCTAssertFalse(try json(thirdStop).contains("ndStopsExact"))
    }

    /// A pre-PTIMER-209 payload (no `ndStopsExact`) still decodes, and a
    /// present exact value wins over the legacy fields on restore.
    func testRestorePrecedenceAndLegacyDecode() throws {
        let legacyJSON = #"{"slotIDRaw":"camera1","ndStop":4}"#
        let legacy = try JSONDecoder().decode(
            PersistentCameraSlotCalculatorSnapshot.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(legacy.ndStopsExact)
        XCTAssertEqual(try XCTUnwrap(legacy.restoredNDStep).stops, 4, accuracy: 1e-9)

        // Exact field present alongside stale legacy fields → exact wins.
        let mixed = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1", selectedPresetFilmID: nil, selectedProfileID: nil,
            baseShutterSeconds: nil, ndStop: 7, ndStopThirds: 23, ndStopsExact: 7.6
        )
        XCTAssertEqual(try XCTUnwrap(mixed.restoredNDStep).stops, 7.6, accuracy: 1e-9)
    }

    /// The fixed product set is a restore-time invariant: a near-match
    /// normalizes to the canonical preset, and an unsupported off-grid
    /// exact value is ignored (falls through to legacy fields, or
    /// restores to default when there are none) rather than resurfacing
    /// as an arbitrary fractional stop.
    func testUnsupportedExactValueIsIgnoredOnRestore() throws {
        // Near-match → normalized to the canonical preset.
        let near = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1", selectedPresetFilmID: nil, selectedProfileID: nil,
            baseShutterSeconds: nil, ndStop: nil, ndStopThirds: nil, ndStopsExact: 16.600_000_4
        )
        XCTAssertEqual(try XCTUnwrap(near.restoredNDStep).stops, 16.6, accuracy: 1e-9)

        // Unsupported value + a legacy field → ignore exact, use legacy.
        let withLegacy = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1", selectedPresetFilmID: nil, selectedProfileID: nil,
            baseShutterSeconds: nil, ndStop: 5, ndStopThirds: nil, ndStopsExact: 12.4
        )
        XCTAssertEqual(try XCTUnwrap(withLegacy.restoredNDStep).stops, 5, accuracy: 1e-9)

        // Unsupported value with no legacy fields → nil (default on restore).
        let orphan = PersistentCameraSlotCalculatorSnapshot(
            slotIDRaw: "camera1", selectedPresetFilmID: nil, selectedProfileID: nil,
            baseShutterSeconds: nil, ndStop: nil, ndStopThirds: nil, ndStopsExact: 12.4
        )
        XCTAssertNil(orphan.restoredNDStep)
    }

    /// Writer invariant (through the real persistence controller): only
    /// a supported commercial preset is recorded in `ndStopsExact`. An
    /// off-grid value that is not one of the three products (which
    /// cannot arise from the picker, exercised here directly) records
    /// none of the three ND fields, so it cannot resurface as an
    /// arbitrary fractional stop on restore.
    func testWriterRecordsExactOnlyForSupportedPresets() throws {
        let store = InMemoryCameraSlotSessionStore()
        let controller = CameraSlotSessionPersistenceController(sessionStore: store, presetFilms: [])

        func persistedCamera1(ndStep: NDStep) throws -> PersistentCameraSlotCalculatorSnapshot {
            controller.save(
                activeSlotID: .camera1,
                activeSlotSnapshot: CameraSlotCalculatorSnapshot(
                    baseShutterSeconds: 1.0,
                    ndStep: ndStep,
                    scaleMode: .oneThirdStop,
                    selectedPresetFilm: nil,
                    selectedProfileOverride: nil
                ),
                inactiveSnapshots: [:]
            )
            return try XCTUnwrap(store.loadSnapshot()?.slots.first { $0.slotIDRaw == "camera1" })
        }

        // Unsupported off-grid value: none of the three ND fields set.
        let foreign = try persistedCamera1(ndStep: NDStep(stops: 12.4))
        XCTAssertNil(foreign.ndStopsExact)
        XCTAssertNil(foreign.ndStop)
        XCTAssertNil(foreign.ndStopThirds)

        // Supported preset: recorded as the canonical exact value only.
        let preset = try persistedCamera1(ndStep: NDStep(stops: 16.6))
        XCTAssertEqual(try XCTUnwrap(preset.ndStopsExact), 16.6, accuracy: 1e-9)
        XCTAssertNil(preset.ndStop)
        XCTAssertNil(preset.ndStopThirds)
    }
}

/// Minimal in-memory session store for the writer-invariant test.
private final class InMemoryCameraSlotSessionStore: CameraSlotSessionPersistenceStoring {
    private var stored: PersistentCameraSlotSessionSnapshot?
    func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { stored }
    func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) { stored = snapshot }
    func clearSnapshot() { stored = nil }
}
