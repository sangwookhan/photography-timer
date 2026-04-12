import ActivityKit
import SwiftUI
import WidgetKit

struct LockScreenTimerTargetWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerTargetLiveActivityAttributes.self) { context in
            LockScreenTimerSurface(context: context)
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LockScreenTimerIslandSurface(context: context)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .font(.caption)
            } compactTrailing: {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    if let target = currentTarget(from: context.state, now: timeline.date) {
                        Text(target.endDate, style: .time)
                            .font(.caption2.monospacedDigit())
                    } else {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                    }
                }
            } minimal: {
                Image(systemName: "timer")
                    .font(.caption2)
            }
        }
    }
}

private struct LockScreenTimerSurface: View {
    let context: ActivityViewContext<TimerTargetLiveActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            LockScreenTimerTargetView(
                target: currentTarget(from: context.state, now: timeline.date)
            )
        }
    }
}

private struct LockScreenTimerTargetView: View {
    let target: LockScreenTimerScheduledTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expected completion")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let target {
                Text(target.endDate, style: .time)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(target.timerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No active timer")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text("Waiting for the next running timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct LockScreenTimerIslandSurface: View {
    let context: ActivityViewContext<TimerTargetLiveActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            LockScreenTimerTargetIslandView(
                target: currentTarget(from: context.state, now: timeline.date)
            )
        }
    }
}

private struct LockScreenTimerTargetIslandView: View {
    let target: LockScreenTimerScheduledTarget?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                if let target {
                    Text(target.timerName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(target.endDate, style: .time)
                        .font(.headline.monospacedDigit())
                } else {
                    Text("No active timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private func currentTarget(
    from state: TimerTargetLiveActivityAttributes.ContentState,
    now: Date
) -> LockScreenTimerScheduledTarget? {
    state.displayTarget(at: now)
}
