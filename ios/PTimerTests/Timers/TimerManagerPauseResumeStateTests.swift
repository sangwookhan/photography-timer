import XCTest
@testable import PTimer

final class TimerManagerPauseResumeStateTests: XCTestCase {
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
        // PausedTimer.endDate is computed as
        // `pausedAt + pausedRemainingTime`, so this synthetic
        // zero-remaining paused → resume → completed corner produces
        // completedAt = pausedAt. The corner is unreachable from the
        // normal pause path because `pausing(at:)` short-circuits to
        // completed when remaining == 0; only the back-compat init or
        // a corrupted snapshot can construct it.
        XCTAssertEqual(resumed.endDate, pausedAt)
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
        // See testTimerStateResumeReturnsCompletedWhenNoRemainingTime
        // for the corner-semantics note.
        XCTAssertEqual(resumed.endDate, pausedAt)
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
}
