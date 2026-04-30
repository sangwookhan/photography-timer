import XCTest
@testable import PTimer

final class TimerManagerTests: XCTestCase {
    @MainActor
    func testStartAddsMultipleRunningTimers() throws {
        let now = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { now }
        )

        let firstID = try XCTUnwrap(manager.start(duration: 5))
        let secondID = try XCTUnwrap(manager.start(duration: 10))

        XCTAssertEqual(manager.timers.count, 2)
        XCTAssertEqual(manager.timers.map(\.id), [firstID, secondID])
        XCTAssertTrue(manager.timers.allSatisfy { $0.status(at: now) == TimerStatus.running })
        XCTAssertEqual(manager.timers[0].startDate, now)
        XCTAssertEqual(manager.timers[0].endDate, now.addingTimeInterval(5))
        XCTAssertEqual(manager.timers[0].remainingTime(at: now), 5, accuracy: 0.0001)
        XCTAssertEqual(manager.timers[1].remainingTime(at: now), 10, accuracy: 0.0001)
    }

    @MainActor
    func testTickUpdatesEachTimerIndependently() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let firstID = try XCTUnwrap(manager.start(duration: 5))
        let secondID = try XCTUnwrap(manager.start(duration: 8))

        manager.tick(now: startDate.addingTimeInterval(3))

        let firstTimer = tryUnwrapTimer(withID: firstID, from: manager.timers)
        let secondTimer = tryUnwrapTimer(withID: secondID, from: manager.timers)

        let currentDate = startDate.addingTimeInterval(3)
        XCTAssertEqual(firstTimer.remainingTime(at: currentDate), 2, accuracy: 0.0001)
        XCTAssertEqual(secondTimer.remainingTime(at: currentDate), 5, accuracy: 0.0001)
        XCTAssertEqual(firstTimer.status(at: currentDate), TimerStatus.running)
        XCTAssertEqual(secondTimer.status(at: currentDate), TimerStatus.running)
    }

    @MainActor
    func testRemainingTimeCalculationTracksEndDateAndClampsAtZero() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        let timer = tryUnwrapTimer(withID: id, from: manager.timers)

        XCTAssertEqual(timer.remainingTime(at: startDate), 10, accuracy: 0.0001)
        XCTAssertEqual(
            timer.remainingTime(at: startDate.addingTimeInterval(5)),
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            timer.remainingTime(at: startDate.addingTimeInterval(10)),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            timer.remainingTime(at: startDate.addingTimeInterval(14)),
            0,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testTickCompletesExpiredTimerWithoutAffectingOthers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let shortID = try XCTUnwrap(manager.start(duration: 3))
        let longID = try XCTUnwrap(manager.start(duration: 10))

        manager.tick(now: startDate.addingTimeInterval(4))

        let shortTimer = tryUnwrapTimer(withID: shortID, from: manager.timers)
        let longTimer = tryUnwrapTimer(withID: longID, from: manager.timers)

        let currentDate = startDate.addingTimeInterval(4)
        XCTAssertEqual(shortTimer.status(at: currentDate), TimerStatus.completed)
        XCTAssertEqual(shortTimer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertEqual(longTimer.status(at: currentDate), TimerStatus.running)
        XCTAssertEqual(longTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
    }

    @MainActor
    func testCompletionAlertFiresExactlyOnceWhenRunningTimerCompletes() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate },
            completionAlertService: alertSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 3))

        manager.tick(now: startDate.addingTimeInterval(3))

        XCTAssertEqual(alertSpy.events, [
            TimerCompletionEvent(
                timerID: id,
                completionDate: startDate.addingTimeInterval(3)
            )
        ])
    }

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
            )
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
            )
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

    @MainActor
    func testCompletedTimerDoesNotTriggerDuplicateAlertOnRepeatedTickOrReevaluation() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate },
            completionAlertService: alertSpy
        )

        _ = try XCTUnwrap(manager.start(duration: 2))

        manager.tick(now: startDate.addingTimeInterval(2))
        manager.tick(now: startDate.addingTimeInterval(5))
        _ = manager.timers.map { $0.status(at: startDate.addingTimeInterval(8)) }
        _ = manager.timers.map { $0.updatingStatus(at: startDate.addingTimeInterval(8)) }

        XCTAssertEqual(alertSpy.events.count, 1)
    }

    @MainActor
    func testPausedTimerDoesNotTriggerCompletionAlertAfterTimePasses() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionAlertService: alertSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(20)
        manager.tick(now: currentDate)

        XCTAssertTrue(alertSpy.events.isEmpty)
        XCTAssertEqual(
            tryUnwrapTimer(withID: id, from: manager.timers).status(at: currentDate),
            .paused
        )
    }

    @MainActor
    func testPausedTimerDoesNotTriggerCompletionAlert() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionAlertService: alertSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 6))

        currentDate = startDate.addingTimeInterval(1)
        manager.pause(id: id)
        manager.tick(now: startDate.addingTimeInterval(10))

        XCTAssertTrue(alertSpy.events.isEmpty)
    }

    @MainActor
    func testMultipleTimersTriggerSeparateCompletionAlertsAtTheirOwnCompletionTimes() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate },
            completionAlertService: alertSpy
        )

        let firstID = try XCTUnwrap(manager.start(duration: 2))
        let secondID = try XCTUnwrap(manager.start(duration: 5))

        manager.tick(now: startDate.addingTimeInterval(2))
        manager.tick(now: startDate.addingTimeInterval(5))

        XCTAssertEqual(alertSpy.events, [
            TimerCompletionEvent(
                timerID: firstID,
                completionDate: startDate.addingTimeInterval(2)
            ),
            TimerCompletionEvent(
                timerID: secondID,
                completionDate: startDate.addingTimeInterval(5)
            )
        ])
    }

    @MainActor
    func testForegroundAlertServiceOnlyPlaysFeedbackWhileAppIsActive() {
        let feedbackSpy = CompletionFeedbackSpy()
        let activeService = ForegroundTimerCompletionAlertService(
            feedbackPlayer: feedbackSpy,
            applicationStateProvider: { .active }
        )
        let inactiveService = ForegroundTimerCompletionAlertService(
            feedbackPlayer: feedbackSpy,
            applicationStateProvider: { .background }
        )
        let event = TimerCompletionEvent(
            timerID: UUID(),
            completionDate: Date(timeIntervalSince1970: 100)
        )

        activeService.handleTimerCompletion(event)
        inactiveService.handleTimerCompletion(event)

        XCTAssertEqual(feedbackSpy.playCount, 1)
    }

    @MainActor
    func testNotificationIdentifierIsDeterministicFromTimerUUID() {
        let timerID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

        XCTAssertEqual(
            UserNotificationTimerCompletionScheduler.notificationIdentifier(for: timerID),
            "timer-completion-12345678-1234-1234-1234-123456789abc"
        )
    }

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
        manager.reconcileAfterAppBecomesActive()

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
        manager.reconcileAfterAppBecomesActive()

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
        manager.reconcileAfterAppBecomesActive()

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
        manager.reconcileAfterAppBecomesActive()

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

    @MainActor
    func testPauseFreezesRemainingTimeInResumablePausedState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let firstID = try XCTUnwrap(manager.start(duration: 5))
        let secondID = try XCTUnwrap(manager.start(duration: 9))

        currentDate = startDate.addingTimeInterval(2)
        manager.pause(id: firstID)

        let firstTimer = tryUnwrapTimer(withID: firstID, from: manager.timers)
        let secondTimer = tryUnwrapTimer(withID: secondID, from: manager.timers)

        XCTAssertEqual(firstTimer.status(at: currentDate), TimerStatus.paused)
        XCTAssertEqual(firstTimer.remainingTime(at: currentDate), 3, accuracy: 0.0001)

        let laterDate = startDate.addingTimeInterval(4)
        XCTAssertEqual(firstTimer.status(at: laterDate), TimerStatus.paused)
        XCTAssertEqual(firstTimer.remainingTime(at: laterDate), 3, accuracy: 0.0001)
        let pausedRemainingTime = try XCTUnwrap(firstTimer.pausedRemainingTime)
        XCTAssertEqual(pausedRemainingTime, 3, accuracy: 0.0001)
        XCTAssertEqual(secondTimer.status(at: currentDate), TimerStatus.running)
        XCTAssertEqual(secondTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)
    }

    @MainActor
    func testTickDoesNotAdvanceFrozenPausedTimerRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(5)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)

        let muchLaterDate = startDate.addingTimeInterval(30)
        manager.tick(now: muchLaterDate)

        let timerAfterTick = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timerAfterTick.status(at: muchLaterDate), TimerStatus.paused)
        XCTAssertEqual(timerAfterTick.remainingTime(at: muchLaterDate), 7, accuracy: 0.0001)
    }

    @MainActor
    func testPauseAtSixSecondsPreservesApproximatelyFourSecondsRemaining() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(6)
        manager.pause(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), TimerStatus.paused)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 4, accuracy: 0.0001)
    }

    @MainActor
    func testResumeContinuesFromFrozenPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(pausedTimer.status(at: currentDate), .paused)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(7)
        manager.resume(id: id)

        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        let laterDate = currentDate.addingTimeInterval(2)
        XCTAssertEqual(resumedTimer.remainingTime(at: laterDate), 4, accuracy: 0.0001)
    }

    @MainActor
    func testResumeRecalculatesEndDateFromFrozenPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(5)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        let pausedRemaining = try XCTUnwrap(pausedTimer.pausedRemainingTime)
        XCTAssertEqual(pausedRemaining, 7, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(9)
        manager.resume(id: id)

        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)
        XCTAssertEqual(
            resumedTimer.endDate,
            currentDate.addingTimeInterval(pausedRemaining)
        )
    }

    @MainActor
    func testPausedTimerPreservesFrozenStatePauseMetadata() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .paused)
        XCTAssertEqual(timer.startDate, startDate)
        XCTAssertEqual(timer.pausedAt, currentDate)
        XCTAssertEqual(try XCTUnwrap(timer.pausedRemainingTime), 6, accuracy: 0.0001)
    }

    @MainActor
    func testCompletedTimerPreservesOriginalDurationMetadata() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 3))
        let completionDate = startDate.addingTimeInterval(5)
        manager.tick(now: completionDate)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: completionDate), .completed)
        XCTAssertEqual(timer.remainingTime(at: completionDate), 0, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 3, accuracy: 0.0001)
        XCTAssertEqual(timer.startDate, startDate)
        XCTAssertEqual(timer.endDate, startDate.addingTimeInterval(3))
    }

    @MainActor
    func testRemoveCompletedTimersKeepsPausedTimersResumable() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let pausedID = try XCTUnwrap(manager.start(duration: 10))
        let completedID = try XCTUnwrap(manager.start(duration: 1))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: pausedID)
        manager.tick(now: currentDate)
        manager.removeCompletedTimers()

        XCTAssertNil(manager.timers.first { $0.id == completedID })

        let pausedTimer = tryUnwrapTimer(withID: pausedID, from: manager.timers)
        XCTAssertEqual(pausedTimer.status(at: currentDate), .paused)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(8)
        manager.resume(id: pausedID)

        let resumedTimer = tryUnwrapTimer(withID: pausedID, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
    }

    @MainActor
    func testResumeMultipleTimesMaintainsCorrectRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 20))

        currentDate = startDate.addingTimeInterval(5)
        manager.pause(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 15, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(9)
        manager.resume(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 15, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(12)
        manager.pause(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 12, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(30)
        manager.resume(id: id)
        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 12, accuracy: 0.0001)
        XCTAssertEqual(resumedTimer.endDate, currentDate.addingTimeInterval(12))
    }

    @MainActor
    func testResumeAfterLongPauseUsesCorrectRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(10_000)
        manager.resume(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .running)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(timer.endDate, currentDate.addingTimeInterval(6))
    }

    @MainActor
    func testPauseDoesNotModifyEndDateUntilResume() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        let originalEndDate = try XCTUnwrap(tryUnwrapTimer(withID: id, from: manager.timers).endDate)

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(pausedTimer.endDate, originalEndDate)
    }

    @MainActor
    func testPausedTimerEndDateIsDerivedFromFreezeMetadata() throws {
        // PausedTimer.endDate is now computed (`pausedAt +
        // pausedRemainingTime`) rather than stored. Verify the derived
        // value equals the original endDate at the pause boundary, and
        // — unlike the legacy stored field — also equals
        // `pausedAt + pausedRemainingTime` for synthetic paused state
        // constructed via the back-compat init.
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(3)
        manager.pause(id: id)

        let paused = tryUnwrapTimer(withID: id, from: manager.timers)
        let pausedAt = try XCTUnwrap(paused.pausedAt)
        let remaining = try XCTUnwrap(paused.pausedRemainingTime)
        XCTAssertEqual(paused.endDate, pausedAt.addingTimeInterval(remaining))
        XCTAssertEqual(paused.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testPersistedPausedSnapshotOmitsExpectedCompletionAt() throws {
        // Per Timer Spec §3.1, `expectedCompletionAt` is meaningful for
        // running status only. The PersistentTimerSnapshot init now
        // writes nil for paused timers; the hypothetical completion
        // date is reconstructed on read from `pausedAt +
        // pausedRemainingDuration`.
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        let snapshot = PersistentTimerSnapshot(timer: pausedTimer)

        XCTAssertEqual(snapshot.status, .paused)
        XCTAssertNil(snapshot.expectedCompletionAt)
        XCTAssertEqual(snapshot.pausedRemainingDuration, 6)
        XCTAssertEqual(snapshot.pausedAt, startDate.addingTimeInterval(4))
    }

    @MainActor
    func testRestoreLegacyPausedSnapshotIgnoresExpectedCompletionAt() throws {
        // Legacy snapshots (pre-PTIMER-118 epic) wrote
        // `expectedCompletionAt` for paused timers. Restore must
        // ignore that field and reconstruct the hypothetical end
        // date from the freeze metadata so the resumable state is
        // identical regardless of whether the snapshot is legacy or
        // current. Simulate a legacy snapshot via JSON decoding
        // because the in-process initializer no longer accepts a
        // non-nil `expectedCompletionAt` for paused.
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)

        // Legacy JSON deliberately makes expectedCompletionAt point
        // somewhere far from `pausedAt + pausedRemainingDuration`
        // (the legacy stored value could go stale across edits).
        let legacyJSON = #"""
        {
          "id": "DEADBEEF-1111-2222-3333-444444444444",
          "status": "paused",
          "duration": 10,
          "startDate": 100,
          "expectedCompletionAt": 199,
          "pausedRemainingDuration": 6,
          "pausedAt": 104,
          "completedAt": null
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let legacy = try decoder.decode(
            PersistentTimerSnapshot.self,
            from: Data(legacyJSON.utf8)
        )

        let restored = legacy.restore(at: startDate.addingTimeInterval(50))

        XCTAssertEqual(restored.status, .paused)
        XCTAssertEqual(restored.pausedRemainingTime, 6)
        XCTAssertEqual(restored.pausedAt, pausedAt)
        XCTAssertEqual(restored.endDate, pausedAt.addingTimeInterval(6))
    }

    @MainActor
    func testTimerWithLongDurationOneDayCompletesCorrectly() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 86_400))
        manager.tick(now: startDate.addingTimeInterval(86_401))

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: startDate.addingTimeInterval(86_401)), .completed)
        XCTAssertEqual(timer.remainingTime(at: startDate.addingTimeInterval(86_401)), 0, accuracy: 0.0001)
    }

    @MainActor
    func testTimerWithVeryLargeDurationDoesNotOverflow() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 31_536_000))
        let timer = tryUnwrapTimer(withID: id, from: manager.timers)

        XCTAssertTrue(timer.duration.isFinite)
        XCTAssertTrue(try XCTUnwrap(timer.endDate).timeIntervalSince1970.isFinite)

        manager.tick(now: startDate.addingTimeInterval(31_536_001))
        let completedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(completedTimer.status(at: startDate.addingTimeInterval(31_536_001)), .completed)
    }

    @MainActor
    func testCompletedTimerHasDeterministicCompletionTimestamp() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        let completionDate = startDate.addingTimeInterval(12)
        manager.tick(now: completionDate)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: completionDate), .completed)
        XCTAssertEqual(timer.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testNonPositiveDurationIsIgnored() {
        let manager = TimerManager(tickInterval: 60, dateProvider: Date.init)

        let zeroID = manager.start(duration: 0)
        let negativeID = manager.start(duration: -3)

        XCTAssertNil(zeroID)
        XCTAssertNil(negativeID)
        XCTAssertTrue(manager.timers.isEmpty)
    }

    @MainActor
    func testNonFiniteDurationIsIgnored() {
        // Per Timer Spec §1.2 the system rejects creation with non-positive,
        // non-finite, or NaN duration values. `+Infinity` previously slipped
        // past the `> 0` guard because `.infinity > 0` is true, so it now
        // requires an explicit `isFinite` check.
        let manager = TimerManager(tickInterval: 60, dateProvider: Date.init)

        let infiniteID = manager.start(duration: .infinity)
        let negativeInfiniteID = manager.start(duration: -.infinity)
        let nanID = manager.start(duration: .nan)
        let signalingNanID = manager.start(duration: .signalingNaN)

        XCTAssertNil(infiniteID)
        XCTAssertNil(negativeInfiniteID)
        XCTAssertNil(nanID)
        XCTAssertNil(signalingNanID)
        XCTAssertTrue(manager.timers.isEmpty)
    }

    @MainActor
    func testRemoveCompletedTimersRemovesOnlyCompletedEntries() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let completedID = try XCTUnwrap(manager.start(duration: 1))
        let runningID = try XCTUnwrap(manager.start(duration: 5))
        manager.tick(now: startDate.addingTimeInterval(2))

        manager.removeCompletedTimers()

        XCTAssertNil(manager.timers.first { $0.id == completedID })
        XCTAssertNotNil(manager.timers.first { $0.id == runningID })
    }

    @MainActor
    func testRemoveCompletedTimersKeepsPausedTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let pausedID = try XCTUnwrap(manager.start(duration: 10))
        let completedID = try XCTUnwrap(manager.start(duration: 1))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: pausedID)
        manager.tick(now: currentDate)
        manager.removeCompletedTimers()

        let pausedTimer = tryUnwrapTimer(withID: pausedID, from: manager.timers)
        XCTAssertEqual(pausedTimer.status(at: currentDate), TimerStatus.paused)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertNil(manager.timers.first { $0.id == completedID })
    }

    @MainActor
    func testDelayedTickUsesAbsoluteTimeWithoutDrift() {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = manager.start(duration: 5)!

        manager.tick(now: startDate.addingTimeInterval(5.8))

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        let currentDate = startDate.addingTimeInterval(5.8)
        XCTAssertEqual(timer.status(at: currentDate), TimerStatus.completed)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
    }

    @MainActor
    func testCompletedTimerKeepsZeroRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 2))
        let completedDate = startDate.addingTimeInterval(5)
        manager.tick(now: completedDate)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: completedDate), TimerStatus.completed)
        XCTAssertEqual(timer.remainingTime(at: completedDate), 0, accuracy: 0.0001)
        XCTAssertEqual(timer.remainingTime(at: completedDate.addingTimeInterval(20)), 0, accuracy: 0.0001)
    }

    @MainActor
    func testTimerStateResumeReturnsCompletedWhenNoRemainingTime() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(5)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: 0,
            pausedAt: pausedAt,
            status: .paused
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(1))

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.remainingTime(at: pausedAt.addingTimeInterval(1)), 0, accuracy: 0.0001)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
        XCTAssertEqual(resumed.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testTimerStateResumeReturnsRunningWhenPauseWindowHasExpired() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let remainingTime: TimeInterval = 6
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: remainingTime,
            pausedAt: pausedAt,
            status: .paused
        )

        let now = pausedAt.addingTimeInterval(remainingTime + 1)
        let resumed = timer.resume(at: now)

        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.remainingTime(at: now), remainingTime, accuracy: 0.0001)
        XCTAssertNil(resumed.pausedRemainingTime)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertEqual(resumed.endDate, now.addingTimeInterval(remainingTime))
    }

    @MainActor
    func testTimerStateResumeReturnsRunningWithNewEndDateWhenStillResumable() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let remainingTime: TimeInterval = 6
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: remainingTime,
            pausedAt: pausedAt,
            status: .paused
        )

        let now = pausedAt.addingTimeInterval(2)
        let resumed = timer.resume(at: now)

        XCTAssertEqual(resumed.status, .running)
        XCTAssertNil(resumed.pausedRemainingTime)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertEqual(resumed.endDate, now.addingTimeInterval(remainingTime))
    }

    @MainActor
    func testResumeAfterLogicalCompletionKeepsTimerRunningFromRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(10)
        manager.resume(id: id)

        XCTAssertEqual(manager.timers.count, 1)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .running)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 1, accuracy: 0.0001)
        XCTAssertNil(timer.pausedAt)
        XCTAssertNil(timer.pausedRemainingTime)
        XCTAssertEqual(timer.endDate, currentDate.addingTimeInterval(1))
    }

    @MainActor
    func testCompletedStateHasNoPausedMetadata() {
        let start = Date(timeIntervalSince1970: 100)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: start,
            endDate: start.addingTimeInterval(10),
            pausedRemainingTime: 5,
            pausedAt: start,
            status: .paused
        )

        let completed = timer.completed()

        XCTAssertEqual(completed.status, .completed)
        XCTAssertNil(completed.pausedAt)
        XCTAssertNil(completed.pausedRemainingTime)
    }

    @MainActor
    func testStatusTransitionsAtEpsilonBoundary() {
        let epsilon = ExposureCalculator.stabilityEpsilon
        let startDate = Date(timeIntervalSince1970: 100)
        let endDate = startDate.addingTimeInterval(10)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        XCTAssertEqual(
            timer.status(at: endDate.addingTimeInterval(-(epsilon * 2))),
            .running
        )
        XCTAssertEqual(
            timer.status(at: endDate.addingTimeInterval(-epsilon / 2)),
            .completed
        )
        XCTAssertEqual(
            timer.status(at: endDate.addingTimeInterval(epsilon / 2)),
            .completed
        )
    }

    @MainActor
    func testRemainingTimeClampsBelowEpsilonToZero() {
        let epsilon = ExposureCalculator.stabilityEpsilon
        let startDate = Date(timeIntervalSince1970: 100)
        let endDate = startDate.addingTimeInterval(epsilon / 2)
        let timer = TimerState(
            id: UUID(),
            duration: 1,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        XCTAssertEqual(timer.remainingTime(at: startDate), 0, accuracy: 0.0001)
    }

    @MainActor
    func testRemainingTimeKeepsValueAboveEpsilon() {
        let epsilon = ExposureCalculator.stabilityEpsilon
        let startDate = Date(timeIntervalSince1970: 100)
        let remaining = epsilon * 2
        let endDate = startDate.addingTimeInterval(remaining)
        let timer = TimerState(
            id: UUID(),
            duration: 1,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        XCTAssertGreaterThan(timer.remainingTime(at: startDate), 0)
        XCTAssertEqual(timer.remainingTime(at: startDate), remaining, accuracy: 0.0001)
    }

    @MainActor
    func testPausingWhenRemainingIsZeroImmediatelyCompletes() {
        let startDate = Date(timeIntervalSince1970: 100)
        let endDate = startDate.addingTimeInterval(10)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let paused = timer.pausing(at: endDate)

        XCTAssertEqual(paused.status, .completed)
        XCTAssertEqual(paused.remainingTime(at: endDate), 0, accuracy: 0.0001)
        XCTAssertNil(paused.pausedRemainingTime)
    }

    @MainActor
    func testResumeBranch_remainingZero() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(5)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: 0,
            pausedAt: pausedAt,
            status: .paused
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(1))

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.endDate, startDate.addingTimeInterval(10))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
    }

    @MainActor
    func testResumeBranch_expiredWhilePausedRestartsFromRemainingTime() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let remaining: TimeInterval = 6
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: remaining,
            pausedAt: pausedAt,
            status: .paused
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(remaining + 1))

        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.endDate, pausedAt.addingTimeInterval((remaining + 1) + remaining))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
    }

    @MainActor
    func testResumeBranch_validResume() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let remaining: TimeInterval = 6
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: remaining,
            pausedAt: pausedAt,
            status: .paused
        )

        let now = pausedAt.addingTimeInterval(2)
        let resumed = timer.resume(at: now)

        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.endDate, now.addingTimeInterval(remaining))
    }

    @MainActor
    func testCompletionDateMatchesRegardlessOfCompletionPath() throws {
        let startDate = Date(timeIntervalSince1970: 100)

        let tickManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let tickID = try XCTUnwrap(tickManager.start(duration: 10))
        tickManager.tick(now: startDate.addingTimeInterval(12))
        let tickCompleted = tryUnwrapTimer(withID: tickID, from: tickManager.timers)

        var currentDate = startDate
        let resumeManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let resumeID = try XCTUnwrap(resumeManager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        resumeManager.pause(id: resumeID)
        currentDate = startDate.addingTimeInterval(11)
        resumeManager.resume(id: resumeID)
        resumeManager.tick(now: currentDate.addingTimeInterval(6))
        let resumeCompleted = tryUnwrapTimer(withID: resumeID, from: resumeManager.timers)

        XCTAssertEqual(tickCompleted.status(at: startDate.addingTimeInterval(12)), .completed)
        XCTAssertEqual(resumeCompleted.status(at: currentDate.addingTimeInterval(6)), .completed)
        XCTAssertEqual(tickCompleted.endDate, startDate.addingTimeInterval(10))
        XCTAssertEqual(resumeCompleted.endDate, currentDate.addingTimeInterval(6))
    }

    @MainActor
    func testStatusAtDoesNotChangeOriginalState() {
        let startDate = Date(timeIntervalSince1970: 100)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let original = timer
        _ = timer.status(at: startDate.addingTimeInterval(20))

        XCTAssertEqual(timer, original)
    }

    @MainActor
    func testTimerManagerStopsLoopWhenNoRunningTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 1))
        manager.tick(now: startDate.addingTimeInterval(2))

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: startDate.addingTimeInterval(2)), .completed)
        XCTAssertFalse(manager.timers.contains { $0.status(at: startDate.addingTimeInterval(2)) == .running })
    }

    @MainActor
    func testRunningTimerAutoCompletesViaUpdatingStatus() {
        let startDate = Date(timeIntervalSince1970: 100)
        let endDate = startDate.addingTimeInterval(10)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let updated = timer.updatingStatus(at: endDate.addingTimeInterval(1))

        XCTAssertEqual(updated.status, .completed)
        XCTAssertEqual(updated.endDate, endDate)
        XCTAssertEqual(updated.remainingTime(at: endDate.addingTimeInterval(1)), 0, accuracy: 0.0001)
    }

    @MainActor
    func testBoundaryCompletionWithEpsilon() {
        let epsilon = ExposureCalculator.stabilityEpsilon
        let startDate = Date(timeIntervalSince1970: 100)
        let endDate = startDate.addingTimeInterval(10)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        XCTAssertEqual(
            timer.updatingStatus(at: endDate.addingTimeInterval(-(epsilon * 2))).status,
            .running
        )
        XCTAssertEqual(
            timer.updatingStatus(at: endDate.addingTimeInterval(-epsilon / 2)).status,
            .completed
        )
        XCTAssertEqual(
            timer.updatingStatus(at: endDate.addingTimeInterval(epsilon / 2)).status,
            .completed
        )
    }

    @MainActor
    func testResumeAfterExpirationRestartsFromRemainingTime() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: 6,
            pausedAt: pausedAt,
            status: .paused
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(10))

        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.endDate, pausedAt.addingTimeInterval(16))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
    }

    @MainActor
    func testPauseLoopUsesResolvedState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 1))
        currentDate = startDate.addingTimeInterval(2)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.updatingStatus(at: currentDate).status, .completed)
        XCTAssertFalse(manager.timers.contains {
            $0.updatingStatus(at: currentDate).status == .running
        })
    }

    private func tryUnwrapTimer(
        withID id: UUID,
        from timers: [TimerState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> TimerState {
        guard let timer = timers.first(where: { $0.id == id }) else {
            XCTFail("Expected timer \(id) to exist", file: file, line: line)
            return TimerState(
                id: id,
                duration: 0,
                startDate: .distantPast,
                endDate: nil,
                pausedRemainingTime: 0,
                pausedAt: nil,
                status: .paused
            )
        }

        return timer
    }

    @MainActor
    func testResumeAfterLongWallClockPauseStillUsesPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate

        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(10)
        manager.resume(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)

        XCTAssertEqual(timer.status(at: currentDate), .running)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 1, accuracy: 0.0001)
        XCTAssertEqual(timer.endDate, currentDate.addingTimeInterval(1))
    }

    @MainActor
    func testLongPausedResumeStaysRunningWithoutAlertAndAlertsOnlyAfterRunningCompletion() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionAlertService: alertSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(100)
        manager.resume(id: id)

        let resumed = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumed.status(at: currentDate), .running)
        XCTAssertEqual(resumed.remainingTime(at: currentDate), 1, accuracy: 0.0001)
        XCTAssertTrue(alertSpy.events.isEmpty)

        currentDate = currentDate.addingTimeInterval(1)
        manager.tick(now: currentDate)

        let completed = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(completed.status(at: currentDate), .completed)
        XCTAssertEqual(alertSpy.events, [
            TimerCompletionEvent(
                timerID: id,
                completionDate: currentDate
            )
        ])
    }

    @MainActor
    func testRestoreRunningTimerAfterTerminationKeepsItRunningWithWallClockRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .running)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testRestoreRunningTimerAfterTerminationCompletesIfExpectedCompletionAlreadyPassed() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 3))

        currentDate = startDate.addingTimeInterval(5)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .completed)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(3))
    }

    @MainActor
    func testRestorePausedTimerAfterTerminationPreservesFrozenRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        initialManager.pause(id: id)

        currentDate = startDate.addingTimeInterval(40)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .paused)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(restored.pausedAt, startDate.addingTimeInterval(4))
    }

    @MainActor
    func testRestoreWithCorruptedPersistedSnapshotSafelyFallsBackToEmptyState() {
        let suiteName = "TimerManagerTests.corrupted.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(Data("not-json".utf8), forKey: "ptimer.timer-state.snapshot")

        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: UserDefaultsTimerPersistenceStore(userDefaults: userDefaults)
        )

        XCTAssertTrue(manager.timers.isEmpty)
    }

    @MainActor
    func testRestoreDecodesLegacyStoppedSnapshotValueAsPaused() throws {
        struct LegacySnapshotStatusTimer: Encodable {
            let id: UUID
            let status: String
            let duration: TimeInterval
            let startDate: Date
            let expectedCompletionAt: Date?
            let pausedRemainingDuration: TimeInterval?
            let pausedAt: Date?
            let completedAt: Date?
        }

        struct LegacySnapshotCollection: Encodable {
            let timers: [LegacySnapshotStatusTimer]
        }

        let suiteName = "TimerManagerTests.legacy.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let timerID = UUID()
        let legacySnapshot = LegacySnapshotCollection(
            timers: [
                LegacySnapshotStatusTimer(
                    id: timerID,
                    status: "stopped",
                    duration: 10,
                    startDate: startDate,
                    expectedCompletionAt: startDate.addingTimeInterval(10),
                    pausedRemainingDuration: 6,
                    pausedAt: pausedAt,
                    completedAt: nil
                )
            ]
        )

        let encoded = try JSONEncoder().encode(legacySnapshot)
        userDefaults.set(encoded, forKey: "ptimer.timer-state.snapshot")

        let currentDate = startDate.addingTimeInterval(40)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: UserDefaultsTimerPersistenceStore(userDefaults: userDefaults)
        )

        let restored = tryUnwrapTimer(withID: timerID, from: manager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .paused)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 6, accuracy: 0.0001)
        XCTAssertEqual(restored.pausedAt, pausedAt)
    }

    @MainActor
    func testRestoreCompletedTimerAfterTerminationKeepsCompletedState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 2))
        currentDate = startDate.addingTimeInterval(2)
        initialManager.tick(now: currentDate)

        currentDate = startDate.addingTimeInterval(20)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .completed)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(2))
    }

    @MainActor
    func testRestoreMultipleTimersAfterTerminationPreservesIDsAndStatuses() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let runningID = try XCTUnwrap(initialManager.start(duration: 10))
        let pausedID = try XCTUnwrap(initialManager.start(duration: 12))
        let completedID = try XCTUnwrap(initialManager.start(duration: 3))

        currentDate = startDate.addingTimeInterval(4)
        initialManager.pause(id: pausedID)
        initialManager.tick(now: currentDate)

        currentDate = startDate.addingTimeInterval(5)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        XCTAssertEqual(restoredManager.timers.map(\.id), [runningID, pausedID, completedID])
        XCTAssertEqual(
            restoredManager.timers.map { $0.status(at: currentDate) },
            [.running, .paused, .completed]
        )
        XCTAssertEqual(
            tryUnwrapTimer(withID: runningID, from: restoredManager.timers).remainingTime(at: currentDate),
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            tryUnwrapTimer(withID: pausedID, from: restoredManager.timers).remainingTime(at: currentDate),
            8,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testResumeThenRelaunchRestoresRunningTimerWithReconciledRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let id = try XCTUnwrap(initialManager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        initialManager.pause(id: id)

        currentDate = startDate.addingTimeInterval(6)
        initialManager.resume(id: id)

        currentDate = startDate.addingTimeInterval(8)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        let restored = tryUnwrapTimer(withID: id, from: restoredManager.timers)
        XCTAssertEqual(restored.status(at: currentDate), .running)
        XCTAssertEqual(restored.remainingTime(at: currentDate), 4, accuracy: 0.0001)
        XCTAssertEqual(restored.endDate, startDate.addingTimeInterval(12))
    }

    @MainActor
    func testRestoreEntryPointLoadsSnapshotOnlyDuringInitialization() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )
        _ = try XCTUnwrap(initialManager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(1)
        let restoredManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        XCTAssertEqual(store.loadCallCount, 2)

        currentDate = startDate.addingTimeInterval(2)
        restoredManager.reconcileAfterAppBecomesActive()
        restoredManager.tick(now: currentDate)

        XCTAssertEqual(store.loadCallCount, 2)
    }

    @MainActor
    func testRemovingLastTimerClearsPersistedSnapshot() throws {
        let store = InMemoryTimerPersistenceStore()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: store
        )

        let id = try XCTUnwrap(manager.start(duration: 5))
        XCTAssertNotNil(store.snapshot)

        manager.remove(id: id)

        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testRepeatedRelaunchRestoreDoesNotDuplicatePersistedTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let store = InMemoryTimerPersistenceStore()

        let initialManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )
        let id = try XCTUnwrap(initialManager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(2)
        let firstRelaunch = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )
        XCTAssertEqual(firstRelaunch.timers.map(\.id), [id])

        currentDate = startDate.addingTimeInterval(4)
        let secondRelaunch = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: store
        )

        XCTAssertEqual(secondRelaunch.timers.count, 1)
        XCTAssertEqual(secondRelaunch.timers.map(\.id), [id])
        XCTAssertEqual(
            tryUnwrapTimer(withID: id, from: secondRelaunch.timers).remainingTime(at: currentDate),
            6,
            accuracy: 0.0001
        )
    }
}

