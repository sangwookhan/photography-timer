// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199 v2: the ND wheel interaction state machine — fire-time
/// judged self-cleaning (§4.2.2), unresolved-motion tracking, the
/// set-commit barrier, generation validation, and the overscroll
/// entry. Timers run through the view model's test seams; every test
/// asserts on the committed wheel array or the published state,
/// never on timing internals.
@MainActor
final class NDWheelAutoRemovalTests: XCTestCase {
    private func settleWindow(_ seconds: Double = 0.4) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Simulates a user scroll passing a row (owned-picker polling).
    private func observeRow(
        _ viewModel: ExposureCalculatorViewModel, _ stops: Double, wheel index: Int
    ) {
        viewModel.ndWheelDidObserveRow(
            NDStep(stops: stops),
            wheelID: viewModel.ndFilterWheelIDs[index],
            generation: viewModel.ndWheelGeneration
        )
    }

    /// Simulates a user selection concluding (owned-picker
    /// didSelectRow).
    private func select(
        _ viewModel: ExposureCalculatorViewModel, _ stops: Double, wheel index: Int
    ) {
        viewModel.ndWheelDidSelect(
            NDStep(stops: stops),
            wheelID: viewModel.ndFilterWheelIDs[index],
            generation: viewModel.ndWheelGeneration
        )
    }

    // MARK: A1/A2 — idle cleanup, fire-time judged

    func testZeroedWheelCleansUpAfterGracePeriod() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        // [10, 0] — a cleanable zero exists; the timer is armed.

