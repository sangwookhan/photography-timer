// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
import PTimerKit

/// PTIMER-73: foreground pre-alert emission from the runtime tick.
///
/// The runtime emits a haptic-bearing pre-alert event only for the pre1 stage,
/// only on foreground ticks, and exactly once per crossing. pre2 is the
/// not-foreground-only escalation and is never emitted here; background
/// reactivation (`reconcile`) never emits pre-alerts.
final class TimerRuntimeForegroundPreAlertTests: XCTestCase {
    @MainActor
    private func makeRuntime(spy: StagedAlertSpy) -> TimerRuntime {
        TimerRuntime(
            dateProvider: { Date(timeIntervalSince1970: 0) },
            completionAlertService: spy
        )
    }

    @MainActor
    func testLongTimerEmitsPre1OnlyAndNeverPre2InForeground() {
        let spy = StagedAlertSpy()
        let runtime = makeRuntime(spy: spy)
        let id = UUID()

        runtime.start(id: id, duration: 75) // pre1@65, pre2@70, completion@75
        runtime.tick(now: at(60))           // establishes the window baseline
        runtime.tick(now: at(66))           // crosses pre1 (65)
        runtime.tick(now: at(71))           // crosses pre2 (70) — must NOT emit
        runtime.tick(now: at(76))           // completes

        XCTAssertEqual(spy.preAlerts.map(\.stage), [.pre1])
        XCTAssertEqual(spy.preAlerts.first?.secondsBeforeCompletion, 10)
        XCTAssertFalse(spy.preAlerts.contains { $0.stage == .pre2 })
        XCTAssertEqual(spy.completions.count, 1)
    }

    @MainActor
    func testMediumTimerEmitsPre1AtFiveSeconds() {
        let spy = StagedAlertSpy()
        let runtime = makeRuntime(spy: spy)
        let id = UUID()

        runtime.start(id: id, duration: 45) // pre1@40, completion@45
        runtime.tick(now: at(38))
        runtime.tick(now: at(41))           // crosses pre1 (40)

        XCTAssertEqual(spy.preAlerts.map(\.stage), [.pre1])
        XCTAssertEqual(spy.preAlerts.first?.secondsBeforeCompletion, 5)
        XCTAssertEqual(spy.preAlerts.first?.timerID, id)
    }

    @MainActor
    func testShortTimerEmitsNoPreAlerts() {
        let spy = StagedAlertSpy()
        let runtime = makeRuntime(spy: spy)

        runtime.start(id: UUID(), duration: 25) // completion@25 only
        runtime.tick(now: at(10))
        runtime.tick(now: at(20))
        runtime.tick(now: at(26))

        XCTAssertTrue(spy.preAlerts.isEmpty)
        XCTAssertEqual(spy.completions.count, 1)
    }

    @MainActor
    func testPre1EmittedExactlyOnceAcrossManyTicks() {
        let spy = StagedAlertSpy()
        let runtime = makeRuntime(spy: spy)

        runtime.start(id: UUID(), duration: 75)
        // Tick every second across the pre1 crossing instant (65).
        for second in 60...68 {
            runtime.tick(now: at(TimeInterval(second)))
        }

        XCTAssertEqual(spy.preAlerts.filter { $0.stage == .pre1 }.count, 1)
    }

    @MainActor
    func testReconcileDoesNotEmitPreAlerts() {
        let spy = StagedAlertSpy()
        let runtime = makeRuntime(spy: spy)

        runtime.start(id: UUID(), duration: 75)
        runtime.tick(now: at(60))      // baseline
        runtime.reconcile(now: at(72)) // spans pre1 and pre2 crossings, but suppressed

        XCTAssertTrue(spy.preAlerts.isEmpty)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private final class StagedAlertSpy: TimerCompletionAlerting {
    private(set) var completions: [TimerCompletionEvent] = []
    private(set) var preAlerts: [TimerPreAlertEvent] = []

    func handleTimerCompletion(_ event: TimerCompletionEvent) {
        completions.append(event)
    }

    func handlePreAlert(_ event: TimerPreAlertEvent) {
        preAlerts.append(event)
    }
}
