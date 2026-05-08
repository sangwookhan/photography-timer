import Combine
import SwiftUI

struct BottomSheetWorkspaceShell: View {
    @ObservedObject var stateStore: BottomSheetWorkspaceStateStore
    let snapshot: BottomSheetWorkspaceSnapshot
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onStartTimerAgain: (UUID) -> Void
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
                    onStartTimerAgain: onStartTimerAgain,
                    onClearCompletedTimers: onClearCompletedTimers
                )
            }
        )
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
    let onStartTimerAgain: (UUID) -> Void
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
                        onStartTimerAgain: onStartTimerAgain,
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
            } else if let filmText = item.identityFilmText {
                // Surface the film/digital descriptor inline so the
                // photographer can read identity from the compact
                // dock without expanding. Uses the same styling slot
                // the relative-time text occupies for completed
                // timers — only one of the two appears per card.
                Text(filmText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(compactTertiaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                    .padding(.horizontal, 2)
                    .accessibilityIdentifier("bottom-sheet-compact-mini-card-film-\(item.id.uuidString)")
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
    let onStartTimerAgain: (UUID) -> Void
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
        case .startAgain:
            onStartTimerAgain(id)
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
                VStack(alignment: .leading, spacing: 3) {
                    if let title = item.title {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("bottom-sheet-large-row-title-\(item.id.uuidString)")
                    }
                    if let subtitle = item.identitySubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("bottom-sheet-large-row-subtitle-\(item.id.uuidString)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.voiceOverLabel)
        .accessibilityValue(item.remainingText)
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
        case .resume, .startAgain:
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

enum BottomSheetIdentityPalette {
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