@MainActor
private final class CompletionAlertSpy: TimerCompletionAlerting {
    private(set) var events: [TimerCompletionEvent] = []

    func handleTimerCompletion(_ event: TimerCompletionEvent) {
        events.append(event)
    }
}

@MainActor
private final class CompletionFeedbackSpy: TimerCompletionFeedbackPlaying {
    private(set) var playCount = 0

    func playCompletionFeedback() {
        playCount += 1
    }
}

private struct ScheduledTimerNotification: Equatable {
    let timerID: UUID
    let endDate: Date
    let status: TimerStatus
}

@MainActor
private final class CompletionNotificationSchedulerSpy: TimerCompletionNotificationScheduling {
    private(set) var authorizationRequestCount = 0
    private(set) var scheduledTimers: [ScheduledTimerNotification] = []
    private(set) var canceledTimerIDs: [UUID] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequestCount += 1
    }

    func scheduleCompletionNotification(for timer: TimerState) {
        scheduledTimers.append(
            ScheduledTimerNotification(
                timerID: timer.id,
                endDate: timer.endDate ?? .distantPast,
                status: timer.status
            )
        )
    }

    func cancelCompletionNotification(forTimerID timerID: UUID) {
        canceledTimerIDs.append(timerID)
    }

    func resetHistory() {
        authorizationRequestCount = 0
        scheduledTimers = []
        canceledTimerIDs = []
    }
}

private final class InMemoryTimerPersistenceStore: TimerPersistenceStoring {
    private(set) var snapshot: PersistentTimerCollectionSnapshot?
    private(set) var loadCallCount = 0

    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        loadCallCount += 1
        return snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}
