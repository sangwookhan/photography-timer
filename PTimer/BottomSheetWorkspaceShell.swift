import SwiftUI

struct BottomSheetWorkspaceShell: View {
    @ObservedObject var stateStore: BottomSheetWorkspaceStateStore
    let snapshot: BottomSheetWorkspaceSnapshot
    let onStopTimer: (UUID) -> Void
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
                    onCollapse: stateStore.collapse,
                    onStopTimer: onStopTimer,
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
}

@MainActor
final class BottomSheetWorkspaceStateStore: ObservableObject {
    private enum DragThreshold {
        static let compactExpand: CGFloat = 92
        static let expandedCollapse: CGFloat = 64
    }

    @Published private(set) var detent: BottomSheetDetent
    @Published private(set) var selectedTimerID: UUID?

    init(detent: BottomSheetDetent = .default) {
        self.detent = detent
    }

    var isExpanded: Bool {
        detent.isExpanded
    }

    func transition(to detent: BottomSheetDetent) {
        self.detent = detent
        if detent == .compact {
            selectedTimerID = nil
        }
    }

    func expand() {
        detent = .large
    }

    func expandAndFocusTimer(_ id: UUID) {
        selectedTimerID = id
        expand()
    }

    func focusTimer(_ id: UUID) {
        selectedTimerID = id
    }

    func collapse() {
        selectedTimerID = nil
        detent = .compact
    }

    func handleDragEnd(translation: CGFloat) {
        switch detent {
        case .compact:
            if translation <= -DragThreshold.compactExpand {
                expand()
            }
        case .large:
            if translation >= DragThreshold.expandedCollapse {
                collapse()
            }
        }
    }
}

