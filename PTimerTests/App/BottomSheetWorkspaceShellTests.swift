import SwiftUI
import UIKit
import XCTest
@testable import PTimer

final class BottomSheetWorkspaceShellTests: XCTestCase {
    func testAppDelegateAdvertisesPortraitOnlyOrientation() {
        let appDelegate = PTimerAppDelegate()

        XCTAssertEqual(
            appDelegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil),
            .portrait
        )
    }

    @MainActor
    func testStateStoreDefaultsToCompact() {
        let store = BottomSheetWorkspaceStateStore()

        XCTAssertEqual(store.detent, .compact)
    }

    @MainActor
    func testStateStoreTransitionsBetweenCompactAndLargeDetents() {
        let store = BottomSheetWorkspaceStateStore()

        store.transition(to: .large)
        XCTAssertEqual(store.detent, .large)

        store.transition(to: .compact)
        XCTAssertEqual(store.detent, .compact)
    }

    @MainActor
    func testStateStoreExpandAndCollapseModelCompactVsLargeFlow() {
        let store = BottomSheetWorkspaceStateStore()

        XCTAssertFalse(store.isExpanded)

        store.expand()
        XCTAssertEqual(store.detent, .large)
        XCTAssertTrue(store.isExpanded)

        store.collapse()
        XCTAssertEqual(store.detent, .compact)
        XCTAssertFalse(store.isExpanded)
    }

    @MainActor
    func testStateStoreDragEndSupportsExpandAndCollapseReturnPath() {
        let store = BottomSheetWorkspaceStateStore()

        store.handleDragEnd(translation: -70)
        XCTAssertEqual(store.detent, .compact)

        store.handleDragEnd(translation: -110)
        XCTAssertEqual(store.detent, .large)

        store.handleDragEnd(translation: 40)
        XCTAssertEqual(store.detent, .large)

        store.handleDragEnd(translation: 92)
        XCTAssertEqual(store.detent, .compact)
    }

    @MainActor
    func testCompactRequiresIntentionalUpwardDragToExpand() {
        let store = BottomSheetWorkspaceStateStore()

        store.handleDragEnd(translation: -91)
        XCTAssertEqual(store.detent, .compact)

        store.handleDragEnd(translation: -92)
        XCTAssertEqual(store.detent, .large)
    }

    @MainActor
    func testLargeCollapsesWithMoreForgivingDownwardDrag() {
        let store = BottomSheetWorkspaceStateStore(detent: .large)

        store.handleDragEnd(translation: 63)
        XCTAssertEqual(store.detent, .large)

        store.handleDragEnd(translation: 64)
        XCTAssertEqual(store.detent, .compact)
    }

    func testLayoutMetricsExposeOnlyLargeFixedHeight() {
        XCTAssertNil(BottomSheetLayoutMetrics.fixedHeight(for: .compact))
        XCTAssertEqual(BottomSheetLayoutMetrics.fixedHeight(for: .large), 560)
    }

    func testLayoutMetricsExposeMainContentReservationPerDetent() {
        let compactReservation = BottomSheetLayoutMetrics.mainContentReservation(for: .compact)
        let largeReservation = BottomSheetLayoutMetrics.mainContentReservation(for: .large)

        XCTAssertGreaterThan(compactReservation, 0)
        XCTAssertLessThan(compactReservation, largeReservation)
        XCTAssertEqual(compactReservation, BottomSheetLayoutMetrics.compactMainContentReservation)
        XCTAssertEqual(largeReservation, BottomSheetLayoutMetrics.largeFixedHeight)
    }

    func testWorkspaceTitleCopyUsesTimersLabel() {
        XCTAssertEqual(BottomSheetWorkspaceCopy.title, "Timers")
    }

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

    /// Compact mini card has a fixed `timerCardHeight` that must
    /// accommodate every internal sub-frame for the worst-case
    /// content path (film-identity timer with the layered decorative
    /// timeline and the bottom identity badge). The card uses
    /// `clipShape` after its frame, so any over-budget content
    /// disappears at the bottom edge — the source of PTIMER-124.
    func testCompactCardHeightAccommodatesWorstCaseLayoutBudget() {
        // Sub-frame heights mirror `CompactTimerMiniCardView`'s body:
        //   - Status header HStack (status icon + secondary total): explicit 22pt frame.
        //   - Primary remaining-text VStack: explicit 34pt minHeight.
        //   - Tertiary status text or identity-film text slot: caption2 line
        //     height (~13pt) plus 2pt top padding = 15pt. Falls back to a 6pt
        //     spacer when both are nil, so 15pt is the worst case.
        //   - Decorative timeline (running/paused) or fallback spacer: 9pt minHeight.
        //   - Bottom identity-badge HStack: 10pt minHeight + 3pt top padding = 13pt.
        // Outer card padding is 9pt top + 12pt bottom = 21pt.
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

    @MainActor
    func testCompactCardSnapshotEntersWorstCaseFilmIdentityLayout() {
        // Reproduces the PTIMER-124 setup: film-mode running timer
        // started from a camera slot with a long-exposure duration.
        // The snapshot must populate `identityFilmText` and request
        // all three decorative timeline layers so the compact card
        // renders the worst-case content stack the metrics test sizes
        // the card height for. If a future refactor stops surfacing
        // either signal here, the regression budget tracked by
        // `testCompactCardHeightAccommodatesWorstCaseLayoutBudget`
        // would silently stop being load-bearing.
        let snapshot = makeSnapshot(from: [filmIdentityRunningTimer()])
        let item = snapshot.compactItems.first

        XCTAssertEqual(item?.identityFilmText, "Provia 100F")
        XCTAssertTrue(item?.showsDecorativeTimeline ?? false)
        XCTAssertEqual(item?.visibleLayerCount, 3)

        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)
        XCTAssertGreaterThan(host.view.bounds.height, 0)
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

    func testDimOpacityOnlyAppearsForLargeState() {
        XCTAssertEqual(BottomSheetLayoutMetrics.dimOpacity(for: .compact), 0)
        XCTAssertGreaterThan(BottomSheetLayoutMetrics.dimOpacity(for: .large), 0)
    }

    @MainActor
    func testLargeDragDownCollapsesDirectlyToCompact() {
        let store = BottomSheetWorkspaceStateStore(detent: .large)

        store.handleDragEnd(translation: 92)
        XCTAssertEqual(store.detent, .compact)
    }

    func testVisiblePausedCopyUsesPausedPresentationLabel() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let pausedItem = snapshot.sections
            .flatMap(\.items)
            .first { $0.status == .paused }

        XCTAssertEqual(pausedItem?.statusLabel, "Paused")
    }

    func testCompactProgressUsesSixtySecondLayerForShortRunningTimer() {
        let snapshot = makeSnapshot(from: [secondsScaleTimer()]) // 30s timer, 25s remaining
        let item = tryUnwrapCompactItem(from: snapshot)

        XCTAssertEqual(item.visibleLayerCount, 1)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertNil(item.sixtyMinuteLayer)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 25.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressUsesSixtyMinuteAndSixtySecondLayersForSixtyFourSecondTimer() throws {
        let snapshot = makeSnapshot(from: [minuteScaleTimer()]) // 64s timer, 54s remaining
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 54.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 54.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressUsesSixtyMinuteAndSixtySecondLayersForEightMinuteTimer() throws {
        let snapshot = makeSnapshot(from: [eightMinuteScaleTimer()]) // 480s timer, 478s remaining
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 478.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 58.0 / 60.0, accuracy: 0.001) // 478 % 60 = 58
    }

    func testCompactProgressUsesSixtyMinuteAndSixtySecondLayersForThirtyFourMinuteTimer() throws {
        let snapshot = makeSnapshot(from: [thirtyFourMinuteScaleTimer()]) // 2048s timer, 2048s remaining
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 2048.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 8.0 / 60.0, accuracy: 0.001) // 2048 % 60 = 8
    }

    func testCompactProgressUsesOriginalScaleSixtyMinuteAndSixtySecondLayersForLongRunningTimer() throws {
        let snapshot = makeSnapshot(from: [hourScaleTimer()]) // 7200s (2h) timer, 7200s remaining
        let item = tryUnwrapCompactItem(from: snapshot)
        let originalScaleLayer = try XCTUnwrap(item.originalScaleLayer)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 3)
        XCTAssertEqual(originalScaleLayer.fraction, 2.0 / 24.0, accuracy: 0.001)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 1.0, accuracy: 0.001) // 7200 % 3600 = 0 -> 1.0
        XCTAssertEqual(item.sixtySecondLayer.fraction, 1.0, accuracy: 0.001) // 7200 % 60 = 0 -> 1.0
    }

    func testCompactVisibleLayerCountPolicyBoundaries() {
        // Use a single captured reference instant so startDate / endDate /
        // referenceDate are derived deterministically; the layered-progress
        // policy depends on `duration`, not absolute clock time.
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Boundary: 59s duration -> 1 layer
        let timer59 = RunningTimerItem(
            id: UUID(), order: 1, name: "59s", basisSummary: "", duration: 59,
            startDate: now, endDate: now.addingTimeInterval(59),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item59 = BottomSheetWorkspaceSnapshot.make(
            from: [timer59],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item59.visibleLayerCount, 1)
        XCTAssertNotNil(item59.sixtySecondLayer)
        XCTAssertNil(item59.sixtyMinuteLayer)
        XCTAssertNil(item59.originalScaleLayer)

        // Boundary: 60s duration -> 2 layers
        let timer60 = RunningTimerItem(
            id: UUID(), order: 1, name: "60s", basisSummary: "", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item60 = BottomSheetWorkspaceSnapshot.make(
            from: [timer60],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item60.visibleLayerCount, 2)
        XCTAssertNotNil(item60.sixtySecondLayer)
        XCTAssertNotNil(item60.sixtyMinuteLayer)
        XCTAssertNil(item60.originalScaleLayer)

        // Boundary: 3599s duration -> 2 layers
        let timer3599 = RunningTimerItem(
            id: UUID(), order: 1, name: "3599s", basisSummary: "", duration: 3599,
            startDate: now, endDate: now.addingTimeInterval(3599),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item3599 = BottomSheetWorkspaceSnapshot.make(
            from: [timer3599],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item3599.visibleLayerCount, 2)

        // Boundary: 3600s duration -> 3 layers
        let timer3600 = RunningTimerItem(
            id: UUID(), order: 1, name: "3600s", basisSummary: "", duration: 3600,
            startDate: now, endDate: now.addingTimeInterval(3600),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let item3600 = BottomSheetWorkspaceSnapshot.make(
            from: [timer3600],
            formatRemaining: { _ in "" },
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        ).compactItems[0]
        XCTAssertEqual(item3600.visibleLayerCount, 3)
        XCTAssertNotNil(item3600.sixtySecondLayer)
        XCTAssertNotNil(item3600.sixtyMinuteLayer)
        XCTAssertNotNil(item3600.originalScaleLayer)
    }

    func testCompactProgressUsesExactFractionsForComplexRemainingTimes() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let timer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Complex Timer",
            basisSummary: "...",
            duration: 120, // 2 minutes
            startDate: now.addingTimeInterval(-35),
            endDate: now.addingTimeInterval(85), // 85s remaining (1m 25s)
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )

        let snapshot = makeSnapshot(from: [timer])
        let item = tryUnwrapCompactItem(from: snapshot)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 25.0 / 60.0, accuracy: 0.001) // 85 % 60 = 25
    }

    func testCompactProgressStaysFrozenForPausedTimer() throws {
        let snapshot = makeSnapshot(from: [pausedProgressTimer()]) // 120s duration, 45s paused remaining
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 45.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 45.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressSettlesAtCompleteForCompletedTimer() throws {
        let snapshot = makeSnapshot(from: [completedProgressTimer()]) // 75s duration, completed
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 0, accuracy: 0.001)
    }

    func testCompactProgressClampsOriginalScaleLayerForMultiDayTimer() throws {
        let snapshot = makeSnapshot(from: [longDurationTimer()]) // 367200s (>24h), running
        let item = tryUnwrapCompactItem(from: snapshot)
        let originalScaleLayer = try XCTUnwrap(item.originalScaleLayer)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 3)
        XCTAssertEqual(originalScaleLayer.fraction, 1, accuracy: 0.001) // Clamped to 24h
        XCTAssertEqual(sixtyMinuteLayer.fraction, 1, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 1, accuracy: 0.001)
    }

    func testCompletedCompactCardPrioritizesExpiredStateAndRelativeTime() {
        let completedTimer = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [completedTimer])

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

        let snapshot = makeSnapshot(from: [oneHourCompleted, oneDayCompleted])

        XCTAssertEqual(snapshot.compactItems.map(\.primaryRemainingText), ["Done", "Done"])
        XCTAssertEqual(snapshot.compactItems.map(\.secondaryTotalText), ["30s", "04:16"])
        XCTAssertEqual(snapshot.compactItems.map(\.tertiaryStatusText), ["1h ago", "1d ago"])
        XCTAssertFalse(snapshot.compactItems.compactMap(\.tertiaryStatusText).contains("long ago"))
    }

    func testLargeItemsKeepTotalDurationAsSingleSecondaryValue() {
        let snapshot = makeSnapshot(from: sampleTimers())
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
        let snapshot = makeSnapshot(from: [redundantLargePresentationTimer()])
        let item = snapshot.sections
            .flatMap(\.items)
            .first

        XCTAssertNil(item?.title)
        XCTAssertEqual(item?.totalDurationText, "02:00")
        XCTAssertEqual(item?.contextText, "Base 1/30s · 6 stops")
    }

    func testCompletedLargeItemUsesSimplerPresentation() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let completedItem = snapshot.sections[1].items.first

        XCTAssertEqual(completedItem?.identityCue.markerText, "T3")
        XCTAssertEqual(completedItem?.remainingText, "Done")
        XCTAssertEqual(completedItem?.totalDurationText, "00:45")
        XCTAssertEqual(completedItem?.timingText, "Completed recently")
        XCTAssertEqual(completedItem?.contextText, "Base 1/15s · 8 stops")
    }

    func testCompletedLargeItemDoesNotUseZeroSecondsAsPrimaryText() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let completedItem = snapshot.sections[1].items.first

        XCTAssertEqual(completedItem?.remainingText, "Done")
        XCTAssertNotEqual(completedItem?.remainingText, "0s")
    }

    func testLargeHeightCreatesLargerManagementViewportBudget() {
        let compactHeight = BottomSheetLayoutMetrics.mainContentReservation(for: .compact)
        let largeHeight = BottomSheetLayoutMetrics.largeFixedHeight

        XCTAssertGreaterThan(largeHeight - compactHeight, 300)
    }

    @MainActor
    func testCompactStateRendersActualSummaryContent() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(snapshot.compactItems.isEmpty)
        XCTAssertEqual(snapshot.compactItems.first?.primaryRemainingText, "55s")
        XCTAssertEqual(snapshot.compactItems.first?.secondaryTotalText, "03:00")
        XCTAssertEqual(snapshot.compactItems.map(\.identityCue.markerText), ["T2", "T1", "T3"])
        XCTAssertEqual(snapshot.compactItems.count, 3)
        XCTAssertEqual(snapshot.compactOverflowText, "+1")
        XCTAssertFalse(host.view.containsText("+2 more in workspace"))
    }

    @MainActor
    func testCompactStateDoesNotRenderStopCountOrStatusWords() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(host.view.containsText("Base 1/30s · 6 stops"))
        XCTAssertFalse(host.view.containsText("Base 1/60s · 10 stops"))
        XCTAssertFalse(host.view.containsText("Running"))
        XCTAssertFalse(host.view.containsText("Paused"))
        XCTAssertFalse(host.view.containsText("Done"))
    }

    @MainActor
    func testLargeStateRendersActualWorkspaceListContent() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .large, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertEqual(snapshot.sections.map(\.title), ["Active", "Recently Completed"])
        XCTAssertEqual(snapshot.sections.first?.items.first?.title, "Paused Hold")
        XCTAssertEqual(snapshot.sections.first?.items.first?.identityCue.markerText, "T2")
        XCTAssertEqual(snapshot.sections.last?.items.first?.identityCue.markerText, "T3")
        XCTAssertEqual(snapshot.sections.first?.items.last?.actions.map(\.title), ["Pause"])
        XCTAssertGreaterThan(snapshot.completedCount, 0)
        XCTAssertNotNil(host.view)
    }

    @MainActor
    func testLargeStateOmitsClearStripWhenNoCompletedTimersExist() {
        let snapshot = makeSnapshot(from: [secondsScaleTimer(), minuteScaleTimer()])
        let host = makeBottomSheetHost(detent: .large, snapshot: snapshot)

        XCTAssertEqual(snapshot.completedCount, 0)
        XCTAssertFalse(host.view.containsText("Clear"))
    }

    @MainActor
    func testLargeHeaderDoesNotRenderSummarySentenceOrCountChips() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .large, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(host.view.containsText("Running 1 · Paused 1 · Done 2"))
        XCTAssertFalse(host.view.containsText("Running 1"))
        XCTAssertFalse(host.view.containsText("Paused 1"))
        XCTAssertFalse(host.view.containsText("Done 2"))
    }

    @MainActor
    func testBottomSheetUsesHandleAreaAndRemovesLargeDetentChevronButton() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .large, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertNil(host.view.findView(accessibilityIdentifier: "bottom-sheet-collapse-button"))
    }

    @MainActor
    func testCompactEmptyStateStaysMinimalWithoutOpenCallToAction() {
        let snapshot = makeSnapshot(from: [])

        XCTAssertEqual(snapshot.compactItems.count, 0)

        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)
        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(host.view.containsText("Open Workspace"))
    }

    @MainActor
    func testExposureScreenLoadsWithBottomSheetShell() {
        let host = UIHostingController(
            rootView: ExposureCalculatorScreen()
                .frame(width: 390, height: 844)
        )

        XCTAssertNotNil(host.view)
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()

        XCTAssertGreaterThan(host.view.bounds.height, 0)
    }

    func testExposureScreenPinsCalculatorReservedHeightToCompactSheetBudget() {
        let reservedHeight = ExposureCalculatorScreen.calculatorReservedHeight(
            screenHeight: 844,
            topSafeArea: 59,
            bottomSafeArea: 34
        )
        let compactHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: 844,
            bottomSheetDetent: .compact,
            topSafeArea: 59,
            bottomSafeArea: 34
        )
        let largeHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: 844,
            bottomSheetDetent: .large,
            topSafeArea: 59,
            bottomSafeArea: 34
        )

        XCTAssertEqual(reservedHeight, compactHeight)
        XCTAssertGreaterThan(reservedHeight, largeHeight)
    }

    @MainActor
    func testLargeStateRendersLargeWorkspaceShell() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .large, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(snapshot.sections.isEmpty)
        XCTAssertEqual(snapshot.sections.map(\.title), ["Active", "Recently Completed"])
        XCTAssertFalse(host.view.containsText("Start a timer to pin it here."))
    }

    func testIPhone17ViewportKeepsDenseMainContentAboveCompactSheet() {
        let availableHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: 844,
            bottomSheetDetent: .compact,
            topSafeArea: 59,
            bottomSafeArea: 34
        )

        let requiredHeight = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .dense)

        XCTAssertGreaterThan(availableHeight, 0)
        XCTAssertGreaterThanOrEqual(availableHeight, requiredHeight)
    }

    func testIPhone17ViewportLeavesMeaningfulLargeWorkspaceHeight() {
        let largeHeight = BottomSheetLayoutMetrics.largeFixedHeight

        XCTAssertGreaterThanOrEqual(largeHeight, 560)
    }

    private func sampleTimers() -> [RunningTimerItem] {
        let now = Date(timeIntervalSince1970: 1_000)

        return [
            RunningTimerItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                order: 3,
                name: "Completed Latest",
                basisSummary: "Base 1/15s · 8 stops",
                duration: 45,
                startDate: now.addingTimeInterval(-45),
                endDate: now.addingTimeInterval(-5),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                order: 1,
                name: "Running Soon",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 120,
                startDate: now,
                endDate: now.addingTimeInterval(25),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                order: 2,
                name: "Paused Hold",
                basisSummary: "Base 1/60s · 10 stops",
                duration: 180,
                startDate: now.addingTimeInterval(-20),
                endDate: now.addingTimeInterval(160),
                pausedRemainingTime: 55,
                pausedAt: now.addingTimeInterval(-15),
                status: .paused,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                order: 4,
                name: "Completed Earlier",
                basisSummary: "Base 1/4s · 4 stops",
                duration: 30,
                startDate: now.addingTimeInterval(-60),
                endDate: now.addingTimeInterval(-20),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            )
        ]
    }

    private func longDurationTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_000)

        return RunningTimerItem(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            order: 5,
            name: "Very Long Timer Name That Exceeds Compact Width",
            basisSummary: "Base 1/2s · 18 stops",
            duration: 367_200,
            startDate: now,
            endDate: now.addingTimeInterval(367_200),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func secondsScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 4_000)

        return RunningTimerItem(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            order: 7,
            name: "Seconds Scale",
            basisSummary: "Base 1/15s · 3 stops",
            duration: 30,
            startDate: now.addingTimeInterval(-5),
            endDate: now.addingTimeInterval(25),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func minuteScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 5_000)

        return RunningTimerItem(
            id: UUID(uuidString: "23232323-2323-2323-2323-232323232323")!,
            order: 8,
            name: "Minute Scale",
            basisSummary: "Base 1/30s · 5 stops",
            duration: 64,
            startDate: now.addingTimeInterval(-10),
            endDate: now.addingTimeInterval(54),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func eightMinuteScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 5_500)

        return RunningTimerItem(
            id: UUID(uuidString: "28282828-2828-2828-2828-282828282828")!,
            order: 12,
            name: "Eight Minute Scale",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 480,
            startDate: now.addingTimeInterval(-2),
            endDate: now.addingTimeInterval(478),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func thirtyFourMinuteScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 5_800)

        return RunningTimerItem(
            id: UUID(uuidString: "38383838-3838-3838-3838-383838383838")!,
            order: 13,
            name: "Thirty Four Minute Scale",
            basisSummary: "Base 1/60s · 7 stops",
            duration: 2_048,
            startDate: now,
            endDate: now.addingTimeInterval(2_048),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func hourScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 6_000)

        return RunningTimerItem(
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!,
            order: 9,
            name: "Hour Scale",
            basisSummary: "Base 1/60s · 7 stops",
            duration: 7_200,
            startDate: now,
            endDate: now.addingTimeInterval(7_200),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func filmIdentityRunningTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 9_000)

        return RunningTimerItem(
            id: UUID(uuidString: "67676767-6767-6767-6767-676767676767")!,
            order: 1,
            name: "Film Identity Card",
            basisSummary: "Base 1/3s · 14 stops",
            duration: 19_660,
            startDate: now,
            endDate: now.addingTimeInterval(19_660),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now,
            cameraSlot: CameraSlotIdentity(id: .camera4),
            filmDisplayName: "Provia 100F",
            filmProfileQualifier: nil,
            exposureSource: .filmAdjustedShutter
        )
    }

    private func pausedProgressTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 7_000)

        return RunningTimerItem(
            id: UUID(uuidString: "45454545-4545-4545-4545-454545454545")!,
            order: 10,
            name: "Paused Progress",
            basisSummary: "Base 1/8s · 4 stops",
            duration: 120,
            startDate: now.addingTimeInterval(-80),
            endDate: now.addingTimeInterval(60),
            pausedRemainingTime: 45,
            pausedAt: now.addingTimeInterval(-10),
            status: .paused,
            referenceDate: now
        )
    }

    private func completedProgressTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 8_000)

        return RunningTimerItem(
            id: UUID(uuidString: "56565656-5656-5656-5656-565656565656")!,
            order: 11,
            name: "Completed Progress",
            basisSummary: "Base 1/4s · 2 stops",
            duration: 75,
            startDate: now.addingTimeInterval(-90),
            endDate: now.addingTimeInterval(-15),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )
    }

    private func redundantLargePresentationTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_500)

        return RunningTimerItem(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            order: 6,
            name: "6 stops - 02:00",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 120,
            startDate: now,
            endDate: now.addingTimeInterval(25),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    private func makeSnapshot(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        let completedRelativeTimeFormatter = CompletedRelativeTimeFormatter()

        return BottomSheetWorkspaceSnapshot.make(
            from: timers,
            formatRemaining: { seconds in
                let remaining = Int(seconds.rounded(.down))
                if remaining >= 3_600 {
                    let hours = remaining / 3_600
                    let minutes = (remaining % 3_600) / 60
                    let secs = remaining % 60
                    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
                }
                let minutes = remaining / 60
                let secs = remaining % 60
                return String(format: "%02d:%02d", minutes, secs)
            },
            timeContext: { timer in
                switch timer.status {
                case .running:
                    return "Ends soon"
                case .paused:
                    return "Paused recently"
                case .completed:
                    return "Completed recently"
                }
            },
            compactCompletedSupplementaryText: { timer in
                switch timer.status {
                case .completed:
                    guard let completionDate = timer.completedAt else {
                        return "--"
                    }

                    return completedRelativeTimeFormatter.compactString(
                        from: completionDate,
                        relativeTo: timer.referenceDate
                    )
                case .running, .paused:
                    return nil
                }
            }
        )
    }

    private func tryUnwrapCompactItem(from snapshot: BottomSheetWorkspaceSnapshot) -> BottomSheetCompactItem {
        guard let item = snapshot.compactItems.first else {
            XCTFail("Expected a compact item in snapshot")
            fatalError("Missing compact item")
        }

        return item
    }

    @MainActor
    private func makeBottomSheetHost(
        detent: BottomSheetDetent,
        snapshot: BottomSheetWorkspaceSnapshot
    ) -> UIViewController {
        let store = BottomSheetWorkspaceStateStore(detent: detent)
        return makeBottomSheetHost(store: store, snapshot: snapshot)
    }

    @MainActor
    private func makeBottomSheetHost(
        store: BottomSheetWorkspaceStateStore,
        snapshot: BottomSheetWorkspaceSnapshot
    ) -> UIViewController {
        let host = UIHostingController(
            rootView: BottomSheetWorkspaceShell(
                stateStore: store,
                snapshot: snapshot,
                onPauseTimer: { _ in },
                onResumeTimer: { _ in },
                onRemoveTimer: { _ in },
                onStartTimerAgain: { _ in },
                onClearCompletedTimers: {}
            )
            .frame(width: 390, height: 480)
        )

        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 480)
        host.view.layoutIfNeeded()
        return host
    }
}

private extension UIView {
    func containsText(_ text: String) -> Bool {
        if let label = self as? UILabel, label.text == text {
            return true
        }

        if let button = self as? UIButton, button.title(for: .normal) == text {
            return true
        }

        for subview in subviews {
            if subview.containsText(text) {
                return true
            }
        }

        return false
    }

    func findView(accessibilityIdentifier: String) -> UIView? {
        if self.accessibilityIdentifier == accessibilityIdentifier {
            return self
        }

        for subview in subviews {
            if let match = subview.findView(accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }

        return nil
    }
}
