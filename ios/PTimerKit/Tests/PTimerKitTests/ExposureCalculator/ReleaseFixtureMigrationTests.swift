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
/// - `ios-slot-session-dev-main-9213f12a.json`: DEVELOPMENT VERIFICATION
///   fixture for the 0.9.1 migration path (Strategy.md, Spec SHA 8aafc382).
///   Source: the exact merged PR commit at the head of `main` at test start,
///   `9213f12a4ddd81334f304a10e491bba96216a806` (#74), where the iOS
///   MARKETING_VERSION is 0.9.0 / build 1 and the README says 0.9.0, so it is
///   not an official iOS 0.9.1 release fixture. Generated in a throwaway
///   worktree of that commit with
///   `FIXTURE_OUT=<path> swift test --package-path ios/PTimerKit --filter ZZFixtureGenerator`
///   (a one-off XCTest, debug configuration, in-memory session store, Sample
///   Filter Sets seeded through `initialFilterInventory`). It replaces the
///   earlier `8b3b6cdb` payload; the two have the same shape apart from the
///   generated Filter Set ids. When `release/ios/0.9.1` exists, the official
///   fixture and installed-upgrade evidence are regenerated from its target
///   and replace this one.
@MainActor
final class ReleaseFixtureMigrationTests: XCTestCase {

    /// Sample Filter Set ids recorded in the development payload.
    private static let magneticSetID = "93CDA289-2545-4FC2-86D5-57A0E4665242"
    private static let squareSetID = "BAA54436-6F0C-4D90-8125-2BD995C2A11F"
    private static let colorSetID = "8D53C2FC-4E79-418E-AAB7-99A09473BF2F"

    private static func fixture(_ name: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        url.appendPathComponent("shared/test-fixtures/camera-migration/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func release080() throws -> String { try fixture("ios-slot-session-0.8.0-build1-bedd9e10.json") }
    private static func releaseDevelopmentMain() throws -> String { try fixture("ios-slot-session-dev-main-9213f12a.json") }

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

    func testDevelopmentMainFixtureMigrationPreservesFilterSetSelections() throws {
        let inventory = FilterInventory(filterSets: [
            FilterSet(id: FilterSetID(rawValue: Self.magneticSetID), name: "Digital Magnetic Filters", color: .teal),
            FilterSet(id: FilterSetID(rawValue: Self.squareSetID), name: "Film Square ND/GND", color: .purple),
            FilterSet(id: FilterSetID(rawValue: Self.colorSetID), name: "Film Color Filters", color: .orange),
        ])

        let migrated = try migrate(Self.releaseDevelopmentMain(), inventory: inventory)

        XCTAssertEqual(migrated.cameras.map(\.name), ["Nikon Z7", "Hasselblad 503CX", "Nikon F2", "Camera 4"])
        XCTAssertEqual(migrated.snapshotsBySlotID[.camera1]?.candidateFilterSetIDs.map(\.rawValue), [Self.magneticSetID])
        XCTAssertEqual(
            migrated.snapshotsBySlotID[.camera2]?.candidateFilterSetIDs.map(\.rawValue),
            [Self.squareSetID, Self.colorSetID]
        )
        XCTAssertEqual(
            migrated.snapshotsBySlotID[.camera3]?.candidateFilterSetIDs.map(\.rawValue),
            [Self.squareSetID, Self.colorSetID]
        )
        XCTAssertNil(migrated.snapshotsBySlotID[.camera4], "Camera 4 stays at its default.")
        XCTAssertEqual(migrated.snapshotsBySlotID[.camera2]?.targetShutterSeconds, 1800)
    }

    func testBothReleasesInitializeTheSequenceAtFiveAndNameTheNextCameraCameraFive() throws {
        for payload in [try Self.release080(), try Self.releaseDevelopmentMain()] {
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
