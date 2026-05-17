import XCTest
@testable import PTimer

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

    @MainActor
    func testSetTargetRejectsZero() {
        let model = TargetShutterModel()

        model.setTarget(0)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testSetTargetRejectsNegativeValue() {
        let model = TargetShutterModel()

        model.setTarget(-5)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testSetTargetRejectsNaN() {
        let model = TargetShutterModel()

        model.setTarget(.nan)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testSetTargetRejectsInfinity() {
        let model = TargetShutterModel()

        model.setTarget(.infinity)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testSetTargetWithNilClearsTarget() {
        let model = TargetShutterModel()
        model.setTarget(120)
        XCTAssertTrue(model.isActive)

        model.setTarget(nil)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
    }

    @MainActor
    func testInvalidValueOverPriorValidValueClearsTarget() {
        let model = TargetShutterModel()
        model.setTarget(120)
        XCTAssertTrue(model.isActive)

        model.setTarget(0)

        XCTAssertNil(model.targetSeconds)
        XCTAssertFalse(model.isActive)
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

    @MainActor
    func testInvalidSetTargetDoesNotEraseLastUsed() {
        let model = TargetShutterModel()
        model.setTarget(180)

        model.setTarget(0)

        XCTAssertNil(model.targetSeconds)
        XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 180, accuracy: 0.0001)
    }

    @MainActor
    func testNilSetTargetDoesNotEraseLastUsed() {
        let model = TargetShutterModel()
        model.setTarget(420)

        model.setTarget(nil)

        XCTAssertNil(model.targetSeconds)
        XCTAssertEqual(model.lastUsedTargetSeconds ?? 0, 420, accuracy: 0.0001)
    }
}
