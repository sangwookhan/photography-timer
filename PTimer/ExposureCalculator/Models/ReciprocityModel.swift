import Foundation
import Observation

/// `ReciprocityModel` is a pure facade over the reciprocity policy
/// evaluator and the film-mode details presenter. It owns no stored
/// business state and exposes evaluation entry points plus reciprocity
/// presentation transforms (badge state, corrected-exposure display
/// state, timer-action state, and reciprocity-duration formatting).
@MainActor
@Observable
final class ReciprocityModel {
    private let evaluator: ReciprocityCalculationPolicyEvaluator
    private let detailsPresenter: FilmModeDetailsPresenter

    init(
        evaluator: ReciprocityCalculationPolicyEvaluator = ReciprocityCalculationPolicyEvaluator(),
        detailsPresenter: FilmModeDetailsPresenter = FilmModeDetailsPresenter()
    ) {
        self.evaluator = evaluator
        self.detailsPresenter = detailsPresenter
    }

    /// Pure transform: given a reciprocity profile and the metered
    /// exposure (calculator output that drives reciprocity), produce
    /// the reciprocity policy result.
    func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityResult {
        evaluator.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    /// Pure transform: given the full presenter input bundle, produce
    /// the details display state. Returns nil when the presenter
    /// declines to surface any sections (the helper returns nil in that
    /// case).
    func makeDetailsDisplayState(
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsDisplayState? {
        detailsPresenter.makeDetailsDisplayState(input: input)
    }

    /// Pure transform: produce the reciprocity-state badge/info display
    /// state for a given binding state.
    func reciprocityStateDisplayState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeReciprocityStateDisplayState {
        detailsPresenter.reciprocityStateDisplayState(for: bindingState)
    }

    // MARK: - Reciprocity duration formatting
    //
    // Pure value transforms with no model state. Formats reciprocity
    // exposure values for the corrected-exposure card, the details
    // sheet, and graph axis labels. Lives on the model because every
    // caller is a reciprocity-presentation site.

    /// Formats a reciprocity exposure for the corrected-exposure card
    /// and the details summary. Sub-second values render with up to
    /// three decimals; up to ten seconds render with one decimal; tens
    /// of seconds round to integers; minutes-and-above use a clock
    /// notation, with days surfaced when the value crosses 24 hours.
    func formatReciprocityDuration(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)

        if safeSeconds < 1 {
            return "\(trimmedReciprocitySubsecondText(safeSeconds))s"
        }

        if safeSeconds < 10 {
            return "\(formatReciprocityNumber(safeSeconds, maximumFractionDigits: 1))s"
        }

        let roundedSeconds = Int(safeSeconds.rounded())

        if roundedSeconds < 60 {
            return "\(roundedSeconds)s"
        }

        let secondsPerMinute = 60
        let secondsPerHour = 60 * secondsPerMinute
        let secondsPerDay = 24 * secondsPerHour

        let days = roundedSeconds / secondsPerDay
        let hours = (roundedSeconds % secondsPerDay) / secondsPerHour
        let minutes = (roundedSeconds % secondsPerHour) / secondsPerMinute
        let seconds = roundedSeconds % secondsPerMinute

        if days > 0 {
            return "\(days)d \(String(format: "%02d:%02d:%02d", hours, minutes, seconds))"
        }

        if roundedSeconds >= secondsPerHour {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Coarse variant used by the corrected-exposure summary card,
    /// where multi-day values collapse to "N,NNNd" with thousands
    /// separators rather than a clock notation.
    func formatReciprocityDurationCoarse(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)
        let roundedSeconds = Int(safeSeconds.rounded())
        let secondsPerDay = 86_400

        guard roundedSeconds >= secondsPerDay else {
            return formatReciprocityDuration(safeSeconds)
        }

        let days = roundedSeconds / secondsPerDay
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return (formatter.string(from: NSNumber(value: days)) ?? "\(days)") + "d"
    }

    /// Tight, axis-friendly variant. Sub-second values keep one decimal,
    /// tens of seconds round to integers, minutes/hours/days use a
    /// single-letter suffix.
    func formatReciprocityAxisDuration(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)

        if safeSeconds < 1 {
            return "\(formatReciprocityNumber(safeSeconds, maximumFractionDigits: 1))s"
        }

        if safeSeconds < 120 {
            return "\(Int(safeSeconds.rounded()))s"
        }

        let roundedSeconds = Int(safeSeconds.rounded())
        let minutes = roundedSeconds / 60
        if roundedSeconds < 3600 {
            return "\(minutes)m"
        }

        let hours = roundedSeconds / 3600
        if roundedSeconds < 86_400 {
            return "\(hours)h"
        }

        let days = roundedSeconds / 86_400
        return "\(days)d"
    }

    private func trimmedReciprocitySubsecondText(_ seconds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.minimumFractionDigits = seconds == 0 ? 0 : 1
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: seconds)) ?? "0"
    }

    private func formatReciprocityNumber(
        _ value: Double,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    // MARK: - Corrected-exposure display

    /// Pure transform: given the current binding state (or nil when no
    /// film is selected / calculation has no success result), produce
    /// the corrected-exposure card display state. Branches on the
    /// reciprocity result form: quantified produces a numeric primary
    /// text via `formatReciprocityDurationCoarse`; advisory and
    /// unsupported forms fall back to guidance text drawn from the
    /// confidence presentation's supporting notes.
    func correctedExposureDisplayState(
        for bindingState: FilmModeReciprocityBindingState?
    ) -> FilmModeCorrectedExposureDisplayState {
        guard let bindingState else {
            return FilmModeCorrectedExposureDisplayState(
                kind: .noFilmSelected,
                correctedExposureSeconds: nil,
                primaryText: "No film selected",
                secondaryText: "Select a preset film",
                usesNumericExposure: false
            )
        }

        if let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds {
            // Outside-guidance numeric results prefix the value with
            // "≈" and add an outside-guidance caption so the user
            // reads them as approximate rather than as published
            // manufacturer guidance.
            let isOutsideManufacturerGuidance = bindingState.presentation.category == .unsupported
            let formattedDuration = formatReciprocityDurationCoarse(correctedExposureSeconds)
            return FilmModeCorrectedExposureDisplayState(
                kind: .quantified,
                correctedExposureSeconds: correctedExposureSeconds,
                primaryText: isOutsideManufacturerGuidance ? "≈\(formattedDuration)" : formattedDuration,
                secondaryText: isOutsideManufacturerGuidance
                    ? "Outside manufacturer guidance — extrapolated from the formula curve."
                    : "",
                usesNumericExposure: true
            )
        }

        switch bindingState.presentation.category {
        case .advisoryOnly:
            return FilmModeCorrectedExposureDisplayState(
                kind: .advisory,
                correctedExposureSeconds: nil,
                primaryText: "No corrected value",
                secondaryText: "No published quantified correction is available for this metered exposure.",
                usesNumericExposure: false
            )
        case .unsupported:
            return FilmModeCorrectedExposureDisplayState(
                kind: .unsupported,
                correctedExposureSeconds: nil,
                primaryText: "Unavailable",
                secondaryText: reciprocityGuidanceExplanation(for: bindingState.presentation),
                usesNumericExposure: false
            )
        case .exact, .estimated, .extrapolated:
            // A quantified path should have provided a corrected exposure.
            return FilmModeCorrectedExposureDisplayState(
                kind: .advisory,
                correctedExposureSeconds: nil,
                primaryText: "No quantified correction",
                secondaryText: reciprocityGuidanceExplanation(for: bindingState.presentation),
                usesNumericExposure: false
            )
        }
    }

    /// Pure transform: given the current binding state (or nil), produce
    /// the timer-action state for the corrected-exposure Start Timer
    /// button. A non-nil corrected exposure with a positive value
    /// enables the timer — including the formula-extrapolated unsupported
    /// path, where the action state additionally flags itself as
    /// outside manufacturer guidance so the button can render with a
    /// warning treatment without losing the start affordance.
    func correctedExposureActionState(
        for bindingState: FilmModeReciprocityBindingState?
    ) -> FilmModeTimerActionState {
        guard let bindingState else {
            return FilmModeTimerActionState(
                targetSeconds: nil,
                canStartTimer: false,
                isOutsideManufacturerGuidance: false,
                accessibilityLabel: "Start timer from corrected exposure",
                accessibilityHint: "Timer unavailable because no film-specific corrected exposure is available"
            )
        }

        let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds
        let isOutsideManufacturerGuidance = bindingState.presentation.category == .unsupported

        if let correctedExposureSeconds, correctedExposureSeconds > 0 {
            let hint = isOutsideManufacturerGuidance
                ? "Starts a timer using a formula-extrapolated corrected exposure outside manufacturer guidance"
                : "Starts a timer using the film-specific corrected exposure value"

            return FilmModeTimerActionState(
                targetSeconds: correctedExposureSeconds,
                canStartTimer: true,
                isOutsideManufacturerGuidance: isOutsideManufacturerGuidance,
                accessibilityLabel: "Start timer from corrected exposure",
                accessibilityHint: hint
            )
        }

        let disabledHint: String
        switch bindingState.presentation.category {
        case .advisoryOnly:
            disabledHint = "Timer unavailable because this corrected result is non-quantified"
        case .unsupported:
            disabledHint = "Timer unavailable because this corrected result is unsupported"
        default:
            disabledHint = "Timer unavailable because no quantified corrected exposure is available"
        }

        return FilmModeTimerActionState(
            targetSeconds: nil,
            canStartTimer: false,
            isOutsideManufacturerGuidance: false,
            accessibilityLabel: "Start timer from corrected exposure",
            accessibilityHint: disabledHint
        )
    }

    private func reciprocityGuidanceExplanation(
        for presentation: ReciprocityConfidencePresentation
    ) -> String {
        let explanation = presentation.supportingNotes.first ?? presentation.defaultExplanation
        let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedExplanation.isEmpty else {
            return "See reciprocity guidance"
        }

        return trimmedExplanation
    }
}
