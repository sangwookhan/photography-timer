// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

final class BottomSheetCompactPresentationTests: XCTestCase {
    // MARK: - Compact card geometry (still drives screen-level strip)

    func testCompactDockUsesSymmetricEighteenPointViewportInsets() {
        let insets = BottomSheetCompactDockMetrics.contentInsets

        XCTAssertEqual(insets.leading, 18)
        XCTAssertEqual(insets.trailing, 18)
        XCTAssertEqual(insets.leading, insets.trailing)
        XCTAssertEqual(insets.top, 1)
        XCTAssertEqual(insets.bottom, 1)
        XCTAssertGreaterThan(BottomSheetCompactDockMetrics.viewportCornerRadius, 0)
        XCTAssertEqual(
            BottomSheetCompactDockMetrics.viewportHeight,
            BottomSheetCompactDockMetrics.timerCardHeight + insets.top + insets.bottom
        )
    }

    func testCompactDockConfigurationUsesHorizontalScrolling() {
        XCTAssertTrue(BottomSheetCompactDockMetrics.scrollsHorizontally)
    }

    func testCompactCardHeightAccommodatesWorstCaseLayoutBudget() {
        let statusHeaderHeight: CGFloat = 22
        let primaryRemainingMinHeight: CGFloat = 34
        let tertiaryOrFilmSlotHeight: CGFloat = 15
        let decorativeTimelineMinHeight: CGFloat = 9
        let identityBadgeHeight: CGFloat = 13
        let verticalPadding: CGFloat = 9 + 12

        let requiredHeight = statusHeaderHeight
            + primaryRemainingMinHeight
            + tertiaryOrFilmSlotHeight
            + decorativeTimelineMinHeight
            + identityBadgeHeight
            + verticalPadding

        XCTAssertGreaterThanOrEqual(
            BottomSheetCompactDockMetrics.timerCardHeight,
            requiredHeight,
            "timerCardHeight must fit the worst-case compact card content " +
            "without bottom clipping (PTIMER-124)."
        )
    }

    func testCompactDockOverflowCaseUsesSameSymmetricInsetModel() {
        let totalHorizontalInset = BottomSheetCompactDockMetrics.contentInsets.leading
            + BottomSheetCompactDockMetrics.contentInsets.trailing
        let widthWithoutOverflow = totalHorizontalInset
            + (BottomSheetCompactDockMetrics.timerCardWidth * 3)
            + (BottomSheetCompactDockMetrics.cardSpacing * 2)
        let widthWithOverflow = totalHorizontalInset
            + (BottomSheetCompactDockMetrics.timerCardWidth * 3)
            + BottomSheetCompactDockMetrics.overflowCardWidth
            + (BottomSheetCompactDockMetrics.cardSpacing * 3)

        XCTAssertEqual(totalHorizontalInset, 36)
        XCTAssertGreaterThan(widthWithOverflow, widthWithoutOverflow)
        XCTAssertEqual(
            widthWithOverflow - widthWithoutOverflow,
            BottomSheetCompactDockMetrics.overflowCardWidth + BottomSheetCompactDockMetrics.cardSpacing
        )
    }

    // MARK: - Snapshot factory: paused / completed presentation

    func testVisiblePausedCopyUsesPausedPresentationLabel() {
        let snapshot = makeBottomSheetSnapshot(from: bottomSheetSampleTimers())
        let pausedItem = snapshot.sections
            .flatMap(\.items)
            .first { $0.status == .paused }

        XCTAssertEqual(pausedItem?.statusLabel, "Paused")
    }

    func testCompletedCompactCardPrioritizesExpiredStateAndRelativeTime() {
        let completedTimer = bottomSheetSampleTimers().first { $0.status == .completed }!
        let snapshot = makeBottomSheetSnapshot(from: [completedTimer])

        XCTAssertEqual(snapshot.compactItems.count, 1)
        XCTAssertEqual(snapshot.compactItems[0].identityCue.markerText, "T3")
        XCTAssertEqual(snapshot.compactItems[0].primaryRemainingText, "Done")
        XCTAssertEqual(snapshot.compactItems[0].secondaryTotalText, "45s")
        XCTAssertEqual(snapshot.compactItems[0].tertiaryStatusText, "just now")
        XCTAssertFalse(snapshot.compactItems[0].showsDecorativeTimeline)
        XCTAssertNotEqual(snapshot.compactItems[0].primaryRemainingText, "0s")
        XCTAssertFalse((snapshot.compactItems[0].tertiaryStatusText ?? "").contains("0s"))
    }

