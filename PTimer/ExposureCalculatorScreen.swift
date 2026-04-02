import SwiftUI

struct ExposureCalculatorScreen: View {
    @StateObject private var viewModel = ExposureCalculatorViewModel()

    init() {
        assertNoKoreanUIStrings([
            "Exposure",
            "Show Advanced Options",
            "View All"
        ])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView()
                VariableSectionView(
                    baseShutter: $viewModel.baseShutter,
                    ndStop: $viewModel.ndStop,
                    shutterSpeeds: ExposureCalculatorViewModel.shutterSpeeds,
                    formatShutter: viewModel.formatShutter
                )
                ResultSectionView(
                    calculationResult: viewModel.calculationResult,
                    ndStop: viewModel.ndStop,
                    formatTimeDisplay: viewModel.formatTimeDisplay
                )
                TimerActionView(
                    canStartTimer: viewModel.canStartTimer,
                    onStart: viewModel.startTimer
                )
                RunningTimerPanelView(
                    timers: viewModel.timers,
                    runningTimerCount: viewModel.runningTimerCount,
                    formattedDuration: viewModel.formatDuration,
                    formatTimeDisplay: viewModel.formatTimeDisplay,
                    formatClockTime: viewModel.formatClockTime,
                    formatDateTime: viewModel.formatDateTime,
                    onStopTimer: viewModel.stopTimer,
                    onResumeTimer: viewModel.resumeTimer,
                    onRemoveTimer: viewModel.removeTimer
                )
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exposure")
                .font(.largeTitle.weight(.bold))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Mode", selection: .constant(0)) {
                        Text("Digital").tag(0)
                        Text("Film").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .disabled(true)

                    Text("Film mode: placeholder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .sectionCardStyle()
    }
}

struct VariableSectionView: View {
    @Binding var baseShutter: Double
    @Binding var ndStop: Int
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Variable Controls")
                .font(.headline)

            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ShutterSelectionRow(
                        baseShutter: $baseShutter,
                        shutterSpeeds: shutterSpeeds,
                        formatShutter: formatShutter
                    )

                    NDStopSelectionRow(ndStop: $ndStop)
                }

                Divider()

                HStack {
                    Text("Show Advanced Options")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Label("Aperture / ISO", systemImage: "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Aperture and ISO placeholders will expand here later.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sectionCardStyle()
    }
}

struct ResultSectionView: View {
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let ndStop: Int
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    private let calculator = ExposureCalculator()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result Set")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Shutter")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    if case .success(let result) = calculationResult {
                        let display = formatTimeDisplay(result.resultShutterSeconds)
                        DurationDisplayBlock(
                            primaryText: display.primary,
                            secondaryText: display.secondary,
                            primaryColor: .primary,
                            primaryFont: .system(size: 28, weight: .bold, design: .rounded),
                            secondaryFont: .footnote
                        )
                    } else {
                        Text(primaryResultText)
                            .font(.title3.weight(.semibold))
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    CompactInfoPill(label: "Base", value: baseShutterText)
                    CompactInfoPill(label: "ND", value: ndText)
                    CompactInfoPill(label: "Status", value: statusText)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle()
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
        switch calculationResult {
        case .success:
            return ndStop == 1 ? "1 stop" : "\(ndStop) stops"
        case .failure:
            return ndStop == 1 ? "1 stop" : "\(ndStop) stops"
        }
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
            .frame(height: 140)
            .clipped()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Stop-based ND selection")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ShutterSelectionRow: View {
    @Binding var baseShutter: Double
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String

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
            .frame(height: 140)
            .clipped()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Full-stop shutter selection")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct TimerActionView: View {
    let canStartTimer: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer Action")
                .font(.headline)

            Button("Start Timer") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!canStartTimer)
        }
        .sectionCardStyle()
    }
}

