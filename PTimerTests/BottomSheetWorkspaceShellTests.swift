import SwiftUI
import UIKit
import XCTest
@testable import PTimer

final class BottomSheetWorkspaceShellTests: XCTestCase {
    @MainActor
    func testStateStoreDefaultsToCompact() {
        let store = BottomSheetWorkspaceStateStore()

        XCTAssertEqual(store.detent, .compact)
    }

    @MainActor
    func testStateStoreTransitionsBetweenDetents() {
        let store = BottomSheetWorkspaceStateStore()

        store.transition(to: .medium)
        XCTAssertEqual(store.detent, .medium)

        store.transition(to: .large)
        XCTAssertEqual(store.detent, .large)
    }

    @MainActor
    func testStateStoreExpandAndCollapseModelCompactVsExpandedFlow() {
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

        store.handleDragEnd(translation: -80)
        XCTAssertEqual(store.detent, .large)

        store.handleDragEnd(translation: 92)
        XCTAssertEqual(store.detent, .compact)
    }

    func testLayoutMetricsIncreaseByDetent() {
        let compact = BottomSheetLayoutMetrics.height(for: .compact)
        let medium = BottomSheetLayoutMetrics.height(for: .medium)
        let large = BottomSheetLayoutMetrics.height(for: .large)

        XCTAssertLessThan(compact, medium)
        XCTAssertLessThan(medium, large)
        XCTAssertGreaterThanOrEqual(large, 560)
        XCTAssertLessThanOrEqual(compact, 122)
        XCTAssertGreaterThanOrEqual(compact, 110)
    }

    func testDimOpacityOnlyAppearsForExpandedStates() {
        XCTAssertEqual(BottomSheetLayoutMetrics.dimOpacity(for: .compact), 0)
        XCTAssertGreaterThan(BottomSheetLayoutMetrics.dimOpacity(for: .medium), 0)
        XCTAssertGreaterThan(BottomSheetLayoutMetrics.dimOpacity(for: .large), BottomSheetLayoutMetrics.dimOpacity(for: .medium))
    }

