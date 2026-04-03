import XCTest
@testable import PTimer

final class TimerStateInvariantTests: XCTestCase {
    func test_running_state_has_endDate_only() {
        let state = makeRunningTimer()

        XCTAssertNotNil(state.endDate)
        XCTAssertNil(state.completionDate)
    }

    func test_completed_state_has_completionDate_only() {
        let state = makeCompletedTimer()

        XCTAssertNil(state.endDate)
        XCTAssertNotNil(state.completionDate)
    }

    func test_stopped_state_has_no_dates() {
        let state = makeStoppedTimer()

        XCTAssertNil(state.endDate)
        XCTAssertNil(state.completionDate)
    }

    func test_resume_after_long_pause_preserves_remaining_time() {
        let start = Date(timeIntervalSince1970: 100)
        let paused = start.addingTimeInterval(5)
        let resume = start.addingTimeInterval(3_600)

        let state = makeRunningTimer(start: start, duration: 10)
            .stopping(at: paused)

        let resumed = state.resume(at: resume)

        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.remainingTime(at: resume), 5, accuracy: 0.01)
    }

    func test_stopped_timer_never_completes_with_time_passage() {
        let start = Date(timeIntervalSince1970: 100)
        let paused = start.addingTimeInterval(5)
        let later = start.addingTimeInterval(3_600)

        let state = makeRunningTimer(start: start, duration: 10)
            .stopping(at: paused)

        let status = state.status(at: later)

        XCTAssertEqual(status, .stopped)
    }

    func test_resume_recalculates_endDate_from_now() {
        let start = Date(timeIntervalSince1970: 100)
        let paused = start.addingTimeInterval(5)
        let resume = start.addingTimeInterval(100)

        let state = makeRunningTimer(start: start, duration: 10)
            .stopping(at: paused)

        let resumed = state.resume(at: resume)

        XCTAssertEqual(resumed.endDate, resume.addingTimeInterval(5))
    }

    @MainActor
    func test_tick_does_not_affect_stopped_timer() throws {
        let start = Date(timeIntervalSince1970: 100)
        var currentDate = start
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        currentDate = start.addingTimeInterval(4)
        manager.stop(id: id)

        let before = try XCTUnwrap(manager.timers.first(where: { $0.id == id }))
        manager.tick(now: start.addingTimeInterval(1_000))
        let after = try XCTUnwrap(manager.timers.first(where: { $0.id == id }))

        XCTAssertEqual(before.remainingTime(at: currentDate), after.remainingTime(at: start.addingTimeInterval(1_000)), accuracy: 0.0001)
    }

    func test_updatingStatus_handles_missing_endDate_safely() {
        let now = Date(timeIntervalSince1970: 100)
        let state = makeUnsafeRunningTimerWithoutEndDate(now: now)

        let updated = state.updatingStatus(at: now)

        XCTAssertEqual(updated.status, .completed)
        XCTAssertNil(updated.endDate)
        XCTAssertEqual(updated.completionDate, now)
    }

    func testRemainingTimeConsistencyBetweenStateAndDisplay() {
        let start = Date(timeIntervalSince1970: 100)
        let end = start.addingTimeInterval(10)
        let reference = start.addingTimeInterval(3)

        let state = TimerState(
            id: UUID(),
            duration: 10,
            startDate: start,
            endDate: end,
            completionDate: nil,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let stateRemaining = state.remainingTime(at: reference)

        XCTAssertEqual(stateRemaining, 7, accuracy: 0.0001)
    }

    func testRemainingTimeDoesNotDriftAcrossMultipleReads() {
        let start = Date(timeIntervalSince1970: 100)
        let end = start.addingTimeInterval(10)
        let reference = start.addingTimeInterval(4)

        let state = TimerState(
            id: UUID(),
            duration: 10,
            startDate: start,
            endDate: end,
            completionDate: nil,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let first = state.remainingTime(at: reference)
        let second = state.remainingTime(at: reference)

        XCTAssertEqual(first, second, accuracy: 0.0001)
    }

    func testRemainingTimePropertyIsNotUsedForRunningLogic() {
        let start = Date(timeIntervalSince1970: 100)
        let end = start.addingTimeInterval(10)

        let state = TimerState(
            id: UUID(),
            duration: 10,
            startDate: start,
            endDate: end,
            completionDate: nil,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )

        let propertyValue = state.remainingTime
        let correctValue = state.remainingTime(at: start.addingTimeInterval(5))

        XCTAssertNotEqual(propertyValue, correctValue)
    }

    private func makeRunningTimer(
        start: Date = Date(timeIntervalSince1970: 100),
        duration: TimeInterval = 10
    ) -> TimerState {
        TimerState(
            id: UUID(),
            duration: duration,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            completionDate: nil,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running
        )
    }

    private func makeStoppedTimer(
        start: Date = Date(timeIntervalSince1970: 100),
        duration: TimeInterval = 10
    ) -> TimerState {
        makeRunningTimer(start: start, duration: duration)
            .stopping(at: start.addingTimeInterval(5))
    }

    private func makeCompletedTimer(
        start: Date = Date(timeIntervalSince1970: 100),
        duration: TimeInterval = 10
    ) -> TimerState {
        makeRunningTimer(start: start, duration: duration)
            .completed(at: start.addingTimeInterval(duration))
    }

    private func makeUnsafeRunningTimerWithoutEndDate(now: Date) -> TimerState {
        typealias RawTimerState = (
            UUID,
            TimeInterval,
            Date,
            Date?,
            Date?,
            TimeInterval?,
            Date?,
            TimerStatus
        )

        let raw: RawTimerState = (
            UUID(),
            10,
            now,
            nil,
            nil,
            nil,
            nil,
            .running
        )

        return unsafeBitCast(raw, to: TimerState.self)
    }
}
