import Combine
import SwiftUI

enum BottomSheetWorkspaceCopy {
    static let title = "Timers"
}

/// Geometry of the compact timer mini cards. Despite the
/// `BottomSheet` prefix (a holdover from when these cards lived
/// inside the bottom-sheet dock), the dimensions are now consumed by
/// the screen-level `CompactTimerCardStripView` — see
/// `ExposureWorkspaceLayoutMetrics.timerStripHeight`, which is
/// derived from `viewportHeight` here.
enum BottomSheetCompactDockMetrics {
    static let scrollsHorizontally = true
    static let contentInsets = EdgeInsets(top: 1, leading: 18, bottom: 1, trailing: 18)
    static let cardSpacing: CGFloat = 10
    static let timerCardWidth: CGFloat = 96
    static let timerCardHeight: CGFloat = 116
    static let overflowCardWidth: CGFloat = 86
    static let viewportHeight: CGFloat = timerCardHeight + contentInsets.top + contentInsets.bottom
    static let viewportCornerRadius: CGFloat = 22
}
