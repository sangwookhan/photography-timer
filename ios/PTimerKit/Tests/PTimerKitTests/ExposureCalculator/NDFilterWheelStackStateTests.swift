// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199 M1a: state tests for the 1–4 ND filter wheel stack on
/// `CalculatorModel` — add/remove commands, availability rules, the
/// wheel-0 `ndStep` proxy, and scale-flip re-snapping across all
/// wheels. Summation into one effective value is covered by the M1b
/// slice's tests.
final class NDFilterWheelStackStateTests: XCTestCase {
    @MainActor
    private func makeModel() -> CalculatorModel {
        CalculatorModel(calculator: ExposureCalculator())
    }

    // MARK: Defaults and the wheel-0 proxy

    @MainActor
    func testModelStartsWithSingleZeroWheel() {
        let model = makeModel()

        XCTAssertEqual(model.ndFilterSteps, [NDStep(stops: 0)])
        XCTAssertTrue(model.canAddFilterWheel)
        XCTAssertFalse(model.canRemoveEmptyFilterWheel, "A single wheel is never removable.")
    }

    @MainActor
    func testNDStepReadsAndWritesWheelZero() {
        let model = makeModel()

        model.ndStep = NDStep(stops: 5)

        XCTAssertEqual(model.ndFilterSteps[0], NDStep(stops: 5))
        XCTAssertEqual(model.ndStep, NDStep(stops: 5))

        model.setNDFilterStep(NDStep(stops: 7), at: 0)
        XCTAssertEqual(model.ndStep, NDStep(stops: 7))
    }

    // MARK: Add

    @MainActor
    func testAddFilterWheelAppendsZeroStopWheelUpToFour() {
        let model = makeModel()
        model.ndStep = NDStep(stops: 10)

        model.addFilterWheel()
        model.addFilterWheel()
        model.addFilterWheel()

        XCTAssertEqual(
            model.ndFilterSteps,
            [NDStep(stops: 10), NDStep(stops: 0), NDStep(stops: 0), NDStep(stops: 0)]
        )
        XCTAssertFalse(model.canAddFilterWheel)

        // No-op at the maximum.
        model.addFilterWheel()
        XCTAssertEqual(model.ndFilterSteps.count, 4)
    }

    @MainActor
    func testAddedWheelDoesNotChangeWheelZeroOrCalculationInput() {
        let model = makeModel()
        model.ndStep = NDStep(stops: 6.6)

        model.addFilterWheel()

        XCTAssertEqual(model.ndStep, NDStep(stops: 6.6))
        XCTAssertEqual(model.ndFilterSteps.count, 2)
        XCTAssertEqual(model.ndFilterSteps[1], NDStep(stops: 0))
    }

    // MARK: Remove

    @MainActor
    func testRemoveEmptyFilterWheelRemovesRightmostZeroWheel() {
        let model = makeModel()
        model.addFilterWheel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 3), at: 1)

        // Wheels: [0, 3, 0] — the rightmost zero (index 2) goes first.
        model.removeEmptyFilterWheel()
        XCTAssertEqual(model.ndFilterSteps, [NDStep(stops: 0), NDStep(stops: 3)])

        // Wheels: [0, 3] — wheel 0 is zero, still removable.
        XCTAssertTrue(model.canRemoveEmptyFilterWheel)
        model.removeEmptyFilterWheel()
        XCTAssertEqual(model.ndFilterSteps, [NDStep(stops: 3)])
    }

    @MainActor
    func testRemoveIsNoOpWhenOnlyValueHoldingWheelsRemain() {
        let model = makeModel()
        model.ndStep = NDStep(stops: 10)
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 6), at: 1)

        XCTAssertFalse(model.canRemoveEmptyFilterWheel)
        model.removeEmptyFilterWheel()
        XCTAssertEqual(
            model.ndFilterSteps,
            [NDStep(stops: 10), NDStep(stops: 6)],
            "Wheels holding a value are never removed."
        )
    }

    @MainActor
    func testRemoveIsNoOpAtSingleWheel() {
        let model = makeModel()

        model.removeEmptyFilterWheel()

        XCTAssertEqual(model.ndFilterSteps.count, 1)
    }

    // MARK: Indexed writes

    @MainActor
    func testSetNDFilterStepIgnoresOutOfRangeIndices() {
        let model = makeModel()

        model.setNDFilterStep(NDStep(stops: 4), at: 1)
        model.setNDFilterStep(NDStep(stops: 4), at: -1)

        XCTAssertEqual(model.ndFilterSteps, [NDStep(stops: 0)])
    }

    // MARK: Scale-flip sanitation

    @MainActor
    func testScaleFlipResnapsEveryWheelNotJustWheelZero() {
        let model = makeModel()
        model.addFilterWheel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 6.6), at: 1)
        model.setNDFilterStep(NDStep(stops: 6.6), at: 2)

        model.scaleMode = .fullStop

        // The commercial preset sits on both scales' ladders, so a
        // flip preserves it on every wheel (ladder-match branch).
        XCTAssertEqual(model.ndFilterSteps[1], NDStep(stops: 6.6))
        XCTAssertEqual(model.ndFilterSteps[2], NDStep(stops: 6.6))
    }
}
