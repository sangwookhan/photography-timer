import Combine
import SwiftUI

struct BottomSheetWorkspaceShell: View {
    @ObservedObject var stateStore: BottomSheetWorkspaceStateStore
    let snapshot: BottomSheetWorkspaceSnapshot
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void

    var body: some View {
        BottomSheetContainer(
            detent: stateStore.detent,
            onDragEnded: stateStore.handleDragEnd(translation:),
            content: {
                BottomSheetContentHost(
                    detent: stateStore.detent,
                    snapshot: snapshot,
                    focusedTimerID: stateStore.selectedTimerID,
                    onCompactItemTap: stateStore.expandAndFocusTimer(_:),
                    onOverflowTap: stateStore.expand,
                    onCollapse: stateStore.collapse,
                    onPauseTimer: onPauseTimer,
                    onResumeTimer: onResumeTimer,
                    onRemoveTimer: onRemoveTimer,
                    onClearCompletedTimers: onClearCompletedTimers
                )
            }
        )
    }
}

enum BottomSheetDetent: String, CaseIterable, Identifiable {
    case compact
    case large

    static let `default`: BottomSheetDetent = .compact

    var id: String { rawValue }

    var isExpanded: Bool {
        self != .compact
    }

    var showsLargeWorkspace: Bool {
        self == .large
    }
}

struct BottomSheetPresentationState: Equatable {
    var detent: BottomSheetDetent
    var selectedTimerID: UUID?

    static let `default` = BottomSheetPresentationState(
        detent: .default,
        selectedTimerID: nil
    )
}

@MainActor
final class BottomSheetWorkspaceStateStore: ObservableObject {
    private enum DragThreshold {
        static let compactExpand: CGFloat = 92
        static let largeCollapse: CGFloat = 64
    }

    @Published private(set) var presentationState: BottomSheetPresentationState

    init(detent: BottomSheetDetent = .default) {
        self.presentationState = BottomSheetPresentationState(
            detent: detent,
            selectedTimerID: nil
        )
    }

    var detent: BottomSheetDetent {
        presentationState.detent
    }

    var selectedTimerID: UUID? {
        presentationState.selectedTimerID
    }

    var isExpanded: Bool {
        detent.isExpanded
    }

    func transition(to detent: BottomSheetDetent) {
        presentationState.detent = detent
        if detent == .compact {
            presentationState.selectedTimerID = nil
        }
    }

    func expand() {
        transition(to: .large)
    }

    func expandAndFocusTimer(_ id: UUID) {
        presentationState.selectedTimerID = id
        expand()
    }

    func focusTimer(_ id: UUID) {
        presentationState.selectedTimerID = id
    }

    func collapse() {
        transition(to: .compact)
    }

    func handleDragEnd(translation: CGFloat) {
        switch detent {
        case .compact:
            if translation <= -DragThreshold.compactExpand {
                expand()
            }
        case .large:
            if translation >= DragThreshold.largeCollapse {
                collapse()
            }
        }
    }
}

struct BottomSheetLayoutMetrics {
    static let compactMainContentReservation: CGFloat = 132
    static let largeFixedHeight: CGFloat = 560

    static func fixedHeight(for detent: BottomSheetDetent) -> CGFloat? {
        switch detent {
        case .compact:
            return nil
        case .large:
            return largeFixedHeight
        }
    }

    static func mainContentReservation(for detent: BottomSheetDetent) -> CGFloat {
        switch detent {
        case .compact:
            return compactMainContentReservation
        case .large:
            return largeFixedHeight
        }
    }

    static func dimOpacity(for detent: BottomSheetDetent) -> Double {
        switch detent {
        case .compact:
            return 0
        case .large:
            return 0.2
        }
    }
}

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

enum BottomSheetWorkspaceCopy {
    static let title = "Timers"
}

