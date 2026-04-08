import SwiftUI
import UIKit
import XCTest
@testable import PTimer

final class BottomSheetWorkspaceShellTests: XCTestCase {
    @MainActor
    func testSnapshotStoreReflectsTimerCreationInCompactAndLargeFromSameRuntimeTruth() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.baseShutter = 1.0 / 30.0
        harness.viewModel.ndStop = 6
        harness.viewModel.startTimer()

        let timer = try XCTUnwrap(harness.viewModel.timers.first)
        let compactItem = try XCTUnwrap(harness.snapshotStore.snapshot.compactItems.first)
        let largeItem = try XCTUnwrap(harness.snapshotStore.snapshot.sections.first?.items.first)

        XCTAssertEqual(harness.stateStore.detent, .compact)
        XCTAssertEqual(compactItem.id, timer.id)
        XCTAssertEqual(largeItem.id, timer.id)
        XCTAssertEqual(compactItem.identityCue, largeItem.identityCue)
        XCTAssertEqual(compactItem.primaryRemainingText, harness.viewModel.formatTimerClock(timer.remainingTime))
        XCTAssertEqual(largeItem.remainingText, harness.viewModel.formatTimerClock(timer.remainingTime))
        XCTAssertEqual(largeItem.contextText, "Base 1/30s · 6 stops")
        XCTAssertFalse(harness.stateStore.isExpanded)
    }

    @MainActor
    func testSnapshotStoreReflectsTickVisibilityForCompactAndLarge() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 10)
        let initialCompact = try XCTUnwrap(harness.snapshotStore.snapshot.compactItems.first)
        let initialLarge = try XCTUnwrap(harness.snapshotStore.snapshot.sections.first?.items.first)

        harness.currentDate = Date(timeIntervalSince1970: 104)
        harness.timerManager.tick(now: harness.currentDate)

        let updatedCompact = try XCTUnwrap(harness.snapshotStore.snapshot.compactItems.first)
        let updatedLarge = try XCTUnwrap(harness.snapshotStore.snapshot.sections.first?.items.first)

        XCTAssertEqual(initialCompact.identityCue, updatedCompact.identityCue)
        XCTAssertEqual(initialLarge.identityCue, updatedLarge.identityCue)
        XCTAssertEqual(initialCompact.primaryRemainingText, harness.viewModel.formatTimerClock(10))
        XCTAssertEqual(updatedCompact.primaryRemainingText, harness.viewModel.formatTimerClock(6))
        XCTAssertEqual(initialLarge.remainingText, harness.viewModel.formatTimerClock(10))
        XCTAssertEqual(updatedLarge.remainingText, harness.viewModel.formatTimerClock(6))
        XCTAssertLessThan(initialLarge.progress, updatedLarge.progress)
    }

    @MainActor
    func testSnapshotStorePropagatesPauseResumeRemoveAndClearCompletedActionsConsistently() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(harness.viewModel.timers.first?.id)

        harness.currentDate = Date(timeIntervalSince1970: 103)
        harness.viewModel.stopTimer(id: id)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.status, .stopped)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.status, .stopped)
        let pausedCompactCue = harness.snapshotStore.snapshot.compactItems.first?.identityCue
        let pausedLargeCue = harness.snapshotStore.snapshot.sections.first?.items.first?.identityCue
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.primaryRemainingText, harness.viewModel.formatTimerClock(7))
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.remainingText, harness.viewModel.formatTimerClock(7))

        harness.currentDate = Date(timeIntervalSince1970: 105)
        harness.viewModel.resumeTimer(id: id)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.status, .running)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.status, .running)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.identityCue, pausedCompactCue)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.identityCue, pausedLargeCue)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.primaryRemainingText, harness.viewModel.formatTimerClock(7))
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.remainingText, harness.viewModel.formatTimerClock(7))

        harness.currentDate = Date(timeIntervalSince1970: 120)
        harness.timerManager.tick(now: harness.currentDate)
        XCTAssertEqual(harness.snapshotStore.snapshot.completedCount, 1)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.last?.items.first?.status, .completed)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.last?.items.first?.identityCue, pausedLargeCue)

        harness.viewModel.clearCompletedTimers()
        XCTAssertEqual(harness.snapshotStore.snapshot.completedCount, 0)
        XCTAssertTrue(harness.snapshotStore.snapshot.compactItems.isEmpty)
        XCTAssertTrue(harness.snapshotStore.snapshot.sections.isEmpty)

        harness.viewModel.baseShutter = 1.0 / 15.0
        harness.viewModel.ndStop = 4
        harness.viewModel.startTimer(from: 12)
        let removeID = try XCTUnwrap(harness.viewModel.timers.first?.id)
        XCTAssertEqual(harness.viewModel.timers.first?.name, "Timer - 12s")
        XCTAssertEqual(harness.viewModel.timers.first?.basisSummary, "Manual timer")
        harness.viewModel.removeTimer(id: removeID)
        XCTAssertTrue(harness.snapshotStore.snapshot.compactItems.isEmpty)
        XCTAssertTrue(harness.snapshotStore.snapshot.sections.isEmpty)
    }

    @MainActor
    func testSnapshotStoreKeepsExistingTimerMetadataIndependentFromLaterCalculatorEdits() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.baseShutter = 1.0 / 30.0
        harness.viewModel.ndStop = 6
        harness.viewModel.startTimer()

        let originalCompact = try XCTUnwrap(harness.snapshotStore.snapshot.compactItems.first)
        let originalLarge = try XCTUnwrap(harness.snapshotStore.snapshot.sections.first?.items.first)

        harness.viewModel.baseShutter = 1
        harness.viewModel.ndStop = 3

        let updatedCompact = try XCTUnwrap(harness.snapshotStore.snapshot.compactItems.first)
        let updatedLarge = try XCTUnwrap(harness.snapshotStore.snapshot.sections.first?.items.first)

        XCTAssertEqual(updatedCompact.id, originalCompact.id)
        XCTAssertEqual(updatedCompact.identityCue, originalCompact.identityCue)
        XCTAssertEqual(updatedCompact.primaryRemainingText, originalCompact.primaryRemainingText)
        XCTAssertEqual(updatedLarge.id, originalLarge.id)
        XCTAssertEqual(updatedLarge.identityCue, originalLarge.identityCue)
        XCTAssertEqual(updatedLarge.title, originalLarge.title)
        XCTAssertEqual(updatedLarge.contextText, "Base 1/30s · 6 stops")
    }

    @MainActor
    func testSnapshotStoreKeepsCompactAndLargeViewsConsistentThroughCompletionOrdering() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 10)
        harness.viewModel.startTimer(from: 30)

        let newestID = try XCTUnwrap(harness.viewModel.timers.first?.id)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.id, newestID)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.id, newestID)

        harness.currentDate = Date(timeIntervalSince1970: 200)
        harness.timerManager.tick(now: harness.currentDate)

        let compactIDs = harness.snapshotStore.snapshot.compactItems.map(\.id)
        let largeIDs = harness.snapshotStore.snapshot.sections.flatMap(\.items).map(\.id)

        XCTAssertEqual(Set(compactIDs), Set(largeIDs))
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.map(\.title), ["Recently Completed"])
        XCTAssertEqual(harness.snapshotStore.snapshot.completedCount, 2)
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
    func testCompactCardTapSelectionExpandsAndStoresFocusedTimer() {
        let store = BottomSheetWorkspaceStateStore()
        let selectedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        store.expandAndFocusTimer(selectedID)

        XCTAssertEqual(store.detent, .large)
        XCTAssertEqual(store.selectedTimerID, selectedID)
    }

    @MainActor
    func testCollapseClearsFocusedTimerSelection() {
        let store = BottomSheetWorkspaceStateStore(detent: .large)
        let selectedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        store.focusTimer(selectedID)
        XCTAssertEqual(store.selectedTimerID, selectedID)

        store.collapse()

        XCTAssertEqual(store.detent, .compact)
        XCTAssertNil(store.selectedTimerID)
    }

    @MainActor
    func testTransitionToCompactClearsFocusedTimerSelection() {
        let store = BottomSheetWorkspaceStateStore(detent: .large)
        let selectedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        store.focusTimer(selectedID)
        store.transition(to: .compact)

        XCTAssertEqual(store.detent, .compact)
        XCTAssertNil(store.selectedTimerID)
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

    func testLayoutMetricsReflectCompactAndLargeHeights() {
        let compact = BottomSheetLayoutMetrics.height(for: .compact)
        let large = BottomSheetLayoutMetrics.height(for: .large)

        XCTAssertLessThan(compact, large)
        XCTAssertGreaterThanOrEqual(large, 560)
        XCTAssertLessThanOrEqual(compact, 122)
        XCTAssertGreaterThanOrEqual(compact, 110)
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

    func testSnapshotSummarizesTimerCounts() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.completedCount, 2)
    }

    func testVisibleStoppedCopyUsesPausedInPresentation() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let pausedItem = snapshot.sections
            .flatMap(\.items)
            .first { $0.status == .stopped }

        XCTAssertEqual(pausedItem?.statusLabel, "Paused")
    }

    func testCompactSummaryRespectsVisibleItemLimit() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactItems.count, BottomSheetWorkspaceSnapshot.compactVisibleLimit)
        XCTAssertEqual(snapshot.hiddenCompactItemCount, 1)
    }

    func testCompactSummaryPrioritizesNewerActiveTimersThenRecentlyCompleted() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactItems.map(\.status), [.stopped, .running, .completed])
        XCTAssertEqual(snapshot.compactItems.map(\.identityCue.markerText), ["T2", "T1", "T3"])
        XCTAssertEqual(
            snapshot.compactItems.map(\.id),
            [
                UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            ]
        )
    }

    func testCompactSummaryCalculatesHiddenCountAndOverflowText() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.hiddenCompactItemCount, 1)
        XCTAssertEqual(snapshot.compactOverflowText, "+1")
    }

    func testCompactPresentationSimplifiesLongDurationContent() {
        let snapshot = makeSnapshot(from: [longDurationTimer()])

        XCTAssertEqual(snapshot.compactItems.count, 1)
        XCTAssertEqual(snapshot.compactItems[0].primaryRemainingText, "4d 6h")
        XCTAssertEqual(snapshot.compactItems[0].secondaryTotalText, "4d 6h")
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
        // Boundary: 59s duration -> 1 layer
        let timer59 = RunningTimerItem(
            id: UUID(), order: 1, name: "59s", basisSummary: "", duration: 59,
            startDate: Date(), endDate: Date().addingTimeInterval(59),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: Date()
        )
        let item59 = BottomSheetWorkspaceSnapshot.make(from: [timer59], formatRemaining: { _ in "" }, timeContext: { _ in nil }).compactItems[0]
        XCTAssertEqual(item59.visibleLayerCount, 1)
        XCTAssertNotNil(item59.sixtySecondLayer)
        XCTAssertNil(item59.sixtyMinuteLayer)
        XCTAssertNil(item59.originalScaleLayer)

        // Boundary: 60s duration -> 2 layers
        let timer60 = RunningTimerItem(
            id: UUID(), order: 1, name: "60s", basisSummary: "", duration: 60,
            startDate: Date(), endDate: Date().addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: Date()
        )
        let item60 = BottomSheetWorkspaceSnapshot.make(from: [timer60], formatRemaining: { _ in "" }, timeContext: { _ in nil }).compactItems[0]
        XCTAssertEqual(item60.visibleLayerCount, 2)
        XCTAssertNotNil(item60.sixtySecondLayer)
        XCTAssertNotNil(item60.sixtyMinuteLayer)
        XCTAssertNil(item60.originalScaleLayer)

        // Boundary: 3599s duration -> 2 layers
        let timer3599 = RunningTimerItem(
            id: UUID(), order: 1, name: "3599s", basisSummary: "", duration: 3599,
            startDate: Date(), endDate: Date().addingTimeInterval(3599),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: Date()
        )
        let item3599 = BottomSheetWorkspaceSnapshot.make(from: [timer3599], formatRemaining: { _ in "" }, timeContext: { _ in nil }).compactItems[0]
        XCTAssertEqual(item3599.visibleLayerCount, 2)

        // Boundary: 3600s duration -> 3 layers
        let timer3600 = RunningTimerItem(
            id: UUID(), order: 1, name: "3600s", basisSummary: "", duration: 3600,
            startDate: Date(), endDate: Date().addingTimeInterval(3600),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: Date()
        )
        let item3600 = BottomSheetWorkspaceSnapshot.make(from: [timer3600], formatRemaining: { _ in "" }, timeContext: { _ in nil }).compactItems[0]
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

    func testActiveTimersPreserveStableRelativeOrderAcrossStatusChanges() {
        let before = makeSnapshot(from: activeOrderingTimers(pausedFirstTimerStatus: .running))
        let after = makeSnapshot(from: activeOrderingTimers(pausedFirstTimerStatus: .stopped))

        XCTAssertEqual(
            before.compactItems.map(\.id),
            [
                UUID(uuidString: "ccccccc3-3333-3333-3333-333333333333")!,
                UUID(uuidString: "bbbbbbb2-2222-2222-2222-222222222222")!,
                UUID(uuidString: "aaaaaaa1-1111-1111-1111-111111111111")!
            ]
        )
        XCTAssertEqual(before.compactItems.map(\.id), after.compactItems.map(\.id))
        XCTAssertEqual(before.sections.first?.items.map(\.id), after.sections.first?.items.map(\.id))
    }

    func testCompletedTimersAreDeferredBehindActiveTimersInWorkspaceOrdering() {
        let ordered = TimerWorkspaceOrdering.sort(completedAheadOfActiveTimers())

        XCTAssertEqual(
            ordered.map(\.id),
            [
                UUID(uuidString: "eeeeeee5-5555-5555-5555-555555555555")!,
                UUID(uuidString: "ddddddd4-4444-4444-4444-444444444444")!,
                UUID(uuidString: "fffffff6-6666-6666-6666-666666666666")!,
                UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
            ]
        )
        XCTAssertEqual(ordered.prefix(2).map(\.status), [.stopped, .running])
        XCTAssertEqual(ordered.suffix(2).map(\.status), [.completed, .completed])
    }

    func testNewTimerIsAlwaysInsertedAtTheTop() {
        let now = Date(timeIntervalSince1970: 5_000)
        let timerA = RunningTimerItem(
            id: UUID(), order: 1, name: "A", basisSummary: "", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let timerB = RunningTimerItem(
            id: UUID(), order: 2, name: "B", basisSummary: "", duration: 120,
            startDate: now, endDate: now.addingTimeInterval(120),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )

        let snapshot = makeSnapshot(from: [timerA, timerB])
        XCTAssertEqual(snapshot.compactItems.map(\.id), [timerB.id, timerA.id])
        XCTAssertEqual(snapshot.sections.first?.items.map(\.id), [timerB.id, timerA.id])

        // Add timer C (newest)
        let timerC = RunningTimerItem(
            id: UUID(), order: 3, name: "C", basisSummary: "", duration: 180,
            startDate: now, endDate: now.addingTimeInterval(180),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let snapshot2 = makeSnapshot(from: [timerA, timerB, timerC])
        XCTAssertEqual(snapshot2.compactItems.map(\.id), [timerC.id, timerB.id, timerA.id])
    }

    func testNewTimerInsertedAtTopEvenWhenCompletedTimersExist() {
        let now = Date(timeIntervalSince1970: 6_000)
        let activeA = RunningTimerItem(
            id: UUID(), order: 1, name: "A", basisSummary: "", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let completedB = RunningTimerItem(
            id: UUID(), order: 2, name: "B", basisSummary: "", duration: 30,
            startDate: now.addingTimeInterval(-60), endDate: now.addingTimeInterval(-30),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .completed, referenceDate: now
        )

        let snapshot = makeSnapshot(from: [activeA, completedB])
        XCTAssertEqual(snapshot.compactItems.map(\.id), [activeA.id, completedB.id])

        // New active C
        let activeC = RunningTimerItem(
            id: UUID(), order: 3, name: "C", basisSummary: "", duration: 120,
            startDate: now, endDate: now.addingTimeInterval(120),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let snapshot2 = makeSnapshot(from: [activeA, completedB, activeC])
        XCTAssertEqual(snapshot2.compactItems.map(\.id), [activeC.id, activeA.id, completedB.id])
    }

    @MainActor
    func testOverflowTapExpandsToLargeWithoutForcingSelection() {
        let snapshot = makeSnapshot(from: completedAheadOfActiveTimers())
        let store = BottomSheetWorkspaceStateStore()

        XCTAssertEqual(snapshot.compactOverflowText, "+1")
        XCTAssertNil(store.selectedTimerID)

        store.expand()

        XCTAssertEqual(store.detent, .large)
        XCTAssertNil(store.selectedTimerID)
    }

    func testCompletedCompactCardUsesZeroRemainingWithoutDoneLabel() {
        let completedTimer = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [completedTimer])

        XCTAssertEqual(snapshot.compactItems.count, 1)
        XCTAssertEqual(snapshot.compactItems[0].identityCue.markerText, "T3")
        XCTAssertEqual(snapshot.compactItems[0].primaryRemainingText, "0s")
        XCTAssertEqual(snapshot.compactItems[0].secondaryTotalText, "45s")
    }

    func testCompactDurationTextUsesSimplifiedMiniDockFormatting() {
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(64), "01:04")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(25), "25s")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(9.64), "9.6s")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(0.83), "0.8s")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(0.25), "0.3s")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(3_661), "1h 1m")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(90_061), "1d 1h")
        XCTAssertEqual(BottomSheetWorkspaceSnapshot.compactDurationText(34_218_061), "1y 1m")
    }

    func testLargeSectionsGroupTimersByPresentationStatus() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.sections.map(\.title), ["Active", "Recently Completed"])
        XCTAssertEqual(snapshot.sections[0].items.count, 2)
        XCTAssertEqual(snapshot.sections[1].items.count, 2)
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
        XCTAssertEqual(completedItem?.remainingText, "0s")
        XCTAssertEqual(completedItem?.totalDurationText, "00:45")
        XCTAssertEqual(completedItem?.timingText, "Completed recently")
        XCTAssertEqual(completedItem?.contextText, "Base 1/15s · 8 stops")
    }

    func testIdentityCueStaysConsistentAcrossCompactAndLargePresentations() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let compactByID = Dictionary(uniqueKeysWithValues: snapshot.compactItems.map { ($0.id, $0.identityCue) })
        let largeByID = Dictionary(
            uniqueKeysWithValues: snapshot.sections.flatMap(\.items).map { ($0.id, $0.identityCue) }
        )

        XCTAssertEqual(compactByID[UUID(uuidString: "33333333-3333-3333-3333-333333333333")!], largeByID[UUID(uuidString: "33333333-3333-3333-3333-333333333333")!])
        XCTAssertEqual(compactByID[UUID(uuidString: "22222222-2222-2222-2222-222222222222")!], largeByID[UUID(uuidString: "22222222-2222-2222-2222-222222222222")!])
        XCTAssertEqual(compactByID[UUID(uuidString: "11111111-1111-1111-1111-111111111111")!], largeByID[UUID(uuidString: "11111111-1111-1111-1111-111111111111")!])
    }

    func testIdentityCueRemainsStableWhenTimerMovesToCompletedSection() {
        let now = Date(timeIntervalSince1970: 9_000)
        let timerID = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!
        let runningTimer = RunningTimerItem(
            id: timerID,
            order: 9,
            name: "Completion Shift",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 90,
            startDate: now.addingTimeInterval(-15),
            endDate: now.addingTimeInterval(75),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
        let completedTimer = RunningTimerItem(
            id: timerID,
            order: 9,
            name: "Completion Shift",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 90,
            startDate: now.addingTimeInterval(-90),
            endDate: now.addingTimeInterval(-1),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )

        let runningSnapshot = makeSnapshot(from: [runningTimer])
        let completedSnapshot = makeSnapshot(from: [completedTimer])

        XCTAssertEqual(runningSnapshot.compactItems.first?.identityCue, completedSnapshot.compactItems.first?.identityCue)
        XCTAssertEqual(runningSnapshot.sections.first?.items.first?.identityCue, completedSnapshot.sections.first?.items.first?.identityCue)
    }

    func testMultipleTimersGetDistinguishableIdentityCues() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let visibleCompactCues = snapshot.compactItems.map(\.identityCue)

        XCTAssertEqual(Set(visibleCompactCues.map(\.markerText)).count, 3)
        XCTAssertGreaterThanOrEqual(Set(visibleCompactCues.map(\.tintSlot)).count, 2)
    }

    func testLargeSectionsCanResolveFocusedTimerAcrossPresentationGroups() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let focusedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        let focusedItem = snapshot.sections
            .flatMap(\.items)
            .first { $0.id == focusedID }

        XCTAssertEqual(focusedItem?.title, "Stopped Hold")
        XCTAssertEqual(focusedItem?.status, .stopped)
    }

    func testLargeHeightCreatesLargerManagementViewportBudget() {
        let compactHeight = BottomSheetLayoutMetrics.height(for: .compact)
        let largeHeight = BottomSheetLayoutMetrics.height(for: .large)

        XCTAssertGreaterThan(largeHeight - compactHeight, 300)
    }

    @MainActor
    func testCompactStateRendersActualSummaryContent() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(snapshot.compactItems.isEmpty)
        XCTAssertTrue(host.view.containsText("T2"))
        XCTAssertTrue(host.view.containsText("T1"))
        XCTAssertEqual(snapshot.compactItems.first?.primaryRemainingText, "55s")
        XCTAssertEqual(snapshot.compactItems.first?.secondaryTotalText, "03:00")
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
        XCTAssertTrue(host.view.containsText("T2"))
        XCTAssertTrue(host.view.containsText("T3"))
        XCTAssertEqual(snapshot.sections.map(\.title), ["Active", "Recently Completed"])
        XCTAssertEqual(snapshot.sections.first?.items.first?.title, "Stopped Hold")
        XCTAssertEqual(snapshot.sections.first?.items.last?.actions.map(\.title), ["Pause"])
        XCTAssertGreaterThan(snapshot.completedCount, 0)
        XCTAssertNotNil(host.view)
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
    func testLargeStateMarksFocusedRowForTappedCompactTimer() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let focusedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let store = BottomSheetWorkspaceStateStore(detent: .large)

        store.focusTimer(focusedID)

        let host = makeBottomSheetHost(store: store, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertEqual(store.selectedTimerID, focusedID)
        XCTAssertTrue(snapshot.sections.flatMap(\.items).contains { $0.id == focusedID })
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
    func testOverflowCardKeepsViewAllRoleWithoutTimerIdentityMarker() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)

        XCTAssertEqual(snapshot.compactOverflowText, "+1")
        XCTAssertTrue(host.view.containsText("View all"))
        XCTAssertFalse(host.view.containsText("T4"))
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
        let largeHeight = BottomSheetLayoutMetrics.height(for: .large)

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
                name: "Stopped Hold",
                basisSummary: "Base 1/60s · 10 stops",
                duration: 180,
                startDate: now.addingTimeInterval(-20),
                endDate: now.addingTimeInterval(160),
                pausedRemainingTime: 55,
                pausedAt: now.addingTimeInterval(-15),
                status: .stopped,
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
            status: .stopped,
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

    private func activeOrderingTimers(pausedFirstTimerStatus: TimerStatus) -> [RunningTimerItem] {
        let now = Date(timeIntervalSince1970: 2_000)

        return [
            RunningTimerItem(
                id: UUID(uuidString: "aaaaaaa1-1111-1111-1111-111111111111")!,
                order: 1,
                name: "First Active",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 90,
                startDate: now.addingTimeInterval(-10),
                endDate: pausedFirstTimerStatus == .running ? now.addingTimeInterval(50) : now.addingTimeInterval(80),
                pausedRemainingTime: pausedFirstTimerStatus == .stopped ? 50 : nil,
                pausedAt: pausedFirstTimerStatus == .stopped ? now.addingTimeInterval(-5) : nil,
                status: pausedFirstTimerStatus,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "bbbbbbb2-2222-2222-2222-222222222222")!,
                order: 2,
                name: "Second Active",
                basisSummary: "Base 1/60s · 10 stops",
                duration: 200,
                startDate: now,
                endDate: now.addingTimeInterval(20),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "ccccccc3-3333-3333-3333-333333333333")!,
                order: 3,
                name: "Third Active",
                basisSummary: "Base 1/15s · 8 stops",
                duration: 140,
                startDate: now.addingTimeInterval(-15),
                endDate: now.addingTimeInterval(110),
                pausedRemainingTime: 70,
                pausedAt: now.addingTimeInterval(-12),
                status: .stopped,
                referenceDate: now
            )
        ]
    }

    private func completedAheadOfActiveTimers() -> [RunningTimerItem] {
        let now = Date(timeIntervalSince1970: 3_000)

        return [
            RunningTimerItem(
                id: UUID(uuidString: "fffffff6-6666-6666-6666-666666666666")!,
                order: 3,
                name: "Completed Latest",
                basisSummary: "Base 1/8s · 5 stops",
                duration: 30,
                startDate: now.addingTimeInterval(-30),
                endDate: now.addingTimeInterval(-5),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                order: 4,
                name: "Completed Earlier",
                basisSummary: "Base 1/4s · 4 stops",
                duration: 20,
                startDate: now.addingTimeInterval(-50),
                endDate: now.addingTimeInterval(-20),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "ddddddd4-4444-4444-4444-444444444444")!,
                order: 1,
                name: "Active First",
                basisSummary: "Base 1/2s · 2 stops",
                duration: 180,
                startDate: now,
                endDate: now.addingTimeInterval(90),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "eeeeeee5-5555-5555-5555-555555555555")!,
                order: 2,
                name: "Active Second",
                basisSummary: "Base 1/1s · 1 stop",
                duration: 240,
                startDate: now.addingTimeInterval(-20),
                endDate: now.addingTimeInterval(160),
                pausedRemainingTime: 55,
                pausedAt: now.addingTimeInterval(-10),
                status: .stopped,
                referenceDate: now
            )
        ]
    }

    private func makeSnapshot(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        BottomSheetWorkspaceSnapshot.make(
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
                case .stopped:
                    return "Paused recently"
                case .completed:
                    return "Completed recently"
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
    private func makeRuntimeHarness(now: TimeInterval) -> RuntimeHarness {
        var currentDate = Date(timeIntervalSince1970: now)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let adapter = BottomSheetWorkspacePresentationAdapter(
            formatRemaining: viewModel.formatTimerClock,
            timeContext: viewModel.timerTimeContext
        )
        let snapshotStore = BottomSheetWorkspaceSnapshotStore(
            initialTimers: viewModel.timers,
            timersPublisher: viewModel.$timers.eraseToAnyPublisher(),
            adapter: adapter
        )
        let stateStore = BottomSheetWorkspaceStateStore()

        return RuntimeHarness(
            timerManager: timerManager,
            viewModel: viewModel,
            snapshotStore: snapshotStore,
            stateStore: stateStore,
            currentDate: { currentDate },
            setCurrentDate: { currentDate = $0 }
        )
    }

    @MainActor
    private struct RuntimeHarness {
        let timerManager: TimerManager
        let viewModel: ExposureCalculatorViewModel
        let snapshotStore: BottomSheetWorkspaceSnapshotStore
        let stateStore: BottomSheetWorkspaceStateStore
        let currentDateProvider: () -> Date
        let setCurrentDate: (Date) -> Void

        var currentDate: Date {
            get { currentDateProvider() }
            nonmutating set { setCurrentDate(newValue) }
        }

        init(
            timerManager: TimerManager,
            viewModel: ExposureCalculatorViewModel,
            snapshotStore: BottomSheetWorkspaceSnapshotStore,
            stateStore: BottomSheetWorkspaceStateStore,
            currentDate: @escaping () -> Date,
            setCurrentDate: @escaping (Date) -> Void
        ) {
            self.timerManager = timerManager
            self.viewModel = viewModel
            self.snapshotStore = snapshotStore
            self.stateStore = stateStore
            self.currentDateProvider = currentDate
            self.setCurrentDate = setCurrentDate
        }
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
                onStopTimer: { _ in },
                onResumeTimer: { _ in },
                onRemoveTimer: { _ in },
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
