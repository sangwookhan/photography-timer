// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class ShootingCollectionSummaryPresenterTests: XCTestCase {
    func testMostUsedCameraWinsAndOtherIdentitiesAreCounted() throws {
        let early = try record(start: 0, camera: .init(id: .camera1, displayName: "Nikon F3"))
        let later = try record(start: 60, camera: .init(id: .camera2, displayName: "Leica M6"))
        let latest = try record(start: 120, camera: .init(id: .camera2, displayName: "Leica M6"))
        let display = summary([latest, early, later])
        XCTAssertEqual(display.representativeCameraName, "Leica M6")
        XCTAssertEqual(display.additionalCameraCount, 1)
        XCTAssertEqual(display.recordCount, 3)
    }

    func testEqualCountsUseFirstShotAndStableRecordIdentity() throws {
        let low = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = try record(id: low, start: 60, camera: .init(id: .camera1, displayName: "First"))
        let second = try record(id: high, start: 60, camera: .init(id: .camera2, displayName: "Second"))
        XCTAssertEqual(summary([second, first]).representativeCameraName, "First")
        let earlier = try record(start: 0, camera: .init(id: .camera2, displayName: "Earlier"))
        XCTAssertEqual(summary([first, earlier]).representativeCameraName, "Earlier")
    }

    func testCameraRenameUsesEarliestCapturedNameAndSameNamesKeepSeparateIdentities() throws {
        let old = try record(start: 0, camera: .init(id: .camera1, displayName: "Original"))
        let renamed = try record(start: 60, camera: .init(id: .camera1, displayName: "Renamed"))
        let other = try record(start: 120, camera: .init(id: .camera2, displayName: "Original"))
        let display = summary([renamed, other, old])
        XCTAssertEqual(display.representativeCameraName, "Original")
        XCTAssertEqual(display.additionalCameraCount, 1)
    }

    func testTimeSpanUsesActualLatestTerminalAndFlagsMissingValues() throws {
        let earlier = try record(start: 86_390, end: 90_000)
        let later = try record(start: 86_410, end: 86_500)
        let missing = try record(start: 86_450, end: nil)
        let display = summary([later, missing, earlier])
        XCTAssertEqual(display.startDate, Date(timeIntervalSince1970: 86_390))
        XCTAssertEqual(display.endDate, Date(timeIntervalSince1970: 90_000))
        XCTAssertEqual(display.missingEndCount, 1)
    }

    func testEmptyAndManualCollectionsDoNotInventCameraOrEndTime() throws {
        let empty = summary([])
        XCTAssertNil(empty.startDate)
        XCTAssertNil(empty.endDate)
        XCTAssertNil(empty.representativeCameraName)
        XCTAssertEqual(empty.recordCount, 0)
        let manual = summary([try record(start: 0, end: nil)])
        XCTAssertNil(manual.representativeCameraName)
        XCTAssertEqual(manual.missingCameraCount, 1)
        XCTAssertNil(manual.endDate)
        XCTAssertEqual(manual.missingEndCount, 1)
    }

    func testLegacyNameOnlyCameraAndMissingCameraFieldsStayHonest() throws {
        let captured = try record(start: 0, camera: .init(id: .camera1, displayName: "Legacy"))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as? [String: Any])
        var metadata = try XCTUnwrap(root["metadata"] as? [String: Any])
        metadata.removeValue(forKey: "cameraSlotIDRaw")
        root["metadata"] = metadata
        let legacy = try JSONDecoder().decode(PersistentShootingRecord.self, from: JSONSerialization.data(withJSONObject: root))
        let display = summary([legacy, try record(start: 60)])
        XCTAssertEqual(display.representativeCameraName, "Legacy")
        XCTAssertEqual(display.additionalCameraCount, 0)
        XCTAssertEqual(display.missingCameraCount, 1)
    }

    func testMostFrequentCameraWithoutNameStillCountsOtherIdentities() throws {
        let capture = try record(start: 0, camera: .init(id: .camera1, displayName: "Unavailable later"))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as? [String: Any])
        var metadata = try XCTUnwrap(root["metadata"] as? [String: Any])
        metadata.removeValue(forKey: "cameraSlotDisplayName")
        root["metadata"] = metadata
        let unknownName = try JSONDecoder().decode(PersistentShootingRecord.self, from: JSONSerialization.data(withJSONObject: root))
        let named = try record(start: 60, camera: .init(id: .camera2, displayName: "Known"))
        // Equal counts choose the earlier captured camera even if its name was not recorded.
        let display = summary([named, unknownName])
        XCTAssertNil(display.representativeCameraName)
        XCTAssertEqual(display.additionalCameraCount, 1)
        XCTAssertEqual(display.missingCameraCount, 1)
    }

    private func summary(_ records: [PersistentShootingRecord]) -> ShootingCollectionSummaryDisplayState {
        ShootingCollectionSummaryPresenter.display(.init(id: UUID(), title: "Same date", createdAt: Date(), records: records))
    }

    private func record(
        id: UUID = UUID(), start: TimeInterval, end: TimeInterval? = 180,
        camera: CameraSlotIdentity? = nil
    ) throws -> PersistentShootingRecord {
        try XCTUnwrap(PersistentShootingRecord(timer: RunningTimerItem(
            id: id, order: 0, name: "Manual", basisSummary: "Captured", duration: 30,
            startDate: Date(timeIntervalSince1970: start), endDate: end.map(Date.init(timeIntervalSince1970:)),
            pausedRemainingTime: nil, pausedAt: nil, status: .completed, referenceDate: Date(), cameraSlot: camera
        )))
    }
}
