import SwiftUI

/// Layout metrics for a result row, injected by the host instead of the app's
/// full layout-style type. Only the values the row needs — the kit never sees
/// the app layout system.
public struct ResultRowLayout: Sendable {
    /// Fixed width of the leading label column.
    public var labelColumnWidth: CGFloat
    /// Font for the dominant primary duration.
    public var primaryFont: Font
    /// Fixed width of the trailing subdued seconds column.
    public var secondsColumnWidth: CGFloat
    /// Minimum row height.
    public var rowMinHeight: CGFloat
    /// Metrics for the trailing start-timer control.
    public var timerAction: TimerActionMetrics

    public init(
        labelColumnWidth: CGFloat,
        primaryFont: Font,
        secondsColumnWidth: CGFloat,
        rowMinHeight: CGFloat,
        timerAction: TimerActionMetrics
    ) {
        self.labelColumnWidth = labelColumnWidth
        self.primaryFont = primaryFont
        self.secondsColumnWidth = secondsColumnWidth
        self.rowMinHeight = rowMinHeight
        self.timerAction = timerAction
    }
}

private struct ResultRowLabel: View {
    let title: String
    let labelColumnWidth: CGFloat

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: labelColumnWidth, alignment: .leading)
    }
}

/// Shared result row used across No Film and Film modes (PTIMER-172),
/// laid out as fixed structured columns so the primary duration stays
/// stable and dominant:
///
///   [ label column ] [ primary duration ] [ seconds ] [ play ]
///
/// - The label column and seconds column have fixed widths; the primary
///   fills the flexible middle and is right-aligned, so its right edge is
///   anchored at the seconds column regardless of whether a seconds value
///   is currently shown — the value no longer jumps as wheel values cross
///   the 60 s / 1 d thresholds.
/// - The seconds column is reserved even when empty and renders subdued,
///   smaller, and lighter than the primary; it shrinks/truncates within
///   its own column and never competes with or dominates the primary.
/// - The host supplies the value color (and so the kit stays free of any
///   app-specific status palette) plus a `ResultRowLayout`.
public struct ResultValueRow: View {
    /// The value area of the row. `duration` renders the dominant
    /// right-aligned primary plus the subdued seconds column; `status`
    /// (non-quantified corrected exposure) renders a short status that
    /// spans the value area, with no seconds column.
    public enum Value: Equatable {
        case duration(primary: String, seconds: String, color: Color)
        case status(text: String, color: Color)
    }

    private let title: String
    private let value: Value
    private let valueAccessibilityIdentifier: String
    private let secondaryAccessibilityIdentifier: String
    private let canStartTimer: Bool
    private let onStartTimer: () -> Void
    private let timerAccessibilityIdentifier: String
    private let timerAccessibilityLabel: String
    private let timerAccessibilityHint: String
    private let layout: ResultRowLayout

    public init(
        title: String,
        value: Value,
        valueAccessibilityIdentifier: String,
        secondaryAccessibilityIdentifier: String,
        canStartTimer: Bool,
        onStartTimer: @escaping () -> Void,
        timerAccessibilityIdentifier: String,
        timerAccessibilityLabel: String,
        timerAccessibilityHint: String,
        layout: ResultRowLayout
    ) {
        self.title = title
        self.value = value
        self.valueAccessibilityIdentifier = valueAccessibilityIdentifier
        self.secondaryAccessibilityIdentifier = secondaryAccessibilityIdentifier
        self.canStartTimer = canStartTimer
        self.onStartTimer = onStartTimer
        self.timerAccessibilityIdentifier = timerAccessibilityIdentifier
        self.timerAccessibilityLabel = timerAccessibilityLabel
        self.timerAccessibilityHint = timerAccessibilityHint
        self.layout = layout
    }

    public var body: some View {
        HStack(spacing: 8) {
            ResultRowLabel(title: title, labelColumnWidth: layout.labelColumnWidth)

            switch value {
            case let .duration(primary, seconds, color):
                Text(primary)
                    .font(layout.primaryFont)
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier(valueAccessibilityIdentifier)

                // Subdued seconds column, reserved even when empty so the
                // primary's right edge stays anchored as wheel values
                // cross the 60 s / 1 d thresholds. Hidden when empty or
                // identical to the primary; shrinks/truncates within its
                // own column and never competes with the primary.
                Text(showsSeconds(primary: primary, seconds: seconds) ? seconds : "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: layout.secondsColumnWidth, alignment: .trailing)
                    .accessibilityIdentifier(secondaryAccessibilityIdentifier)

            case let .status(text, color):
                // Short status spans the full value area (no seconds
                // column) so it stays readable. The long explanation
                // lives in Reciprocity Details — never in the main card.
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier(valueAccessibilityIdentifier)
            }

            TimerActionButton(
                isEnabled: canStartTimer,
                metrics: layout.timerAction,
                style: .recessed,
                accessibilityLabel: timerAccessibilityLabel,
                accessibilityHint: timerAccessibilityHint,
                accessibilityIdentifier: timerAccessibilityIdentifier,
                action: onStartTimer
            )
        }
        .frame(minHeight: layout.rowMinHeight, alignment: .center)
    }

    private func showsSeconds(primary: String, seconds: String) -> Bool {
        !seconds.isEmpty && seconds != primary
    }
}
