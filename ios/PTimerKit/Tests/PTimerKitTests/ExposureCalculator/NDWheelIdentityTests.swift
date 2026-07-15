// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199 §4.3: stable per-wheel identity on `CalculatorModel`.
/// `ndFilterWheelIDs` stays parallel to `ndFilterSteps` and follows
/// each wheel through the commit sort, so the UI can animate a
/// reorder as wheel movement. Tests assert on id RELATIONSHIPS
/// (which wheel kept which id), never on concrete id values.
final class NDWheelIdentityTests: XCTestCase {
    @MainActor
    private func makeModel() -> CalculatorModel {
        CalculatorModel(calculator: ExposureCalculator())
    }

    private func steps(_ stops: [Double]) -> [NDStep] {
        stops.map(NDStep.init(stops:))
    }

    @MainActor
    func testIDsStayParallelThroughAddCommitAndCleanup() {
        let model = makeModel()

        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 10), at: 0)
        model.addFilterWheel()
        XCTAssertEqual(model.ndFilterWheelIDs.count, model.ndFilterSteps.count)

        model.cleanupEmptyFilterWheels()
        XCTAssertEqual(model.ndFilterWheelIDs.count, model.ndFilterSteps.count)
        XCTAssertEqual(model.ndFilterSteps, steps([10]))
    }

    @MainActor
    func testCommitSortMovesIDsWithTheirWheels() {
        let model = makeModel()
        model.setNDFilterStep(NDStep(stops: 10), at: 0)
        model.addFilterWheel()
        // [10, 0]
        let idOfTen = model.ndFilterWheelIDs[0]
        let idOfNew = model.ndFilterWheelIDs[1]

        // Committing 13 on the second wheel sorts it in front.
        model.setNDFilterStep(NDStep(stops: 13), at: 1)

        XCTAssertEqual(model.ndFilterSteps, steps([13, 10]))
        XCTAssertEqual(
            model.ndFilterWheelIDs,
            [idOfNew, idOfTen],
            "The wheel that was committed carries its id to the front."
        )
    }

    @MainActor
    func testEqualValuesKeepTheirRelativeOrderAndIDs() {
        let model = makeModel()
        model.setNDFilterStep(NDStep(stops: 10), at: 0)
        model.addFilterWheel()
        let idsBefore = model.ndFilterWheelIDs

        // Equal value: the stable sort must not swap the wheels.
        model.setNDFilterStep(NDStep(stops: 10), at: 1)

        XCTAssertEqual(model.ndFilterSteps, steps([10, 10]))
        XCTAssertEqual(model.ndFilterWheelIDs, idsBefore)
    }

    @MainActor
    func testAddAppendsAFreshID() {
        let model = makeModel()
        let existing = model.ndFilterWheelIDs

        model.addFilterWheel()

        XCTAssertEqual(model.ndFilterWheelIDs.count, 2)
        XCTAssertEqual(Array(model.ndFilterWheelIDs.prefix(1)), existing)
        XCTAssertFalse(existing.contains(model.ndFilterWheelIDs[1]))
    }

    @MainActor
    func testIndexedRemovalDropsThePulledWheelID() {
        let model = makeModel()
        model.setNDFilterStep(NDStep(stops: 10), at: 0)
        model.addFilterWheel()
        model.addFilterWheel()
        // [10, 0, 0]
        let ids = model.ndFilterWheelIDs

        // Pulling the LEFT zero removes that wheel's identity; the
        // rightmost zero keeps its own.
        model.removeEmptyFilterWheel(at: 1)

        XCTAssertEqual(model.ndFilterSteps, steps([10, 0]))
        XCTAssertEqual(model.ndFilterWheelIDs, [ids[0], ids[2]])

        // Guards: non-zero wheels and the last wheel are refused.
        model.removeEmptyFilterWheel(at: 0)
        XCTAssertEqual(model.ndFilterWheelIDs, [ids[0], ids[2]])
        model.removeEmptyFilterWheel(at: 1)
        model.setNDFilterStep(NDStep(stops: 0), at: 0)
        model.removeEmptyFilterWheel(at: 0)
        XCTAssertEqual(model.ndFilterSteps.count, 1)
    }

    @MainActor
    func testRemovalDropsTheRightmostZeroWheelID() {
        let model = makeModel()
        model.setNDFilterStep(NDStep(stops: 10), at: 0)
        model.addFilterWheel()
        model.addFilterWheel()
        // [10, 0, 0]
        let survivingIDs = Array(model.ndFilterWheelIDs.prefix(2))

        model.removeEmptyFilterWheel()

        XCTAssertEqual(model.ndFilterSteps, steps([10, 0]))
        XCTAssertEqual(model.ndFilterWheelIDs, survivingIDs)
    }

    @MainActor
    func testRestoreRegeneratesParallelUniqueIDs() {
        let model = makeModel()
        model.restoreNDFilterSteps(steps([7, 3, 0]))

        XCTAssertEqual(model.ndFilterWheelIDs.count, 3)
        XCTAssertEqual(Set(model.ndFilterWheelIDs).count, 3)

        // The reject path also lands on a consistent single wheel.
        model.restoreNDFilterSteps(steps([40]))
        XCTAssertEqual(model.ndFilterSteps.count, 1)
        XCTAssertEqual(model.ndFilterWheelIDs.count, 1)
    }

    @MainActor
    func testLegacySingleAssignmentResetsToOneID() {
        let model = makeModel()
        model.addFilterWheel()
        model.addFilterWheel()

        model.ndStep = NDStep(stops: 5)

        XCTAssertEqual(model.ndFilterSteps, steps([5]))
        XCTAssertEqual(model.ndFilterWheelIDs.count, 1)
    }
}
