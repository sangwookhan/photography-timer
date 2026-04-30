import Combine
import SwiftUI

struct CompactRemainingScaleLayer: Equatable {
    let fraction: Double
}

struct BottomSheetIdentityCue: Equatable {
    let markerText: String
    let tintSlot: Int
}

struct BottomSheetCompactItem: Identifiable, Equatable {
    let id: UUID
    let status: TimerStatus
    let identityCue: BottomSheetIdentityCue
    let primaryRemainingText: String
    let secondaryTotalText: String?
    let tertiaryStatusText: String?
    let showsDecorativeTimeline: Bool
    let sixtySecondLayer: CompactRemainingScaleLayer
    let sixtyMinuteLayer: CompactRemainingScaleLayer?
    let originalScaleLayer: CompactRemainingScaleLayer?

    var visibleLayerCount: Int {
        [originalScaleLayer, sixtyMinuteLayer, sixtySecondLayer as CompactRemainingScaleLayer?]
            .compactMap { $0 }
            .count
    }
}

struct BottomSheetLargeItem: Identifiable, Equatable {
    let id: UUID
    let title: String?
    let statusLabel: String
    let status: TimerStatus
    let identityCue: BottomSheetIdentityCue
    let remainingText: String
    let totalDurationText: String?
    let timingText: String?
    let contextText: String?
    let progress: Double
    let actions: [BottomSheetLargeAction]
}

struct TimerWorkspaceSection: Identifiable, Equatable {
    let title: String
    let items: [BottomSheetLargeItem]

    var id: String { title }
}

struct BottomSheetWorkspaceSnapshot: Equatable {
    static let compactVisibleLimit = 3

    /// Number of completed timers, used to determine if "Clear" button should be shown in the large workspace.
    let completedCount: Int

    /// The top-N timers to be shown in the compact mini dock.
    let compactItems: [BottomSheetCompactItem]

    /// Number of timers not shown in the compact dock due to the visible limit.
    let hiddenCompactItemCount: Int

    /// Sections for the large workspace list (e.g. "Active", "Recently Completed").
    let sections: [TimerWorkspaceSection]

    /// Defines the number of visible remaining scale layers based on timer duration.
    ///
    /// The policy is:
    /// - < 60s: 1 layer (sixtySecondLayer only)
    /// - 60s <= d < 3600s: 2 layers (sixtySecondLayer + sixtyMinuteLayer)
    /// - >= 3600s: 3 layers (sixtySecondLayer + sixtyMinuteLayer + originalScaleLayer)
    static func compactLayerCount(for duration: TimeInterval) -> Int {
        if duration < 60 {
            return 1
        } else if duration < 3600 {
            return 2
        } else {
            return 3
        }
    }

