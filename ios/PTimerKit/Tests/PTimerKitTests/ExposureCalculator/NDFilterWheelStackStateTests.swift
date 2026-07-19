// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199: state tests for the 1–4 ND filter wheel stack on
/// `CalculatorModel` — add/remove commands, availability rules, the
/// effective (summed) `ndStep` surface, per-wheel commits with the
/// post-commit sort, per-wheel live preview, budget-truncated
/// ladders, and scale-flip re-snapping across all wheels.
final class NDFilterWheelStackStateTests: XCTestCase {
    @MainActor
    private func makeModel() -> CalculatorModel {
        CalculatorModel(calculator: ExposureCalculator())
    }

    private func steps(_ stops: [Double]) -> [NDStep] {
        stops.map(NDStep.init(stops:))
    }

    // MARK: C1 enforcement on the add command

    @MainActor
    func testAddFilterWheelCommandRefusedWhenNewWheelCouldHoldNoValue() {
        // 16.6 + 13 = 29.6 leaves 0.4 stop — below every ladder value
        // above 0, so the command itself must refuse, not just the UI
        // affordance.
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 16.6), at: 0)
        model.setNDFilterStep(NDStep(stops: 13), at: 1)
        XCTAssertFalse(model.canAddFilterWheel)

        model.addFilterWheel()

        XCTAssertEqual(model.ndFilterSteps.count, 2)
    }

    @MainActor
    func testAddFilterWheelCommandRefusedAtBudgetSaturation() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 29), at: 0)
        model.setNDFilterStep(NDStep(stops: 1), at: 1)
        // Sum 30: a new wheel could never hold a value.
        model.addFilterWheel()

        XCTAssertEqual(model.ndFilterSteps.count, 2)
    }

    // MARK: Defaults and the effective ndStep surface

    @MainActor
    func testModelStartsWithSingleZeroWheel() {
        let model = makeModel()

        XCTAssertEqual(model.ndFilterSteps, steps([0]))
        XCTAssertTrue(model.canAddFilterWheel)
        XCTAssertFalse(model.canRemoveEmptyFilterWheel, "A single wheel is never removable.")
    }

    @MainActor
    func testNDStepReadsEffectiveSumAndWritesSingleWheel() {
        let model = makeModel()

        // Write = single-filter assignment (replaces the stack).
        model.ndStep = NDStep(stops: 5)
        XCTAssertEqual(model.ndFilterSteps, steps([5]))
        XCTAssertEqual(model.ndStep, NDStep(stops: 5))

        // Read = effective sum across every wheel.
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 3), at: 1)
        XCTAssertEqual(model.ndStep, NDStep(stops: 8))

        // Assigning ndStep collapses back to one wheel.
        model.ndStep = NDStep(stops: 2)
        XCTAssertEqual(model.ndFilterSteps, steps([2]))
    }

    @MainActor
    func testCalculationResultUsesTheEffectiveSum() {
        let model = makeModel()
        model.baseShutterSeconds = 1.0 / 30.0
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 6.6), at: 0)
        model.setNDFilterStep(NDStep(stops: 6.6), at: 1)

        guard case .success(let result) = model.calculationResult else {
            XCTFail("6.6 + 6.6 stops on 1/30 should succeed.")
            return
        }

        // 1/30 × 2^13.2 — the fractional sum feeds the engine
        // unsnapped on the shipping 1/3-stop scale.
        XCTAssertEqual(
            result.resultShutterSeconds,
            (1.0 / 30.0) * pow(2.0, 13.2),
            accuracy: 1e-6
        )
    }

    // MARK: Add

    @MainActor
    func testAddFilterWheelAppendsZeroStopWheelUpToFour() {
        let model = makeModel()
        model.ndStep = NDStep(stops: 10)

        model.addFilterWheel()
        model.addFilterWheel()
        model.addFilterWheel()

        XCTAssertEqual(model.ndFilterSteps, steps([10, 0, 0, 0]))
        XCTAssertFalse(model.canAddFilterWheel)

        // No-op at the maximum.
        model.addFilterWheel()
        XCTAssertEqual(model.ndFilterSteps.count, 4)
    }

    @MainActor
    func testAddedWheelDoesNotChangeTheEffectiveValue() {
        let model = makeModel()
        model.ndStep = NDStep(stops: 6.6)

        model.addFilterWheel()

        XCTAssertEqual(model.ndStep.stops, 6.6, accuracy: 1e-9)
        XCTAssertEqual(model.ndFilterSteps, steps([6.6, 0]))
    }

    // MARK: Per-wheel commit + post-commit sort

    @MainActor
    func testCommitSortsDescendingWithZerosRightmost() {
        let model = makeModel()
        model.addFilterWheel()
        model.addFilterWheel()

        // Wheels [0, 0, 0]: committing 3 on the middle wheel sorts it
        // to the front, zeros trailing.
        model.setNDFilterStep(NDStep(stops: 3), at: 1)
        XCTAssertEqual(model.ndFilterSteps, steps([3, 0, 0]))

        // Committing 10 on a trailing zero wheel sorts above the 3.
        model.setNDFilterStep(NDStep(stops: 10), at: 2)
        XCTAssertEqual(model.ndFilterSteps, steps([10, 3, 0]))
    }

    @MainActor
    func testCommitSortKeepsEffectiveSum() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 6.6), at: 1)

        XCTAssertEqual(model.ndFilterSteps, steps([6.6, 0]))
        XCTAssertEqual(model.ndStep.stops, 6.6, accuracy: 1e-9)
    }

    // MARK: Remove

    @MainActor
    func testRemoveEmptyFilterWheelRemovesRightmostZeroWheel() {
        let model = makeModel()
        model.addFilterWheel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 3), at: 1)

        // Post-commit sort makes the stack [3, 0, 0].
        model.removeEmptyFilterWheel()
        XCTAssertEqual(model.ndFilterSteps, steps([3, 0]))

        XCTAssertTrue(model.canRemoveEmptyFilterWheel)
        model.removeEmptyFilterWheel()
        XCTAssertEqual(model.ndFilterSteps, steps([3]))
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
            steps([10, 6]),
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

        XCTAssertEqual(model.ndFilterSteps, steps([0]))
    }

    // MARK: Per-wheel live preview (live wheel + committed others)

    @MainActor
    func testLivePreviewOverlaysOnlyTheDraggingWheel() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 10), at: 0)

        // Stack [10, 0]; dragging wheel 1 to 6 previews 16 without
        // committing anything.
        model.updateLiveNDFilterStep(NDStep(stops: 6), forWheel: 1)

        XCTAssertEqual(model.effectiveNDStep, NDStep(stops: 16))
        XCTAssertEqual(model.ndFilterSteps, steps([10, 0]), "Live preview never commits.")

        model.clearLiveNDStopPreview()
        XCTAssertEqual(model.effectiveNDStep, NDStep(stops: 10))
    }

    @MainActor
    func testLivePreviewEqualToCommittedValueClears() {
        let model = makeModel()
        model.addFilterWheel()
        model.updateLiveNDFilterStep(NDStep(stops: 4), forWheel: 1)
        XCTAssertNotNil(model.liveNDStep)

        model.updateLiveNDFilterStep(NDStep(stops: 0), forWheel: 1)

        XCTAssertNil(model.liveNDStep)
    }

    @MainActor
    func testLegacyWheelZeroLivePreviewKeepsSingleWheelBehavior() {
        let model = makeModel()
        model.ndStep = NDStep(stops: 3)

        model.updateLiveNDStep(NDStep(stops: 7))

        XCTAssertEqual(model.effectiveNDStep, NDStep(stops: 7))

        model.updateLiveNDStep(NDStep(stops: 3))
        XCTAssertNil(model.liveNDStep, "Equal-clears rule is preserved.")
    }

    // MARK: Budget-truncated ladders

    @MainActor
    func testPickerLaddersTruncateToRemainingBudget() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 25), at: 0)

        // Wheel 1's budget: 30 − 25 = 5.
        XCTAssertEqual(model.pickerNDSteps(forWheel: 1).last, NDStep(stops: 5))
        // Wheel 0's own ladder keeps the full cap minus the other
        // wheel (0), so 30 stays selectable.
        XCTAssertEqual(model.pickerNDSteps(forWheel: 0).last, NDStep(stops: 30))
    }

    @MainActor
    func testPickerLadderAtZeroBudgetOffersOnlyZero() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 30), at: 0)

        XCTAssertEqual(model.pickerNDSteps(forWheel: 1), steps([0]))
    }

    // MARK: Add availability (C1)

    @MainActor
    func testAddIsUnavailableWhenTheNewWheelCouldOnlyHoldZero() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 29), at: 0)
        model.setNDFilterStep(NDStep(stops: 1), at: 1)

        // Sum 30: a third wheel's ladder would be [0] only.
        XCTAssertFalse(model.canAddFilterWheel)

        // Freeing one stop re-enables Add (ladder gains a 1).
        model.setNDFilterStep(NDStep(stops: 0), at: 1)
        XCTAssertTrue(model.canAddFilterWheel)
    }

    @MainActor
    func testAddIsUnavailableWhenBudgetIsPositiveButBelowEveryLadderValue() {
        let model = makeModel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 16.6), at: 0)
        model.setNDFilterStep(NDStep(stops: 13), at: 1)

        // Sum 29.6 leaves 0.4 — above zero, but below every integer
        // and preset: the C1 rule hides Add anyway.
        XCTAssertFalse(model.canAddFilterWheel)
    }

    // MARK: Scale-flip sanitation

    @MainActor
    func testScaleFlipOverflowDowngradesRightmostWheelsDeterministically() {
        // Reserved fractional path: a LEGAL third-stop stack summing
        // to exactly 30 whose per-wheel nearest-snap would round up
        // to 31 on the full-stop scale (10⅔ + 10⅔ + 8⅔ → 11+11+9).
        // The overflow policy floors from the rightmost wheel until
        // the sum fits — deterministically [11, 11, 8], never a crash.
        let model = makeModel()
        model.addFilterWheel()
        model.addFilterWheel()
        model.setNDFilterStep(NDStep(stops: 32.0 / 3.0), at: 0)
        model.setNDFilterStep(NDStep(stops: 32.0 / 3.0), at: 1)
        model.setNDFilterStep(NDStep(stops: 26.0 / 3.0), at: 2)

        model.scaleMode = .fullStop

        XCTAssertEqual(model.ndFilterSteps, steps([11, 11, 8]))
        XCTAssertEqual(model.ndStep, NDStep(stops: 30))
    }

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
        // Post-commit sort has moved both presets to the front.
        XCTAssertEqual(model.ndFilterSteps, steps([6.6, 6.6, 0]))
    }
}
