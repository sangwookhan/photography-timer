// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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

    // PTIMER-73 (silent-mode audible): the completion feedback drives the
    // app-owned audible alarm player so completion is heard even in silent mode.

    @MainActor
    func testCompletionFeedbackPlaysAppOwnedAudibleAlarm() {
        let alarmSpy = AlarmAudioPlayerSpy()
        let player = SystemTimerCompletionFeedbackPlayer(alarmPlayer: alarmSpy)

        player.playCompletionFeedback()

        XCTAssertEqual(alarmSpy.playCount, 1)
    }

    @MainActor
    func testPreAlertFeedbackDoesNotPlayTheAudibleAlarm() {
        // pre1 is haptic-first; it must not trigger the audible completion alarm.
        let alarmSpy = AlarmAudioPlayerSpy()
        let player = SystemTimerCompletionFeedbackPlayer(alarmPlayer: alarmSpy)

        player.playPreAlertFeedback()

        XCTAssertEqual(alarmSpy.playCount, 0)
    }

    @MainActor
    func testForegroundCompletionDrivesAudibleAlarmOnlyWhileActiveAndNotOnCancel() {
        let alarmSpy = AlarmAudioPlayerSpy()
        let feedbackPlayer = SystemTimerCompletionFeedbackPlayer(alarmPlayer: alarmSpy)
        let service = ForegroundTimerCompletionAlertService(
            feedbackPlayer: feedbackPlayer,
            applicationStateProvider: { .active }
        )
        let event = TimerCompletionEvent(timerID: UUID(), completionDate: Date(timeIntervalSince1970: 100))

        // A pre-alert (the only foreground event a pre-completion timer raises,
        // e.g. before a cancel/remove) must not sound the alarm...
        service.handlePreAlert(
            TimerPreAlertEvent(timerID: event.timerID, stage: .pre1, secondsBeforeCompletion: 5)
        )
        XCTAssertEqual(alarmSpy.playCount, 0)

        // ...only an actual completion does.
        service.handleTimerCompletion(event)
        XCTAssertEqual(alarmSpy.playCount, 1)
    }

    // PTIMER-73 (background-audio keep-alive): a completion that fires while the
    // app is backgrounded (kept alive by the audio session) plays the audible
    // alarm only — no haptic — while a foreground completion plays full feedback.

    @MainActor
    func testBackgroundCompletionPlaysAlarmOnlyAndForegroundPlaysFullFeedback() {
        let event = TimerCompletionEvent(timerID: UUID(), completionDate: Date(timeIntervalSince1970: 100))

        let foregroundSpy = CompletionFeedbackSpy()
        ForegroundTimerCompletionAlertService(
            feedbackPlayer: foregroundSpy,
            applicationStateProvider: { .active }
        ).handleTimerCompletion(event)
        XCTAssertEqual(foregroundSpy.playCount, 1)
        XCTAssertEqual(foregroundSpy.alarmOnlyPlayCount, 0)

        let backgroundSpy = CompletionFeedbackSpy()
        ForegroundTimerCompletionAlertService(
            feedbackPlayer: backgroundSpy,
            applicationStateProvider: { .background }
        ).handleTimerCompletion(event)
        XCTAssertEqual(backgroundSpy.playCount, 0)
        XCTAssertEqual(backgroundSpy.alarmOnlyPlayCount, 1)
    }

    @MainActor
    func testKeepAliveStartsWhileTimerRunsAndStopsWhenNoneRemain() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let keepAlive = BackgroundAudioKeepAliveSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            backgroundAudioKeepAlive: keepAlive
        )

        let id = try XCTUnwrap(manager.start(duration: 5))
        XCTAssertGreaterThanOrEqual(keepAlive.startCount, 1)

        // Drive the timer to completion: keep-alive is released when nothing runs.
        currentDate = startDate.addingTimeInterval(5)
        manager.tick(now: currentDate)
        XCTAssertGreaterThanOrEqual(keepAlive.stopCount, 1)
    }
}