enum BottomSheetCompactDockMetrics {
    static let scrollsHorizontally = true
    static let contentInsets = EdgeInsets(top: 1, leading: 18, bottom: 1, trailing: 18)
    static let cardSpacing: CGFloat = 10
    static let timerCardWidth: CGFloat = 96
    static let timerCardHeight: CGFloat = 96
    static let overflowCardWidth: CGFloat = 86
    static let viewportHeight: CGFloat = timerCardHeight + contentInsets.top + contentInsets.bottom
    static let viewportCornerRadius: CGFloat = 22
}

@MainActor
final class BottomSheetWorkspaceSnapshotStore: ObservableObject {
    @Published private(set) var snapshot: BottomSheetWorkspaceSnapshot

    private var cancellables: Set<AnyCancellable> = []

    init(
        initialTimers: [RunningTimerItem] = [],
        timersPublisher: AnyPublisher<[RunningTimerItem], Never>,
        adapter: BottomSheetWorkspacePresentationAdapter
    ) {
        self.snapshot = adapter.makeSnapshot(from: initialTimers)

        timersPublisher
            .map { adapter.makeSnapshot(from: $0) }
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
            .store(in: &cancellables)
    }
}

enum BottomSheetQuickAction: String, Equatable {
    case pause
    case resume

    var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        }
    }

    var systemImageName: String {
        switch self {
        case .pause:
            return "pause.fill"
        case .resume:
            return "play.fill"
        }
    }
}

enum BottomSheetLargeAction: String, Equatable {
    case pause
    case resume
    case remove

    var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        case .remove:
            return "Remove"
        }
    }
}

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

private struct BottomSheetContainer<Content: View>: View {
    let detent: BottomSheetDetent
    let onDragEnded: (CGFloat) -> Void
    @ViewBuilder let content: Content

    private var handleDragGesture: some Gesture {
        DragGesture(minimumDistance: detent == .compact ? 20 : 14)
            .onEnded { value in
                onDragEnded(value.translation.height)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: detent == .compact ? 34 : 42, height: 5)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, detent == .compact ? 5 : 10)
            .padding(.bottom, detent.isExpanded ? 8 : 6)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
            .gesture(handleDragGesture)
            .accessibilityIdentifier("bottom-sheet-handle-area")

            content
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .ifLet(BottomSheetLayoutMetrics.fixedHeight(for: detent)) { view, height in
            view.frame(height: height)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(detent.isExpanded ? 0.45 : 0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(detent.isExpanded ? 0.22 : 0.12), radius: detent.isExpanded ? 30 : 18, x: 0, y: -6)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 0)
        .accessibilityIdentifier("bottom-sheet-shell")
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: detent)
    }
}

private struct BottomSheetContentHost: View {
    let detent: BottomSheetDetent
    let snapshot: BottomSheetWorkspaceSnapshot
    let focusedTimerID: UUID?
    let onCompactItemTap: (UUID) -> Void
    let onOverflowTap: () -> Void
    let onCollapse: () -> Void
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: detent.isExpanded ? 10 : 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(BottomSheetWorkspaceCopy.title)
                    .font(detent == .compact ? .subheadline.weight(.semibold) : .headline)

                Spacer()
            }

            Group {
                switch detent {
                case .compact:
                    BottomSheetCompactSummaryView(
                        snapshot: snapshot,
                        onItemTap: onCompactItemTap,
                        onOverflowTap: onOverflowTap
                    )
                case .large:
                    BottomSheetLargeWorkspaceView(
                        snapshot: snapshot,
                        focusedTimerID: focusedTimerID,
                        onPauseTimer: onPauseTimer,
                        onResumeTimer: onResumeTimer,
                        onRemoveTimer: onRemoveTimer,
                        onClearCompletedTimers: onClearCompletedTimers,
                        onCollapse: onCollapse
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: detent.isExpanded ? .infinity : nil,
                alignment: .top
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, detent.isExpanded ? 14 : 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: detent.isExpanded ? .infinity : nil,
            alignment: .topLeading
        )
    }
}

