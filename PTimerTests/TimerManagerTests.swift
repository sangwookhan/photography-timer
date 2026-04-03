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
    func testStopPreservesRemainingTimeAndMarksTimerStopped() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let firstID = try XCTUnwrap(manager.start(duration: 5))
        let secondID = try XCTUnwrap(manager.start(duration: 9))

        currentDate = startDate.addingTimeInterval(2)
        manager.stop(id: firstID)

        let firstTimer = tryUnwrapTimer(withID: firstID, from: manager.timers)
        let secondTimer = tryUnwrapTimer(withID: secondID, from: manager.timers)

        XCTAssertEqual(firstTimer.status(at: currentDate), TimerStatus.stopped)
        XCTAssertEqual(firstTimer.remainingTime(at: currentDate), 3, accuracy: 0.0001)

        let laterDate = startDate.addingTimeInterval(4)
        XCTAssertEqual(firstTimer.status(at: laterDate), TimerStatus.stopped)
        XCTAssertEqual(firstTimer.remainingTime(at: laterDate), 3, accuracy: 0.0001)
        let pausedRemainingTime = try XCTUnwrap(firstTimer.pausedRemainingTime)
        XCTAssertEqual(pausedRemainingTime, 3, accuracy: 0.0001)
        XCTAssertEqual(secondTimer.status(at: currentDate), TimerStatus.running)
        XCTAssertEqual(secondTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)
    }

    @MainActor
    func testTickDoesNotChangeStoppedTimerRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(5)
        manager.stop(id: id)

        let stoppedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(stoppedTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)

        let muchLaterDate = startDate.addingTimeInterval(30)
        manager.tick(now: muchLaterDate)

        let timerAfterTick = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timerAfterTick.status(at: muchLaterDate), TimerStatus.stopped)
        XCTAssertEqual(timerAfterTick.remainingTime(at: muchLaterDate), 7, accuracy: 0.0001)
    }

    @MainActor
    func testStopAtSixSecondsPreservesApproximatelyFourSecondsRemaining() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(6)
        manager.stop(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), TimerStatus.stopped)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 4, accuracy: 0.0001)
    }

    @MainActor
    func testResumeContinuesFromPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.stop(id: id)

        let stoppedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(stoppedTimer.status(at: currentDate), .stopped)
        XCTAssertEqual(stoppedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(7)
        manager.resume(id: id)

        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        let laterDate = currentDate.addingTimeInterval(2)
        XCTAssertEqual(resumedTimer.remainingTime(at: laterDate), 4, accuracy: 0.0001)
    }

    @MainActor
    func testResumeRecalculatesEndDateFromPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(5)
        manager.stop(id: id)

        let stoppedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        let pausedRemaining = try XCTUnwrap(stoppedTimer.pausedRemainingTime)
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
    func testStoppedTimerPreservesPauseMetadata() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.stop(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .stopped)
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
    func testRemoveCompletedTimersKeepsStoppedTimersResumable() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let stoppedID = try XCTUnwrap(manager.start(duration: 10))
        let completedID = try XCTUnwrap(manager.start(duration: 1))

        currentDate = startDate.addingTimeInterval(4)
        manager.stop(id: stoppedID)
        manager.tick(now: currentDate)
        manager.removeCompletedTimers()

        XCTAssertNil(manager.timers.first { $0.id == completedID })

        let stoppedTimer = tryUnwrapTimer(withID: stoppedID, from: manager.timers)
        XCTAssertEqual(stoppedTimer.status(at: currentDate), .stopped)
        XCTAssertEqual(stoppedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(8)
        manager.resume(id: stoppedID)

        let resumedTimer = tryUnwrapTimer(withID: stoppedID, from: manager.timers)
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
        manager.stop(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 15, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(9)
        manager.resume(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 15, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(12)
        manager.stop(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 12, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(30)
        manager.resume(id: id)
        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .completed)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
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
        manager.stop(id: id)

        currentDate = startDate.addingTimeInterval(10_000)
        manager.resume(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .completed)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
    }

    @MainActor
    func testStopDoesNotModifyEndDateUntilResume() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        let originalEndDate = try XCTUnwrap(tryUnwrapTimer(withID: id, from: manager.timers).endDate)

        currentDate = startDate.addingTimeInterval(4)
        manager.stop(id: id)

        let stoppedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(stoppedTimer.endDate, originalEndDate)
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
    func testRemoveCompletedTimersKeepsStoppedTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let stoppedID = try XCTUnwrap(manager.start(duration: 10))
        let completedID = try XCTUnwrap(manager.start(duration: 1))

        currentDate = startDate.addingTimeInterval(4)
        manager.stop(id: stoppedID)
        manager.tick(now: currentDate)
        manager.removeCompletedTimers()

        let stoppedTimer = tryUnwrapTimer(withID: stoppedID, from: manager.timers)
        XCTAssertEqual(stoppedTimer.status(at: currentDate), TimerStatus.stopped)
        XCTAssertEqual(stoppedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
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
            status: .stopped
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(1))

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.remainingTime(at: pausedAt.addingTimeInterval(1)), 0, accuracy: 0.0001)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
        XCTAssertEqual(resumed.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testTimerStateResumeReturnsCompletedWhenPauseWindowHasExpired() {
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
            status: .stopped
        )

        let now = pausedAt.addingTimeInterval(remainingTime + 1)
        let resumed = timer.resume(at: now)

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.remainingTime(at: now), 0, accuracy: 0.0001)
        XCTAssertNil(resumed.pausedRemainingTime)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertEqual(resumed.endDate, pausedAt.addingTimeInterval(remainingTime))
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
            status: .stopped
        )

        let now = pausedAt.addingTimeInterval(2)
        let resumed = timer.resume(at: now)

        XCTAssertEqual(resumed.status, .running)
        XCTAssertNil(resumed.pausedRemainingTime)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertEqual(resumed.endDate, now.addingTimeInterval(remainingTime))
    }

    @MainActor
    func testResumeAfterLogicalCompletionKeepsTimerAndMarksItCompleted() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(4)
        manager.stop(id: id)

        currentDate = startDate.addingTimeInterval(10)
        manager.resume(id: id)

        XCTAssertEqual(manager.timers.count, 1)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .completed)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
        XCTAssertNil(timer.pausedAt)
        XCTAssertNil(timer.pausedRemainingTime)
        XCTAssertEqual(timer.endDate, startDate.addingTimeInterval(5))
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
            status: .stopped
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
    func testStoppingWhenRemainingIsZeroImmediatelyCompletes() {
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

        let stopped = timer.stopping(at: endDate)

        XCTAssertEqual(stopped.status, .completed)
        XCTAssertEqual(stopped.remainingTime(at: endDate), 0, accuracy: 0.0001)
        XCTAssertNil(stopped.pausedRemainingTime)
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
            status: .stopped
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(1))

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.endDate, startDate.addingTimeInterval(10))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
    }

    @MainActor
    func testResumeBranch_expiredWhilePaused() {
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
            status: .stopped
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(remaining + 1))

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.endDate, pausedAt.addingTimeInterval(remaining))
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
            status: .stopped
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
        resumeManager.stop(id: resumeID)
        currentDate = startDate.addingTimeInterval(11)
        resumeManager.resume(id: resumeID)
        let resumeCompleted = tryUnwrapTimer(withID: resumeID, from: resumeManager.timers)

        XCTAssertEqual(tickCompleted.status(at: startDate.addingTimeInterval(12)), .completed)
        XCTAssertEqual(resumeCompleted.status(at: currentDate), .completed)
        XCTAssertEqual(tickCompleted.endDate, startDate.addingTimeInterval(10))
        XCTAssertEqual(resumeCompleted.endDate, startDate.addingTimeInterval(10))
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
    func testResumeAfterExpirationBecomesCompleted() {
        let startDate = Date(timeIntervalSince1970: 100)
        let pausedAt = startDate.addingTimeInterval(4)
        let timer = TimerState(
            id: UUID(),
            duration: 10,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(10),
            pausedRemainingTime: 6,
            pausedAt: pausedAt,
            status: .stopped
        )

        let resumed = timer.resume(at: pausedAt.addingTimeInterval(10))

        XCTAssertEqual(resumed.status, .completed)
        XCTAssertEqual(resumed.endDate, startDate.addingTimeInterval(10))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.pausedRemainingTime)
    }

    @MainActor
    func testStopLoopUsesResolvedState() throws {
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
                status: .stopped
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
        manager.stop(id: id)

        currentDate = startDate.addingTimeInterval(10)
        manager.resume(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)

        XCTAssertEqual(timer.status(at: currentDate), .completed)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 0, accuracy: 0.0001)
    }
}
