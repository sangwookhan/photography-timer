import SwiftUI
import PTimerKit
import PTimerCore

struct RunningTimerPanelView: View {
    let timers: [RunningTimerItem]
    let runningTimerCount: Int
    let formattedDuration: (TimeInterval) -> String
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatClockTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let onPauseTimer: (UUID) -> Void
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
                            onPause: { onPauseTimer(timer.id) },
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
    let onPause: () -> Void
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
                        accessibilityLabel: "Pause timer",
                        action: onPause
                    )
                }

                if timer.status == .paused {
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
        case .running, .paused:
            return timer.remainingTime
        case .completed, .canceled:
            return timer.duration
        }
    }

    private func targetContextText(targetDisplay: TimeDisplay) -> String? {
        switch timer.status {
        case .running:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        case .completed, .canceled:
            return nil
        case .paused:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        }
    }

    private var timeContextText: String? {
        switch timer.status {
        case .running:
            let completionText = timer.endDate.map(formatDateTime) ?? "--"
            return "Ends \(completionText)"
        case .completed:
            let completionText = timer.completedAt.map(formatDateTime) ?? "--"
            return "Completed \(completionText)"
        case .canceled:
            let canceledText = timer.endDate.map(formatDateTime) ?? "--"
            return "Canceled \(canceledText)"
        case .paused:
            let pausedText = timer.pausedAt.map(formatDateTime) ?? "--"
            return "Paused \(pausedText)"
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
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        case .canceled:
            return "Canceled"
        }
    }

    private var statusSymbol: String {
        switch timer.status {
        case .running:
            return "circle.fill"
        case .paused:
            return "square.fill"
        case .completed:
            return "checkmark"
        case .canceled:
            return "xmark"
        }
    }

    private var statusColor: Color {
        switch timer.status {
        case .running:
            return .green
        case .paused:
            return .orange
        case .completed, .canceled:
            return .gray
        }
    }

    private var primaryTimeColor: Color {
        switch timer.status {
        case .running:
            return .primary
        case .paused:
            return .orange
        case .completed, .canceled:
            return .secondary
        }
    }

    private var cardBackgroundColor: Color {
        switch timer.status {
        case .running:
            return Color(.secondarySystemBackground)
        case .paused:
            return Color(.systemGray6)
        case .completed, .canceled:
            return Color(.tertiarySystemBackground)
        }
    }

    private var borderColor: Color {
        switch timer.status {
        case .running:
            return .green.opacity(0.18)
        case .paused:
            return .orange.opacity(0.18)
        case .completed, .canceled:
            return .gray.opacity(0.18)
        }
    }
}
