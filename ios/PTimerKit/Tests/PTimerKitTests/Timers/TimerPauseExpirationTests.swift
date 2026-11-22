// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import XCTest
import PTimerCore
@testable import PTimerKit

final class TimerPauseExpirationTests: XCTestCase {
    @MainActor
    func testPausedOnlyRuntimeExpiresWithoutCompletionFeedback() throws {
        var now = Date(timeIntervalSince1970: 100)
        let alerts = PauseCompletionSpy()
        let runtime = TimerRuntime(dateProvider: { now }, completionAlertService: alerts)
        let id = try XCTUnwrap(runtime.start(duration: 90))
        now += 30
        runtime.pause(id: id)
        XCTAssertTrue(runtime.needsTicking)
        now += 119.999
        runtime.tick()
        XCTAssertEqual(runtime.timers.first?.status, .paused)
        now += 0.001
        runtime.tick()
        let canceled = try XCTUnwrap(runtime.timers.first)
        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(canceled.remainingAtCancel, 60)
        XCTAssertEqual(canceled.endDate, Date(timeIntervalSince1970: 250))
        XCTAssertFalse(runtime.needsTicking)
        XCTAssertTrue(alerts.completions.isEmpty)
        runtime.tick()
        XCTAssertEqual(runtime.timers, [canceled])
    }

    @MainActor
    func testNewStartCancelsEveryPausedButKeepsOtherRunningTimer() throws {
        var now = Date(timeIntervalSince1970: 100)
        let runtime = TimerRuntime(dateProvider: { now })
        let first = try XCTUnwrap(runtime.start(duration: 600))
        let second = try XCTUnwrap(runtime.start(duration: 700))
        let running = try XCTUnwrap(runtime.start(duration: 900))
        now += 10
        runtime.pause(id: first)
        runtime.pause(id: second)
        let runningBefore = try XCTUnwrap(runtime.timers.first { $0.id == running })
        XCTAssertNil(runtime.start(duration: .nan))
        XCTAssertEqual(runtime.timers.filter { $0.status == .paused }.count, 2)
        let newID = try XCTUnwrap(runtime.start(duration: 60))
        for id in [first, second] {
            let canceled = try XCTUnwrap(runtime.timers.first { $0.id == id })
            XCTAssertEqual(canceled.status, .canceled)
            XCTAssertEqual(canceled.cancellationReason, .newTimerStarted)
            XCTAssertTrue(canceled.cancellationNoticePending)
        }
        XCTAssertEqual(runtime.timers.first { $0.id == running }, runningBefore)
        XCTAssertEqual(runtime.timers.first { $0.id == newID }?.status, .running)
        XCTAssertEqual(runtime.timers.count, 4)
    }

    @MainActor
    func testManualCancelAfterDeadlineStillRecordsExpirationAtDeadline() throws {
        var now = Date(timeIntervalSince1970: 100)
        let runtime = TimerRuntime(dateProvider: { now })
        let id = try XCTUnwrap(runtime.start(duration: 300))
        runtime.pause(id: id)
        now += 500
        runtime.cancel(id: id)
        XCTAssertEqual(runtime.timers.first?.endDate, Date(timeIntervalSince1970: 220))
        XCTAssertEqual(runtime.timers.first?.cancellationReason, .pauseExpired)
        XCTAssertEqual(runtime.timers.first?.remainingAtCancel, 300)
    }

    @MainActor
    func testExpiredResumeDoesNotScheduleCompletionNotification() throws {
        var now = Date(timeIntervalSince1970: 100)
        let scheduler = PauseNotificationSpy()
        let runtime = TimerRuntime(dateProvider: { now }, completionNotificationScheduler: scheduler)
        let id = try XCTUnwrap(runtime.start(duration: 300))
        now += 10
        runtime.pause(id: id)
        now += 120
        runtime.resume(id: id)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertTrue(scheduler.canceled.contains(id))
        XCTAssertEqual(runtime.timers.first?.status, .canceled)
    }

