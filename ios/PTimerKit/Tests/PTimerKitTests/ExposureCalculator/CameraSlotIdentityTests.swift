// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

/// Unit tests for the camera-slot identity domain type. The display
/// name carries a deliberate split between `defaultDisplayName` and
/// `customDisplayName` so rename / reset can change the visible slot
/// label without changing stable slot identity.
final class CameraSlotIdentityTests: XCTestCase {

    func testDefaultIdentityFallsBackToCanonicalLabel() {
        let identity = CameraSlotIdentity(id: .camera2)

        XCTAssertEqual(identity.defaultDisplayName, "Camera 2")
        XCTAssertNil(identity.customDisplayName)
        XCTAssertEqual(identity.displayName, "Camera 2")
    }

    func testCustomDisplayNameWinsOverDefault() {
        let identity = CameraSlotIdentity(
            id: .camera1,
            customDisplayName: "Hasselblad 500CM"
        )

        XCTAssertEqual(identity.defaultDisplayName, "Camera 1")
        XCTAssertEqual(identity.customDisplayName, "Hasselblad 500CM")
        XCTAssertEqual(identity.displayName, "Hasselblad 500CM")
    }

    func testWhitespaceCustomNameFallsBackToDefault() {
        let identity = CameraSlotIdentity(
            id: .camera3,
            customDisplayName: "   "
        )

        XCTAssertEqual(identity.displayName, "Camera 3")
    }

    func testNilCustomNameFallsBackToDefault() {
        let identity = CameraSlotIdentity(id: .camera4, customDisplayName: nil)
        XCTAssertEqual(identity.displayName, "Camera 4")
    }

    func testCustomDisplayNameIsTrimmedWhenRendered() {
        let identity = CameraSlotIdentity(
            id: .camera2,
            customDisplayName: "  Leica M6  "
        )

        XCTAssertEqual(identity.displayName, "Leica M6")
    }

    func testConvenienceInitMapsDefaultLabelToNoCustomName() {
        // A caller that already had a single combined "displayName"
        // (e.g., persisted timer metadata) restores back into the
        // split shape via the convenience init. When the supplied
        // name equals the canonical default, no custom name should
        // be recorded — clearing later would hide a phantom value.
        let identity = CameraSlotIdentity(id: .camera2, displayName: "Camera 2")

        XCTAssertEqual(identity.defaultDisplayName, "Camera 2")
        XCTAssertNil(identity.customDisplayName)
        XCTAssertEqual(identity.displayName, "Camera 2")
    }

    func testConvenienceInitMapsDifferingNameIntoCustomSlot() {
        let identity = CameraSlotIdentity(id: .camera2, displayName: "Hasselblad 500CM")

        XCTAssertEqual(identity.defaultDisplayName, "Camera 2")
        XCTAssertEqual(identity.customDisplayName, "Hasselblad 500CM")
        XCTAssertEqual(identity.displayName, "Hasselblad 500CM")
    }
}
