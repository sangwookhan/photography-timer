import SwiftUI
import UIKit
import XCTest
@testable import PTimer
import PTimerCore
import PTimerKit

final class BottomSheetWorkspaceSnapshotFactoryTests: XCTestCase {
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
        XCTAssertEqual(compactItem.primaryRemainingText, BottomSheetWorkspaceSnapshot.compactDurationText(timer.remainingTime))
        XCTAssertEqual(largeItem.remainingText, harness.viewModel.formatTimerClock(timer.remainingTime))
        XCTAssertEqual(largeItem.contextText, timer.basisSummary)
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
        XCTAssertEqual(initialCompact.primaryRemainingText, BottomSheetWorkspaceSnapshot.compactDurationText(10))
        XCTAssertEqual(updatedCompact.primaryRemainingText, BottomSheetWorkspaceSnapshot.compactDurationText(6))
        XCTAssertEqual(initialLarge.remainingText, harness.viewModel.formatTimerClock(10))
        XCTAssertEqual(updatedLarge.remainingText, harness.viewModel.formatTimerClock(6))
        XCTAssertLessThan(initialLarge.progress, updatedLarge.progress)
    }

    @MainActor
    func testWorkspaceSnapshotReflectsAppReactivationStateReconciliationForCompactAndLarge() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 10)
        harness.viewModel.startTimer(from: 3)

        let initialCompact = harness.snapshotStore.snapshot.compactItems
        XCTAssertEqual(initialCompact.map(\.status), [.running, .running])

        harness.currentDate = Date(timeIntervalSince1970: 104)
        harness.viewModel.reconcileTimersAfterAppBecomesActive()

        let compactItems = harness.snapshotStore.snapshot.compactItems
        let activeSection = try XCTUnwrap(
            harness.snapshotStore.snapshot.sections.first(where: { $0.title == "Active" })
        )
        let completedSection = try XCTUnwrap(
            harness.snapshotStore.snapshot.sections.first(where: { $0.title == "Recently Completed" })
        )

        XCTAssertEqual(compactItems.count, 2)
        XCTAssertEqual(compactItems.map(\.status), [.running, .completed])
        XCTAssertEqual(compactItems.first?.primaryRemainingText, BottomSheetWorkspaceSnapshot.compactDurationText(6))
        XCTAssertEqual(activeSection.items.count, 1)
        XCTAssertEqual(activeSection.items.first?.remainingText, harness.viewModel.formatTimerClock(6))
        XCTAssertEqual(completedSection.items.count, 1)
        XCTAssertEqual(completedSection.items.first?.status, .completed)
        XCTAssertEqual(harness.snapshotStore.snapshot.completedCount, 1)
    }

    @MainActor
    func testCompletedLargeItemShowsAbsoluteAndRelativeCompletionTime() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 10)
        harness.currentDate = Date(timeIntervalSince1970: 130)
        harness.timerManager.tick(now: harness.currentDate)

        let completedItem = try XCTUnwrap(
            harness.snapshotStore.snapshot.sections
                .first(where: { $0.title == "Recently Completed" })?
                .items
                .first
        )

        XCTAssertEqual(
            completedItem.timingText,
            "Completed 1970-01-01 00:01:50 · just now"
        )
    }

    @MainActor
    func testCompletedLargeItemsUseEachCompletionDateForRelativeTimingText() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let olderCompleted = RunningTimerItem(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            order: 1,
            name: "Older",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 45,
            startDate: now.addingTimeInterval(-300),
            endDate: now.addingTimeInterval(-180),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )
        let newerCompleted = RunningTimerItem(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            order: 2,
            name: "Newer",
            basisSummary: "Base 1/15s · 8 stops",
            duration: 30,
            startDate: now.addingTimeInterval(-90),
            endDate: now.addingTimeInterval(-60),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { now }
            )
        )
        viewModel.scaleMode = .fullStop

        let snapshot = BottomSheetWorkspaceSnapshot.make(
            from: [olderCompleted, newerCompleted],
            formatRemaining: viewModel.formatTimerClock,
            timeContext: viewModel.timerTimeContext,
            compactCompletedSupplementaryText: viewModel.compactCompletedSupplementaryText
        )
        let completedItems: [BottomSheetLargeItem] = snapshot.sections.first?.items ?? []

        XCTAssertEqual(completedItems.count, 2)
        XCTAssertEqual(
            completedItems.map(\.timingText),
            [
                "Completed 1970-01-01 02:45:40 · 1 min ago",
                "Completed 1970-01-01 02:43:40 · 3 min ago",
            ]
        )
    }

    @MainActor
    func testSnapshotStorePropagatesPauseResumeRemoveAndClearCompletedActionsConsistently() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(harness.viewModel.timers.first?.id)

        harness.currentDate = Date(timeIntervalSince1970: 103)
        harness.viewModel.pauseTimer(id: id)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.status, .paused)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.status, .paused)
        let pausedCompactCue = harness.snapshotStore.snapshot.compactItems.first?.identityCue
        let pausedLargeCue = harness.snapshotStore.snapshot.sections.first?.items.first?.identityCue
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.primaryRemainingText, BottomSheetWorkspaceSnapshot.compactDurationText(7))
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.remainingText, harness.viewModel.formatTimerClock(7))

        harness.currentDate = Date(timeIntervalSince1970: 105)
        harness.viewModel.resumeTimer(id: id)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.status, .running)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.status, .running)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.identityCue, pausedCompactCue)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.identityCue, pausedLargeCue)
        XCTAssertEqual(harness.snapshotStore.snapshot.compactItems.first?.primaryRemainingText, BottomSheetWorkspaceSnapshot.compactDurationText(7))
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
        XCTAssertEqual(updatedLarge.contextText, harness.viewModel.timers.first?.basisSummary)
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

    func testSnapshotSummarizesTimerCounts() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.completedCount, 2)
    }

    func testCompactSummaryRespectsVisibleItemLimit() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactItems.count, BottomSheetWorkspaceSnapshot.compactVisibleLimit)
        XCTAssertEqual(snapshot.hiddenCompactItemCount, 1)
    }

    func testCompactSummaryPrioritizesNewerActiveTimersThenRecentlyCompleted() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactItems.map(\.status), [.paused, .running, .completed])
        XCTAssertEqual(snapshot.compactItems.map(\.identityCue.markerText), ["T2", "T1", "T3"])
        XCTAssertEqual(
            snapshot.compactItems.map(\.id),
            [
                UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
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

    @MainActor
    func testClearCompletedRemovesCompletedSectionMetadataAndIdentityMarkers() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.baseShutter = 1.0 / 30.0
        harness.viewModel.ndStop = 6
        harness.viewModel.startTimer()

        harness.viewModel.baseShutter = 1
        harness.viewModel.ndStop = 3
        harness.viewModel.startTimer()

        harness.currentDate = Date(timeIntervalSince1970: 103)
        harness.timerManager.tick(now: harness.currentDate)

        XCTAssertEqual(harness.snapshotStore.snapshot.sections.map(\.title), ["Active", "Recently Completed"])
        XCTAssertEqual(harness.snapshotStore.snapshot.completedCount, 1)

        harness.viewModel.clearCompletedTimers()

        XCTAssertEqual(harness.snapshotStore.snapshot.completedCount, 0)
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.map(\.title), ["Active"])
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.count, 1)
        // Surviving timer was started from the default `camera1` slot,
        // so its identity badge is `C1`. Camera-slot identity replaces
        // the prior `T<order>` marker on the dock when a slot is
        // present.
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.identityCue.markerText, "C1")
        XCTAssertEqual(harness.snapshotStore.snapshot.sections.first?.items.first?.contextText, "Base 1s · 3 stops")

        XCTAssertFalse(harness.snapshotStore.snapshot.sections.contains { $0.title == "Recently Completed" })
        XCTAssertFalse(harness.snapshotStore.snapshot.sections.flatMap(\.items).contains { $0.timingText == "Completed recently" })
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
            ),
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
        viewModel.scaleMode = .fullStop
        let adapter = BottomSheetWorkspacePresentationAdapter(
            formatRemaining: viewModel.formatTimerClock,
            timeContext: viewModel.timerTimeContext,
            compactCompletedSupplementaryText: viewModel.compactCompletedSupplementaryText
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
}