struct RunningTimerPanelView: View {
    let timers: [RunningTimerItem]
    let runningTimerCount: Int
    let formattedDuration: (TimeInterval) -> String
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatClockTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let onStopTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panelTitle)
                    .font(.headline)

                Spacer()

                Button("View All") {
                }
                    .font(.footnote.weight(.semibold))
                    .disabled(true)
            }

            if timers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.title3)
                        .foregroundStyle(.tertiary)

                    Text("No active timers")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(timers) { timer in
                        TimerSummaryCard(
                            timer: timer,
                            formattedDuration: formattedDuration,
                            formatTimeDisplay: formatTimeDisplay,
                            formatClockTime: formatClockTime,
                            formatDateTime: formatDateTime,
                            onStop: { onStopTimer(timer.id) },
                            onResume: { onResumeTimer(timer.id) },
                            onRemove: { onRemoveTimer(timer.id) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var panelTitle: String {
        "Running Timers: \(runningTimerCount)"
    }
}

private struct TimerSummaryCard: View {
    let timer: RunningTimerItem
    let formattedDuration: (TimeInterval) -> String
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatClockTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let onStop: () -> Void
    let onResume: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let primaryDisplay = formatTimeDisplay(primaryDuration)
        let targetDisplay = formatTimeDisplay(timer.duration)

        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Timer \(timer.order)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    statusBadge
                }

                VStack(alignment: .leading, spacing: 2) {
                    DurationDisplayBlock(
                        primaryText: primaryDisplay.primary,
                        secondaryText: primaryDisplay.secondary,
                        primaryColor: primaryTimeColor,
                        primaryFont: .system(size: 28, weight: .bold, design: .rounded),
                        secondaryFont: .footnote
                    )

                    if timer.status == .stopped {
                        Text("Remaining \(primaryDisplay.primary)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if let targetContextText = targetContextText(targetDisplay: targetDisplay) {
                    Text(targetContextText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if let timeContextText {
                    Text(timeContextText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(timer.basisSummary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                if timer.status == .running {
                    iconActionButton(
                        systemName: "pause.circle",
                        tint: .orange,
                        accessibilityLabel: "Stop timer",
                        action: onStop
                    )
                }

                if timer.status == .stopped {
                    iconActionButton(
                        systemName: "play.circle",
                        tint: .blue,
                        accessibilityLabel: "Resume timer",
                        action: onResume
                    )
                }

                if timer.status != .running {
                    iconActionButton(
                        systemName: "trash",
                        tint: .secondary,
                        accessibilityLabel: "Remove timer",
                        action: onRemove
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var primaryDuration: TimeInterval {
        switch timer.status {
        case .running, .stopped:
            return timer.remainingTime
        case .completed:
            return timer.duration
        }
    }

    private func targetContextText(targetDisplay: TimeDisplay) -> String? {
        switch timer.status {
        case .running:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        case .completed:
            return nil
        case .stopped:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        }
    }

    private var timeContextText: String? {
        switch timer.status {
        case .running:
            return timer.endDate.map(formatDateTime) ?? "--"
        case .completed:
            return timer.completedAt.map(formatDateTime) ?? "--"
        case .stopped:
            return timer.pausedAt.map(formatDateTime) ?? "--"
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private func iconActionButton(
        systemName: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(
            Circle()
                .fill(tint.opacity(0.12))
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusText: String {
        switch timer.status {
        case .running:
            return "Running"
        case .stopped:
            return "Stopped"
        case .completed:
            return "Completed"
        }
    }

    private var statusSymbol: String {
        switch timer.status {
        case .running:
            return "circle.fill"
        case .stopped:
            return "square.fill"
        case .completed:
            return "checkmark"
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

    private var primaryTimeColor: Color {
        switch timer.status {
        case .running:
            return .primary
        case .stopped:
            return .orange
        case .completed:
            return .secondary
        }
    }

    private var cardBackgroundColor: Color {
        switch timer.status {
        case .running:
            return Color(.secondarySystemBackground)
        case .stopped:
            return Color(.systemGray6)
        case .completed:
            return Color(.tertiarySystemBackground)
        }
    }

    private var borderColor: Color {
        switch timer.status {
        case .running:
            return .green.opacity(0.18)
        case .stopped:
            return .orange.opacity(0.18)
        case .completed:
            return .gray.opacity(0.18)
        }
    }
}

private struct DurationDisplayBlock: View {
    let primaryText: String
    let secondaryText: String
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


private struct ResultPlaceholderRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

private extension View {
    func sectionCardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
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