    static func make(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        timeContext: (RunningTimerItem) -> String?,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> BottomSheetWorkspaceSnapshot {
        let orderedTimers = TimerWorkspaceOrdering.sort(timers)

        let compactItems = orderedTimers
            .prefix(Self.compactVisibleLimit)
            .map { timer in
                let identityCue = identityCue(for: timer)

                return BottomSheetCompactItem(
                    id: timer.id,
                    status: timer.status,
                    identityCue: identityCue,
                    primaryRemainingText: compactRemainingText(
                        for: timer,
                        formatRemaining: formatRemaining,
                        compactCompletedSupplementaryText: compactCompletedSupplementaryText
                    ),
                    secondaryTotalText: compactSecondaryText(
                        for: timer,
                        compactCompletedSupplementaryText: compactCompletedSupplementaryText
                    ),
                    tertiaryStatusText: compactTertiaryText(
                        for: timer,
                        compactCompletedSupplementaryText: compactCompletedSupplementaryText
                    ),
                    showsDecorativeTimeline: timer.status != .completed,
                    sixtySecondLayer: compactSixtySecondLayer(for: timer),
                    sixtyMinuteLayer: compactSixtyMinuteLayer(for: timer),
                    originalScaleLayer: compactOriginalScaleLayer(for: timer)
                )
            }

        let sections = makeSections(
            from: orderedTimers,
            formatRemaining: formatRemaining,
            timeContext: timeContext
        )

        return BottomSheetWorkspaceSnapshot(
            completedCount: timers.filter { $0.status == .completed }.count,
            compactItems: compactItems,
            hiddenCompactItemCount: max(0, orderedTimers.count - compactItems.count),
            sections: sections
        )
    }

    var compactOverflowText: String? {
        guard hiddenCompactItemCount > 0 else {
            return nil
        }

        return "+\(hiddenCompactItemCount)"
    }

    private static func makeSections(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        timeContext: (RunningTimerItem) -> String?
    ) -> [TimerWorkspaceSection] {
        let activeTimers = timers.filter { $0.status != .completed }
        let completedTimers = timers.filter { $0.status == .completed }

        return [
            makeSection(
                title: "Active",
                timers: activeTimers,
                formatRemaining: formatRemaining,
                timeContext: timeContext
            ),
            makeSection(
                title: "Recently Completed",
                timers: completedTimers,
                formatRemaining: formatRemaining,
                timeContext: timeContext
            )
        ].compactMap { $0 }
    }

    private static func makeSection(
        title: String,
        timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        timeContext: (RunningTimerItem) -> String?
    ) -> TimerWorkspaceSection? {
        guard !timers.isEmpty else {
            return nil
        }

        return TimerWorkspaceSection(
            title: title,
            items: timers.map { timer in
                let totalDurationText = largeTotalDurationText(for: timer, formatRemaining: formatRemaining)
                let contextText = largeContextText(for: timer)
                let identityCue = identityCue(for: timer)

                return BottomSheetLargeItem(
                    id: timer.id,
                    title: largeTitleText(
                        for: timer,
                        totalDurationText: totalDurationText,
                        contextText: contextText
                    ),
                    statusLabel: visibleStatusLabel(for: timer.status),
                    status: timer.status,
                    identityCue: identityCue,
                    remainingText: largeRemainingText(for: timer, formatRemaining: formatRemaining),
                    totalDurationText: totalDurationText,
                    timingText: timeContext(timer),
                    contextText: contextText,
                    progress: progress(for: timer),
                    actions: largeActions(for: timer.status)
                )
            }
        )
    }

    private static func identityCue(for timer: RunningTimerItem) -> BottomSheetIdentityCue {
        BottomSheetIdentityCue(
            markerText: "T\(timer.order)",
            tintSlot: stableIdentityTintSlot(for: timer.id)
        )
    }

    private static func stableIdentityTintSlot(for id: UUID) -> Int {
        id.uuidString.utf8.reduce(0) { partial, byte in
            ((partial * 33) + Int(byte)) % BottomSheetIdentityPalette.slotCount
        }
    }

    private static func progress(for timer: RunningTimerItem) -> Double {
        guard timer.duration > 0 else {
            return 0
        }

        return min(max(timer.elapsedTime / timer.duration, 0), 1)
    }

    private static func compactSixtySecondLayer(for timer: RunningTimerItem) -> CompactRemainingScaleLayer {
        CompactRemainingScaleLayer(
            fraction: repeatingRemainingFraction(
                remainingTime: timer.remainingTime,
                unitDuration: 60,
                status: timer.status
            )
        )
    }

    private static func compactSixtyMinuteLayer(for timer: RunningTimerItem) -> CompactRemainingScaleLayer? {
        guard compactLayerCount(for: timer.duration) >= 2 else {
            return nil
        }

        return CompactRemainingScaleLayer(
            fraction: repeatingRemainingFraction(
                remainingTime: timer.remainingTime,
                unitDuration: 3_600,
                status: timer.status
            )
        )
    }

    private static func compactOriginalScaleLayer(for timer: RunningTimerItem) -> CompactRemainingScaleLayer? {
        guard compactLayerCount(for: timer.duration) >= 3 else {
            return nil
        }

        switch timer.status {
        case .completed:
            return CompactRemainingScaleLayer(fraction: 0)
        case .running, .paused:
            let cappedOriginalDuration = min(max(timer.duration, 0), 86_400)
            let cappedRemainingTime = min(max(timer.remainingTime, 0), cappedOriginalDuration)
            let fraction = cappedOriginalDuration > 0 ? cappedRemainingTime / 86_400 : 0
            return CompactRemainingScaleLayer(fraction: min(max(fraction, 0), 1))
        }
    }

    private static func repeatingRemainingFraction(
        remainingTime: TimeInterval,
        unitDuration: TimeInterval,
        status: TimerStatus
    ) -> Double {
        switch status {
        case .completed:
            return 0
        case .running, .paused:
            guard unitDuration > 0 else {
                return 0
            }

            let clampedRemaining = max(0, remainingTime)
            guard clampedRemaining > 0 else {
                return 0
            }

            let remainder = clampedRemaining.truncatingRemainder(dividingBy: unitDuration)
            if remainder == 0 {
                return 1
            }

            return min(max(remainder / unitDuration, 0), 1)
        }
    }

    private static func largeActions(for status: TimerStatus) -> [BottomSheetLargeAction] {
        switch status {
        case .running:
            return [.pause]
        case .paused:
            return [.resume, .remove]
        case .completed:
            return [.remove]
        }
    }

    private static func compactRemainingText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String {
        switch timer.status {
        case .running, .paused:
            return compactDurationText(timer.remainingTime)
        case .completed:
            return "Done"
        }
    }

    private static func compactSecondaryText(
        for timer: RunningTimerItem,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String? {
        switch timer.status {
        case .completed:
            guard timer.duration > 0 else {
                return nil
            }

            return compactDurationText(timer.duration)
        case .running, .paused:
            guard timer.duration > 0 else {
                return nil
            }

            return compactDurationText(timer.duration)
        }
    }

    private static func compactTertiaryText(
        for timer: RunningTimerItem,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String? {
        guard timer.status == .completed else {
            return nil
        }

        return compactCompletedSupplementaryText(timer)
    }

    private static func largeRemainingText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String {
        switch timer.status {
        case .running, .paused:
            return formatRemaining(timer.remainingTime)
        case .completed:
            return "Done"
        }
    }

    private static func largeTotalDurationText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String? {
        guard timer.duration > 0 else {
            return nil
        }

        return formatRemaining(timer.duration)
    }

    private static func largeContextText(for timer: RunningTimerItem) -> String? {
        let summary = timer.basisSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private static func largeTitleText(
        for timer: RunningTimerItem,
        totalDurationText: String?,
        contextText: String?
    ) -> String? {
        let rawTitle = timer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else {
            return nil
        }

        var normalizedTitle = rawTitle

        if let totalDurationText, normalizedTitle.contains(totalDurationText) {
            normalizedTitle = normalizedTitle
                .replacingOccurrences(of: totalDurationText, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -:."))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !normalizedTitle.isEmpty else {
            return nil
        }

        if let contextText, contextText.localizedCaseInsensitiveContains(normalizedTitle) {
            return nil
        }

        if normalizedTitle == "Timer" || normalizedTitle == "Manual timer" {
            return nil
        }

        return normalizedTitle
    }

    private static func visibleStatusLabel(for status: TimerStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .completed:
            return "Done"
        }
    }

    static func compactDurationText(_ duration: TimeInterval) -> String {
        let clamped = max(duration, 0)

        if clamped < 10 {
            let roundedToTenth = (clamped * 10).rounded() / 10
            return String(format: "%.1fs", roundedToTenth)
        }

        let roundedDown = Int(clamped.rounded(.down))

        if roundedDown < 60 {
            return "\(roundedDown)s"
        }

        if roundedDown < 3_600 {
            let minutes = roundedDown / 60
            let seconds = roundedDown % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        let units: [(label: String, seconds: Int)] = [
            ("y", 31_536_000),
            ("m", 2_592_000),
            ("d", 86_400),
            ("h", 3_600),
            ("m", 60)
        ]

        var remaining = roundedDown
        var parts: [String] = []

        for unit in units {
            guard remaining >= unit.seconds else {
                continue
            }

            let value = remaining / unit.seconds
            remaining %= unit.seconds
            parts.append("\(value)\(unit.label)")

            if parts.count == 2 {
                break
            }
        }

        if parts.isEmpty {
            return "\(roundedDown)s"
        }

        return parts.joined(separator: " ")
    }
}
