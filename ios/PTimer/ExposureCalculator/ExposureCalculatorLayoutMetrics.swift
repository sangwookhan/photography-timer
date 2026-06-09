import SwiftUI
import PTimerKit

enum ExposureWorkspaceLayoutDensity {
    case regular
    case compact
    case dense
}

/// Screen-level layout metrics for the exposure-calculator screen.
///
/// The bottom of the trimmed workspace area is partitioned, top to
/// bottom, into: camera workspace → marker gap → page marker →
/// marker-to-rail gap → timer preview rail → rail bottom margin.
/// The rail footprint is reserved unconditionally so timer presence
/// never reflows the camera workspace; only the rail's *contents*
/// (`CompactTimerCardStripView`) are conditional.
///
/// The screen-level `GeometryReader` is hosted inside the default
/// safe area, so `geometry.size.height` is already safe-area-trimmed
/// and the metrics below partition that trimmed area only.
struct ExposureWorkspaceLayoutMetrics {

    /// Height of the timer preview rail band.
    static let timerStripHeight: CGFloat = BottomSheetCompactDockMetrics.viewportHeight

    /// Distance from the trimmed-area bottom edge to the rail's
    /// bottom edge.
    static let timerStripBottomMargin: CGFloat = 2

    /// Visual gap between the rail's top edge and the page marker's
    /// bottom edge.
    static let pageMarkerToStripGap: CGFloat = 4

    /// Effective vertical footprint of the page marker view.
    static let pageMarkerHeight: CGFloat = 12

    /// Visual gap between the page marker's top edge and the camera
    /// workspace's bottom edge.
    static let workspaceMarkerGap: CGFloat = 4

    /// Total reservation below the camera workspace: marker gap +
    /// marker + marker-to-rail gap + rail + rail bottom margin.
    static let bottomReservation: CGFloat =
        timerStripBottomMargin
        + timerStripHeight
        + pageMarkerToStripGap
        + pageMarkerHeight
        + workspaceMarkerGap

    // MARK: - Page marker

    /// Bottom-anchored y-offset of the page marker. The marker
    /// always sits above the rail's reserved band; its position is
    /// independent of timer presence.
    static func pageMarkerBottomOffset() -> CGFloat {
        timerStripBottomMargin
            + timerStripHeight
            + pageMarkerToStripGap
    }

    // MARK: - Timer rail offset

    /// Bottom-anchored y-offset of the rail (boundary background
    /// and, when present, the compact strip cards).
    static func timerStripBottomOffset() -> CGFloat {
        timerStripBottomMargin
    }

    // MARK: - Camera workspace budget

    /// Available height for the camera workspace, derived from the
    /// trimmed `workspaceArea` minus the unconditional bottom
    /// reservation. Safe-area insets are already excluded from
    /// `workspaceArea` and must not be subtracted again here.
    static func availableMainContentHeight(workspaceArea: CGFloat) -> CGFloat {
        workspaceArea - bottomReservation
    }

    /// Minimum workspace budget at which the given density tier is
    /// allowed to render the page without overflowing required
    /// visible content.
    static func estimatedMainContentHeight(for density: ExposureWorkspaceLayoutDensity) -> CGFloat {
        switch density {
        case .regular:
            return 700
        case .compact:
            return 600
        case .dense:
            return 488
        }
    }
}