    @MainActor
    func testReturnCancelsExpiredPauseButSilentlyCompletesRunningTimer() throws {
        var now = Date(timeIntervalSince1970: 100)
        let alerts = PauseCompletionSpy()
        let runtime = TimerRuntime(dateProvider: { now }, completionAlertService: alerts)
        let paused = try XCTUnwrap(runtime.start(duration: 600))
        let running = try XCTUnwrap(runtime.start(duration: 60))
        now += 10
        runtime.pause(id: paused)
        now += 200
        runtime.reconcile()
        XCTAssertEqual(runtime.timers.first { $0.id == paused }?.status, .canceled)
        XCTAssertEqual(runtime.timers.first { $0.id == running }?.endDate, Date(timeIntervalSince1970: 160))
        XCTAssertTrue(alerts.completions.isEmpty)
    }

    @MainActor
    func testLiveCompletionStillSignalsOnceAlongsidePauseExpiration() throws {
        var now = Date(timeIntervalSince1970: 100)
        let alerts = PauseCompletionSpy()
        let runtime = TimerRuntime(dateProvider: { now }, completionAlertService: alerts)
        let paused = try XCTUnwrap(runtime.start(duration: 300))
        let running = try XCTUnwrap(runtime.start(duration: 120))
        runtime.pause(id: paused)
        now += 120
        runtime.tick()
        runtime.tick()
        XCTAssertEqual(alerts.completions.map(\.timerID), [running])
        XCTAssertEqual(runtime.timers.first { $0.id == paused }?.cancellationReason, .pauseExpired)
    }

    @MainActor
    func testUnshownRestoreNoticeSurvivesRelaunchAndShownNoticeDoesNotReplay() throws {
        var now = Date(timeIntervalSince1970: 100)
        let store = PausePersistenceStore()
        let manager = RuntimeBackedTimerManaging(dateProvider: { now }, persistenceStore: store)
        let id = try XCTUnwrap(manager.start(id: UUID(), duration: 600))
        now += 10
        manager.pause(id: id)
        now += 1_000
        let restored = RuntimeBackedTimerManaging(dateProvider: { now }, persistenceStore: store)
        let notice = TimerCancellationNoticeModel(timerManager: restored)
        XCTAssertNil(notice.text)
        XCTAssertEqual(notice.pendingTimerIDs, [id])
        let reopened = RuntimeBackedTimerManaging(dateProvider: { now }, persistenceStore: store)
        let visibleNotice = TimerCancellationNoticeModel(timerManager: reopened)
        visibleNotice.presentPendingNotice()
        XCTAssertEqual(visibleNotice.text, "Paused timer canceled")
        XCTAssertTrue(visibleNotice.pendingTimerIDs.isEmpty)
        XCTAssertFalse(try XCTUnwrap(store.snapshot?.timers.first?.cancellationNoticePending))
        let again = RuntimeBackedTimerManaging(dateProvider: { now }, persistenceStore: store)
        let noReplay = TimerCancellationNoticeModel(timerManager: again)
        noReplay.presentPendingNotice()
        XCTAssertNil(noReplay.text)
        XCTAssertEqual(again.timers.first?.endDate, Date(timeIntervalSince1970: 230))
        XCTAssertEqual(again.timers.first?.remainingAtCancel, 590)
    }
}

@MainActor
private final class PauseCompletionSpy: TimerCompletionAlerting {
    var completions: [TimerCompletionEvent] = []
    func handleTimerCompletion(_ event: TimerCompletionEvent) { completions.append(event) }
}

@MainActor
private final class PauseNotificationSpy: TimerCompletionNotificationScheduling {
    var scheduled: [UUID] = []
    var canceled: [UUID] = []
    func requestAuthorizationIfNeeded() {}
    func scheduleCompletionNotification(for timer: TimerState) { scheduled.append(timer.id) }
    func cancelCompletionNotification(forTimerID id: UUID) { canceled.append(id) }
}

@MainActor
private final class PausePersistenceStore: TimerPersistenceStoring {
    var snapshot: PersistentTimerCollectionSnapshot?
    func loadSnapshot() -> PersistentTimerCollectionSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) { self.snapshot = snapshot }
    func clearSnapshot() { snapshot = nil }
}