private struct BottomSheetCompactSummaryView: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let onItemTap: (UUID) -> Void
    let onOverflowTap: () -> Void

    var body: some View {
        Group {
            if snapshot.compactItems.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)

                    Text("Start a timer to pin it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("bottom-sheet-compact-empty")
            } else {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: BottomSheetCompactDockMetrics.viewportCornerRadius,
                        style: .continuous
                    )
                    .fill(Color(.secondarySystemBackground).opacity(0.58))

                    ScrollView(
                        BottomSheetCompactDockMetrics.scrollsHorizontally ? .horizontal : .vertical,
                        showsIndicators: false
                    ) {
                        LazyHStack(spacing: BottomSheetCompactDockMetrics.cardSpacing) {
                            Color.clear
                                .frame(width: BottomSheetCompactDockMetrics.contentInsets.leading, height: 1)
                                .accessibilityHidden(true)

                            ForEach(snapshot.compactItems) { item in
                                CompactTimerMiniCardView(
                                    item: item,
                                    onTap: {
                                        onItemTap(item.id)
                                    }
                                )
                            }

                            if let overflowText = snapshot.compactOverflowText {
                                CompactOverflowMiniCard(
                                    text: overflowText,
                                    onTap: onOverflowTap
                                )
                            }

                            Color.clear
                                .frame(width: BottomSheetCompactDockMetrics.contentInsets.trailing, height: 1)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, BottomSheetCompactDockMetrics.contentInsets.top)
                    }
                }
                .frame(height: BottomSheetCompactDockMetrics.viewportHeight, alignment: .top)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: BottomSheetCompactDockMetrics.viewportCornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityIdentifier("bottom-sheet-compact-dock")
            }
        }
    }
}

