// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimer

final class TimerManagerNotificationSchedulingTests: XCTestCase {
    @MainActor
    func testStartSchedulesCompletionNotificationForRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate },
            completionNotificationScheduler: schedulerSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 3))

        XCTAssertEqual(schedulerSpy.authorizationRequestCount, 1)
        XCTAssertEqual(schedulerSpy.scheduledTimers, [
            ScheduledTimerNotification(
                timerID: id,
                endDate: startDate.addingTimeInterval(3),
                status: .running
            ),
        ])
    }

    @MainActor
    func testPauseCancelsPendingCompletionNotification() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionNotificationScheduler: schedulerSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        XCTAssertEqual(schedulerSpy.canceledTimerIDs, [id])
    }

    @MainActor
    func testResumeReschedulesCompletionNotificationUsingNewEndDate() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionNotificationScheduler: schedulerSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(9)
        manager.resume(id: id)

        XCTAssertEqual(schedulerSpy.authorizationRequestCount, 2)
        XCTAssertEqual(schedulerSpy.scheduledTimers, [
            ScheduledTimerNotification(
                timerID: id,
                endDate: startDate.addingTimeInterval(10),
                status: .running
            ),
            ScheduledTimerNotification(
                timerID: id,
                endDate: currentDate.addingTimeInterval(6),
                status: .running
            ),
        ])
        XCTAssertEqual(schedulerSpy.canceledTimerIDs, [id])
    }

    @MainActor
    func testRemoveCancelsRelatedCompletionNotification() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate },
            completionNotificationScheduler: schedulerSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        manager.remove(id: id)

        XCTAssertEqual(schedulerSpy.canceledTimerIDs, [id])
    }

    @MainActor
    func testForegroundCompletionCleansUpStalePendingNotification() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate },
            completionNotificationScheduler: schedulerSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 2))

        manager.tick(now: startDate.addingTimeInterval(2))

        XCTAssertEqual(schedulerSpy.canceledTimerIDs, [id])
    }

    @MainActor
    func testRemoveCompletedTimersCancelsStalePendingNotificationsForCompletedTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionNotificationScheduler: schedulerSpy
        )

        let completedID = try XCTUnwrap(manager.start(duration: 1))
        let pausedID = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: pausedID)
        manager.tick(now: currentDate)
        schedulerSpy.resetHistory()

        manager.removeCompletedTimers()

        XCTAssertEqual(schedulerSpy.canceledTimerIDs, [completedID])
    }

    @MainActor
    func testPausedAndCompletedTimersDoNotLeaveScheduledNotifications() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionNotificationScheduler: schedulerSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 6))

        currentDate = startDate.addingTimeInterval(1)
        manager.pause(id: id)
        manager.tick(now: startDate.addingTimeInterval(10))

        let activeScheduleIDs = schedulerSpy.scheduledTimers
            .map(\.timerID)
            .filter { id in !schedulerSpy.canceledTimerIDs.contains(id) }
        XCTAssertTrue(activeScheduleIDs.isEmpty)
    }

    @MainActor
    func testMultipleTimersScheduleAndCancelUsingDeterministicPerTimerLifecycle() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let schedulerSpy = CompletionNotificationSchedulerSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionNotificationScheduler: schedulerSpy
        )

        let firstID = try XCTUnwrap(manager.start(duration: 2))
        let secondID = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(1)
        manager.pause(id: secondID)
        currentDate = startDate.addingTimeInterval(2)
        manager.tick(now: currentDate)

        XCTAssertEqual(
            schedulerSpy.scheduledTimers.map(\.timerID),
            [firstID, secondID]
        )
        XCTAssertEqual(
            schedulerSpy.canceledTimerIDs,
            [secondID, firstID]
        )
    }
}
