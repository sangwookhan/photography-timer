// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Layout metrics for the target-shutter card, injected by the host instead of
/// the app's full layout-style type. Only what the card needs — the kit never
/// sees the app layout system. (The card's spacings are intrinsic; its only
/// host-derived metric is the start-timer control size.)
public struct TargetShutterCardLayout: Sendable {
    /// Metrics for the trailing start-timer control.
    public var timerAction: TimerActionMetrics

    public init(timerAction: TimerActionMetrics) {
        self.timerAction = timerAction
    }
}

/// Reusable target-shutter card/row. Renders a `TargetShutterDisplayState`,
/// invokes `onEdit` to open the host's input sheet, and reuses
/// `TimerActionButton` for the start affordance. SwiftUI-only; semantic colors
/// come from `PTimerComponentTheme`. The host keeps the input sheet, the
/// `.sheet` orchestration, and the section-card chrome.
public struct TargetShutterCard: View {
    @Environment(\.ptimerComponentTheme) private var theme

    private let displayState: TargetShutterDisplayState
    private let canStartTimer: Bool
    private let onEdit: () -> Void
    private let onStartTimer: () -> Void
    private let layout: TargetShutterCardLayout

    public init(
        displayState: TargetShutterDisplayState,
        canStartTimer: Bool,
        onEdit: @escaping () -> Void,
        onStartTimer: @escaping () -> Void,
        layout: TargetShutterCardLayout
    ) {
        self.displayState = displayState
        self.canStartTimer = canStartTimer
        self.onEdit = onEdit
        self.onStartTimer = onStartTimer
        self.layout = layout
    }

    @ViewBuilder
    public var body: some View {
        switch displayState {
        case .unavailable(.inactive):
            inactiveRow
        case .available(let availableState):
            activeRow(availableState)
        case .unavailable(.noComparisonAvailable):
            // Reserved enum case; the presenter never emits this form
            // today (target-set + comparison-unavailable goes through
            // `.available` with `comparison: nil`). Render inactive
            // so any future routing change still produces something
            // sensible instead of an empty card.
            inactiveRow
        }
    }

    private var inactiveRow: some View {
        Button {
            onEdit()
        } label: {
            HStack(spacing: 12) {
                Text("Target Shutter")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Off")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            // Broad tap target — without `.frame(maxWidth:.infinity)`
            // the Button's label would shrink-wrap to its content and
            // tapping the empty trailing area inside the section card
            // would miss the Button.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("target-shutter-set-button")
        .accessibilityLabel("Target Shutter is off")
        .accessibilityHint("Opens a sheet to enable Target Shutter")
    }

    @ViewBuilder
    private func activeRow(_ state: TargetShutterAvailableState) -> some View {
        // Compact single-row layout.
        // [edit-area: label + value + stop diff] [play].
        //
        // The edit-area is a real `Button` (matching the inactive
        // row's structure) so VoiceOver, Switch Control, Voice
        // Control, and external-keyboard focus navigation all treat
        // it as a first-class actionable element. The play `Button`
        // is a sibling — both buttons live side by side in the outer
        // HStack, never nested, so SwiftUI routes taps to each
        // independently. Clear is intentionally **not** on the main
        // row — the input sheet's `Use Target Shutter` switch owns
        // target removal.
        HStack(spacing: 12) {
            Button {
                onEdit()
            } label: {
                HStack(spacing: 8) {
                    Text("Target Shutter")
                        // PTIMER-172: keep the label on one line so the
                        // row never grows to two lines on a narrow phone.
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Text(targetText(state.targetSeconds))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("target-shutter-target-value")
                    compactStopDifference(state)
                }
                // Broad tap target — without `.frame(maxWidth:.infinity)`
                // the Button's label would shrink-wrap, leaving the
                // gap between the value and the play button untappable.
                // The play button stays a sibling outside this Button,
                // so taps on the play glyph still route to the start-
                // timer action rather than to edit.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(activeRowAccessibilityLabel(state))
            .accessibilityHint("Opens a sheet to change the target duration")
            .accessibilityIdentifier("target-shutter-edit-button")

            TimerActionButton(
                isEnabled: canStartTimer,
                metrics: layout.timerAction,
                style: .tintedWhenEnabled,
                accessibilityLabel: "Start target shutter timer",
                accessibilityHint: "Starts a timer using the photographer-supplied target duration",
                accessibilityIdentifier: "target-shutter-start-timer-button",
                action: onStartTimer
            )
        }
    }

    /// Compact arrow + stop-difference glyph for the active row.
    /// Sized to subheadline so it matches the row's overall scale.
    /// Accessibility is intentionally hidden here — the enclosing
    /// edit-area's combined label already conveys the same info.
    @ViewBuilder
    private func compactStopDifference(_ state: TargetShutterAvailableState) -> some View {
        if let stopDifference = state.stopDifference {
            HStack(spacing: 4) {
                Image(systemName: stopDifferenceArrow(stopDifference.kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(stopDifferenceColor(for: stopDifference.kind))
                Text(stopDifference.formattedText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stopDifferenceColor(for: stopDifference.kind))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("target-shutter-stop-difference")
            }
            .accessibilityHidden(true)
        } else {
            Text("—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-shutter-stop-difference")
                .accessibilityHidden(true)
        }
    }

    /// VoiceOver label for the combined edit-area accessibility
    /// element. Folds the (no-longer-visible) comparison basis and
    /// stop-difference into a single readable sentence so blind
    /// users still get the same information sighted users used to
    /// read on the dropped second row.
    private func activeRowAccessibilityLabel(_ state: TargetShutterAvailableState) -> String {
        let value = "Target Shutter \(targetText(state.targetSeconds))"
        let basis: String
        if let comparison = state.comparison {
            basis = " vs \(comparison.label)"
        } else {
            basis = ""
        }
        if let stopDifference = state.stopDifference {
            switch stopDifference.kind {
            case .match:
                return "\(value)\(basis), matches calculated exposure"
            case .longerThanComparison:
                return "\(value)\(basis), \(stopDifference.formattedText) longer"
            case .shorterThanComparison:
                return "\(value)\(basis), \(stopDifference.formattedText) shorter"
            }
        }
        return "\(value)\(basis)"
    }

    private func stopDifferenceArrow(_ kind: TargetShutterStopDifferenceKind) -> String {
        switch kind {
        case .match:
            return "equal"
        case .longerThanComparison:
            return "arrow.up"
        case .shorterThanComparison:
            return "arrow.down"
        }
    }

    /// Stop-difference comparison colors. Reuses the shared accent tokens
    /// (the host maps them to the platform's green/blue/orange), so the kit
    /// holds no UIKit-backed color and needs no target-shutter-specific token.
    private func stopDifferenceColor(for kind: TargetShutterStopDifferenceKind) -> Color {
        switch kind {
        case .match:
            return theme.accentRunning
        case .longerThanComparison:
            return theme.accentInfo
        case .shorterThanComparison:
            return theme.accentWarning
        }
    }

    private func targetText(_ seconds: TimeInterval) -> String {
        // Compact h/m/s formatting (`3m 20s`, `2h 16m`) — same shape
        // the input sheet's Fine Tune readout uses, so the main card
        // and the sheet stay typographically aligned.
        let total = max(1, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        if h > 0 {
            if m == 0 && s == 0 {
                return "\(h)h"
            }
            if s == 0 {
                return "\(h)h \(m)m"
            }
            return "\(h)h \(m)m \(s)s"
        }
        if m > 0 {
            if s == 0 {
                return "\(m)m"
            }
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }
}
