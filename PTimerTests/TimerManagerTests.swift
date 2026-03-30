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
                status: .stopped
            )
        }

        return timer
    }
}
