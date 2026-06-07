import XCTest
import PTimerCore
@testable import PTimer

final class TimerManagerPauseResumeTests: XCTestCase {
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
            ),
        ])
    }
}
