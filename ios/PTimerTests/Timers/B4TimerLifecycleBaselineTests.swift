import XCTest
import PTimerCore
@testable import PTimer

/// Record-replay baselines for timer lifecycle scenarios. Each
/// scenario drives `RecordReplayHarness.underlyingTimerManager`
/// directly with a fixed UUID so the captured trace is deterministic.
///
/// These tests deliberately *only* observe externally-visible side
/// effects (lock-screen exposer, completion notification scheduler,
/// persistence store). The trace format is locked by
/// `RecordReplayBaseline.assert` so internal refactors can prove
/// externally observable behavior remains unchanged.
///
/// Notes on the public surface used:
/// - There is no dedicated `clearCompletedTimers(_:)` API. The closest
///   public equivalent on `TimerManager` is `removeCompletedTimers()`,
///   which deletes every timer whose `status(at:)` is `.completed`.
///   Scenario `completed-clear-then-restart` uses that.
/// - The reactivation reconciliation hook is
///   `reconcileAfterAppBecomesActive(now:)`. Per its contract, it does
///   *not* emit foreground completion alerts, so scenario
///   `reactivation-reconciliation` exercises that branch directly.
final class B4TimerLifecycleBaselineTests: XCTestCase {

    // Distinct fixed UUIDs per scenario keep traces deterministic and
    // also prevent a stray cross-scenario collision from masking a bug.
    private static let timerA = UUID(uuidString: "AAAAAAAA-1111-2222-3333-444444444444")!
    private static let timerB = UUID(uuidString: "BBBBBBBB-1111-2222-3333-444444444444")!

    @MainActor
    func testPauseThenRemoveBaseline() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(viewModel.timers.isEmpty)

        // Start a 60s timer at t=0.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerA,
            duration: 60
        )
        // Advance to t=10 with a tick so the running state is observed
        // before pausing.
        harness.advanceAndTick(by: 10)
        // Pause at t=10.
        harness.underlyingTimerManager.pause(id: Self.timerA)
        // Advance to t=20 (paused timers must not consume wall-clock
        // time per Timer Spec §2).
        harness.advance(by: 10)
        // Remove at t=20.
        harness.underlyingTimerManager.remove(id: Self.timerA)

        RecordReplayBaseline.assert(harness.recorder, named: "pause-then-remove")
    }

    @MainActor
    func testPauseResumeCompleteBaseline() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(viewModel.timers.isEmpty)

        // Start a 60s timer at t=0.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerA,
            duration: 60
        )
        // Advance to t=10 and tick.
        harness.advanceAndTick(by: 10)
        // Pause at t=10. Remaining time = 50.
        harness.underlyingTimerManager.pause(id: Self.timerA)
        // Advance 30s while paused (no tick — paused is frozen).
        harness.advance(by: 30)
        // Resume at t=40. New endDate = t=90.
        harness.underlyingTimerManager.resume(id: Self.timerA)
        // Advance 50s and tick to drive completion at t=90.
        harness.advanceAndTick(by: 50)

        RecordReplayBaseline.assert(harness.recorder, named: "pause-resume-complete")
    }

    @MainActor
    func testMultiTimerStaggeredCompletionBaseline() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(viewModel.timers.isEmpty)

        // Timer A: 60s at t=0, finishes at t=60.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerA,
            duration: 60
        )
        // Advance to t=5 and start Timer B: 90s, finishes at t=95.
        harness.advance(by: 5)
        _ = harness.underlyingTimerManager.start(
            id: Self.timerB,
            duration: 90
        )
        // Advance to t=60 and tick — Timer A completes, Timer B still
        // running with 35s remaining.
        harness.advanceAndTick(by: 55)
        // Advance to t=95 and tick — Timer B completes.
        harness.advanceAndTick(by: 35)

        RecordReplayBaseline.assert(harness.recorder, named: "multi-timer-staggered-completion")
    }

    @MainActor
    func testCompletedClearThenRestartBaseline() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(viewModel.timers.isEmpty)

        // Start a 30s timer and run to completion.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerA,
            duration: 30
        )
        harness.advanceAndTick(by: 30)
        // No public `clearCompletedTimers(_:)` exists; the closest
        // public surface is `removeCompletedTimers()`, which the
        // ViewModel's "clear completed" path also funnels through.
        harness.underlyingTimerManager.removeCompletedTimers()
        // Start a fresh 20s timer with a different UUID and tick a
        // small amount so we record one save/expose cycle.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerB,
            duration: 20
        )
        harness.advanceAndTick(by: 5)

        RecordReplayBaseline.assert(harness.recorder, named: "completed-clear-then-restart")
    }

    @MainActor
    func testPauseWhileNotRunningNoOpBaseline() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(viewModel.timers.isEmpty)

        // Start a 60s timer and let it auto-complete via tick.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerA,
            duration: 60
        )
        harness.advanceAndTick(by: 60)
        // Now attempt to pause the completed timer. Per Timer Spec
        // §1.2 (running ⇄ paused is the only pause edge) and the
        // current `TimerState.pausing(at:)` implementation, this is a
        // no-op transition that nonetheless still triggers the
        // `cancelCompletionNotification` + persistence save events.
        // Capture exactly that observable behavior here so the no-op
        // shape is preserved byte-for-byte.
        harness.underlyingTimerManager.pause(id: Self.timerA)

        RecordReplayBaseline.assert(harness.recorder, named: "pause-while-not-running-noop")
    }

    @MainActor
    func testReactivationReconciliationBaseline() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(viewModel.timers.isEmpty)

        // Start a 60s timer at t=0 and do NOT tick.
        _ = harness.underlyingTimerManager.start(
            id: Self.timerA,
            duration: 60
        )
        // Simulate the app being inactive past completion: the virtual
        // clock jumps to t=120 without any intervening tick.
        harness.advance(by: 120)
        // Reactivation hook reconciles running timers → completed
        // without firing foreground alerts.
        harness.underlyingTimerManager.reconcileAfterAppBecomesActive(
            now: harness.virtualNow
        )

        RecordReplayBaseline.assert(harness.recorder, named: "reactivation-reconciliation")
    }
}
