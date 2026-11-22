// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

final class TimerPauseDeadlineTests: XCTestCase {
    private let pauseDate = Date(timeIntervalSince1970: 1_000)

    private func pausedTimer() -> TimerState {
        .paused(PausedTimer(
            id: UUID(), duration: 90, startDate: pauseDate.addingTimeInterval(-30),
            pausedRemainingTime: 60, pausedAt: pauseDate
        ))
    }

    func testResumeJustBeforeDeadlinePreservesIdentityAndExposure() {
        let timer = pausedTimer()
        let resumedAt = pauseDate.addingTimeInterval(119.999)
        let resumed = timer.resume(at: resumedAt)
        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.id, timer.id)
        XCTAssertEqual(resumed.duration, 90)
        XCTAssertEqual(resumed.endDate, resumedAt.addingTimeInterval(60))
    }

    func testResumeAtOrAfterDeadlineCancelsAtDeadlineWithFrozenRemaining() {
        for elapsed in [120.0, 120.001, 10_000] {
            let timer = pausedTimer()
            let canceled = timer.resume(at: pauseDate.addingTimeInterval(elapsed))
            XCTAssertEqual(canceled.status, .canceled)
            XCTAssertEqual(canceled.id, timer.id)
            XCTAssertEqual(canceled.endDate, pauseDate.addingTimeInterval(120))
            XCTAssertEqual(canceled.remainingAtCancel, 60)
            XCTAssertEqual(canceled.cancellationReason, .pauseExpired)
            XCTAssertTrue(canceled.cancellationNoticePending)
            XCTAssertEqual(canceled.resume(at: pauseDate.addingTimeInterval(elapsed)), canceled)
        }
    }

    func testRepeatedPauseDoesNotExtendDeadline() {
        let timer = pausedTimer()
        XCTAssertEqual(timer.pausing(at: pauseDate.addingTimeInterval(60)), timer)
        XCTAssertEqual(timer.pausing(at: pauseDate.addingTimeInterval(121)).status, .canceled)
    }

    func testStatusAndReconciliationAgreeAtDeadline() {
        let timer = pausedTimer()
        XCTAssertEqual(timer.status(at: pauseDate.addingTimeInterval(119.999)), .paused)
        XCTAssertEqual(timer.status(at: pauseDate.addingTimeInterval(120)), .canceled)
        XCTAssertEqual(timer.updatingStatus(at: pauseDate.addingTimeInterval(120)).status, .canceled)
        XCTAssertEqual(timer.remainingTime(at: pauseDate.addingTimeInterval(119)), 60)
    }

    func testResumedTimerIsNotCanceledByItsOldPauseDeadline() {
        let timer = pausedTimer().resume(at: pauseDate.addingTimeInterval(119))
        XCTAssertEqual(timer.updatingStatus(at: pauseDate.addingTimeInterval(120)).status, .running)
        let again = timer.pausing(at: pauseDate.addingTimeInterval(120))
        XCTAssertEqual(again.resume(at: pauseDate.addingTimeInterval(239)).status, .running)
        XCTAssertEqual(again.resume(at: pauseDate.addingTimeInterval(240)).status, .canceled)
    }

    func testLegacyPausedSnapshotExpiresWithoutNewFields() throws {
        let snapshot = PersistentTimerSnapshot(timer: pausedTimer())
        let data = try JSONEncoder().encode(snapshot)
        let restoredSnapshot = try JSONDecoder().decode(PersistentTimerSnapshot.self, from: data)
        XCTAssertNil(restoredSnapshot.cancellationReason)
        XCTAssertNil(restoredSnapshot.cancellationNoticePending)
        XCTAssertEqual(restoredSnapshot.restore(at: pauseDate.addingTimeInterval(119)).status, .paused)
        let expired = restoredSnapshot.restore(at: pauseDate.addingTimeInterval(10_000))
        XCTAssertEqual(expired.status, .canceled)
        XCTAssertEqual(expired.endDate, pauseDate.addingTimeInterval(120))
        XCTAssertEqual(expired.remainingAtCancel, 60)
    }

    func testCancellationReasonAndNoticeAcknowledgmentSurviveRoundTrip() throws {
        let canceled = pausedTimer().updatingStatus(at: pauseDate.addingTimeInterval(120))
        for state in [canceled, canceled.acknowledgingCancellationNotice()] {
            let data = try JSONEncoder().encode(PersistentTimerSnapshot(timer: state))
            let restored = try JSONDecoder().decode(PersistentTimerSnapshot.self, from: data)
                .restore(at: pauseDate.addingTimeInterval(10_000))
            XCTAssertEqual(restored, state)
        }
    }
}
