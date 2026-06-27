// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import PTimerKit
import PTimerCore
import SwiftUI

/// PTIMER-126 redesign: the closed-state Timers UI is no longer a
/// custom bottom-sheet dock. Timers surface in two screen-level
/// places:
///
/// - When timers exist: `CompactTimerCardStripView` is rendered as a
///   screen-level strip above the bottom safe area. Tapping the
///   strip opens `FullScreenTimersWindow`.
/// - When no timers exist: nothing is rendered for the timer surface
///   at all (no dock, no handle, no title).
///
/// `FullScreenTimersWindow` replaces the former 70%-height bottom
/// sheet for the opened state. It owns the full management surface
/// and is presented via `.fullScreenCover`.
///
/// Types kept from the old shell, used by the new layout:
///
/// - `CompactTimerCardStripView` — screen-level closed-state strip.
/// - `BottomSheetLargeWorkspaceView` — list-rendering body of the
///   opened Timers window. Internal so `FullScreenTimersWindow` can
///   embed it.

/// Screen-level row of compact timer mini-cards. It is rendered
/// outside any dock or sheet container so cards are not clipped.
/// When no timers exist, this strip is not rendered.
struct CompactTimerCardStripView: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let onItemTap: (UUID) -> Void
    let onOverflowTap: () -> Void

    var body: some View {
        Group {
            if snapshot.compactItems.isEmpty {
                EmptyView()
                    .accessibilityIdentifier("main-screen-timer-strip-empty")
            } else {
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
                .frame(height: BottomSheetCompactDockMetrics.viewportHeight, alignment: .top)
                .accessibilityIdentifier("main-screen-timer-strip")
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
                // card without expanding. Uses the same styling slot
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
        case .canceled:
            return "xmark"
        }
    }

    private var sixtySecondFillColor: Color {
        switch item.status {
        case .completed, .canceled:
            return statusColor(for: item.status).opacity(0.72)
        case .paused:
            return Color.orange.opacity(0.88)
        case .running:
            return Color.red.opacity(0.92)
        }
    }

    private var sixtySecondTrackColor: Color {
        switch item.status {
        case .completed, .canceled:
            return statusColor(for: item.status).opacity(0.16)
        case .paused:
            return Color.orange.opacity(0.16)
        case .running:
            return Color.red.opacity(0.18)
        }
    }

    private var sixtyMinuteFillColor: Color {
        switch item.status {
        case .completed, .canceled:
            return statusColor(for: item.status).opacity(0.56)
        case .paused:
            return Color.yellow.opacity(0.72)
        case .running:
            return Color.orange.opacity(0.74)
        }
    }

    private var sixtyMinuteTrackColor: Color {
        switch item.status {
        case .completed, .canceled:
            return statusColor(for: item.status).opacity(0.12)
        case .paused:
            return Color.yellow.opacity(0.11)
        case .running:
            return Color.orange.opacity(0.12)
        }
    }

    private var originalScaleFillColor: Color {
        switch item.status {
        case .completed, .canceled:
            return statusColor(for: item.status).opacity(0.38)
        case .paused:
            return Color.mint.opacity(0.48)
        case .running:
            return Color.teal.opacity(0.46)
        }
    }

    private var originalScaleTrackColor: Color {
        switch item.status {
        case .completed, .canceled:
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

/// Body of the opened Timers workspace — active + completed sections,
/// per-row actions, and "clear completed" affordance. Embedded in
/// `FullScreenTimersWindow` for the opened state. Kept internal so
/// the screen layer can compose the navigation chrome around it.
struct BottomSheetLargeWorkspaceView: View {
    /// Stable scroll-target identifier for the Active section
    /// header. Used by `applyFocusIfNeeded` when the photographer
    /// tapped an active compact card — scrolling the row by id
    /// would push the `Active` title above the viewport.
    static let activeSectionScrollID = "timers-section-active"

    /// Stable scroll-target identifier for the Recently Completed
    /// section header. Used so the workspace can scroll the section
    /// header (and the `Clear` button) into view when the
    /// photographer drilled in from a completed compact card —
    /// scrolling the first completed row by id would push the
    /// header above the viewport.
    static let recentlyCompletedSectionScrollID = "timers-section-recently-completed"

    let snapshot: BottomSheetWorkspaceSnapshot
    let openFocus: TimersOpenFocus
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onCancelTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onCloneTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void
    let onCollapse: () -> Void
    @State private var hasAppliedInitialFocus = false
    /// Pending Clone/Cancel/Remove action awaiting confirmation; nil when
    /// no confirmation dialog is shown.
    @State private var pendingConfirm: PendingTimerConfirm?
    /// Whether the "Clear completed timers?" confirmation is shown.
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The `Clear` affordance used to live in a top-level
            // summary strip. That strip was conditionally rendered,
            // which caused the Active section to shift when the
            // first timer completed (PTIMER-126). The button now
            // lives in the Recently Completed section header so
            // Active section position is independent of `Clear`.
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
                                    sectionHeader(for: section)

                                    ForEach(section.items) { item in
                                        LargeWorkspaceTimerRowView(
                                            item: item,
                                            isFocused: item.id == openFocus.activeTimerID,
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
                        .onChange(of: openFocus) { _, _ in
                            applyFocusIfNeeded(using: proxy, animated: true)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("bottom-sheet-large-workspace")
                }
            }
        }
        .confirmationDialog(
            pendingConfirm.map { confirmTitle(for: $0.action) } ?? "",
            isPresented: Binding(
                get: { pendingConfirm != nil },
                set: { presented in if !presented { pendingConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirm
        ) { pending in
            Button(confirmButtonTitle(for: pending.action), role: confirmRole(for: pending.action)) {
                execute(pending)
                pendingConfirm = nil
            }
        } message: { pending in
            Text(confirmMessage(for: pending.action))
        }
        .confirmationDialog(
            "Clear completed timers?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                onClearCompletedTimers()
            }
        } message: {
            Text("Completed timer records will be removed. Canceled timers will be kept.")
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: TimerWorkspaceSection) -> some View {
        let header = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if section.isCompletedSection {
                Button("Clear") {
                    showClearConfirm = true
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityIdentifier("bottom-sheet-clear-completed-button")
            }
        }

        // Tag each section header with a stable scroll id so
        // `applyFocusIfNeeded` can land on the header (and not on a
        // row) when the photographer drilled in from a compact
        // card. Both Active and Recently Completed taps preserve
        // their section title this way.
        if section.isCompletedSection {
            header.id(Self.recentlyCompletedSectionScrollID)
        } else {
            header.id(Self.activeSectionScrollID)
        }
    }

    private func applyFocusIfNeeded(using proxy: ScrollViewProxy, animated: Bool) {
        let scroll: (() -> Void)?
        switch openFocus {
        case .none:
            scroll = nil
        case .activeSection:
            // Always scroll to the Active section header — the
            // optional highlighted timer id is *not* used as a
            // scroll anchor (which would push the section title
            // above the viewport).
            scroll = {
                proxy.scrollTo(Self.activeSectionScrollID, anchor: .top)
            }
        case .recentlyCompletedSection:
            // Land on the section header so the `Recently Completed`
            // title and `Clear` button stay visible after opening.
            scroll = {
                proxy.scrollTo(Self.recentlyCompletedSectionScrollID, anchor: .top)
            }
        }

        guard let scroll else {
            return
        }

        if !animated && hasAppliedInitialFocus {
            return
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
        case .clone, .cancel, .remove:
            // Clone, Cancel, and Remove confirm before running (parity with
            // Android). Pause/Resume stay immediate.
            pendingConfirm = PendingTimerConfirm(action: action, timerID: id)
        }
    }

    private func execute(_ pending: PendingTimerConfirm) {
        switch pending.action {
        case .clone:
            onCloneTimer(pending.timerID)
        case .cancel:
            onCancelTimer(pending.timerID)
        case .remove:
            onRemoveTimer(pending.timerID)
        case .pause, .resume:
            break
        }
    }

    private func confirmTitle(for action: BottomSheetLargeAction) -> String {
        switch action {
        case .clone:
            return "Clone timer?"
        case .cancel:
            return "Cancel timer?"
        case .remove:
            return "Remove timer?"
        case .pause, .resume:
            return ""
        }
    }

    private func confirmButtonTitle(for action: BottomSheetLargeAction) -> String {
        switch action {
        case .clone:
            return "Clone"
        case .cancel:
            return "Cancel Timer"
        case .remove:
            return "Remove"
        case .pause, .resume:
            return ""
        }
    }

    private func confirmRole(for action: BottomSheetLargeAction) -> ButtonRole? {
        switch action {
        case .cancel, .remove:
            return .destructive
        case .clone, .pause, .resume:
            return nil
        }
    }

    private func confirmMessage(for action: BottomSheetLargeAction) -> String {
        switch action {
        case .clone:
            return "Start a new timer with the same settings. This timer will stay unchanged."
        case .cancel:
            return "This timer will be marked as canceled and moved to history."
        case .remove:
            return "This timer record will be removed."
        case .pause, .resume:
            return ""
        }
    }
}

/// A pending Clone/Cancel/Remove action awaiting confirmation in the
/// workspace shell.
private struct PendingTimerConfirm: Identifiable {
    let action: BottomSheetLargeAction
    let timerID: UUID
    var id: UUID { timerID }
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

                    // Stable per-timer sequence number, placed in the
                    // existing trailing space beside the identity badge so
                    // repeated same-camera/film timers stay distinguishable
                    // without adding a row.
                    Text(item.sequenceNumberText)
                        .font(.caption.monospacedDigit())
                        // Neutral gray, one step up from the faded metadata
                        // (.tertiary) so the number is readable at a glance
                        // while staying secondary to the title and badge.
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Timer \(item.sequenceNumberText)")

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
        case .resume, .clone:
            return .blue
        case .cancel, .remove:
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
            if action == .remove || action == .cancel {
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
        ((slot % BottomSheetIdentityCue.tintSlotCount) + BottomSheetIdentityCue.tintSlotCount) % BottomSheetIdentityCue.tintSlotCount
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
    case .completed, .canceled:
        return .gray
    }
}

/// Full-screen Timers management window (PTIMER-126). Replaces the
/// former 70%-height bottom sheet for the opened state. Wraps the
/// existing list-rendering body in a `NavigationStack` with a title
/// and an explicit close button — opening Timers no longer takes a
/// fractional slice of the screen.
struct FullScreenTimersWindow: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let openFocus: TimersOpenFocus
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onCancelTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void
    let onCloneTimer: (UUID) -> Void
    let onClearCompletedTimers: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            BottomSheetLargeWorkspaceView(
                snapshot: snapshot,
                openFocus: openFocus,
                onPauseTimer: onPauseTimer,
                onResumeTimer: onResumeTimer,
                onCancelTimer: onCancelTimer,
                onRemoveTimer: onRemoveTimer,
                onCloneTimer: onCloneTimer,
                onClearCompletedTimers: onClearCompletedTimers,
                onCollapse: onClose
            )
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(BottomSheetWorkspaceCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Close timers"))
                    .accessibilityIdentifier("full-screen-timers-close-button")
                }
            }
        }
        .accessibilityIdentifier("full-screen-timers-window")
    }
}
