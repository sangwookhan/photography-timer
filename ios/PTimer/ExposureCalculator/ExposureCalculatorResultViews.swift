import SwiftUI
import PTimerKit
import PTimerCore

/// Result-section views for the Exposure Calculator. Hosts the
/// digital-mode block (one read), the film-mode 3-row hierarchy
/// (Adjusted Shutter / Reciprocity / Corrected Exposure), and the
/// shared timer-start affordance.

struct ResultSectionView: View {
    let isFilmWorkflowActive: Bool
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let filmModeExposureResultState: FilmModeExposureResultState?
    let canShowFilmDetails: Bool
    /// Single shared result-row duration policy used by both No Film and
    /// Film rows (PTIMER-172): coarse primary + whole-seconds secondary
    /// shown only in the 60 s–1 d band.
    let resultDurationDisplay: (TimeInterval) -> TimeDisplay
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let onStartFilmAdjustedShutterTimer: () -> Void
    let onStartFilmCorrectedExposureTimer: () -> Void
    let onShowFilmDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            VStack(alignment: .leading, spacing: style.resultTopSpacerMinLength) {
                if isFilmWorkflowActive,
                   let filmModeExposureResultState {
                    FilmModeResultHierarchyView(
                        resultState: filmModeExposureResultState,
                        canShowDetails: canShowFilmDetails,
                        resultDurationDisplay: resultDurationDisplay,
                        onStartAdjustedShutterTimer: onStartFilmAdjustedShutterTimer,
                        onStartCorrectedExposureTimer: onStartFilmCorrectedExposureTimer,
                        onShowDetails: onShowFilmDetails,
                        style: style
                    )
                } else if case .success(let result) = calculationResult {
                    DigitalModeResultView(
                        resultShutterSeconds: result.resultShutterSeconds,
                        resultDurationDisplay: resultDurationDisplay,
                        canStartTimer: canStartTimer,
                        onStartTimer: onStartTimer,
                        style: style
                    )
                } else {
                    Text(primaryResultText)
                        .font(.title3.weight(.semibold))
                }

                if let validationMessage {
                    Divider()

                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(style.resultBlockPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: isFilmWorkflowActive ? style.filmResultCardMinHeight : nil,
                alignment: .topLeading
            )
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle(style: style)
    }

    private var primaryResultText: String {
        switch calculationResult {
        case .success(let result):
            return resultDurationDisplay(result.resultShutterSeconds).primary
        case .failure:
            return "Result unavailable"
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

private struct DigitalModeResultView: View {
    let resultShutterSeconds: TimeInterval
    let resultDurationDisplay: (TimeInterval) -> TimeDisplay
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        let display = resultDurationDisplay(resultShutterSeconds)

        // PTIMER-172: No Film uses the same shared row + duration policy
        // as Film mode — leading label, dominant right-aligned duration,
        // subdued whole-seconds (60 s–1 d only), trailing timer.
        ResultValueRow(
            title: "Adjusted\nShutter",
            value: .duration(
                primary: display.primary,
                seconds: display.secondary,
                color: .primary
            ),
            valueAccessibilityIdentifier: "digital-result-primary",
            secondaryAccessibilityIdentifier: "digital-result-secondary",
            canStartTimer: canStartTimer,
            onStartTimer: onStartTimer,
            timerAccessibilityIdentifier: "digital-result-start-timer-button",
            timerAccessibilityLabel: "Start timer from calculated result",
            timerAccessibilityHint: "Starts a timer using the calculated result",
            style: style
        )
    }
}

private struct FilmModeResultHierarchyView: View {
    let resultState: FilmModeExposureResultState
    let canShowDetails: Bool
    let resultDurationDisplay: (TimeInterval) -> TimeDisplay
    let onStartAdjustedShutterTimer: () -> Void
    let onStartCorrectedExposureTimer: () -> Void
    let onShowDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            let adjustedDisplay = resultDurationDisplay(resultState.adjustedShutterSeconds)
            ResultValueRow(
                title: "Adjusted\nShutter",
                value: .duration(
                    primary: adjustedDisplay.primary,
                    seconds: adjustedDisplay.secondary,
                    color: .primary.opacity(0.88)
                ),
                valueAccessibilityIdentifier: "adjusted-shutter-primary",
                secondaryAccessibilityIdentifier: "adjusted-shutter-secondary",
                canStartTimer: resultState.adjustedShutterAction.canStartTimer,
                onStartTimer: onStartAdjustedShutterTimer,
                timerAccessibilityIdentifier: "adjusted-shutter-start-timer-button",
                timerAccessibilityLabel: resultState.adjustedShutterAction.accessibilityLabel,
                timerAccessibilityHint: resultState.adjustedShutterAction.accessibilityHint,
                style: style
            )

            Divider()

            FilmModeReciprocityStateRow(
                reciprocityState: resultState.reciprocityState,
                showsDetailsEntry: canShowDetails,
                onShowDetails: onShowDetails,
                style: style
            )

            Divider()

            FilmModeCorrectedExposureRow(
                correctedExposure: resultState.correctedExposure,
                actionState: resultState.correctedExposureAction,
                onStartTimer: onStartCorrectedExposureTimer,
                style: style
            )

        }
    }
}

/// Intentional two-line label for the shared result row (PTIMER-172).
/// The caller passes the two words separated by a newline ("Adjusted\n
/// Shutter"); the explicit break plus a fixed-width column keeps the
/// label stable and prevents it from competing with the value area.
private struct ResultRowLabel: View {
    let title: String
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: style.resultLabelColumnWidth, alignment: .leading)
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
private struct ResultValueRow: View {
    /// The value area of the row. `duration` renders the dominant
    /// right-aligned primary plus the subdued seconds column; `status`
    /// (non-quantified corrected exposure) renders a short status that
    /// spans the value area, with no seconds column.
    enum Value {
        case duration(primary: String, seconds: String, color: Color)
        case status(text: String, color: Color)
    }

