import XCTest
@testable import PTimer

/// End-to-end smoke test for the record-replay infrastructure.
/// Drives a single timer through start → completion against a
/// fully-spied dependency set and asserts the captured event trace
/// matches a committed baseline.
///
/// The scenario uses a fixed UUID and `TimerManager.start(id:duration:)`
/// directly (rather than `viewModel.startTimer(from:)` which would
/// allocate a fresh UUID via `UUID()`) so the trace is reproducible
/// across runs. Higher-level scenarios that exercise the ViewModel
/// metadata path will need to inject UUIDs another way; that is left
/// to whichever B1/B4 task introduces the requirement.
final class RecordReplayBaselineSmokeTests: XCTestCase {

    @MainActor
    func testSingleTimerStartCompletePublishesExposerCallSequence() {
        let harness = RecordReplayHarness()
        let viewModel = ExposureCalculatorViewModel(
            dependencies: harness.makeDependencies()
        )
        // Reading from `viewModel.timers` here would silence the
        // "viewModel is unused" warning if this assertion were the
        // only consumer; we want the ViewModel observed end-to-end
        // so we keep an explicit reference and a trivial check.
        XCTAssertTrue(viewModel.timers.isEmpty)

        let fixedTimerID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        // 1. Start a 60s timer at t=0.
        _ = harness.underlyingTimerManager.start(
            id: fixedTimerID,
            duration: 60
        )

        // 2. Advance 60s and tick to drive the running→completed
        //    transition. The TimerManager's internal RunLoop timer
        //    is configured with a 1-hour interval so it does not
        //    fire spontaneously inside this short test.
        harness.advanceAndTick(by: 60)

        // 3. Assert the trace matches the baseline.
        RecordReplayBaseline.assert(harness.recorder, named: "single-timer-start-complete")
    }
}
