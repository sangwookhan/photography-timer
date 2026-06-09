import SwiftUI

/// Layout metrics for a timer-action control, injected by the host instead of
/// the app's full layout-style type. Keeps the reusable component free of any
/// app-specific layout system — the host derives these values and passes only
/// what the control needs.
public struct TimerActionMetrics: Sendable, Equatable {
    /// Circular tap-target diameter.
    public var diameter: CGFloat
    /// Point size of the `play.fill` glyph.
    public var iconPointSize: CGFloat

    public init(diameter: CGFloat, iconPointSize: CGFloat) {
        self.diameter = diameter
        self.iconPointSize = iconPointSize
    }
}

/// Background treatment for a `TimerActionButton`.
public enum TimerActionButtonStyle: Sendable, Equatable {
    /// Always uses the recessed surface fill (a quiet, secondary affordance).
    case recessed
    /// Tints the background with the action accent while enabled (a more
    /// prominent affordance), falling back to the recessed fill when disabled.
    case tintedWhenEnabled
}

/// Reusable circular "start timer" (play) control. Renders from injected
/// `TimerActionMetrics` and reads its semantic colors from
/// `PTimerComponentTheme`, so it carries no UIKit dependency and no
/// app-specific layout style.
public struct TimerActionButton: View {
    @Environment(\.ptimerComponentTheme) private var theme

    private let isEnabled: Bool
    private let metrics: TimerActionMetrics
    private let style: TimerActionButtonStyle
    private let accessibilityLabelText: String
    private let accessibilityHintText: String
    private let accessibilityIdentifierValue: String
    private let action: () -> Void

    public init(
        isEnabled: Bool,
        metrics: TimerActionMetrics,
        style: TimerActionButtonStyle = .recessed,
        accessibilityLabel: String,
        accessibilityHint: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.metrics = metrics
        self.style = style
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityHintText = accessibilityHint
        self.accessibilityIdentifierValue = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: metrics.iconPointSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: metrics.diameter, height: metrics.diameter)
                .background(
                    Circle()
                        .fill(backgroundFill)
                )
                .overlay(
                    Circle()
                        .stroke(theme.separator.opacity(0.55), lineWidth: 0.8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityIdentifier(accessibilityIdentifierValue)
    }

    private var glyphColor: Color {
        isEnabled ? theme.timerActionAccent : theme.timerActionDisabledGlyph.opacity(0.8)
    }

    private var backgroundFill: Color {
        if style == .tintedWhenEnabled, isEnabled {
            return theme.timerActionAccent.opacity(0.14)
        }
        return theme.recessedFill
    }
}
