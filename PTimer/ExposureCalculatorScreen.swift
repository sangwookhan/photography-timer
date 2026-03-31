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
                    ndStop: viewModel.ndStop
                )
                TimerActionView(
                    canStartTimer: viewModel.canStartTimer,
                    onStart: viewModel.startTimer
                )
                RunningTimerPanelView(
                    timers: viewModel.timers,
                    runningTimerCount: viewModel.runningTimerCount,
                    formattedDuration: viewModel.formatDuration,
                    formattedClock: viewModel.formatTimerClock,
                    onStopTimer: viewModel.stopTimer,
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
                ShutterSelectionRow(
                    baseShutter: $baseShutter,
                    shutterSpeeds: shutterSpeeds,
                    formatShutter: formatShutter
                )

                Divider()

                NDStopSelectionRow(ndStop: $ndStop)

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
                    .foregroundStyle(.secondary)
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

                    Text(primaryResultText)
                        .font(.title3.weight(.semibold))
                }

                Divider()

                ResultPlaceholderRow(label: "Base Shutter", value: baseShutterText)
                ResultPlaceholderRow(label: "ND", value: ndText)
                ResultPlaceholderRow(label: "Status", value: statusText)

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
            return calculator.formatShutter(result.resultShutterSeconds)
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
            return "\(ndStop) stop"
        case .failure:
            return "\(ndStop) stop"
        }
    }

    private var statusText: String {
        switch calculationResult {
        case .success:
            return "Updated instantly"
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

                Text("\(ndStop) stop")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Picker("ND", selection: $ndStop) {
                ForEach(0...30, id: \.self) { stop in
                    Text("\(stop) stop").tag(stop)
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
    let formattedClock: (TimeInterval) -> String
    let onStopTimer: (UUID) -> Void
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
                            formattedClock: formattedClock,
                            onStop: { onStopTimer(timer.id) },
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
    let formattedClock: (TimeInterval) -> String
    let onStop: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Timer \(timer.order)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    statusBadge
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedClock(timer.remainingTime))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryTimeColor)
                        .monospacedDigit()
                        .lineLimit(1)

                    Text("/ \(formattedDuration(timer.duration))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(timer.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timer.status == .completed ? .secondary : .primary)
                    .lineLimit(1)

                Text(timer.basisSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    timerMetric(label: "Elapsed", value: formattedClock(timer.elapsedTime))
                    timerMetric(label: "Duration", value: formattedClock(timer.duration))
                }
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

    private func timerMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
