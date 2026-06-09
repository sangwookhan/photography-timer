import SwiftUI

public enum BottomSheetWorkspaceCopy {
    public static let title = "Timers"
}

/// Geometry of the compact timer mini cards. Despite the
/// `BottomSheet` prefix (a holdover from when these cards lived
/// inside the bottom-sheet dock), the dimensions are now consumed by
/// the screen-level `CompactTimerCardStripView` — see
/// `ExposureWorkspaceLayoutMetrics.timerStripHeight`, which is
/// derived from `viewportHeight` here.
public enum BottomSheetCompactDockMetrics {
    public static let scrollsHorizontally = true
    public static let contentInsets = EdgeInsets(top: 1, leading: 18, bottom: 1, trailing: 18)
    public static let cardSpacing: CGFloat = 10
    public static let timerCardWidth: CGFloat = 96
    public static let timerCardHeight: CGFloat = 116
    public static let overflowCardWidth: CGFloat = 86
    public static let viewportHeight: CGFloat = timerCardHeight + contentInsets.top + contentInsets.bottom
    public static let viewportCornerRadius: CGFloat = 22
}
