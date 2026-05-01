import Combine
import SwiftUI

struct BottomSheetWorkspacePresentationAdapter {
    let formatRemaining: (TimeInterval) -> String
    let timeContext: (RunningTimerItem) -> String?
    let compactCompletedSupplementaryText: (RunningTimerItem) -> String?

    func makeSnapshot(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        BottomSheetWorkspaceSnapshot.make(
            from: timers,
            formatRemaining: formatRemaining,
            timeContext: timeContext,
            compactCompletedSupplementaryText: compactCompletedSupplementaryText
        )
    }
}