private struct CompactTimerMiniCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRunningPulseActive = false

    let item: BottomSheetCompactItem
    let onTap: () -> Void

    private var compactPrimaryTextFont: Font {
        item.status == .completed ? .headline.weight(.bold) : .title3.weight(.bold)
    }

    private var compactPrimaryTextScaleFactor: CGFloat {
        item.status == .completed ? 0.9 : 0.75
    }

    private var compactPrimaryTextColor: Color {
        item.status == .completed ? .primary.opacity(0.92) : .primary
    }

    private var compactSecondaryTextColor: Color {
        item.status == .completed ? .secondary.opacity(0.52) : .secondary.opacity(0.86)
    }

    private var compactTertiaryTextColor: Color {
        .secondary.opacity(0.72)
    }

    private var compactStatusSymbolFont: Font {
        item.status == .completed ? .caption2.weight(.medium) : .caption.weight(.semibold)
    }

    private var compactStatusSymbolOpacity: Double {
        item.status == .completed ? 0.46 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 5) {
                ZStack {
                    if shouldAnimateRunningCue {
                        Circle()
                            .fill(statusColor(for: item.status).opacity(isRunningPulseActive ? 0.10 : 0.24))
                            .frame(
                                width: isRunningPulseActive ? 22 : 13,
                                height: isRunningPulseActive ? 22 : 13
                            )

                        Circle()
                            .stroke(statusColor(for: item.status).opacity(isRunningPulseActive ? 0.06 : 0.18), lineWidth: 1)
                            .frame(
                                width: isRunningPulseActive ? 18 : 12,
                                height: isRunningPulseActive ? 18 : 12
                            )
                    }

                    Image(systemName: compactStatusSymbol(for: item.status))
                        .font(compactStatusSymbolFont)
                        .foregroundStyle(statusColor(for: item.status))
                        .scaleEffect(shouldAnimateRunningCue ? (isRunningPulseActive ? 1.08 : 0.92) : 1)
                        .opacity(
                            shouldAnimateRunningCue
                                ? (isRunningPulseActive ? 1 : 0.72)
                                : compactStatusSymbolOpacity
                        )
                }
                .frame(width: 22, height: 22)
                .animation(
                    shouldAnimateRunningCue
                        ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                        : .default,
                    value: isRunningPulseActive
                )

                Spacer(minLength: 0)

                if let totalText = item.secondaryTotalText {
                    Text(totalText)
                        .font(.caption2)
                        .foregroundStyle(compactSecondaryTextColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                }
            }
            .frame(height: 22, alignment: .top)

            VStack(spacing: 0) {
                Text(item.primaryRemainingText)
                    .font(compactPrimaryTextFont)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(compactPrimaryTextScaleFactor)
                    .foregroundStyle(compactPrimaryTextColor)
                    .padding(.top, 5)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)

            if let tertiaryText = item.tertiaryStatusText {
                Text(tertiaryText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(compactTertiaryTextColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            } else {
                Spacer(minLength: 6)
            }

            if item.showsDecorativeTimeline {
                VStack(spacing: 3) {
                    if let originalScaleLayer = item.originalScaleLayer {
                        CompactProgressBar(
                            progress: originalScaleLayer.fraction,
                            fillColor: originalScaleFillColor,
                            trackColor: originalScaleTrackColor,
                            height: 1
                        )
                    }

                    if let sixtyMinuteLayer = item.sixtyMinuteLayer {
                        CompactProgressBar(
                            progress: sixtyMinuteLayer.fraction,
                            fillColor: sixtyMinuteFillColor,
                            trackColor: sixtyMinuteTrackColor,
                            height: 1
                        )
                    }

                    CompactProgressBar(
                        progress: item.sixtySecondLayer.fraction,
                        fillColor: sixtySecondFillColor,
                        trackColor: sixtySecondTrackColor,
                        height: 1
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 9, alignment: .bottom)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity, minHeight: 9, alignment: .bottom)
            }

            HStack {
                Spacer(minLength: 0)

                IdentityMarkerBadge(
                    cue: item.identityCue,
                    size: .compact
                )
                .opacity(item.status == .completed ? 0.64 : 1)
            }
            .padding(.top, 3)
            .padding(.trailing, 1)
            .frame(maxWidth: .infinity, minHeight: 10, alignment: .bottomTrailing)
        }
        .padding(.top, 9)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(
            width: BottomSheetCompactDockMetrics.timerCardWidth,
            height: BottomSheetCompactDockMetrics.timerCardHeight,
            alignment: .topLeading
        )
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(statusColor(for: item.status).opacity(0.16), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("bottom-sheet-compact-mini-card-\(item.id.uuidString)")
        .onTapGesture(perform: onTap)
        .onAppear {
            updateRunningPulse()
        }
        .onChange(of: item.status) { _, _ in
            updateRunningPulse()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateRunningPulse()
        }
    }

    private var shouldAnimateRunningCue: Bool {
        item.status == .running && !reduceMotion
    }

    private func updateRunningPulse() {
        guard shouldAnimateRunningCue else {
            isRunningPulseActive = false
            return
        }

        isRunningPulseActive = true
    }

    private func compactStatusSymbol(for status: TimerStatus) -> String {
        switch status {
        case .running:
            return "hourglass.bottomhalf.filled"
        case .paused:
            return "pause.fill"
        case .completed:
            return "checkmark"
        }
    }

    private var sixtySecondFillColor: Color {
        switch item.status {
        case .completed:
            return statusColor(for: item.status).opacity(0.72)
        case .paused:
            return Color.orange.opacity(0.88)
        case .running:
            return Color.red.opacity(0.92)
        }
    }

    private var sixtySecondTrackColor: Color {
        switch item.status {
        case .completed:
            return statusColor(for: item.status).opacity(0.16)
        case .paused:
            return Color.orange.opacity(0.16)
        case .running:
            return Color.red.opacity(0.18)
        }
    }

    private var sixtyMinuteFillColor: Color {
        switch item.status {
        case .completed:
            return statusColor(for: item.status).opacity(0.56)
        case .paused:
            return Color.yellow.opacity(0.72)
        case .running:
            return Color.orange.opacity(0.74)
        }
    }

    private var sixtyMinuteTrackColor: Color {
        switch item.status {
        case .completed:
            return statusColor(for: item.status).opacity(0.12)
        case .paused:
            return Color.yellow.opacity(0.11)
        case .running:
            return Color.orange.opacity(0.12)
        }
    }

    private var originalScaleFillColor: Color {
        switch item.status {
        case .completed:
            return statusColor(for: item.status).opacity(0.38)
        case .paused:
            return Color.mint.opacity(0.48)
        case .running:
            return Color.teal.opacity(0.46)
        }
    }

    private var originalScaleTrackColor: Color {
        switch item.status {
        case .completed:
            return statusColor(for: item.status).opacity(0.08)
        case .paused:
            return Color.mint.opacity(0.08)
        case .running:
            return Color.teal.opacity(0.08)
        }
    }
}

private struct CompactProgressBar: View {
    let progress: Double
    let fillColor: Color
    let trackColor: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(max(progress, 0), 1)
            let width = max(geometry.size.width * clampedProgress, clampedProgress > 0 ? height : 0)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)

                Capsule(style: .continuous)
                    .fill(fillColor)
                    .frame(width: width)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct IdentityMarkerBadge: View {
    let cue: BottomSheetIdentityCue
    let size: IdentityMarkerBadgeSize

    var body: some View {
        Text(cue.markerText)
            .font(size.font)
            .foregroundStyle(identityTintColor(for: cue).opacity(size.foregroundOpacity))
            .lineLimit(1)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(identityTintColor(for: cue).opacity(size.backgroundOpacity))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }
}

private enum IdentityMarkerBadgeSize {
    case compact
    case regular

    var font: Font {
        switch self {
        case .compact:
            return .caption2.weight(.medium)
        case .regular:
            return .caption2.weight(.medium)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact:
            return 3
        case .regular:
            return 5
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return 1
        case .regular:
            return 2
        }
    }

    var backgroundOpacity: Double {
        switch self {
        case .compact:
            return 0.06
        case .regular:
            return 0.06
        }
    }

    var foregroundOpacity: Double {
        switch self {
        case .compact:
            return 0.68
        case .regular:
            return 0.68
        }
    }
}

private struct CompactOverflowMiniCard: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)

            Text(text)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)

            Text("View all")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(
            width: BottomSheetCompactDockMetrics.overflowCardWidth,
            height: BottomSheetCompactDockMetrics.timerCardHeight,
            alignment: .topLeading
        )
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("bottom-sheet-compact-overflow-card")
        .onTapGesture(perform: onTap)
    }
}

