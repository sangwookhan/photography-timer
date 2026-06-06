import XCTest
@testable import PTimer
import PTimerCore
import PTimerKit

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
    func testNotificationIdentifierIsDeterministicFromTimerUUID() {
        let timerID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

        XCTAssertEqual(
            UserNotificationTimerCompletionScheduler.notificationIdentifier(for: timerID),
            "timer-completion-12345678-1234-1234-1234-123456789abc"
        )
    }

    // MARK: - Edge durations and removal

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

    // MARK: - Status semantics around the stability epsilon

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
}