    func testCompletedCompactCardUsesShortHourAndDayRelativeCopyWithoutLongAgo() {
        let now = Date(timeIntervalSince1970: 20_000)
        let oneHourCompleted = RunningTimerItem(
            id: UUID(uuidString: "90909090-1111-2222-3333-444444444444")!,
            order: 8,
            name: "One Hour Completed",
            basisSummary: "",
            duration: 30,
            startDate: now.addingTimeInterval(-3_700),
            endDate: now.addingTimeInterval(-3_600),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )
        let oneDayCompleted = RunningTimerItem(
            id: UUID(uuidString: "91919191-1111-2222-3333-444444444444")!,
            order: 9,
            name: "One Day Completed",
            basisSummary: "",
            duration: 256,
            startDate: now.addingTimeInterval(-86_500),
            endDate: now.addingTimeInterval(-86_400),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )

        let snapshot = makeBottomSheetSnapshot(from: [oneHourCompleted, oneDayCompleted])

        XCTAssertEqual(snapshot.compactItems.map(\.primaryRemainingText), ["Done", "Done"])
        XCTAssertEqual(snapshot.compactItems.map(\.secondaryTotalText), ["30s", "04:16"])
        XCTAssertEqual(snapshot.compactItems.map(\.tertiaryStatusText), ["1h ago", "1d ago"])
        XCTAssertFalse(snapshot.compactItems.compactMap(\.tertiaryStatusText).contains("long ago"))
    }

    func testLargeItemsKeepTotalDurationAsSingleSecondaryValue() {
        let snapshot = makeBottomSheetSnapshot(from: bottomSheetSampleTimers())
        let runningItem = snapshot.sections
            .flatMap(\.items)
            .first { $0.id == UUID(uuidString: "22222222-2222-2222-2222-222222222222")! }

        XCTAssertEqual(runningItem?.identityCue.markerText, "T1")
        XCTAssertEqual(runningItem?.remainingText, "00:25")
        XCTAssertEqual(runningItem?.totalDurationText, "02:00")
        XCTAssertEqual(runningItem?.timingText, "Ends soon")
        XCTAssertEqual(runningItem?.contextText, "Base 1/30s · 6 stops")
    }

    func testLargeItemsHideTopLineWhenNameOnlyRepeatsDurationOrContext() {
        let snapshot = makeBottomSheetSnapshot(from: [bottomSheetRedundantLargePresentationTimer()])
        let item = snapshot.sections
            .flatMap(\.items)
            .first

        XCTAssertNil(item?.title)
        XCTAssertEqual(item?.totalDurationText, "02:00")
        XCTAssertEqual(item?.contextText, "Base 1/30s · 6 stops")
    }

    func testCompletedLargeItemUsesSimplerPresentation() {
        let snapshot = makeBottomSheetSnapshot(from: bottomSheetSampleTimers())
        let completedItem = snapshot.sections[1].items.first

        XCTAssertEqual(completedItem?.identityCue.markerText, "T3")
        XCTAssertEqual(completedItem?.remainingText, "Done")
        XCTAssertEqual(completedItem?.totalDurationText, "00:45")
        XCTAssertEqual(completedItem?.timingText, "Completed recently")
        XCTAssertEqual(completedItem?.contextText, "Base 1/15s · 8 stops")
    }

    func testCompletedLargeItemDoesNotUseZeroSecondsAsPrimaryText() {
        let snapshot = makeBottomSheetSnapshot(from: bottomSheetSampleTimers())
        let completedItem = snapshot.sections[1].items.first

        XCTAssertEqual(completedItem?.remainingText, "Done")
        XCTAssertNotEqual(completedItem?.remainingText, "0s")
    }
}
