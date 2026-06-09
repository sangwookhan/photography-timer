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
            layout: ResultRowLayout(style)
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
                layout: ResultRowLayout(style)
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
            layout: ResultRowLayout(style)
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

private extension ResultRowLayout {
    /// Builds the reusable row layout from the app's workspace layout style.
    /// Keeps `ExposureWorkspaceMainLayoutStyle` in the app; the kit only sees
    /// the small config.
    init(_ style: ExposureWorkspaceMainLayoutStyle) {
        self.init(
            labelColumnWidth: style.resultLabelColumnWidth,
            primaryFont: style.unifiedResultPrimaryFont,
            secondsColumnWidth: style.resultSecondsColumnWidth,
            rowMinHeight: style.filmResultRowMinHeight,
            timerAction: TimerActionMetrics(
                diameter: style.timerActionSize,
                iconPointSize: style.timerActionIconSize
            )
        )
    }
}
