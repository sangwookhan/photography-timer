import SwiftUI
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
    }

    func testDimOpacityOnlyAppearsForExpandedStates() {
        XCTAssertEqual(BottomSheetLayoutMetrics.dimOpacity(for: .compact), 0)
        XCTAssertGreaterThan(BottomSheetLayoutMetrics.dimOpacity(for: .medium), 0)
        XCTAssertGreaterThan(BottomSheetLayoutMetrics.dimOpacity(for: .large), BottomSheetLayoutMetrics.dimOpacity(for: .medium))
    }

    func testSnapshotSummarizesTimerCounts() {
        let now = Date(timeIntervalSince1970: 1_000)
        let timers = [
            RunningTimerItem(
                id: UUID(),
                order: 1,
                name: "Running",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 120,
                startDate: now,
                endDate: now.addingTimeInterval(120),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(),
                order: 2,
                name: "Stopped",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 180,
                startDate: now,
                endDate: nil,
                pausedRemainingTime: 45,
                pausedAt: now,
                status: .stopped,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(),
                order: 3,
                name: "Completed",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 30,
                startDate: now,
                endDate: now,
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            )
        ]

        let snapshot = BottomSheetWorkspaceSnapshot.make(from: timers)

        XCTAssertEqual(snapshot.totalCount, 3)
        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertEqual(snapshot.stoppedCount, 1)
        XCTAssertEqual(snapshot.completedCount, 1)
        XCTAssertEqual(snapshot.summaryText, "Running 1 · Stopped 1 · Completed 1")
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
}