private struct BottomSheetLargeWorkspaceView: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let focusedTimerID: UUID?
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void
    let onCollapse: () -> Void
    @State private var hasAppliedInitialFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.completedCount > 0 {
                LargeWorkspaceSummaryStrip(
                    onClearCompletedTimers: onClearCompletedTimers
                )
            }

            if snapshot.sections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No timers in workspace")
                        .font(.subheadline.weight(.semibold))

                    Text("Return to the calculator and start a timer to see it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Back to Calculator") {
                        onCollapse()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(snapshot.sections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    ForEach(section.items) { item in
                                        LargeWorkspaceTimerRowView(
                                            item: item,
                                            isFocused: item.id == focusedTimerID,
                                            onAction: { action in
                                                handle(action: action, for: item.id)
                                            }
                                        )
                                        .id(item.id)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            applyFocusIfNeeded(using: proxy, animated: false)
                        }
                        .onChange(of: focusedTimerID) { _, _ in
                            applyFocusIfNeeded(using: proxy, animated: true)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("bottom-sheet-large-workspace")
                }
            }
        }
    }

    private func applyFocusIfNeeded(using proxy: ScrollViewProxy, animated: Bool) {
        guard let focusedTimerID else {
            return
        }

        if !animated && hasAppliedInitialFocus {
            return
        }

        let scroll = {
            proxy.scrollTo(focusedTimerID, anchor: .top)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                scroll()
            }
        } else {
            scroll()
            hasAppliedInitialFocus = true
        }
    }

    private func handle(action: BottomSheetLargeAction, for id: UUID) {
        switch action {
        case .pause:
            onPauseTimer(id)
        case .resume:
            onResumeTimer(id)
        case .remove:
            onRemoveTimer(id)
        }
    }
}

private struct LargeWorkspaceSummaryStrip: View {
    let onClearCompletedTimers: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Button("Clear") {
                onClearCompletedTimers()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("bottom-sheet-clear-completed-button")
        }
    }
}

