import Foundation

public struct BottomSheetWorkspacePresentationAdapter {
    public let formatRemaining: (TimeInterval) -> String
    public let timeContext: (RunningTimerItem) -> String?
    public let compactCompletedSupplementaryText: (RunningTimerItem) -> String?

    public init(
        formatRemaining: @escaping (TimeInterval) -> String,
        timeContext: @escaping (RunningTimerItem) -> String?,
        compactCompletedSupplementaryText: @escaping (RunningTimerItem) -> String?
    ) {
        self.formatRemaining = formatRemaining
        self.timeContext = timeContext
        self.compactCompletedSupplementaryText = compactCompletedSupplementaryText
    }

    public func makeSnapshot(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        BottomSheetWorkspaceSnapshot.make(
            from: timers,
            formatRemaining: formatRemaining,
            timeContext: timeContext,
            compactCompletedSupplementaryText: compactCompletedSupplementaryText
        )
    }
}
