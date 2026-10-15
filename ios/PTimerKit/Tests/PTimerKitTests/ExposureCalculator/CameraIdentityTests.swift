// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

/// Camera identity and naming rules (CAMERA-004, CAMERA-NAME-001/003).
final class CameraIdentityTests: XCTestCase {
    func testLegacyIdentitiesKeepTheirRawValuesVerbatim() {
        XCTAssertEqual(
            CameraSlotID.legacyOrdered.map(\.rawValue),
            ["camera1", "camera2", "camera3", "camera4"]
        )
        XCTAssertEqual(CameraSlotID(rawValue: "camera2"), .camera2)
    }

    func testBlankRawIdentityIsRejected() {
        XCTAssertNil(CameraSlotID(rawValue: ""))
        XCTAssertNil(CameraSlotID(rawValue: "  "))
    }

    func testIdentityRoundTripsAsAPlainString() throws {
        let data = try JSONEncoder().encode([CameraSlotID.camera3])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"camera3\"]")
        XCTAssertEqual(try JSONDecoder().decode([CameraSlotID].self, from: data), [.camera3])
        XCTAssertThrowsError(try JSONDecoder().decode([CameraSlotID].self, from: Data("[\"\"]".utf8)))
    }

    func testGeneratedIdentitiesAreUniqueAndNeverALegacyIdentity() {
        let generated = (0..<200).map { _ in CameraSlotID.generate() }
        XCTAssertEqual(Set(generated).count, generated.count)
        XCTAssertTrue(Set(generated).isDisjoint(with: CameraSlotID.legacyOrdered))
    }

    func testIdentityRestoredWithoutAStoredNameFallsBackToTheLegacyLabel() {
        XCTAssertEqual(CameraSlotIdentity(id: .camera2, displayName: nil as String?).displayName, "Camera 2")
        let generated = CameraSlotID.generate()
        XCTAssertEqual(CameraSlotIdentity(id: generated, displayName: "  " as String?).displayName, generated.rawValue)
        XCTAssertEqual(CameraSlotIdentity(id: .camera1, displayName: " Leica " as String?).displayName, "Leica")
    }

    func testDefaultNameIsTheLocalizedCameraNumber() {
        XCTAssertEqual(CameraNaming.defaultName(number: 1), "Camera 1")
        XCTAssertEqual(CameraNaming.defaultName(number: 5), "Camera 5")
        XCTAssertEqual(CameraNaming.defaultName(number: 120), "Camera 120")
    }

    func testTrimmedNameRejectsBlankInput() {
        XCTAssertEqual(CameraNaming.trimmedName("  Leica M6 \n"), "Leica M6")
        XCTAssertNil(CameraNaming.trimmedName(""))
        XCTAssertNil(CameraNaming.trimmedName("   "))
        XCTAssertNil(CameraNaming.trimmedName(nil))
    }
}