        await settleWindow()

        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
        XCTAssertFalse(viewModel.isNDWheelCleanupPending)
    }

    func testAddedZeroWheelIsAlsoCleanedUp() async {
        // Wheel origin is not tracked — a wheel added through the
        // Add control is just as ephemeral as a zeroed-out one.
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05

        viewModel.addFilterWheel()

        await settleWindow()
        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 0)],
            "All-zero stacks keep exactly one wheel."
        )
    }

    func testCleanupRemovesAllZerosAtOnce() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        // [10, 0, 0]

        await settleWindow()

        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
    }

    func testAllZeroStackKeepsExactlyOneWheel() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        // [0, 0, 0, 0]

        await settleWindow()

        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 0)])
    }

    // MARK: A0 — budget saturation cleans inside the barrier

    func testBudgetSaturationCleansImmediatelyWithoutGracePeriod() {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 29), at: 0)
        // [29, 0, 0] — below the cap, zeros wait on the timer.
        XCTAssertEqual(viewModel.ndFilterSteps.count, 3)

        // Committing 1 saturates the cap (29 + 1 = 30): the barrier
        // sheds the leftover zero in the same set commit.
        viewModel.setNDFilterStep(NDStep(stops: 1), at: 1)

        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 29), NDStep(stops: 1)]
        )
    }

    // MARK: Fire-time judgment (v2 §8 — no cancellation concept)

    func testScrollingDefersCleanupUntilQuiet() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.05)  // leave RESHAPING
        // [10, 0]; grace timer armed. A scroll starts on the zero:
        observeRow(viewModel, 3, wheel: 1)
        XCTAssertEqual(viewModel.ndWheelInteractionState, .scrolling)

        // The timer fires while scrolling: it must re-arm, not
        // remove a wheel in motion.
        await settleWindow(0.2)
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)

        // The selection concludes back on 0; after the set commit
        // the zero collects normally.
        select(viewModel, 0, wheel: 1)
        await settleWindow()
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
    }

    func testTouchBlocksCleanupAtFireTime() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.03)  // leave RESHAPING (< cleanup delay)
        let zeroID = viewModel.ndFilterWheelIDs[1]

        // A motionless hold (no row changes) — data-invisible, so
        // the blocking-only touch signal must defer the fire.
        viewModel.ndWheelTouchBegan(
            wheelID: zeroID, generation: viewModel.ndWheelGeneration
        )
        await settleWindow(0.2)
        XCTAssertEqual(
            viewModel.ndFilterSteps.count, 2,
            "A wheel never vanishes under a resting finger."
        )

        viewModel.ndWheelTouchEnded(wheelID: zeroID)
        await settleWindow()
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
    }

    // MARK: Unresolved tracking (v2 §3.1)

    func testReturnToCommittedResolvesWithoutACommit() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.2
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.1)

        // The zero wheel jiggles up and returns to its committed
        // row; no didSelectRow will follow.
        observeRow(viewModel, 1, wheel: 1)
        observeRow(viewModel, 0, wheel: 1)
        XCTAssertEqual(viewModel.ndWheelInteractionState, .scrolling)

        // Resolution ② (row stable on the committed value for S)
        // returns the machine to IDLE without a barrier, and the
        // cleanup then collects the zero.
        await settleWindow(0.6)
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
    }

    func testStableRowAwayFromCommittedStaysUnresolved() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.1)

        // A row resting AWAY from the committed value is a
        // didSelectRow waiting to happen (selectedRow jumps to the
        // target early): the wheel must stay unresolved past S.
        observeRow(viewModel, 3, wheel: 1)
        try? await Task.sleep(nanoseconds: 150_000_000)  // > S seam

        XCTAssertEqual(viewModel.ndWheelInteractionState, .scrolling)
        XCTAssertFalse(viewModel.isNDWheelResolved(viewModel.ndFilterWheelIDs[1]))
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)
    }

    // MARK: Set commit (v2 §3.2/§7)

    func testSetCommitDefersUntilEveryWheelResolves() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        await settleWindow(0.05)  // leave RESHAPING
        // Both wheels in motion:
        observeRow(viewModel, 4, wheel: 0)
        observeRow(viewModel, 3, wheel: 1)

        // Wheel 0 concludes while wheel 1 still moves: recorded, but
        // the committed stack must not change mid-motion.
        select(viewModel, 4, wheel: 0)
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 0), NDStep(stops: 0)])
        // The display already reflects both wheels' current values.
        XCTAssertEqual(viewModel.ndStackTotalDisplayState.totalStopsText, "7")

        // The LAST wheel concludes: the set applies and sorts once.
        select(viewModel, 3, wheel: 1)
        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 4), NDStep(stops: 3)]
        )
    }

    func testSetCommitRejectsOverBudgetSelectionInSettleOrder() async {
        // Frozen ladders can transiently allow a combined selection
        // above 30 stops; the set commit applies in settle order and
        // the domain refuses the overflowing wheel (reject, never
        // clamp).
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        await settleWindow(0.05)  // leave RESHAPING
        observeRow(viewModel, 20, wheel: 0)
        observeRow(viewModel, 20, wheel: 1)

        select(viewModel, 20, wheel: 0)
        select(viewModel, 20, wheel: 1)

        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 20), NDStep(stops: 0)],
            "First-settled wins; the second selection would exceed 30 and reverts."
        )
    }

    // MARK: Structural-mutation gate (IDLE ∧ no touch)

    func testStructuralMutationRefusedWhileAnyMotionOrTouchExists() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.1)
        XCTAssertTrue(viewModel.canAddFilterWheel)
        XCTAssertTrue(viewModel.canRemoveEmptyFilterWheel)

        // Motion: availability drops, the layout slot stays, and the
        // commands are no-ops.
        observeRow(viewModel, 3, wheel: 1)
        XCTAssertFalse(viewModel.canAddFilterWheel)
        XCTAssertTrue(viewModel.showsAddFilterWheelControl)
        XCTAssertFalse(viewModel.canRemoveEmptyFilterWheel)
        viewModel.cleanupEmptyFilterWheels()
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)

        // Conclude and let the machine go quiet.
        select(viewModel, 3, wheel: 1)
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10), NDStep(stops: 3)])
        await settleWindow(0.1)

        // A motionless HOLD alone (no row changes) also blocks the
        // structural commands (v2 §3.3).
        let heldID = viewModel.ndFilterWheelIDs[1]
        viewModel.ndWheelTouchBegan(
            wheelID: heldID, generation: viewModel.ndWheelGeneration
        )
        XCTAssertFalse(viewModel.canAddFilterWheel)
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)

        viewModel.ndWheelTouchEnded(wheelID: heldID)
        XCTAssertTrue(viewModel.canAddFilterWheel)
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.ndFilterSteps.count, 3)
    }

    // MARK: Generation validation (v2 §3.5)

    func testStaleGenerationEventsAreDiscarded() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        let staleGeneration = viewModel.ndWheelGeneration
        let zeroID = viewModel.ndFilterWheelIDs[1]

        // A structural transition bumps the generation.
        await settleWindow()  // cleanup collects the zero -> [10]
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
        XCTAssertNotEqual(viewModel.ndWheelGeneration, staleGeneration)

        // Late callbacks from the previous generation must be inert
        // even though the machine is IDLE now.
        viewModel.ndWheelDidSelect(
            NDStep(stops: 9), wheelID: zeroID, generation: staleGeneration
        )
        viewModel.ndWheelDidObserveRow(
            NDStep(stops: 9), wheelID: zeroID, generation: staleGeneration
        )
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
        XCTAssertEqual(viewModel.ndWheelInteractionState, .idle)
    }

    func testReshapingDropsPickerEvents() {
        let viewModel = makeViewModel()
        viewModel.ndWheelReshapeDuration = 5  // hold the window open
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.ndWheelInteractionState, .reshaping)

        // Events arriving inside the window are programmatic
        // artifacts by definition (input is blocked) — dropped even
        // with a CURRENT generation stamp.
        viewModel.ndWheelDidSelect(
            NDStep(stops: 9),
            wheelID: viewModel.ndFilterWheelIDs[0],
            generation: viewModel.ndWheelGeneration
        )
        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 0), NDStep(stops: 0)]
        )
    }

    // MARK: §4.2.3 — overscroll removal entry

    func testOverscrollRemovesThePulledWheelImmediately() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.1)  // leave RESHAPING; timer still ahead
        // [10, 0, 0]
        let pulledID = viewModel.ndFilterWheelIDs[1]

        viewModel.removeZeroWheelFromOverscroll(at: 1)

        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 10), NDStep(stops: 0)],
            "The gesture removes exactly one wheel, immediately."
        )
        XCTAssertFalse(
            viewModel.ndFilterWheelIDs.contains(pulledID),
            "The PULLED wheel goes, not the rightmost zero — identity drives the removal animation."
        )
    }

    func testOverscrollRefusedWhileAnotherWheelIsUnresolved() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.1)

        observeRow(viewModel, 8, wheel: 0)
        viewModel.removeZeroWheelFromOverscroll(at: 1)

        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)
    }

    func testOverscrollRefusesNonZeroWheelsAndTheLastWheel() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        await settleWindow(0.1)

        // Non-zero wheel: refused.
        viewModel.removeZeroWheelFromOverscroll(at: 0)
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)

        // Remove the zero, then the last wheel: refused even at 0.
        viewModel.removeZeroWheelFromOverscroll(at: 1)
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 10)])
        viewModel.setNDFilterStep(NDStep(stops: 0), at: 0)
        viewModel.removeZeroWheelFromOverscroll(at: 0)
        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 0)])
    }

    // MARK: §4.2.4 — accessibility cleanup command

    func testAccessibilityCleanupRunsTheFullA2RuleInOneAction() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 7), at: 0)
        await settleWindow(0.1)
        // [7, 0, 0]

        viewModel.cleanupEmptyFilterWheels()

        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 7)],
            "One action cleans every zero — no repetition needed."
        )
    }

    // MARK: Availability restoration

    func testFourWheelCleanupRestoresAddAvailability() async {
        let viewModel = makeViewModel()
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        viewModel.setNDFilterStep(NDStep(stops: 6), at: 1)
        viewModel.setNDFilterStep(NDStep(stops: 3), at: 2)
        viewModel.setNDFilterStep(NDStep(stops: 1), at: 3)
        await settleWindow(0.1)
        XCTAssertFalse(viewModel.canAddFilterWheel)

        viewModel.setNDFilterStep(NDStep(stops: 0), at: 3)

        await settleWindow()
        XCTAssertEqual(
            viewModel.ndFilterSteps,
            [NDStep(stops: 10), NDStep(stops: 6), NDStep(stops: 3)]
        )
        XCTAssertTrue(viewModel.canAddFilterWheel)
    }

    // MARK: C1 on the add command

    func testDirectAddCommandCannotBypassTheLadderRule() async {
        let viewModel = makeViewModel()
        viewModel.addFilterWheel()
        viewModel.setNDFilterStep(NDStep(stops: 16.6), at: 0)
        viewModel.setNDFilterStep(NDStep(stops: 13), at: 1)
        await settleWindow(0.1)
        // 29.6 total, 0.4 stop of budget left: refused.
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)

        viewModel.setNDFilterStep(NDStep(stops: 13.4), at: 1)
        await settleWindow(0.1)
        // Saturated at 30: still refused.
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.ndFilterSteps.count, 2)
    }

    // MARK: Helper

    private func makeViewModel() -> ExposureCalculatorViewModel {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: NoOpCameraSlotSessionPersistenceStore()
        )
        // Long default so the fire-time-judged timer never interferes
        // with a test's setup; cleanup-focused tests shorten it
        // explicitly.
        viewModel.ndWheelCleanupDelay = 10
        viewModel.ndWheelResolutionDelay = 0.05
        viewModel.ndWheelResolutionBackstopDelay = 1.0
        viewModel.ndWheelReshapeDuration = 0.02
        return viewModel
    }
}
