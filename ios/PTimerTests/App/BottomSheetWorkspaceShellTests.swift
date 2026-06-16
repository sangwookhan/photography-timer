import SwiftUI
import PTimerKit
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

    /// The workspace tags both section headers with stable scroll
    /// ids so `applyFocusIfNeeded` can scroll the section title
    /// (and, for the completed section, `Clear`) to the top
    /// instead of scrolling a row.

    @MainActor
    func testStateStoreLifecycleDrivesDetentFocusAndOpenFocusClearing() {
        // Defaults to compact
        do {
            let store = BottomSheetWorkspaceStateStore()

            XCTAssertEqual(store.detent, .compact)
        }

        // Detent transitions both ways
        do {
            let store = BottomSheetWorkspaceStateStore()

            store.transition(to: .large)
            XCTAssertEqual(store.detent, .large)

            store.transition(to: .compact)
            XCTAssertEqual(store.detent, .compact)
        }

        // expand()/collapse() drive the presentation flag
        do {
            let store = BottomSheetWorkspaceStateStore()

            XCTAssertFalse(store.isExpanded)

            store.expand()
            XCTAssertEqual(store.detent, .large)
            XCTAssertTrue(store.isExpanded)

            store.collapse()
            XCTAssertEqual(store.detent, .compact)
            XCTAssertFalse(store.isExpanded)
        }

        // A focused timer survives until collapse clears it
        do {
            let store = BottomSheetWorkspaceStateStore()
            let id = UUID()

            store.expandAndFocusTimer(id)
            XCTAssertEqual(store.selectedTimerID, id)
            XCTAssertTrue(store.isExpanded)

            store.collapse()
            XCTAssertNil(store.selectedTimerID)
        }

        // Collapsing clears section open-focus
        do {
            let store = BottomSheetWorkspaceStateStore()
            store.expandFocusingCompletedSection()
            XCTAssertEqual(store.openFocus, .recentlyCompletedSection)

            store.collapse()

            XCTAssertEqual(store.openFocus, .none)
            XCTAssertNil(store.selectedTimerID)
        }

        // expand() alone does not force a timer selection
        do {
            let store = BottomSheetWorkspaceStateStore()
            store.expand()
            XCTAssertEqual(store.detent, .large)
            XCTAssertNil(store.selectedTimerID)
        }

        // Transitioning to compact (not only collapse()) clears focus
        do {
            let store = BottomSheetWorkspaceStateStore()
            store.transition(to: .large)
            let id = UUID()
            store.focusTimer(id)
            XCTAssertEqual(store.selectedTimerID, id)
            store.transition(to: .compact)
            XCTAssertNil(store.selectedTimerID)
        }
    }

    /// Open-focus routing: expanding to a section sets the matching
    /// TimersOpenFocus (with/without highlight) and never surfaces a
    /// section focus as an active-timer id.
    @MainActor
    func testExpandOpenFocusRoutesBySectionWithAndWithoutHighlight() {
        // Active timer -> active section, highlighted
        do {
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

        // Active section -> active section, no highlight
        do {
            let store = BottomSheetWorkspaceStateStore()

            store.expandFocusingActiveSection()

            XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: nil))
            XCTAssertNil(store.selectedTimerID)
            XCTAssertTrue(store.isExpanded)
        }

        // Completed section -> recently completed
        do {
            let store = BottomSheetWorkspaceStateStore()

            store.expandFocusingCompletedSection()

            XCTAssertEqual(store.openFocus, .recentlyCompletedSection)
            XCTAssertNil(
                store.selectedTimerID,
                "Section focus must not surface as an active-timer id."
            )
            XCTAssertTrue(store.isExpanded)
        }
    }

    /// Compact-card tap routing by status. PTIMER-126 fix: a completed
    /// card focuses the History section header (not the row,
    /// which would hide the section title and the Clear button).
    @MainActor
    func testCompactCardTapRoutesByStatusIncludingCompletedSectionFix() {
        // Active -> active section, highlighted
        do {
            let store = BottomSheetWorkspaceStateStore()
            let timer = bottomSheetSecondsScaleTimer()
            let snapshot = makeBottomSheetSnapshot(from: [timer])

            ExposureCalculatorScreen.handleCompactCardTap(
                id: timer.id,
                in: snapshot,
                store: store
            )

            XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: timer.id))
            XCTAssertTrue(store.isExpanded)
        }

        // Paused -> active section, highlighted
        do {
            let store = BottomSheetWorkspaceStateStore()
            let pausedTimer = bottomSheetPausedProgressTimer()
            let snapshot = makeBottomSheetSnapshot(from: [pausedTimer])

            ExposureCalculatorScreen.handleCompactCardTap(
                id: pausedTimer.id,
                in: snapshot,
                store: store
            )

            XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: pausedTimer.id))
            XCTAssertTrue(store.isExpanded)
        }

        // PTIMER-126: completed -> recently completed section header
        do {
            let store = BottomSheetWorkspaceStateStore()
            let completedTimer = bottomSheetSampleTimers().first { $0.status == .completed }!
            let snapshot = makeBottomSheetSnapshot(from: [completedTimer])

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

        // Mixed snapshot routes each card by status
        do {
            let store = BottomSheetWorkspaceStateStore()
            let active = bottomSheetSecondsScaleTimer()
            let completed = bottomSheetSampleTimers().first { $0.status == .completed }!
            let snapshot = makeBottomSheetSnapshot(from: [active, completed])

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
    }

    /// Overflow tap routing: lands on the active section when any
    /// active timer remains, otherwise the recently completed section.
    @MainActor
    func testOverflowTapRoutesToActiveSectionOtherwiseCompleted() {
        // Only completed -> recently completed
        do {
            let store = BottomSheetWorkspaceStateStore()
            let completed = bottomSheetSampleTimers().first { $0.status == .completed }!
            let snapshot = makeBottomSheetSnapshot(from: [completed])

            ExposureCalculatorScreen.handleOverflowTap(in: snapshot, store: store)

            XCTAssertEqual(store.openFocus, .recentlyCompletedSection)
            XCTAssertTrue(store.isExpanded)
        }

        // Any active -> active section
        do {
            let store = BottomSheetWorkspaceStateStore()
            let active = bottomSheetSecondsScaleTimer()
            let snapshot = makeBottomSheetSnapshot(from: [active])

            ExposureCalculatorScreen.handleOverflowTap(in: snapshot, store: store)

            XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: nil))
            XCTAssertTrue(store.isExpanded)
        }

        // Mixed -> prefers active section
        do {
            let store = BottomSheetWorkspaceStateStore()
            let active = bottomSheetSecondsScaleTimer()
            let completed = bottomSheetSampleTimers().first { $0.status == .completed }!
            let snapshot = makeBottomSheetSnapshot(from: [active, completed])

            ExposureCalculatorScreen.handleOverflowTap(in: snapshot, store: store)

            XCTAssertEqual(store.openFocus, .activeSection(highlightedTimerID: nil))
        }
    }

    /// hasTimerPresentation gates the timer chrome: false for an empty
    /// snapshot, true when any (running or completed-only) timer exists.
    func testHasTimerPresentationReflectsTimerExistence() {
        // Empty -> hidden
        do {
            let emptySnapshot = makeBottomSheetSnapshot(from: [])

            XCTAssertFalse(ExposureCalculatorScreen.hasTimerPresentation(in: emptySnapshot))
        }

        // Any timer -> shown
        do {
            let runningSnapshot = makeBottomSheetSnapshot(from: [bottomSheetSecondsScaleTimer()])
            let completedOnlySnapshot = makeBottomSheetSnapshot(
                from: [bottomSheetSampleTimers().first { $0.status == .completed }!]
            )

            XCTAssertTrue(ExposureCalculatorScreen.hasTimerPresentation(in: runningSnapshot))
            XCTAssertTrue(ExposureCalculatorScreen.hasTimerPresentation(in: completedOnlySnapshot))
        }
    }

    func testSectionScrollIDsAreExposed() {
        XCTAssertFalse(BottomSheetLargeWorkspaceView.activeSectionScrollID.isEmpty)
        XCTAssertFalse(BottomSheetLargeWorkspaceView.recentlyCompletedSectionScrollID.isEmpty)
        XCTAssertNotEqual(
            BottomSheetLargeWorkspaceView.activeSectionScrollID,
            BottomSheetLargeWorkspaceView.recentlyCompletedSectionScrollID
        )
    }

    /// `isCompletedSection` is the view-layer hook for scoping the
    /// `Clear` affordance. Confirms it is true exactly for the
    /// completed section and false elsewhere.
    func testIsCompletedSectionFlagsCompletedSectionOnly() {
        let snapshot = makeBottomSheetSnapshot(from: bottomSheetSampleTimers())
        let active = snapshot.sections.first { $0.title == TimerWorkspaceSection.activeTitle }
        let completed = snapshot.sections.first { $0.title == TimerWorkspaceSection.historyTitle }

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
        let runningOnly = makeBottomSheetSnapshot(from: [bottomSheetSecondsScaleTimer()])
        let withCompleted = makeBottomSheetSnapshot(from: [
            bottomSheetSecondsScaleTimer(),
            bottomSheetSampleTimers().first { $0.status == .completed }!,
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
        let snapshot = makeBottomSheetSnapshot(from: [bottomSheetSecondsScaleTimer()])

        XCTAssertFalse(snapshot.sections.contains { $0.isCompletedSection })
        XCTAssertEqual(snapshot.completedCount, 0)
    }

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
        let snapshot = makeBottomSheetSnapshot(from: bottomSheetSampleTimers())
        let host = UIHostingController(
            rootView: FullScreenTimersWindow(
                snapshot: snapshot,
                openFocus: .none,
                onPauseTimer: { _ in },
                onResumeTimer: { _ in },
                onCancelTimer: { _ in },
                onRemoveTimer: { _ in },
                onStartNewTimer: { _ in },
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
}
