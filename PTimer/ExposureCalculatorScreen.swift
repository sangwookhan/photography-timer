import SwiftUI

enum FloatingTimerDockDisplayMode: Equatable {
    case collapsed
    case expanded

    static func resolve(hasVisibleTimers: Bool) -> FloatingTimerDockDisplayMode {
        hasVisibleTimers ? .expanded : .collapsed
    }
}

struct ExposureWorkspaceScreen: View {
    @StateObject private var viewModel: ExposureCalculatorViewModel
    @State private var selectedTimerId: UUID?

    init(
        viewModel: ExposureCalculatorViewModel? = nil,
        timerRuntimeStore: TimerRuntimeStore? = nil
    ) {
        let resolvedViewModel: ExposureCalculatorViewModel

        if let timerRuntimeStore {
            resolvedViewModel = viewModel ?? ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: timerRuntimeStore
            )
        } else if let viewModel {
            resolvedViewModel = viewModel
        } else {
            resolvedViewModel = ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerRuntimeStore: TimerRuntimeStore()
            )
        }

        _viewModel = StateObject(wrappedValue: resolvedViewModel)

        assertNoKoreanUIStrings([
            "Exposure",
            "Show Advanced Options",
            "View All",
            "Add Timer",
            "Timers"
        ])
    }

    var body: some View {
        GeometryReader { proxy in
            let visibleTimers = viewModel.timerRuntimeStore.visibleTimers
            let dockDisplayMode = FloatingTimerDockDisplayMode.resolve(
                hasVisibleTimers: !visibleTimers.isEmpty
            )
            let narrowPortraitLayout = proxy.size.width < 430 && proxy.size.height > proxy.size.width
            let workspaceSpacing: CGFloat = narrowPortraitLayout ? 10 : 16
            let workspacePadding: CGFloat = narrowPortraitLayout ? 10 : (proxy.size.width < 430 ? 12 : 16)
            let selectedTimer = selectedTimerId.flatMap(viewModel.timerRuntimeStore.timer(id:))

            ZStack {
                HStack(alignment: .top, spacing: workspaceSpacing) {
                    ExposureCalculatorPanel(
                        viewModel: viewModel,
                        onAddTimer: viewModel.startTimer,
                        usesStableCompactLayout: narrowPortraitLayout
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("exposure.workspace.calculatorPanel")

                    FloatingTimerDock(
                        timers: visibleTimers,
                        displayMode: dockDisplayMode,
                        formatTimeDisplay: viewModel.formatTimeDisplay,
                        onOpenTimerDetail: { selectedTimerId = $0 },
                        onViewAll: nil
                    )
                    .frame(
                        width: dockWidth(
                            for: proxy.size.width,
                            displayMode: dockDisplayMode,
                            isNarrowPortrait: narrowPortraitLayout
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityIdentifier("exposure.workspace.dock")
                }
                .padding(workspacePadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .background(Color(.systemGroupedBackground))
                .accessibilityIdentifier("exposure.workspace.root")

                if let selectedTimer {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .accessibilityIdentifier("exposure.workspace.timerDetail.scrim")
                        .onTapGesture {
                            selectedTimerId = nil
                        }

                    TimerDetailOverlay(
                        timer: selectedTimer,
                        formatTimeDisplay: viewModel.formatTimeDisplay,
                        formatClockTime: viewModel.formatClockTime,
                        formatDateTime: viewModel.formatDateTime,
                        timerTargetContext: viewModel.timerTargetContext(for:),
                        timerTimeContext: viewModel.timerTimeContext(for:),
                        onPause: { viewModel.stopTimer(id: selectedTimer.id) },
                        onResume: { viewModel.resumeTimer(id: selectedTimer.id) },
                        onStop: { viewModel.completeTimer(id: selectedTimer.id) },
                        onDelete: {
                            viewModel.removeTimer(id: selectedTimer.id)
                            selectedTimerId = nil
                        },
                        onDismiss: {
                            selectedTimerId = nil
                        }
                    )
                    .frame(maxWidth: min(proxy.size.width - 32, 360))
                    .padding(.horizontal, 16)
                }
            }
            .onChange(of: visibleTimers.map(\.id)) { _, ids in
                if let selectedTimerId, !ids.contains(selectedTimerId) {
                    self.selectedTimerId = nil
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func dockWidth(
        for availableWidth: CGFloat,
        displayMode: FloatingTimerDockDisplayMode,
        isNarrowPortrait: Bool
    ) -> CGFloat {
        switch displayMode {
        case .collapsed:
            if isNarrowPortrait {
                return 86
            }
            return 84
        case .expanded:
            if isNarrowPortrait {
                return 86
            }

            if availableWidth < 390 {
                return 130
            }

            if availableWidth < 430 {
                return 144
            }

            if availableWidth < 520 {
                return 160
            }

            return min(max(220, availableWidth * 0.3), 280)
        }
    }
}

struct ExposureCalculatorScreen: View {
    var body: some View {
        ExposureWorkspaceScreen()
    }
}

struct ExposureCalculatorPanel: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let onAddTimer: () -> Void
    let usesStableCompactLayout: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = ExposureCalculatorPanelMetrics(
                containerHeight: proxy.size.height,
                containerWidth: proxy.size.width,
                prefersCompactLayout: usesStableCompactLayout
            )

            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                HeaderView(metrics: metrics)
                VariableSectionView(
                    baseShutter: $viewModel.baseShutter,
                    ndStop: $viewModel.ndStop,
                    shutterSpeeds: ExposureCalculatorViewModel.shutterSpeeds,
                    formatShutter: viewModel.formatShutter,
                    metrics: metrics
                )
                ResultSectionView(
                    calculationResult: viewModel.calculationResult,
                    ndStop: viewModel.ndStop,
                    formatTimeDisplay: viewModel.formatTimeDisplay,
                    metrics: metrics
                )
                TimerActionView(
                    canStartTimer: viewModel.canStartTimer,
                    onStart: onAddTimer,
                    metrics: metrics
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct FloatingTimerDock: View {
    let timers: [RunningTimerItem]
    let displayMode: FloatingTimerDockDisplayMode
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let onOpenTimerDetail: (UUID) -> Void
    let onViewAll: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            dockBody(for: proxy.size.width)
        }
    }

    @ViewBuilder
    private func dockBody(for dockWidth: CGFloat) -> some View {
        let isNarrow = dockWidth < 120

        Group {
            switch displayMode {
            case .collapsed:
                collapsedDock
            case .expanded:
                expandedDock(isCompact: dockWidth < 180, isNarrow: isNarrow)
            }
        }
        .padding(isNarrow ? 8 : 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var collapsedDock: some View {
        VStack(spacing: 12) {
            Text("T(0)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Image(systemName: "plus")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)

            Text("Dock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(-90))
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("exposure.workspace.dock.collapsed")
    }

    private func expandedDock(isCompact: Bool, isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: isNarrow ? 7 : 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isNarrow {
                    Text("\(timers.count)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()

                    Text("Timers")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Timers \(timers.count)")
                        .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                if !isNarrow {
                    if let onViewAll {
                        Button("View All", action: onViewAll)
                            .font((isCompact ? Font.caption2 : Font.footnote).weight(.semibold))
                    } else {
                        Text("View All")
                            .font((isCompact ? Font.caption2 : Font.footnote).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("exposure.workspace.dock.viewAllPlaceholder")
                    }
                }
            }

            ScrollView {
                Group {
                    if isNarrow {
                        narrowPortraitDockList
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(timers) { timer in
                                FloatingTimerDockTile(
                                    timer: timer,
                                    timeDisplay: formatTimeDisplay(timerPrimaryDuration(for: timer)),
                                    targetContext: nil,
                                    isCompact: isCompact,
                                    isNarrow: isNarrow,
                                    onOpenTimerDetail: { onOpenTimerDetail(timer.id) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityIdentifier("exposure.workspace.dock.scrollContent")
            }
            .accessibilityIdentifier("exposure.workspace.dock.scrollView")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("exposure.workspace.dock.expanded")
    }

    private var narrowPortraitDockList: some View {
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(timers.enumerated()), id: \.element.id) { index, timer in
                UltraCompactTimerRow(
                    timer: timer,
                    timeDisplay: DockCompactTimeFormatter.format(timerPrimaryDuration(for: timer)),
                    onOpenTimerDetail: { onOpenTimerDetail(timer.id) }
                )
                .accessibilityIdentifier("exposure.workspace.dock.narrowRow.\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("exposure.workspace.dock.narrowList")
    }

    private func timerPrimaryDuration(for timer: RunningTimerItem) -> TimeInterval {
        switch timer.status {
        case .running, .stopped:
            return timer.remainingTime
        case .completed:
            return timer.duration
        }
    }

}

private struct FloatingTimerDockTile: View {
    let timer: RunningTimerItem
    let timeDisplay: TimeDisplay
    let targetContext: String?
    let isCompact: Bool
    let isNarrow: Bool
    let onOpenTimerDetail: () -> Void

    var body: some View {
        Button(action: onOpenTimerDetail) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactTitleText)
                            .font((isCompact ? Font.caption : Font.subheadline).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityIdentifier("exposure.workspace.dock.primaryTitle")

                        Text(statusText)
                            .font((isCompact ? Font.caption2 : Font.caption).weight(.medium))
                            .foregroundStyle(statusColor)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.left.circle.fill")
                        .font(isCompact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                DurationDisplayBlock(
                    primaryText: timeDisplay.primary,
                    secondaryText: (isCompact || isNarrow) ? nil : timeDisplay.secondary,
                    primaryColor: statusColor == .gray ? .secondary : .primary,
                    primaryFont: .system(size: isNarrow ? 16 : (isCompact ? 20 : 24), weight: .bold, design: .rounded),
                    secondaryFont: isCompact ? .caption : .footnote
                )

                if let targetContext {
                    Text(targetContext)
                        .font((isCompact ? Font.caption2 : Font.footnote).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if !isCompact {
                    Text(timer.basisSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isCompact ? 10 : 14)
            .background(tileBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(statusColor.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exposure.workspace.dock.tile.\(timer.id.uuidString)")
    }

    private var statusText: String {
        switch timer.status {
        case .running:
            return "Running"
        case .stopped:
            return "Paused"
        case .completed:
            return "Completed"
        }
    }

    private var compactTitleText: String {
        guard isNarrow else {
            return timer.name
        }

        switch timer.status {
        case .running:
            return "Running"
        case .stopped:
            return "Paused"
        case .completed:
            return "Done"
        }
    }

    private var statusColor: Color {
        switch timer.status {
        case .running:
            return .green
        case .stopped:
            return .orange
        case .completed:
            return .gray
        }
    }

    private var tileBackgroundColor: Color {
        switch timer.status {
        case .running:
            return Color(.secondarySystemBackground)
        case .stopped:
            return Color(.systemGray6)
        case .completed:
            return Color(.tertiarySystemBackground)
        }
    }
}

struct UltraCompactTimerRow: View {
    let timer: RunningTimerItem
    let timeDisplay: DockCompactTimeDisplay
    let onOpenTimerDetail: () -> Void

    private static let rowHeight: CGFloat = 44

    var body: some View {
        Button(action: onOpenTimerDetail) {
            rowContainer
        }
        .buttonStyle(.plain)
    }

    private var rowContainer: some View {
        let isCompleted = timer.status == .completed

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)

            Rectangle()
                .fill(statusColor.opacity(isCompleted ? 0.28 : 0.72))
                .frame(height: isCompleted ? 2 : 2.5)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("exposure.workspace.dock.stateAccent")

            HStack(spacing: 0) {
                CompactDockTimeBlock(timeDisplay: timeDisplay, isCompleted: isCompleted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("exposure.workspace.dock.compactTime")

                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 7)
            .padding(.top, 5)
            .padding(.bottom, 4)
        }
        .frame(height: Self.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(statusColor.opacity(isCompleted ? 0.05 : 0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fullStatusText) \(timeDisplay.accessibilityText)")
        .accessibilityIdentifier("exposure.workspace.dock.cell.\(statusIdentifier)")
    }

    private var statusIdentifier: String {
        switch timer.status {
        case .running:
            return "running"
        case .stopped:
            return "paused"
        case .completed:
            return "completed"
        }
    }

    private var fullStatusText: String {
        switch timer.status {
        case .running:
            return "Running"
        case .stopped:
            return "Paused"
        case .completed:
            return "Completed"
        }
    }

    private var statusColor: Color {
        switch timer.status {
        case .running:
            return Color.green
        case .stopped:
            return Color.orange
        case .completed:
            return Color.gray
        }
    }

    private var backgroundColor: Color {
        switch timer.status {
        case .running:
            return Color.green.opacity(0.09)
        case .stopped:
            return Color.orange.opacity(0.12)
        case .completed:
            return Color.gray.opacity(0.04)
        }
    }
}

private struct TimerDetailOverlay: View {
    let timer: RunningTimerItem
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatClockTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let timerTargetContext: (RunningTimerItem) -> String?
    let timerTimeContext: (RunningTimerItem) -> String?
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timer.name)
                        .font(.title3.weight(.bold))
                        .accessibilityIdentifier("exposure.workspace.timerDetail.title")

                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("exposure.workspace.timerDetail.status")
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("exposure.workspace.timerDetail.dismiss")
            }

            VStack(alignment: .leading, spacing: 12) {
                detailRow(label: "Remaining", value: preciseRemainingTime)
                    .accessibilityIdentifier("exposure.workspace.timerDetail.remaining")
                detailRow(label: "Total", value: preciseTotalTime)
                detailRow(label: "Elapsed", value: preciseElapsedTime)

                if let targetContext = timerTargetContext(timer) {
                    detailRow(label: "Target", value: targetContext)
                }

                detailRow(label: "Summary", value: timer.basisSummary)

                detailRow(label: "Started", value: formatClockTime(timer.startDate))

                if let timeContext = timerTimeContext(timer) {
                    detailRow(label: "Context", value: timeContext)
                }

                if let endDate = timer.endDate {
                    detailRow(label: timer.status == .completed ? "Completed" : "Ends", value: formatDateTime(endDate))
                }

                if let pausedAt = timer.pausedAt {
                    detailRow(label: "Paused", value: formatDateTime(pausedAt))
                }
            }

            HStack(spacing: 10) {
                if timer.status == .running {
                    actionButton("Pause", style: .borderedProminent, action: onPause)
                        .accessibilityIdentifier("exposure.workspace.timerDetail.action.pause")
                }

                if timer.status == .stopped {
                    actionButton("Resume", style: .borderedProminent, action: onResume)
                        .accessibilityIdentifier("exposure.workspace.timerDetail.action.resume")
                }

                if timer.status != .completed {
                    actionButton("Stop", style: .bordered, action: onStop)
                        .accessibilityIdentifier("exposure.workspace.timerDetail.action.stop")
                }

                actionButton("Delete", style: .bordered, role: .destructive, action: onDelete)
                    .accessibilityIdentifier("exposure.workspace.timerDetail.action.delete")
            }

            HStack {
                Spacer()
                Button("Close", action: onDismiss)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exposure.workspace.timerDetail.close")
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        .accessibilityIdentifier("exposure.workspace.timerDetail.overlay")
    }

    private var statusText: String {
        switch timer.status {
        case .running:
            return "Running"
        case .stopped:
            return "Paused"
        case .completed:
            return "Completed"
        }
    }

    private var statusColor: Color {
        switch timer.status {
        case .running:
            return .green
        case .stopped:
            return .orange
        case .completed:
            return .secondary
        }
    }

    private var preciseRemainingTime: String {
        formatPreciseDuration(timer.remainingTime)
    }

    private var preciseTotalTime: String {
        formatPreciseDuration(timer.duration)
    }

    private var preciseElapsedTime: String {
        formatPreciseDuration(timer.elapsedTime)
    }

    private func formatPreciseDuration(_ seconds: TimeInterval) -> String {
        let display = formatTimeDisplay(seconds)
        if display.secondary.isEmpty {
            return display.primary
        }
        return "\(display.primary) \(display.secondary)"
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum OverlayActionStyle {
        case bordered
        case borderedProminent
    }

    private func actionButton(
        _ title: String,
        style: OverlayActionStyle,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(title, role: role, action: action)

        switch style {
        case .bordered:
            return AnyView(button.buttonStyle(.bordered))
        case .borderedProminent:
            return AnyView(button.buttonStyle(.borderedProminent))
        }
    }
}

private struct CompactDockTimeBlock: View {
    let timeDisplay: DockCompactTimeDisplay
    var isCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(timeDisplay.primaryText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCompleted ? Color.secondary : Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(timeDisplay.secondaryText.isEmpty ? "00" : timeDisplay.secondaryText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isCompleted ? Color.secondary.opacity(0.62) : Color.secondary.opacity(0.88))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(timeDisplay.secondaryText.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
    }
}

struct HeaderView: View {
    let metrics: ExposureCalculatorPanelMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            Text("Exposure")
                .font(metrics.titleFont)

            HStack(alignment: .top, spacing: metrics.inlineSpacing) {
                VStack(alignment: .leading, spacing: metrics.compactHeaderSpacing) {
                    Picker("Mode", selection: .constant(0)) {
                        Text("Digital").tag(0)
                        Text("Film").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .disabled(true)

                    Text("Film mode: placeholder")
                        .font(metrics.captionFont)
                        .foregroundStyle(.secondary)
                }

                Button {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(metrics.controlIconFont)
                        .frame(width: metrics.compactButtonSize, height: metrics.compactButtonSize)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .sectionCardStyle(metrics: metrics)
    }
}

struct VariableSectionView: View {
    @Binding var baseShutter: Double
    @Binding var ndStop: Int
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String
    let metrics: ExposureCalculatorPanelMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            Text("Variable Controls")
                .font(.headline)

            VStack(spacing: metrics.contentSpacing) {
                if metrics.stackControlsVertically {
                    VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                        ShutterSelectionRow(
                            baseShutter: $baseShutter,
                            shutterSpeeds: shutterSpeeds,
                            formatShutter: formatShutter,
                            metrics: metrics
                        )

                        NDStopSelectionRow(ndStop: $ndStop, metrics: metrics)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ShutterSelectionRow(
                            baseShutter: $baseShutter,
                            shutterSpeeds: shutterSpeeds,
                            formatShutter: formatShutter,
                            metrics: metrics
                        )

                        NDStopSelectionRow(ndStop: $ndStop, metrics: metrics)
                    }
                }

                Divider()

                HStack(spacing: metrics.inlineSpacing) {
                    Text(metrics.advancedTitle)
                        .font(metrics.advancedTitleFont)
                        .lineLimit(1)

                    Spacer()

                    if metrics.showsAdvancedTrailingText {
                        Label(metrics.advancedTrailingLabel, systemImage: "chevron.down")
                            .font(metrics.advancedTrailingFont)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(metrics.advancedTrailingFont.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(metrics.advancedPlaceholderText)
                    .font(metrics.captionFont)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(metrics.advancedPlaceholderPadding)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .lineLimit(metrics.showsFullAdvancedPlaceholder ? nil : 1)
            }
        }
        .sectionCardStyle(metrics: metrics)
    }
}

struct ResultSectionView: View {
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let ndStop: Int
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let metrics: ExposureCalculatorPanelMetrics
    private let calculator = ExposureCalculator()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            Text("Result Set")
                .font(.headline)

            VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Shutter")
                        .font(metrics.captionFont.weight(.medium))
                        .foregroundStyle(.secondary)

                    if case .success(let result) = calculationResult {
                        let display = formatTimeDisplay(result.resultShutterSeconds)
                        DurationDisplayBlock(
                            primaryText: display.primary,
                            secondaryText: display.secondary,
                            primaryColor: .primary,
                            primaryFont: metrics.resultFont,
                            secondaryFont: metrics.captionFont
                        )
                    } else {
                        Text(primaryResultText)
                            .font(.title3.weight(.semibold))
                    }
                }

                Divider()

                HStack(spacing: metrics.inlineSpacing) {
                    CompactInfoPill(label: "Base", value: baseShutterText)
                    CompactInfoPill(label: "ND", value: ndText)
                    CompactInfoPill(label: "Status", value: statusText)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(metrics.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(metrics.innerPadding)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle(metrics: metrics)
    }

    private var primaryResultText: String {
        switch calculationResult {
        case .success(let result):
            return formatTimeDisplay(result.resultShutterSeconds).primary
        case .failure:
            return "Result unavailable"
        }
    }

    private var baseShutterText: String {
        switch calculationResult {
        case .success(let result):
            return calculator.formatShutter(result.baseShutterSeconds)
        case .failure:
            return "-"
        }
    }

    private var ndText: String {
        ndStop == 1 ? "1 stop" : "\(ndStop) stops"
    }

    private var statusText: String {
        switch calculationResult {
        case .success:
            return "Live update"
        case .failure:
            return "Needs valid input"
        }
    }

    private var validationMessage: String? {
        switch calculationResult {
        case .success:
            return nil
        case .failure(let error):
            return error.errorDescription
        }
    }
}

private struct NDStopSelectionRow: View {
    @Binding var ndStop: Int
    let metrics: ExposureCalculatorPanelMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text("ND")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(ndStop == 1 ? "1 stop" : "\(ndStop) stops")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Picker("ND", selection: $ndStop) {
                ForEach(0...30, id: \.self) { stop in
                    Text(stop == 1 ? "1 stop" : "\(stop) stops").tag(stop)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.pickerHeight)
            .clipped()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Stop-based ND selection")
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ShutterSelectionRow: View {
    @Binding var baseShutter: Double
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String
    let metrics: ExposureCalculatorPanelMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text("Shutter")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(formatShutter(baseShutter))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Picker("Shutter", selection: $baseShutter) {
                ForEach(shutterSpeeds, id: \.self) { speed in
                    Text(formatShutter(speed)).tag(speed)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.pickerHeight)
            .clipped()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Full-stop shutter selection")
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct TimerActionView: View {
    let canStartTimer: Bool
    let onStart: () -> Void
    let metrics: ExposureCalculatorPanelMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            Text("Timer Action")
                .font(.headline)

            Button("Add Timer") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!canStartTimer)
            .controlSize(metrics.isUltraCompact ? .small : .regular)
            .accessibilityIdentifier("exposure.workspace.timerAction.button")
        }
        .sectionCardStyle(metrics: metrics)
        .accessibilityIdentifier("exposure.workspace.timerAction")
    }
}

private struct DurationDisplayBlock: View {
    let primaryText: String
    let secondaryText: String?
    let primaryColor: Color
    let primaryFont: Font
    let secondaryFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Text(primaryText)
                    .font(primaryFont)
                    .foregroundStyle(primaryColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
            }

            if let secondaryText {
                HStack {
                    Spacer()
                    Spacer()
                    Text(secondaryText)
                        .font(secondaryFont)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactInfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func sectionCardStyle(metrics: ExposureCalculatorPanelMetrics) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.cardPadding)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
    }
}

struct ExposureCalculatorPanelMetrics {
    let sectionSpacing: CGFloat
    let contentSpacing: CGFloat
    let cardPadding: CGFloat
    let innerPadding: CGFloat
    let pickerHeight: CGFloat
    let titleFont: Font
    let resultFont: Font
    let captionFont: Font
    let stackControlsVertically: Bool
    let inlineSpacing: CGFloat
    let compactButtonSize: CGFloat
    let compactHeaderSpacing: CGFloat
    let controlIconFont: Font
    let advancedTitle: String
    let advancedTitleFont: Font
    let advancedTrailingLabel: String
    let advancedTrailingFont: Font
    let advancedPlaceholderText: String
    let advancedPlaceholderPadding: CGFloat
    let showsAdvancedTrailingText: Bool
    let showsFullAdvancedPlaceholder: Bool
    let isUltraCompact: Bool

    init(
        containerHeight: CGFloat,
        containerWidth: CGFloat,
        prefersCompactLayout: Bool
    ) {
        let compactLayout = prefersCompactLayout || containerHeight < 760 || containerWidth < 250
        isUltraCompact = prefersCompactLayout || containerHeight < 860 || containerWidth < 270
        stackControlsVertically = prefersCompactLayout ? false : containerWidth < 250

        if isUltraCompact {
            sectionSpacing = 10
            contentSpacing = 8
            cardPadding = 10
            innerPadding = 10
            inlineSpacing = 8
            compactButtonSize = 32
            compactHeaderSpacing = 8
            pickerHeight = 72
            titleFont = .title2.weight(.bold)
            resultFont = .system(size: 18, weight: .bold, design: .rounded)
            captionFont = .caption2
            controlIconFont = .subheadline.weight(.semibold)
            advancedTitle = "Advanced"
            advancedTitleFont = .subheadline.weight(.semibold)
            advancedTrailingLabel = "Aperture / ISO"
            advancedTrailingFont = .caption
            advancedPlaceholderText = "Aperture and ISO placeholders."
            advancedPlaceholderPadding = 8
            showsAdvancedTrailingText = false
            showsFullAdvancedPlaceholder = false
        } else if compactLayout {
            sectionSpacing = 12
            contentSpacing = 10
            cardPadding = 12
            innerPadding = 12
            inlineSpacing = 10
            compactButtonSize = 36
            compactHeaderSpacing = 10
            pickerHeight = stackControlsVertically ? 82 : 96
            titleFont = .title.weight(.bold)
            resultFont = .system(size: 24, weight: .bold, design: .rounded)
            captionFont = .caption
            controlIconFont = .headline
            advancedTitle = "Show Advanced Options"
            advancedTitleFont = .subheadline.weight(.semibold)
            advancedTrailingLabel = "Aperture / ISO"
            advancedTrailingFont = .footnote
            advancedPlaceholderText = "Aperture and ISO placeholders will expand here later."
            advancedPlaceholderPadding = innerPadding
            showsAdvancedTrailingText = true
            showsFullAdvancedPlaceholder = true
        } else {
            sectionSpacing = 16
            contentSpacing = 14
            cardPadding = 16
            innerPadding = 16
            inlineSpacing = 12
            compactButtonSize = 36
            compactHeaderSpacing = 10
            pickerHeight = 140
            titleFont = .largeTitle.weight(.bold)
            resultFont = .system(size: 28, weight: .bold, design: .rounded)
            captionFont = .footnote
            controlIconFont = .headline
            advancedTitle = "Show Advanced Options"
            advancedTitleFont = .subheadline.weight(.semibold)
            advancedTrailingLabel = "Aperture / ISO"
            advancedTrailingFont = .footnote
            advancedPlaceholderText = "Aperture and ISO placeholders will expand here later."
            advancedPlaceholderPadding = innerPadding
            showsAdvancedTrailingText = true
            showsFullAdvancedPlaceholder = true
        }
    }
}

private extension String {
    var containsKoreanCharacters: Bool {
        unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
        }
    }
}

private func assertNoKoreanUIStrings(_ strings: [String]) {
#if DEBUG
    assert(strings.allSatisfy { !$0.containsKoreanCharacters })
#endif
}