    func testSnapshotSummarizesTimerCounts() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertEqual(snapshot.stoppedCount, 1)
        XCTAssertEqual(snapshot.completedCount, 2)
        XCTAssertEqual(snapshot.summaryText, "Running 1 · Paused 1 · Done 2")
    }

    func testVisibleStoppedCopyUsesPausedInPresentation() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.sections[1].items[0].statusLabel, "Paused")
    }

    func testCompactSummaryRespectsVisibleItemLimit() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactItems.count, BottomSheetWorkspaceSnapshot.compactVisibleLimit)
        XCTAssertEqual(snapshot.hiddenCompactItemCount, 1)
    }

    func testCompactSummaryPrioritizesRunningThenStoppedThenRecentlyCompleted() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactItems.map(\.status), [.running, .stopped, .completed])
        XCTAssertEqual(
            snapshot.compactItems.map(\.id),
            [
                UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            ]
        )
    }

    func testCompactSummaryCalculatesHiddenCountAndSummaryText() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.hiddenCompactItemCount, 1)
        XCTAssertEqual(snapshot.compactSummaryText, "+1 more")
        XCTAssertEqual(snapshot.compactOverflowText, "+1")
    }

    func testCompactPresentationSimplifiesLongDurationContent() {
        let snapshot = makeSnapshot(from: [longDurationTimer()])

        XCTAssertEqual(snapshot.compactItems.count, 1)
        XCTAssertEqual(snapshot.compactItems[0].primaryRemainingText, "4d 6h")
        XCTAssertEqual(snapshot.compactItems[0].secondaryTotalText, "4d 6h")
    }

    func testCompletedCompactCardUsesZeroRemainingWithoutDoneLabel() {
        let completedTimer = sampleTimers().first { $0.status == .completed }!
        let snapshot = makeSnapshot(from: [completedTimer])

        XCTAssertEqual(snapshot.compactItems.count, 1)
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

    func testExpandedSectionsGroupTimersByPresentationStatus() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.sections.map(\.title), ["Running", "Stopped", "Recently Completed"])
        XCTAssertEqual(snapshot.sections[0].items.count, 1)
        XCTAssertEqual(snapshot.sections[1].items.count, 1)
        XCTAssertEqual(snapshot.sections[2].items.count, 2)
    }

    func testExpandedSummaryTextReflectsWorkspaceCounts() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.expandedSummaryText, "Running 1 · Paused 1 · Done 2")
    }

    func testExpandedHeightCreatesLargerManagementViewportBudget() {
        let compactHeight = BottomSheetLayoutMetrics.height(for: .compact)
        let expandedHeight = BottomSheetLayoutMetrics.height(for: .large)

        XCTAssertGreaterThan(expandedHeight - compactHeight, 300)
    }

    @MainActor
    func testCompactStateRendersActualSummaryContent() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(snapshot.compactItems.isEmpty)
        XCTAssertEqual(snapshot.compactItems.first?.primaryRemainingText, "25s")
        XCTAssertEqual(snapshot.compactItems.first?.secondaryTotalText, "02:00")
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
    func testExpandedStateRendersActualWorkspaceListContent() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .large, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertEqual(snapshot.sections.map(\.title), ["Running", "Stopped", "Recently Completed"])
        XCTAssertEqual(snapshot.sections.first?.items.first?.title, "Running Soon")
        XCTAssertEqual(snapshot.sections[1].items.first?.actions.map(\.title), ["Resume", "Remove"])
        XCTAssertGreaterThan(snapshot.completedCount, 0)
    }

    @MainActor
    func testPlaceholderCopyIsRemovedFromBottomSheetContent() {
        let host = makeBottomSheetHost(detent: .large, snapshot: makeSnapshot(from: sampleTimers()))

        XCTAssertFalse(host.view.containsText("Summary Zone"))
        XCTAssertFalse(host.view.containsText("List Zone"))
        XCTAssertFalse(host.view.containsText("Return Path"))
        XCTAssertFalse(host.view.containsText("PTIMER-47 summary content mounts here"))
    }

    @MainActor
    func testCompactHeaderDoesNotRenderSummaryTextOrOpenButton() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)

        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertFalse(host.view.containsText(snapshot.compactSummaryText))
        XCTAssertFalse(host.view.containsText("Open"))
        XCTAssertTrue(host.view.containsText("Timer Workspace"))
    }

    @MainActor
    func testCompactEmptyStateStaysMinimalWithoutOpenCallToAction() {
        let snapshot = makeSnapshot(from: [])

        XCTAssertEqual(snapshot.compactItems.count, 0)

        let host = makeBottomSheetHost(detent: .compact, snapshot: snapshot)
        XCTAssertGreaterThan(host.view.bounds.height, 0)
        XCTAssertEqual(snapshot.compactSummaryText, "No timers yet")
        XCTAssertFalse(host.view.containsText(snapshot.compactSummaryText))
        XCTAssertFalse(host.view.containsText("Open"))
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

    func testIPhone17ViewportLeavesMeaningfulExpandedWorkspaceHeight() {
        let expandedHeight = BottomSheetLayoutMetrics.height(for: .large)

        XCTAssertGreaterThanOrEqual(expandedHeight, 560)
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
            duration: 367_384,
            startDate: now,
            endDate: now.addingTimeInterval(367_384),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
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
            targetContext: { timer in
                switch timer.status {
                case .running, .stopped:
                    return "Target \(Int(timer.duration))s"
                case .completed:
                    return nil
                }
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

    @MainActor
    private func makeBottomSheetHost(
        detent: BottomSheetDetent,
        snapshot: BottomSheetWorkspaceSnapshot
    ) -> UIViewController {
        let store = BottomSheetWorkspaceStateStore(detent: detent)
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
}
