import Foundation
import PTimerKit
import PTimerCore
@testable import PTimer

/// Scenario runner with deterministic time. Builds a fully-spied
/// `ViewModelDependencies` whose collaborators all funnel into a
/// shared `RecordReplayRecorder`, plus exposes a mutable virtual
/// clock so scenarios advance time without `XCTWaiter` flakiness.
///
/// The harness deliberately does *not* drive the ViewModel or
/// TimerManager directly — scenarios construct the ViewModel and
/// invoke its public surface (start, pause, etc.) themselves. The
/// harness only owns the seam (clock, recorder, spies).
@MainActor
final class RecordReplayHarness {
    let recorder = RecordReplayRecorder()
    let referenceDate: Date

    /// Mutable virtual clock. Scenarios call `advance(by:)` to move
    /// time forward and then invoke `tick()` on TimerManager (or
    /// any other entry point) to make the ViewModel observe the
    /// new wall time.
    private(set) var virtualNow: Date

    private let calculator: ExposureCalculator
    private let presetFilms: [FilmIdentity]
    private let timerManager: TimerManager
    private let lockScreenExposer: RecordingLockScreenExposer

    init(
        referenceDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        presetFilms: [FilmIdentity] = LaunchPresetFilmCatalog.films
    ) {
        self.referenceDate = referenceDate
        self.virtualNow = referenceDate
        self.calculator = ExposureCalculator()
        self.presetFilms = presetFilms

        let recorder = self.recorder
        let lockScreenExposer = RecordingLockScreenExposer(
            recorder: recorder,
            referenceDate: referenceDate
        )
        self.lockScreenExposer = lockScreenExposer

        // The harness retains itself via closure capture for the
        // dateProvider; that's fine because the harness's lifetime
        // matches the scenario.
        var clockBox: () -> Date = { referenceDate }
        let timerManager = TimerManager(
            // Disable the auto-firing real Timer by keeping the loop
            // logically valid but forcing scenarios to drive time
            // through `tick(now:)`. A tiny tick interval keeps the
            // RunLoop-attached timer technically operational; we just
            // never observe it because scenarios advance the virtual
            // clock and call `tick(now:)` explicitly.
            tickInterval: 3600,
            dateProvider: { clockBox() },
            completionAlertService: NoOpTimerCompletionAlertService(),
            completionNotificationScheduler: RecordingTimerCompletionScheduler(
                recorder: recorder,
                referenceDate: referenceDate
            ),
            persistenceStore: RecordingTimerPersistenceStore(
                recorder: recorder,
                referenceDate: referenceDate
            )
        )
        self.timerManager = timerManager

        // Wire the clock closure to read from this harness's mutable
        // `virtualNow`. The closure is captured by reference via
        // `self` so subsequent `advance(by:)` calls are visible to
        // the timer manager.
        clockBox = { [weak self] in
            self?.virtualNow ?? referenceDate
        }
    }

    /// Builds a fully-spied dependency set. The persistence stores
    /// for ExposureCalculator context and timer metadata are NoOp
    /// (those surfaces are out of scope for this record-replay
    /// coverage; spies can be added when needed).
    func makeDependencies() -> ViewModelDependencies {
        ViewModelDependencies(
            calculator: calculator,
            timerManager: timerManager,
            presetFilms: presetFilms,
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: NoOpCameraSlotSessionPersistenceStore(),
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            lockScreenTargetExposer: lockScreenExposer,
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    /// Direct access to the underlying TimerManager for scenarios
    /// that need to drive ticks at specific virtual times.
    var underlyingTimerManager: TimerManager { timerManager }

    /// Advances the virtual clock by `delta` seconds. Does **not**
    /// auto-tick — scenarios decide when to invoke
    /// `timerManager.tick(now:)` to let the ViewModel observe the
    /// new state.
    func advance(by delta: TimeInterval) {
        virtualNow = virtualNow.addingTimeInterval(delta)
    }

    /// Advances the clock to a specific offset from the reference
    /// date.
    func advance(to offsetFromReference: TimeInterval) {
        virtualNow = referenceDate.addingTimeInterval(offsetFromReference)
    }

    /// Convenience: advance the clock and immediately tick the
    /// TimerManager so any state transitions are observed.
    func advanceAndTick(by delta: TimeInterval) {
        advance(by: delta)
        timerManager.tick(now: virtualNow)
    }
}
