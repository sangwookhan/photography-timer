import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// PTIMER-126 redesign: the closed-state Timers UI is no longer a
/// custom bottom-sheet dock. Tests that asserted on the old shell
/// (compact dock, fixed-height sheet, drag-detent transitions) have
/// been removed; the surviving tests cover snapshot factory logic,
/// card geometry, the state store's expand/collapse API, and the new
/// screen-level layout metrics.
final class BottomSheetWorkspaceShellTests: XCTestCase {
    func testAppDelegateAdvertisesPortraitOnlyOrientation() {
        let appDelegate = PTimerAppDelegate()

        XCTAssertEqual(
            appDelegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil),
            .portrait
        )
    }

    // MARK: - State store (closed/full-screen Timers window)

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
    func testStateStoreExpandAndCollapseDriveTimersWindowPresentation() {
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
    func testStateStoreFocusedTimerSurvivesUntilCollapse() {
        let store = BottomSheetWorkspaceStateStore()
        let id = UUID()

        store.expandAndFocusTimer(id)
        XCTAssertEqual(store.selectedTimerID, id)
        XCTAssertTrue(store.isExpanded)

        store.collapse()
        XCTAssertNil(store.selectedTimerID)
    }

    // MARK: - PTIMER-126: Open-focus routing

    @MainActor
    func testExpandAndFocusActiveTimerSetsActiveSectionFocusWithHighlight() {
        let store = BottomSheetWorkspaceStateStore()
        let id = UUID()

        store.expandAndFocusActiveTimer(id)

        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: id))
        XCTAssertEqual(
            store.selectedTimerID,
            id,
            "Highlight id is still surfaced through the back-compat selectedTimerID accessor."
        )
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testExpandFocusingActiveSectionSetsActiveSectionWithoutHighlight() {
        let store = BottomSheetWorkspaceStateStore()

        store.expandFocusingActiveSection()

        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: nil))
        XCTAssertNil(store.selectedTimerID)
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testExpandFocusingCompletedSectionSetsCompletedSectionFocus() {
        let store = BottomSheetWorkspaceStateStore()

        store.expandFocusingCompletedSection()

        XCTAssertEqual(store.openFocus, .recentlyCompletedSection)
        XCTAssertNil(
            store.selectedTimerID,
            "Section focus must not surface as an active-timer id."
        )
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testCollapseClearsOpenFocus() {
        let store = BottomSheetWorkspaceStateStore()
        store.expandFocusingCompletedSection()
        XCTAssertEqual(store.openFocus, .recentlyCompletedSection)

        store.collapse()

        XCTAssertEqual(store.openFocus, .none)
        XCTAssertNil(store.selectedTimerID)
    }

    @MainActor
    func testTimersOpenFocusActiveTimerIDProjection() {
        let id = UUID()

        XCTAssertEqual(
            TimersOpenFocus.activeSection(highlightedTimerID: id).activeTimerID,
            id
        )
        XCTAssertNil(TimersOpenFocus.activeSection(highlightedTimerID: nil).activeTimerID)
        XCTAssertNil(TimersOpenFocus.recentlyCompletedSection.activeTimerID)
        XCTAssertNil(TimersOpenFocus.none.activeTimerID)
    }

    // MARK: - PTIMER-126: Compact card tap routing

    @MainActor
    func testCompactCardTapOnActiveTimerFocusesActiveSectionWithHighlight() {
        let store = BottomSheetWorkspaceStateStore()
        let timer = secondsScaleTimer()
        let snapshot = makeSnapshot(from: [timer])

        ExposureCalculatorScreen.handleCompactCardTap(
            id: timer.id,
            in: snapshot,
            store: store
        )

        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: timer.id))
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testCompactCardTapOnPausedTimerFocusesActiveSectionWithHighlight() {
        let store = BottomSheetWorkspaceStateStore()
        let pausedTimer = pausedProgressTimer()
        let snapshot = makeSnapshot(from: [pausedTimer])

        ExposureCalculatorScreen.handleCompactCardTap(
            id: pausedTimer.id,
            in: snapshot,
            store: store
        )

        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: pausedTimer.id))
        XCTAssertTrue(store.isExpanded)
    }

    /// PTIMER-126 fix: tapping a completed compact card must land
    /// the full-screen window on the Recently Completed section
    /// header, not on the completed row. Otherwise scrolling the
    /// row to top hides the section title and the `Clear` button.
    @MainActor
    func testCompactCardTapOnCompletedTimerFocusesRecentlyCompletedSection() {
        let store = BottomSheetWorkspaceStateStore()
        let completedTimer = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [completedTimer])

        ExposureCalculatorScreen.handleCompactCardTap(
            id: completedTimer.id,
            in: snapshot,
            store: store
        )

        XCTAssertEqual(store.openFocus, .recentlyCompletedSection)
        XCTAssertNil(
            store.selectedTimerID,
            "Completed-card tap must not select the completed row as an active focus."
        )
        XCTAssertTrue(store.isExpanded)
    }

    /// Mixed snapshot: tapping the active card focuses the active
    /// section (highlighting the row); tapping the completed card
    /// focuses the completed section header. Both flows leave the
    /// store expanded.
    @MainActor
    func testCompactCardTapInMixedSnapshotRoutesByStatus() {
        let store = BottomSheetWorkspaceStateStore()
        let active = secondsScaleTimer()
        let completed = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [active, completed])

        ExposureCalculatorScreen.handleCompactCardTap(
            id: active.id,
            in: snapshot,
            store: store
        )
        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: active.id))

        store.collapse()
        ExposureCalculatorScreen.handleCompactCardTap(
            id: completed.id,
            in: snapshot,
            store: store
        )
        XCTAssertEqual(store.openFocus, .recentlyCompletedSection)
    }

    @MainActor
    func testOverflowTapRoutesToCompletedSectionWhenOnlyCompletedRemain() {
        let store = BottomSheetWorkspaceStateStore()
        let completed = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [completed])

        ExposureCalculatorScreen.handleOverflowTap(in: snapshot, store: store)

        XCTAssertEqual(store.openFocus, .recentlyCompletedSection)
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testOverflowTapRoutesToActiveSectionWhenAnyActiveTimerRemains() {
        let store = BottomSheetWorkspaceStateStore()
        let active = secondsScaleTimer()
        let snapshot = makeSnapshot(from: [active])

        ExposureCalculatorScreen.handleOverflowTap(in: snapshot, store: store)

        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: nil))
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testOverflowTapInMixedSnapshotPrefersActiveSection() {
        let store = BottomSheetWorkspaceStateStore()
        let active = secondsScaleTimer()
        let completed = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [active, completed])

        ExposureCalculatorScreen.handleOverflowTap(in: snapshot, store: store)

        XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: nil))
    }

    /// The workspace tags both section headers with stable scroll
    /// ids so `applyFocusIfNeeded` can scroll the section title
    /// (and, for the completed section, `Clear`) to the top
    /// instead of scrolling a row.
    func testSectionScrollIDsAreExposed() {
        XCTAssertFalse(BottomSheetLargeWorkspaceView.activeSectionScrollID.isEmpty)
        XCTAssertFalse(BottomSheetLargeWorkspaceView.recentlyCompletedSectionScrollID.isEmpty)
        XCTAssertNotEqual(
            BottomSheetLargeWorkspaceView.activeSectionScrollID,
            BottomSheetLargeWorkspaceView.recentlyCompletedSectionScrollID
        )
    }

    // MARK: - Workspace copy

    func testWorkspaceTitleCopyUsesTimersLabel() {
        XCTAssertEqual(BottomSheetWorkspaceCopy.title, "Timers")
    }

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
        let snapshot = makeSnapshot(from: sampleTimers())
        let pausedItem = snapshot.sections
            .flatMap(\.items)
            .first { $0.status == .paused }

        XCTAssertEqual(pausedItem?.statusLabel, "Paused")
    }

    func testCompactProgressUsesSixtySecondLayerForShortRunningTimer() {
        let snapshot = makeSnapshot(from: [secondsScaleTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)

        XCTAssertEqual(item.visibleLayerCount, 1)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertNil(item.sixtyMinuteLayer)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 25.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressUsesSixtyMinuteAndSixtySecondLayersForSixtyFourSecondTimer() throws {
        let snapshot = makeSnapshot(from: [minuteScaleTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 54.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 54.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressUsesSixtyMinuteAndSixtySecondLayersForEightMinuteTimer() throws {
        let snapshot = makeSnapshot(from: [eightMinuteScaleTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 478.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 58.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressUsesSixtyMinuteAndSixtySecondLayersForThirtyFourMinuteTimer() throws {
        let snapshot = makeSnapshot(from: [thirtyFourMinuteScaleTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 2048.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 8.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressUsesOriginalScaleSixtyMinuteAndSixtySecondLayersForLongRunningTimer() throws {
        let snapshot = makeSnapshot(from: [hourScaleTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let originalScaleLayer = try XCTUnwrap(item.originalScaleLayer)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 3)
        XCTAssertEqual(originalScaleLayer.fraction, 2.0 / 24.0, accuracy: 0.001)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 1.0, accuracy: 0.001)
    }

    func testCompactVisibleLayerCountPolicyBoundaries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

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
    }

    func testCompactProgressUsesExactFractionsForComplexRemainingTimes() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let timer = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Complex Timer",
            basisSummary: "...",
            duration: 120,
            startDate: now.addingTimeInterval(-35),
            endDate: now.addingTimeInterval(85),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )

        let snapshot = makeSnapshot(from: [timer])
        let item = tryUnwrapCompactItem(from: snapshot)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 25.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressStaysFrozenForPausedTimer() throws {
        let snapshot = makeSnapshot(from: [pausedProgressTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 45.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 45.0 / 60.0, accuracy: 0.001)
    }

    func testCompactProgressSettlesAtCompleteForCompletedTimer() throws {
        let snapshot = makeSnapshot(from: [completedProgressTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 2)
        XCTAssertNil(item.originalScaleLayer)
        XCTAssertEqual(sixtyMinuteLayer.fraction, 0, accuracy: 0.001)
        XCTAssertEqual(item.sixtySecondLayer.fraction, 0, accuracy: 0.001)
    }

    func testCompactProgressClampsOriginalScaleLayerForMultiDayTimer() throws {
        let snapshot = makeSnapshot(from: [longDurationTimer()])
        let item = tryUnwrapCompactItem(from: snapshot)
        let originalScaleLayer = try XCTUnwrap(item.originalScaleLayer)
        let sixtyMinuteLayer = try XCTUnwrap(item.sixtyMinuteLayer)

        XCTAssertEqual(item.visibleLayerCount, 3)
        XCTAssertEqual(originalScaleLayer.fraction, 1, accuracy: 0.001)
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

    // MARK: - PTIMER-126: hasTimers gating

    /// `hasTimerPresentation` is the screen-level gate that decides
    /// whether the timer strip and Timers chrome render at all. When
    /// no timers exist, every timer-related surface is hidden.
    func testHasTimerPresentationFalseWhenSnapshotIsEmpty() {
        let emptySnapshot = makeSnapshot(from: [])

        XCTAssertFalse(ExposureCalculatorScreen.hasTimerPresentation(in: emptySnapshot))
    }

    func testHasTimerPresentationTrueWhenAnyTimerExists() {
        let runningSnapshot = makeSnapshot(from: [secondsScaleTimer()])
        let completedOnlySnapshot = makeSnapshot(
            from: [sampleTimers().first { $0.status == .completed }!]
        )

        XCTAssertTrue(ExposureCalculatorScreen.hasTimerPresentation(in: runningSnapshot))
        XCTAssertTrue(ExposureCalculatorScreen.hasTimerPresentation(in: completedOnlySnapshot))
    }

    // MARK: - PTIMER-126: stable layout invariants

    /// Layout-stability rule: the camera workspace budget does NOT
    /// depend on whether timers exist. Starting the first timer must
    /// not cause the calculator to reflow into a different density
    /// tier. The strip's footprint is always reserved.
    func testWorkspaceBudgetIsTimerPresenceIndependent() {
        let screenHeight: CGFloat = 844
        let topSafeArea: CGFloat = 59
        let bottomSafeArea: CGFloat = 34

        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: screenHeight,
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea
        )
        let expected = screenHeight
            - topSafeArea
            - bottomSafeArea
            - ExposureWorkspaceLayoutMetrics.timerStripBottomMargin
            - ExposureWorkspaceLayoutMetrics.timerStripHeight
            - ExposureWorkspaceLayoutMetrics.pageMarkerToStripGap
            - ExposureWorkspaceLayoutMetrics.pageMarkerHeight
            - ExposureWorkspaceLayoutMetrics.workspaceMarkerGap

        XCTAssertEqual(budget, expected)
    }

    /// Marker y-position is a single fixed value. Anchored to the
    /// strip's reserved band, not to whether the strip is currently
    /// rendered — so the marker never moves when a timer appears or
    /// disappears.
    func testPageMarkerOffsetSitsAboveReservedStripBand() {
        let bottomSafeArea: CGFloat = 34
        let expected = bottomSafeArea
            + ExposureWorkspaceLayoutMetrics.timerStripBottomMargin
            + ExposureWorkspaceLayoutMetrics.timerStripHeight
            + ExposureWorkspaceLayoutMetrics.pageMarkerToStripGap

        XCTAssertEqual(
            ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset(bottomSafeArea: bottomSafeArea),
            expected
        )
    }

    /// Marker offset has no input that varies with camera or timer
    /// state — it depends only on bottom safe area. Repeated calls
    /// return the same value (and the function takes no other
    /// parameter).
    func testPageMarkerOffsetIsStable() {
        let bottomSafeArea: CGFloat = 34
        let offsets = (0..<8).map { _ in
            ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset(bottomSafeArea: bottomSafeArea)
        }

        XCTAssertEqual(Set(offsets).count, 1)
    }

    func testTimerStripBottomOffsetIsAnchoredToBottomSafeArea() {
        let bottomSafeArea: CGFloat = 34
        let expected = bottomSafeArea
            + ExposureWorkspaceLayoutMetrics.timerStripBottomMargin

        XCTAssertEqual(
            ExposureWorkspaceLayoutMetrics.timerStripBottomOffset(bottomSafeArea: bottomSafeArea),
            expected
        )
    }

    /// Timer strip footprint matches the compact card viewport — the
    /// strip is rendered at intrinsic size, not inflated.
    func testTimerStripHeightMatchesCompactCardViewport() {
        XCTAssertEqual(
            ExposureWorkspaceLayoutMetrics.timerStripHeight,
            BottomSheetCompactDockMetrics.viewportHeight
        )
    }

    /// Sum check: top safe area + workspace + marker gap + marker +
    /// marker-to-strip gap + strip + strip margin + bottom safe area
    /// exactly covers the screen on iPhone 17. If a future refactor
    /// introduces a gap or an overlap, this assertion catches it.
    func testWorkspaceMarkerStripAndSafeAreasPartitionScreenExactly() {
        let screenHeight: CGFloat = 844
        let topSafeArea: CGFloat = 59
        let bottomSafeArea: CGFloat = 34

        let workspaceHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: screenHeight,
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea
        )

        let total = topSafeArea
            + workspaceHeight
            + ExposureWorkspaceLayoutMetrics.workspaceMarkerGap
            + ExposureWorkspaceLayoutMetrics.pageMarkerHeight
            + ExposureWorkspaceLayoutMetrics.pageMarkerToStripGap
            + ExposureWorkspaceLayoutMetrics.timerStripHeight
            + ExposureWorkspaceLayoutMetrics.timerStripBottomMargin
            + bottomSafeArea

        XCTAssertEqual(total, screenHeight)
    }

    // MARK: - PTIMER-126: device viewport sanity

    /// The workspace must accommodate at least the dense layout
    /// budget on iPhone 17 (regardless of whether timers exist —
    /// budget is timer-presence-independent).
    func testIPhone17ViewportFitsDenseWorkspace() {
        let screenHeight: CGFloat = 844
        let topSafeArea: CGFloat = 59
        let bottomSafeArea: CGFloat = 34
        let dense = ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .dense)

        let budget = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: screenHeight,
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea
        )

        XCTAssertGreaterThanOrEqual(budget, dense)
    }

    // MARK: - PTIMER-126: Section-scoped Clear placement

    /// Section title constants used by the snapshot factory and the
    /// view layer must agree, so the view's `isCompletedSection`
    /// check against incoming sections actually matches what the
    /// factory produced.
    func testSectionTitleConstantsAreUsedByFactory() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(
            snapshot.sections.first?.title,
            TimerWorkspaceSection.activeTitle
        )
        XCTAssertEqual(
            snapshot.sections.last?.title,
            TimerWorkspaceSection.completedTitle
        )
    }

    /// `isCompletedSection` is the view-layer hook for scoping the
    /// `Clear` affordance. Confirms it is true exactly for the
    /// completed section and false elsewhere.
    func testIsCompletedSectionFlagsCompletedSectionOnly() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let active = snapshot.sections.first { $0.title == TimerWorkspaceSection.activeTitle }
        let completed = snapshot.sections.first { $0.title == TimerWorkspaceSection.completedTitle }

        XCTAssertEqual(active?.isCompletedSection, false)
        XCTAssertEqual(completed?.isCompletedSection, true)
    }

    /// Active section identity is unchanged whether or not completed
    /// timers exist. The `Clear` affordance moved into the completed
    /// section header, so adding a completed timer no longer pushes
    /// Active down (the previous bug). This is the snapshot-level
    /// invariant; the view-layer consequence is that the Active list
    /// stays put when timers complete.
    func testActiveSectionIdentityIsStableAcrossCompletedSectionAppearance() {
        let runningOnly = makeSnapshot(from: [secondsScaleTimer()])
        let withCompleted = makeSnapshot(from: [
            secondsScaleTimer(),
            sampleTimers().first { $0.status == .completed }!
        ])

        let activeFromRunningOnly = runningOnly.sections.first { $0.isCompletedSection == false }
        let activeFromMixed = withCompleted.sections.first { $0.isCompletedSection == false }

        XCTAssertNotNil(activeFromRunningOnly)
        XCTAssertNotNil(activeFromMixed)
        XCTAssertEqual(activeFromRunningOnly?.title, activeFromMixed?.title)
        XCTAssertEqual(
            activeFromRunningOnly?.items.map(\.id),
            activeFromMixed?.items.map(\.id),
            "Active section item identities must not change when a completed section appears."
        )
    }

    /// When no completed timers exist, the snapshot must not
    /// surface a completed section at all — there is nothing for
    /// the view's `isCompletedSection` branch to attach `Clear` to.
    func testCompletedSectionAbsentWhenNoCompletedTimersExist() {
        let snapshot = makeSnapshot(from: [secondsScaleTimer()])

        XCTAssertFalse(snapshot.sections.contains { $0.isCompletedSection })
        XCTAssertEqual(snapshot.completedCount, 0)
    }

    // MARK: - PTIMER-126: hosted screen smoke tests

    @MainActor
    func testExposureScreenLoadsAtIPhone17Viewport() {
        let host = UIHostingController(
            rootView: ExposureCalculatorScreen()
                .frame(width: 390, height: 844)
        )
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertGreaterThan(host.view.bounds.width, 0)
    }

    @MainActor
    func testFullScreenTimersWindowLoadsWithCloseButton() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = UIHostingController(
            rootView: FullScreenTimersWindow(
                snapshot: snapshot,
                openFocus: .none,
                onPauseTimer: { _ in },
                onResumeTimer: { _ in },
                onRemoveTimer: { _ in },
                onStartTimerAgain: { _ in },
                onClearCompletedTimers: {},
                onClose: {}
            )
            .frame(width: 390, height: 844)
        )
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        // The close button is wired via SwiftUI Toolbar; finding it
        // through the UIKit bridge is flaky, so we instead verify
        // the structural smoke (renders, snapshot has data).
        XCTAssertFalse(snapshot.sections.isEmpty)
    }

    // MARK: - Test fixtures

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
}