    let title: String
    let value: Value
    let valueAccessibilityIdentifier: String
    let secondaryAccessibilityIdentifier: String
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let timerAccessibilityIdentifier: String
    let timerAccessibilityLabel: String
    let timerAccessibilityHint: String
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        HStack(spacing: 8) {
            ResultRowLabel(title: title, style: style)

            switch value {
            case let .duration(primary, seconds, color):
                Text(primary)
                    .font(style.unifiedResultPrimaryFont)
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
                    .frame(width: style.resultSecondsColumnWidth, alignment: .trailing)
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

            TimerActionView(
                canStartTimer: canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: timerAccessibilityIdentifier,
                accessibilityLabel: timerAccessibilityLabel,
                accessibilityHint: timerAccessibilityHint
            )
        }
        .frame(minHeight: style.filmResultRowMinHeight, alignment: .center)
    }

    private func showsSeconds(primary: String, seconds: String) -> Bool {
        !seconds.isEmpty && seconds != primary
    }
}

private struct FilmModeReciprocityStateRow: View {
    let reciprocityState: FilmModeReciprocityStateDisplayState
    let showsDetailsEntry: Bool
    let onShowDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Reciprocity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if showsDetailsEntry {
                Button(action: onShowDetails) {
                    HStack(spacing: 8) {
                        Text(reciprocityState.badgeText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(badgeForegroundColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(badgeBackgroundColor)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("film-mode-reciprocity-badge")

                        if reciprocityState.showsInfoAffordance {
                            Image(systemName: "info.circle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("film-mode-reciprocity-info")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("film-mode-reciprocity-details-button")
                .accessibilityLabel("Open reciprocity details")
                .accessibilityValue(reciprocityState.badgeText)
                .accessibilityHint(reciprocityState.infoText)
            } else {
                HStack(spacing: 8) {
                    Text(reciprocityState.badgeText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(badgeForegroundColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(badgeBackgroundColor)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("film-mode-reciprocity-badge")

                    if reciprocityState.showsInfoAffordance {
                        Image(systemName: "info.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("film-mode-reciprocity-info")
                    }
                }
            }
        }
        .frame(minHeight: style.filmResultRowMinHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reciprocity")
        .accessibilityValue(reciprocityState.badgeText)
        .accessibilityHint(reciprocityState.infoText)
    }

    private var badgeForegroundColor: Color {
        switch reciprocityState.tone {
        case .trusted:
            return Color(.systemGreen)
        case .measured:
            return Color(.systemBlue)
        case .caution:
            return Color(.systemOrange)
        case .limitedGuidance:
            return Color(.systemBrown)
        case .unsupported:
            return Color(.systemRed)
        }
    }

    private var badgeBackgroundColor: Color {
        switch reciprocityState.tone {
        case .trusted:
            return Color(.systemGreen).opacity(0.14)
        case .measured:
            return Color(.systemBlue).opacity(0.14)
        case .caution:
            return Color(.systemOrange).opacity(0.16)
        case .limitedGuidance:
            return Color(.systemBrown).opacity(0.14)
        case .unsupported:
            return Color(.systemRed).opacity(0.14)
        }
    }
}

private struct FilmModeCorrectedExposureRow: View {
    let correctedExposure: FilmModeCorrectedExposureDisplayState
    let actionState: FilmModeTimerActionState
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        // PTIMER-172: a quantified corrected exposure uses the same
        // single-line labeled row as Adjusted Shutter (duration +
        // optional seconds comparison + timer). Non-quantified states
        // stay compact — a short status sits inline with the label and
        // the long explanation lives in Reciprocity Details, so the
        // main card never grows to fit a wrapped sentence.
        ResultValueRow(
            title: "Corrected\nExposure",
            value: rowValue,
            valueAccessibilityIdentifier: "film-mode-corrected-exposure-primary",
            secondaryAccessibilityIdentifier: "film-mode-corrected-exposure-secondary",
            canStartTimer: actionState.canStartTimer,
            onStartTimer: onStartTimer,
            timerAccessibilityIdentifier: "corrected-exposure-start-timer-button",
            timerAccessibilityLabel: actionState.accessibilityLabel,
            timerAccessibilityHint: actionState.accessibilityHint,
            style: style
        )
    }

    private var rowValue: ResultValueRow.Value {
        // Quantified → dominant duration + subdued seconds (shared
        // policy). Non-quantified → a short status; the long explanation
        // stays in Reciprocity Details, never in the main card.
        if correctedExposure.kind == .quantified {
            return .duration(
                primary: correctedExposure.primaryText,
                seconds: correctedExposure.secondaryText,
                color: .primary
            )
        }
        return .status(text: correctedExposure.primaryText, color: nonQuantifiedColor)
    }

    private var nonQuantifiedColor: Color {
        switch correctedExposure.kind {
        case .limitedGuidance:
            return Color(.systemOrange)
        case .unsupported:
            return Color(.systemRed)
        case .noFilmSelected:
            return .secondary
        case .quantified:
            return .primary
        }
    }
}

private struct TimerActionView: View {
    let canStartTimer: Bool
    let onStart: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        Button {
            onStart()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: style.timerActionIconSize, weight: .semibold))
                .foregroundStyle(canStartTimer ? Color.accentColor : Color.secondary.opacity(0.8))
                .frame(width: style.timerActionSize, height: style.timerActionSize)
                .background(
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                )
                .overlay(
                    Circle()
                        .stroke(Color(.separator).opacity(0.55), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStartTimer)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
