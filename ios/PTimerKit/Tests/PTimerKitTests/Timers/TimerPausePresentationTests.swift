// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class TimerPausePresentationTests: XCTestCase {
    @MainActor
    func testResumeCountdownDecreasesWithoutConsumingExposureOrChangingFilmCue() throws {
        var now = Date(timeIntervalSince1970: 100)
        let manager = RuntimeBackedTimerManaging(dateProvider: { now })
        let model = TimerWorkspaceModel(
            timerManager: manager,
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            defaultName: { _ in "Timer" }
        )
        let id = try XCTUnwrap(model.startTimer(
            duration: 90, name: "Exposure", basisSummary: "Base 1s",
            filmDisplayName: "Tri-X 400", exposureSource: .filmCorrectedExposure
        ))
        now += 30
        model.pauseTimer(id: id)
        let initial = snapshot(model.timers)
        XCTAssertEqual(initial.sections.first?.items.first?.resumeNoticeText,
                       "Resume within 2:00 or this timer will be canceled.")
        now += 60
        manager.tick(now: now)
        let updated = snapshot(model.timers)
        let card = try XCTUnwrap(updated.sections.first?.items.first)
        XCTAssertEqual(card.resumeNoticeText, "Resume within 1:00 or this timer will be canceled.")
        XCTAssertEqual(card.resumeCountdownText, "Resume in 1:00 · auto-cancel")
        XCTAssertEqual(model.timers.first?.remainingTime, 60)
        XCTAssertEqual(updated.compactItems.first?.identityFilmText, initial.compactItems.first?.identityFilmText)
        XCTAssertTrue(card.actions.contains(.resume))
        XCTAssertTrue(model.cancellationNotice.hasPausedTimers)
    }

    @MainActor
    func testExpiredRecordShowsReasonAndSeparateRemainingWithoutResume() throws {
        var now = Date(timeIntervalSince1970: 100)
        let manager = RuntimeBackedTimerManaging(dateProvider: { now })
        let model = TimerWorkspaceModel(
            timerManager: manager,
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            defaultName: { _ in "Timer" }
        )
        let id = try XCTUnwrap(model.startTimer(duration: 90, name: "Exposure", basisSummary: "Manual"))
        now += 30
        model.pauseTimer(id: id)
        now += 120
        manager.tick(now: now)
        let history = try XCTUnwrap(snapshot(model.timers).sections.first)
        let card = try XCTUnwrap(history.items.first)
        XCTAssertTrue(history.isCompletedSection)
        XCTAssertEqual(card.remainingText, "Canceled")
        XCTAssertEqual(card.cancellationReasonText, "Resume expired")
        XCTAssertTrue(try XCTUnwrap(card.timingText).contains("01:00 left"))
        XCTAssertNil(card.resumeNoticeText)
        XCTAssertFalse(card.actions.contains(.resume))
        XCTAssertFalse(model.cancellationNotice.hasPausedTimers)
    }

    private func snapshot(_ timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        .make(
            from: timers,
            formatRemaining: { BottomSheetWorkspaceSnapshot.compactDurationText($0) },
            formatShutter: { String($0) },
            ndNotationMode: .stops,
            timeContext: { _ in "Canceled recently" },
            compactCompletedSupplementaryText: { _ in nil }
        )
    }
}
