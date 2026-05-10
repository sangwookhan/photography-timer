import SwiftUI

enum ExposureWorkspaceLayoutDensity {
    case regular
    case compact
    case dense
}

/// Screen-level layout metrics for the exposure-calculator screen.
///
/// PTIMER-126 redesign: the closed-state Timers UI is no longer a
/// custom bottom-sheet dock. Timers surface in two screen-level
/// places:
///
/// - When timers exist: `CompactTimerCardStripView` is rendered as a
///   screen-level strip just above the bottom safe area.
/// - When no timers exist: nothing is rendered for the timer surface.
///
/// **Layout stability rule (PTIMER-126):** the camera workspace
/// budget and the page marker y-position do *not* depend on whether
/// timers exist. Both are computed against a single reservation that
/// always assumes the strip's footprint. The strip's *rendering* is
/// conditional, but the *space it would occupy* is always reserved
/// — so the calculator does not visibly reflow when the first timer
/// starts (no density change, no marker jump, no result-card
/// resize). Only the strip view itself appears or disappears.
///
/// Opened state: `FullScreenTimersWindow` is presented via
/// `.fullScreenCover`. The camera screen layout underneath is
/// unchanged because the window covers it.
struct ExposureWorkspaceLayoutMetrics {

    /// Vertical extent of the screen-level timer-card strip. Sized to
    /// fit the compact card viewport exactly. Always reserved in the
    /// layout budget even when no timers are rendered, so a timer
    /// appearing does not cause the workspace to reflow.
    static let timerStripHeight: CGFloat = BottomSheetCompactDockMetrics.viewportHeight

    /// Distance from the top of the bottom safe area to the timer
    /// strip's bottom edge. Provides breathing room so cards don't
    /// crowd the home-indicator zone.
    static let timerStripBottomMargin: CGFloat = 12

    /// Visual gap between the timer strip's top edge and the page
    /// marker's bottom edge. Always reserved.
    static let pageMarkerToStripGap: CGFloat = 8

    /// Effective vertical footprint of the page marker view.
    static let pageMarkerHeight: CGFloat = 14

    /// Visual gap between the page marker's top edge and the camera
    /// workspace's bottom edge.
    static let workspaceMarkerGap: CGFloat = 6

    // MARK: - Page marker

    /// Bottom-anchored y-offset of the page marker. The marker sits
    /// at the same y whether or not timers exist — the strip's
    /// footprint is always reserved in the layout, so a timer
    /// appearing or disappearing does not move the marker.
    static func pageMarkerBottomOffset(bottomSafeArea: CGFloat) -> CGFloat {
        bottomSafeArea
            + timerStripBottomMargin
            + timerStripHeight
            + pageMarkerToStripGap
    }

    // MARK: - Timer strip offset

    /// Bottom-anchored y-offset of the timer strip. Used only when
    /// the strip is rendered (i.e., timers exist). The reservation
    /// for this band exists in the workspace budget regardless.
    static func timerStripBottomOffset(bottomSafeArea: CGFloat) -> CGFloat {
        bottomSafeArea + timerStripBottomMargin
    }

    // MARK: - Camera workspace budget

    /// The camera workspace's available content height. Independent
    /// of whether timers exist — always reserves the full timer-strip
    /// + marker stack so the workspace size is stable across timer
    /// presence transitions.
    static func availableMainContentHeight(
        screenHeight: CGFloat,
        topSafeArea: CGFloat = 0,
        bottomSafeArea: CGFloat = 34
    ) -> CGFloat {
        let bottomReservation = timerStripBottomMargin
            + timerStripHeight
            + pageMarkerToStripGap
            + pageMarkerHeight
            + workspaceMarkerGap

        return screenHeight - topSafeArea - bottomSafeArea - bottomReservation
    }

    static func estimatedMainContentHeight(for density: ExposureWorkspaceLayoutDensity) -> CGFloat {
        switch density {
        case .regular:
            return 620
        case .compact:
            return 560
        case .dense:
            return 488
        }
    }
}