private struct LargeWorkspaceTimerRowView: View {
    let item: BottomSheetLargeItem
    let isFocused: Bool
    let onAction: (BottomSheetLargeAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let title = item.title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                StatusChip(status: item.status, label: item.statusLabel, size: .regular)
            }

            VStack(alignment: .trailing, spacing: 2) {
                if let totalDurationText = item.totalDurationText {
                    Text(totalDurationText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Text(item.remainingText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if item.timingText != nil || item.contextText != nil {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let timingText = item.timingText {
                            Text(timingText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if let contextText = item.contextText {
                            Text(contextText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 0)

                    IdentityMarkerBadge(
                        cue: item.identityCue,
                        size: .regular
                    )
                }
            }

            ProgressView(value: item.progress)
                .tint(statusColor(for: item.status))
                .opacity(0.88)

            if !item.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.actions, id: \.rawValue) { action in
                        LargeActionButton(
                            action: action,
                            tint: tint(for: action),
                            onTap: {
                                onAction(action)
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            isFocused
                ? statusColor(for: item.status).opacity(0.04)
                : Color(.secondarySystemBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    statusColor(for: item.status).opacity(isFocused ? 0.22 : 0.12),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }

    private var rowAccessibilityIdentifier: String {
        if isFocused {
            return "bottom-sheet-large-row-focused-\(item.id.uuidString)"
        }

        return "bottom-sheet-large-row-\(item.id.uuidString)"
    }

    private func tint(for action: BottomSheetLargeAction) -> Color {
        switch action {
        case .pause:
            return .orange
        case .resume:
            return .blue
        case .remove:
            return .secondary
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func ifLet<Value, Content: View>(
        _ value: Value?,
        transform: (Self, Value) -> Content
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

private struct LargeActionButton: View {
    let action: BottomSheetLargeAction
    let tint: Color
    let onTap: () -> Void

    var body: some View {
        Group {
            if action == .remove {
                Button(action.title) {
                    onTap()
                }
                .buttonStyle(BorderedButtonStyle())
            } else {
                Button(action.title) {
                    onTap()
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .tint(tint)
        .controlSize(.small)
    }
}

private struct StatusChip: View {
    let status: TimerStatus
    let label: String
    let size: StatusChipSize

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: size.dotSize, height: size.dotSize)

            Text(label)
                .font(size.font)
                .foregroundStyle(statusColor(for: status))
                .lineLimit(1)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(statusColor(for: status).opacity(0.12))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: true)
    }
}

private enum StatusChipSize {
    case compact
    case regular

    var dotSize: CGFloat {
        switch self {
        case .compact:
            return 6
        case .regular:
            return 7
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact:
            return 7
        case .regular:
            return 8
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return 4
        case .regular:
            return 5
        }
    }

    var font: Font {
        switch self {
        case .compact:
            return .caption2.weight(.semibold)
        case .regular:
            return .caption.weight(.semibold)
        }
    }
}

private enum BottomSheetIdentityPalette {
    static let slotCount = 6

    static func color(for slot: Int) -> Color {
        switch normalized(slot) {
        case 0:
            return Color(red: 0.14, green: 0.43, blue: 0.78)
        case 1:
            return Color(red: 0.00, green: 0.53, blue: 0.60)
        case 2:
            return Color(red: 0.74, green: 0.27, blue: 0.40)
        case 3:
            return Color(red: 0.43, green: 0.34, blue: 0.72)
        case 4:
            return Color(red: 0.55, green: 0.39, blue: 0.25)
        default:
            return Color(red: 0.10, green: 0.56, blue: 0.73)
        }
    }

    private static func normalized(_ slot: Int) -> Int {
        ((slot % slotCount) + slotCount) % slotCount
    }
}

private func identityTintColor(for cue: BottomSheetIdentityCue) -> Color {
    BottomSheetIdentityPalette.color(for: cue.tintSlot)
}

private func statusColor(for status: TimerStatus) -> Color {
    switch status {
    case .running:
        return .green
    case .paused:
        return .orange
    case .completed:
        return .gray
    }
}