struct BottomSheetLayoutMetrics {
    static func height(for detent: BottomSheetDetent) -> CGFloat {
        switch detent {
        case .compact:
            return 122
        case .large:
            return 560
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

enum BottomSheetExpandedAction: String, Equatable {
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

struct BottomSheetCompactItem: Identifiable, Equatable {
    let id: UUID
    let status: TimerStatus
    let primaryRemainingText: String
    let secondaryTotalText: String?
    let progress: Double
}

struct BottomSheetExpandedItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let statusLabel: String
    let status: TimerStatus
    let remainingText: String
    let targetText: String?
    let timeText: String?
    let basisText: String
    let progress: Double
    let actions: [BottomSheetExpandedAction]
}

struct TimerWorkspaceSection: Identifiable, Equatable {
    let title: String
    let items: [BottomSheetExpandedItem]

    var id: String { title }
}

struct BottomSheetWorkspaceSnapshot: Equatable {
    static let compactVisibleLimit = 3

    let totalCount: Int
    let runningCount: Int
    let stoppedCount: Int
    let completedCount: Int
    let compactItems: [BottomSheetCompactItem]
    let hiddenCompactItemCount: Int
    let firstHiddenCompactItemID: UUID?
    let sections: [TimerWorkspaceSection]

    static func make(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        targetContext: (RunningTimerItem) -> String?,
        timeContext: (RunningTimerItem) -> String?
    ) -> BottomSheetWorkspaceSnapshot {
        let orderedTimers = TimerWorkspaceOrdering.sort(timers)

        let compactItems = orderedTimers
            .prefix(Self.compactVisibleLimit)
            .map { timer in
                BottomSheetCompactItem(
                    id: timer.id,
                    status: timer.status,
                    primaryRemainingText: compactRemainingText(for: timer, formatRemaining: formatRemaining),
                    secondaryTotalText: compactTotalText(for: timer),
                    progress: progress(for: timer)
                )
            }

        let sections = makeSections(
            from: orderedTimers,
            formatRemaining: formatRemaining,
            targetContext: targetContext,
            timeContext: timeContext
        )

        return BottomSheetWorkspaceSnapshot(
            totalCount: timers.count,
            runningCount: timers.filter { $0.status == .running }.count,
            stoppedCount: timers.filter { $0.status == .stopped }.count,
            completedCount: timers.filter { $0.status == .completed }.count,
            compactItems: compactItems,
            hiddenCompactItemCount: max(0, orderedTimers.count - compactItems.count),
            firstHiddenCompactItemID: orderedTimers.dropFirst(compactItems.count).first?.id,
            sections: sections
        )
    }

    var summaryText: String {
        "Running \(runningCount) · Paused \(stoppedCount) · Done \(completedCount)"
    }

    var expandedSummaryText: String {
        if totalCount == 0 {
            return "No timers in workspace"
        }

        return summaryText
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
        targetContext: (RunningTimerItem) -> String?,
        timeContext: (RunningTimerItem) -> String?
    ) -> [TimerWorkspaceSection] {
        let activeTimers = timers.filter { $0.status != .completed }
        let completedTimers = timers.filter { $0.status == .completed }

        return [
            makeSection(
                title: "Active",
                timers: activeTimers,
                formatRemaining: formatRemaining,
                targetContext: targetContext,
                timeContext: timeContext
            ),
            makeSection(
                title: "Recently Completed",
                timers: completedTimers,
                formatRemaining: formatRemaining,
                targetContext: targetContext,
                timeContext: timeContext
            )
        ].compactMap { $0 }
    }

    private static func makeSection(
        title: String,
        timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        targetContext: (RunningTimerItem) -> String?,
        timeContext: (RunningTimerItem) -> String?
    ) -> TimerWorkspaceSection? {
        guard !timers.isEmpty else {
            return nil
        }

        return TimerWorkspaceSection(
            title: title,
            items: timers.map { timer in
                    BottomSheetExpandedItem(
                        id: timer.id,
                        title: timer.name,
                        statusLabel: visibleStatusLabel(for: timer.status),
                        status: timer.status,
                        remainingText: expandedRemainingText(for: timer, formatRemaining: formatRemaining),
                        targetText: targetContext(timer),
                        timeText: timeContext(timer),
                        basisText: timer.basisSummary,
                        progress: progress(for: timer),
                        actions: expandedActions(for: timer.status)
                    )
                }
        )
    }

    private static func progress(for timer: RunningTimerItem) -> Double {
        guard timer.duration > 0 else {
            return 0
        }

        return min(max(timer.elapsedTime / timer.duration, 0), 1)
    }

    private static func expandedActions(for status: TimerStatus) -> [BottomSheetExpandedAction] {
        switch status {
        case .running:
            return [.pause]
        case .stopped:
            return [.resume, .remove]
        case .completed:
            return [.remove]
        }
    }

    private static func compactRemainingText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String {
        switch timer.status {
        case .running, .stopped:
            return compactDurationText(timer.remainingTime)
        case .completed:
            return "0s"
        }
    }

    private static func compactTotalText(for timer: RunningTimerItem) -> String? {
        guard timer.duration > 0 else {
            return nil
        }

        return compactDurationText(timer.duration)
    }

    private static func expandedRemainingText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String {
        switch timer.status {
        case .running, .stopped:
            return formatRemaining(timer.remainingTime)
        case .completed:
            return "Completed"
        }
    }

    private static func visibleStatusLabel(for status: TimerStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .stopped:
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: BottomSheetLayoutMetrics.height(for: detent))
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
    let onCollapse: () -> Void
    let onStopTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: detent.isExpanded ? 10 : 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: detent == .compact ? 2 : 4) {
                    Text("Timer Workspace")
                        .font(detent == .compact ? .subheadline.weight(.semibold) : .headline)

                    if detent.isExpanded {
                        Text(snapshot.expandedSummaryText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()
            }

            Group {
                switch detent {
                case .compact:
                    CompactTimerMiniDockView(
                        snapshot: snapshot,
                        onItemTap: onCompactItemTap
                    )
                case .large:
                    ExpandedTimerWorkspaceView(
                        snapshot: snapshot,
                        focusedTimerID: focusedTimerID,
                        onStopTimer: onStopTimer,
                        onResumeTimer: onResumeTimer,
                        onRemoveTimer: onRemoveTimer,
                        onClearCompletedTimers: onClearCompletedTimers,
                        onCollapse: onCollapse
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, detent.isExpanded ? 14 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CompactTimerMiniDockView: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let onItemTap: (UUID) -> Void

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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(snapshot.compactItems) { item in
                            CompactTimerMiniCardView(
                                item: item,
                                onTap: {
                                    onItemTap(item.id)
                                }
                            )
                        }

                        if
                            let overflowText = snapshot.compactOverflowText,
                            let overflowTargetID = snapshot.firstHiddenCompactItemID
                        {
                            CompactOverflowMiniCard(
                                text: overflowText,
                                onTap: {
                                    onItemTap(overflowTargetID)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(for: item.status))
                        .scaleEffect(shouldAnimateRunningCue ? (isRunningPulseActive ? 1.08 : 0.92) : 1)
                        .opacity(shouldAnimateRunningCue ? (isRunningPulseActive ? 1 : 0.72) : 1)
                }
                .frame(width: 22, height: 22)

                Spacer(minLength: 0)

                if let totalText = item.secondaryTotalText {
                    Text(totalText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(item.primaryRemainingText)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            ProgressView(value: item.progress)
                .tint(statusColor(for: item.status))
                .scaleEffect(x: 1, y: 0.75, anchor: .center)
        }
        .padding(10)
        .frame(width: 96, height: 96, alignment: .topLeading)
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
        .animation(
            shouldAnimateRunningCue
                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                : .default,
            value: isRunningPulseActive
        )
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
        case .stopped:
            return "pause.fill"
        case .completed:
            return "checkmark"
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

            Text("more timers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 86, height: 96, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("bottom-sheet-compact-overflow-card")
        .onTapGesture(perform: onTap)
    }
}

private struct ExpandedTimerWorkspaceView: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let focusedTimerID: UUID?
    let onStopTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void
    let onCollapse: () -> Void
    @State private var hasAppliedInitialFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExpandedSummaryStrip(
                snapshot: snapshot,
                onClearCompletedTimers: onClearCompletedTimers
            )

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
                                        ExpandedTimerRowView(
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
                    .accessibilityIdentifier("bottom-sheet-expanded-workspace")
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

    private func handle(action: BottomSheetExpandedAction, for id: UUID) {
        switch action {
        case .pause:
            onStopTimer(id)
        case .resume:
            onResumeTimer(id)
        case .remove:
            onRemoveTimer(id)
        }
    }
}

private struct ExpandedSummaryStrip: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let onClearCompletedTimers: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            SummaryPill(title: "Running", value: "\(snapshot.runningCount)")
            SummaryPill(title: "Paused", value: "\(snapshot.stoppedCount)")
            SummaryPill(title: "Done", value: "\(snapshot.completedCount)")

            Spacer(minLength: 0)

            if snapshot.completedCount > 0 {
                Button("Clear") {
                    onClearCompletedTimers()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("bottom-sheet-clear-completed-button")
            }
        }
    }
}

private struct ExpandedTimerRowView: View {
    let item: BottomSheetExpandedItem
    let isFocused: Bool
    let onAction: (BottomSheetExpandedAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                StatusChip(status: item.status, label: item.statusLabel, size: .regular)
            }

            Text(item.remainingText)
                .font(.title3.weight(.bold))
                .monospacedDigit()

            if let targetText = item.targetText {
                Text(targetText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let timeText = item.timeText {
                Text(timeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(item.basisText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            ProgressView(value: item.progress)
                .tint(statusColor(for: item.status))

            if !item.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.actions, id: \.rawValue) { action in
                        ExpandedActionButton(
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
                ? statusColor(for: item.status).opacity(0.10)
                : Color(.secondarySystemBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    statusColor(for: item.status).opacity(isFocused ? 0.42 : 0.18),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }

    private var rowAccessibilityIdentifier: String {
        if isFocused {
            return "bottom-sheet-expanded-row-focused-\(item.id.uuidString)"
        }

        return "bottom-sheet-expanded-row-\(item.id.uuidString)"
    }

    private func tint(for action: BottomSheetExpandedAction) -> Color {
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

private struct ExpandedActionButton: View {
    let action: BottomSheetExpandedAction
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

private struct SummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private func statusColor(for status: TimerStatus) -> Color {
    switch status {
    case .running:
        return .green
    case .stopped:
        return .orange
    case .completed:
        return .gray
    }
}
