// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Migration of the fixed-slot storage shapes of the supported releases into
/// the managed camera list (CAMERA-PERSIST-002/003, Strategy.md "release
/// migration fixtures").
///
/// Provenance (full detail in `shared/test-fixtures/camera-migration/ios-provenance.txt`).
/// - `ios-slot-session-0.8.0-build1-bedd9e10.json`: the official 0.8.0 fixture.
///   iOS marketing version 0.8.0, build 1, from `release/ios/0.8.0` (commit
///   `bedd9e107679437baec4ea68d3e1300cf2aaf535`). The raw bytes the production
///   `UserDefaultsCameraSlotSessionStore` wrote while an app-hosted test, built in
///   the Release configuration, applied the Strategy.md configuration through
///   `ViewModelDependencyFactory.production()`. Not a capture from a
///   store-installed binary.
@MainActor
final class ReleaseFixtureMigrationTests: XCTestCase {

    private static func fixture(_ name: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        url.appendPathComponent("shared/test-fixtures/camera-migration/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func release080() throws -> String { try fixture("ios-slot-session-0.8.0-build1-bedd9e10.json") }

    func testRelease080MigratesToTheManagedList() throws {
        // The 0.8.0 build had no Sample Filter Sets; a later build seeds them,
        // and migration alone must not select any of them for a camera.
        let migrated = try migrate(Self.release080(), inventory: FilterInventory.samples())
        XCTAssertEqual(FilterInventory.samples().filterSets.count, 3, "The inventory under test holds the Sample Filter Sets.")

        XCTAssertEqual(migrated.cameras.map(\.id), [.camera1, .camera2, .camera3, .camera4])
        XCTAssertEqual(migrated.cameras.map(\.name), ["Nikon Z7", "Hasselblad 503CX", "Nikon F2", "Camera 4"])
        XCTAssertTrue(migrated.cameras.allSatisfy(\.isDisplayed))
        XCTAssertEqual(migrated.activeSlotID, .camera1)
        XCTAssertEqual(migrated.issuedIDs, [.camera1, .camera2, .camera3, .camera4])

        let first = try XCTUnwrap(migrated.snapshotsBySlotID[.camera1])
        XCTAssertNil(first.selectedPresetFilm)
        XCTAssertEqual(first.targetShutterSeconds, 120)
        let second = try XCTUnwrap(migrated.snapshotsBySlotID[.camera2])
        XCTAssertEqual(second.selectedPresetFilm?.id, "kodak-tmax-100")
        XCTAssertEqual(second.targetShutterSeconds, 1800)
        XCTAssertEqual(second.baseShutterSeconds, 1.0 / 30.0, accuracy: 1e-12, "The default base shutter the release wrote.")
        let third = try XCTUnwrap(migrated.snapshotsBySlotID[.camera3])
        XCTAssertEqual(third.selectedPresetFilm?.id, "ilford-kentmere-pan-100")
        XCTAssertNil(third.targetShutterSeconds)
        XCTAssertNil(migrated.snapshotsBySlotID[.camera4], "Camera 4 keeps the factory default state.")
        for slot in [first, second, third] {
            XCTAssertTrue(slot.candidateFilterSetIDs.isEmpty, "Migration selects no seeded Sample Filter Set for a camera.")
        }
    }

    func testRelease080InitializesTheSequenceAtFiveAndNamesTheNextCameraCameraFive() throws {
        let payload = try Self.release080()
        let session = InMemoryCameraListSessionStore()
        session.legacy = try JSONDecoder().decode(PersistentCameraSlotSessionSnapshot.self, from: Data(payload.utf8))
        let sequence = InMemoryCameraNameSequenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: session,
            cameraNameSequenceStore: sequence
        )

        XCTAssertEqual(viewModel.cameraList.map(\.name), ["Nikon Z7", "Hasselblad 503CX", "Nikon F2", "Camera 4"])
        let added = try XCTUnwrap(viewModel.addCamera())

        XCTAssertEqual(viewModel.cameraSlotIdentity(for: added)?.displayName, "Camera 5")
        XCTAssertEqual(sequence.result, .value(6))
        XCTAssertEqual(session.legacy, try JSONDecoder().decode(PersistentCameraSlotSessionSnapshot.self, from: Data(payload.utf8)), "The legacy source is never modified.")
    }

    // MARK: - Helpers

    private func migrate(
        _ payload: String,
        inventory: FilterInventory
    ) throws -> CameraSlotSessionPersistenceController.RestoredManagedList {
        let session = InMemoryCameraListSessionStore()
        session.legacy = try JSONDecoder().decode(PersistentCameraSlotSessionSnapshot.self, from: Data(payload.utf8))
        let controller = CameraSlotSessionPersistenceController(
            sessionStore: session,
            presetFilms: LaunchPresetFilmCatalogV2.films,
            currentFilterInventory: { inventory }
        )
        guard case .absent = controller.loadManagedList() else {
            XCTFail("A legacy-only install has no managed payload.")
            throw CocoaError(.fileReadUnknown)
        }
        let restored = try XCTUnwrap(controller.loadSession())
        return controller.migratedList(from: restored)
    }
}
