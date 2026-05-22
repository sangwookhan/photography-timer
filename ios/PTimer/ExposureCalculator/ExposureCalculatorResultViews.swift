import SwiftUI

/// Result-section views for the Exposure Calculator. Hosts the
/// digital-mode block (one read), the film-mode 3-row hierarchy
/// (Adjusted Shutter / Reciprocity / Corrected Exposure), and the
/// shared timer-start affordance.

struct ResultSectionView: View {
    let isFilmWorkflowActive: Bool
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let filmModeExposureResultState: FilmModeExposureResultState?
    let canShowFilmDetails: Bool
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatReciprocityTimeDisplay: (TimeInterval) -> TimeDisplay
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
                        formatReciprocityTimeDisplay: formatReciprocityTimeDisplay,
                        onStartAdjustedShutterTimer: onStartFilmAdjustedShutterTimer,
                        onStartCorrectedExposureTimer: onStartFilmCorrectedExposureTimer,
                        onShowDetails: onShowFilmDetails,
                        style: style
                    )
                } else if case .success(let result) = calculationResult {
                    DigitalModeResultView(
                        resultShutterSeconds: result.resultShutterSeconds,
                        formatTimeDisplay: formatTimeDisplay,
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
            return formatTimeDisplay(result.resultShutterSeconds).primary
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
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        let display = formatTimeDisplay(resultShutterSeconds)

        HStack(alignment: .center, spacing: style.resultActionSpacing) {
            Color.clear
                .frame(width: style.resultActionFootprint, height: 1)
                .accessibilityHidden(true)

            DurationDisplayBlock(
                primaryText: display.primary,
                secondaryText: display.secondary,
                primaryColor: .primary,
                primaryFont: style.resultPrimaryFont,
                secondaryFont: .footnote
            )
            .frame(maxWidth: .infinity)

            TimerActionView(
                canStartTimer: canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: "digital-result-start-timer-button",
                accessibilityLabel: "Start timer from calculated result",
                accessibilityHint: "Starts a timer using the calculated result"
            )
        }
    }
}

private struct FilmModeResultHierarchyView: View {
    let resultState: FilmModeExposureResultState
    let canShowDetails: Bool
    let formatReciprocityTimeDisplay: (TimeInterval) -> TimeDisplay
    let onStartAdjustedShutterTimer: () -> Void
    let onStartCorrectedExposureTimer: () -> Void
    let onShowDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            FilmModeResultRow(
                title: "Adjusted Shutter",
                display: formatReciprocityTimeDisplay(resultState.adjustedShutterSeconds),
                primaryFont: .headline.weight(.semibold),
                secondaryFont: .footnote,
                primaryColor: .primary.opacity(0.88),
                actionState: resultState.adjustedShutterAction,
                onStartTimer: onStartAdjustedShutterTimer,
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

private struct FilmModeResultRow: View {
    let title: String
    let display: TimeDisplay
    let primaryFont: Font
    let secondaryFont: Font
    let primaryColor: Color
    let actionState: FilmModeTimerActionState
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        HStack(alignment: .top, spacing: style.resultActionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                DurationDisplayBlock(
                    primaryText: display.primary,
                    secondaryText: display.secondary,
                    primaryColor: primaryColor,
                    primaryFont: primaryFont,
                    secondaryFont: secondaryFont
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TimerActionView(
                canStartTimer: actionState.canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: "adjusted-shutter-start-timer-button",
                accessibilityLabel: actionState.accessibilityLabel,
                accessibilityHint: actionState.accessibilityHint
            )
        }
        .frame(minHeight: style.filmResultRowMinHeight, alignment: .top)
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
        HStack(alignment: .top, spacing: style.resultActionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Corrected Exposure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                CorrectedExposureDisplayBlock(
                    kind: correctedExposure.kind,
                    primaryText: correctedExposure.primaryText,
                    secondaryText: correctedExposure.secondaryText,
                    style: style
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: style.filmResultRowMinHeight, alignment: .topLeading)

            TimerActionView(
                canStartTimer: actionState.canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: "corrected-exposure-start-timer-button",
                accessibilityLabel: actionState.accessibilityLabel,
                accessibilityHint: actionState.accessibilityHint
            )
        }
    }
}

private struct CorrectedExposureDisplayBlock: View {
    let kind: FilmModeCorrectedExposureDisplayKind
    let primaryText: String
    let secondaryText: String
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(primaryText)
                .font(primaryFont)
                .foregroundStyle(primaryColor)
                .monospacedDigit()
                .lineLimit(kind == .quantified ? 1 : 2)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("film-mode-corrected-exposure-primary")

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(style.correctedExposureSecondaryFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("film-mode-corrected-exposure-secondary")
            }
        }
        .frame(maxWidth: .infinity, minHeight: style.correctedExposureValueMinHeight, alignment: .topLeading)
    }

    private var primaryFont: Font {
        switch kind {
        case .quantified:
            return style.correctedExposurePrimaryFont
        case .limitedGuidance, .unsupported, .noFilmSelected:
            return .headline.weight(.semibold)
        }
    }

    private var primaryColor: Color {
        switch kind {
        case .quantified:
            return .primary
        case .limitedGuidance:
            return Color(.systemOrange)
        case .unsupported:
            return Color(.systemRed)
        case .noFilmSelected:
            return .secondary
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
