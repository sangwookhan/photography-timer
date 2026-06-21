// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

final class TargetShutterModelTests: XCTestCase {
    @MainActor
    func testInitialStateIsInactive() {
        let model = TargetShutterModel()

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testSetTargetActivatesModelWithFinitePositiveValue() {
        let model = TargetShutterModel()

        model.setTarget(60)

        XCTAssertEqual(model.targetSeconds ?? 0, 60, accuracy: 0.0001)
        XCTAssertTrue(model.isActive)
    }

    /// Every non-finite-positive input — zero, negative, NaN,
    /// infinity, nil — rejects identically: the model returns to (or
    /// stays in) the inactive state and `targetSeconds` is nil. The
    /// check runs from a fresh model and from a model that previously
    /// held a valid target, so the predicate is exercised in both
    /// arrange-states.
    @MainActor
    func testSetTargetRejectsEveryNonFinitePositiveInput() {
        let invalidInputs: [(label: String, value: Double?)] = [
            ("zero", 0),
            ("negative", -5),
            ("NaN", .nan),
            ("positive infinity", .infinity),
            ("nil", nil),
        ]
        for arrange in ["fresh model", "model holding a prior valid target"] {
            for (label, value) in invalidInputs {
                let model = TargetShutterModel()
                if arrange == "model holding a prior valid target" {
                    model.setTarget(120)
                    XCTAssertTrue(model.isActive, "Arrange step failed for \(label).")
                }

                model.setTarget(value)

                XCTAssertNil(
                    model.targetSeconds,
                    "[\(arrange) / input=\(label)] rejected input must leave targetSeconds nil."
                )
                XCTAssertFalse(
                    model.isActive,
                    "[\(arrange) / input=\(label)] rejected input must leave the model inactive."
                )
            }
        }
    }

    @MainActor
    func testClearReturnsModelToInactiveState() {
        let model = TargetShutterModel()
        model.setTarget(900)
        XCTAssertTrue(model.isActive)

        model.clear()

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testInitializerSanitizesInvalidInputs() {
        let model = TargetShutterModel(targetSeconds: -10)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testInitializerAcceptsValidInputs() {
        let model = TargetShutterModel(targetSeconds: 1200)

        XCTAssertEqual(model.targetSeconds ?? 0, 1200, accuracy: 0.0001)
        XCTAssertTrue(model.isActive)
    }

    // MARK: - Last-used target memory

    @MainActor
    func testLastUsedSeconsStartsNil() {
        let model = TargetShutterModel()
        XCTAssertNil(model.lastUsedTargetSeconds)
    }

    @MainActor
    func testInitializerSeedsLastUsedFromValidValue() {
        let model = TargetShutterModel(targetSeconds: 600)
        XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 600, accuracy: 0.0001)
    }

    @MainActor
    func testInitializerLeavesLastUsedNilForInvalidSeed() {
        let model = TargetShutterModel(targetSeconds: -1)
        XCTAssertNil(model.lastUsedTargetSeconds)
    }

    @MainActor
    func testSetTargetUpdatesLastUsed() {
        let model = TargetShutterModel()

        model.setTarget(120)
        XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 120, accuracy: 0.0001)

        model.setTarget(900)
        XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 900, accuracy: 0.0001)
    }

    @MainActor
    func testClearPreservesLastUsedMemory() {
        let model = TargetShutterModel()
        model.setTarget(300)

        model.clear()

        XCTAssertNil(model.targetSeconds)
        XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 300, accuracy: 0.0001,
                       "Clear must not erase the last positive value the photographer set")
    }

    /// Last-used memory is preserved across every rejecting input
    /// path. The user set a positive target before; whatever invalid
    /// input arrives later must not erase that memory. Same rejection
    /// matrix as `testSetTargetRejectsEveryNonFinitePositiveInput`.
    @MainActor
    func testInvalidSetTargetDoesNotEraseLastUsedMemory() {
        let invalidInputs: [(label: String, value: Double?)] = [
            ("zero", 0),
            ("negative", -1),
            ("NaN", .nan),
            ("positive infinity", .infinity),
            ("nil", nil),
        ]
        for (label, value) in invalidInputs {
            let model = TargetShutterModel()
            model.setTarget(420)
            XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 420, accuracy: 0.0001)

            model.setTarget(value)

            XCTAssertNil(
                model.targetSeconds,
                "[input=\(label)] rejected input must leave targetSeconds nil."
            )
            XCTAssertEqual(
                model.lastUsedTargetSeconds ?? 0,
                420,
                accuracy: 0.0001,
                "[input=\(label)] rejected input must not erase last-used memory."
            )
        }
    }
}
