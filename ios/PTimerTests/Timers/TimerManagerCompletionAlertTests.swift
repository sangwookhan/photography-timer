import XCTest
import PTimerKit
@testable import PTimer

final class TimerManagerCompletionAlertTests: XCTestCase {
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
            ),
        ])
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
            ),
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
}
