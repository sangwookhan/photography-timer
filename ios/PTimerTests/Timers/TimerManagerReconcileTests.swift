// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimer

final class TimerManagerReconcileTests: XCTestCase {
    @MainActor
    func testReconcileAfterAppBecomesActiveKeepsStillRunningTimerRunningWithRefreshedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.reconcile()

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .running)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
    }

    @MainActor
    func testReconcileAfterAppBecomesActiveCompletesExpiredRunningTimerWithoutReplayingCompletionAlert() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionAlertService: alertSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 3))

        currentDate = startDate.addingTimeInterval(5)
        manager.reconcile()

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .completed)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertTrue(alertSpy.events.isEmpty)
    }

    @MainActor
    func testReconcileAfterAppBecomesActiveKeepsPausedTimerUnchanged() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(20)
        manager.reconcile()

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .paused)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
    }

    @MainActor
    func testReconcileAfterAppBecomesActiveKeepsMultipleTimersConsistentAcrossStatuses() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionAlertService: alertSpy
        )

        let runningID = try XCTUnwrap(manager.start(duration: 10))
        let completingID = try XCTUnwrap(manager.start(duration: 3))
        let pausedID = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: pausedID)

        currentDate = startDate.addingTimeInterval(5)
        manager.reconcile()

        let runningTimer = tryUnwrapTimer(withID: runningID, from: manager.timers)
        let completedTimer = tryUnwrapTimer(withID: completingID, from: manager.timers)
        let pausedTimer = tryUnwrapTimer(withID: pausedID, from: manager.timers)

        XCTAssertEqual(runningTimer.status(at: currentDate), .running)
        XCTAssertEqual(runningTimer.remainingTime(at: currentDate), 5, accuracy: 0.0001)
        XCTAssertEqual(completedTimer.status(at: currentDate), .completed)
        XCTAssertEqual(completedTimer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertEqual(pausedTimer.status(at: currentDate), .paused)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 8, accuracy: 0.0001)
        XCTAssertTrue(alertSpy.events.isEmpty)
    }
}
