import Foundation
import Observation

/// `ReciprocityModel` carries the *reciprocity policy* responsibility
/// extracted from the legacy `ExposureCalculatorViewModel` monolith as
/// the second step of B1 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`).
///
/// PR2 of 6 — pure facade. The model owns the two collaborators that
/// previously lived directly on the ViewModel:
/// - `ReciprocityCalculationPolicyEvaluator` (policy evaluation entry)
/// - `FilmModeDetailsPresenter` (A8 details display-state transform)
///
/// Per spec §3.1 row "ReciprocityModel" the model carries **no stored
/// business state**: it exposes evaluation entry points only. Cached
/// binding state stays on the ViewModel for now and migrates with PR4
/// (`FilmSelectionModel`), which owns the active film identity that
/// feeds the binding.
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
    /// declines to surface any sections (matches the pre-decomposition
    /// behavior).
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
            return FilmModeCorrectedExposureDisplayState(
                kind: .quantified,
                correctedExposureSeconds: correctedExposureSeconds,
                primaryText: formatReciprocityDurationCoarse(correctedExposureSeconds),
                secondaryText: "",
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
    /// button. A non-nil quantified corrected exposure with a positive
    /// value enables the timer; everything else returns a disabled state
    /// with a category-specific accessibility hint.
    func correctedExposureActionState(
        for bindingState: FilmModeReciprocityBindingState?
    ) -> FilmModeTimerActionState {
        guard let bindingState else {
            return FilmModeTimerActionState(
                targetSeconds: nil,
                canStartTimer: false,
                accessibilityLabel: "Start timer from corrected exposure",
                accessibilityHint: "Timer unavailable because no film-specific corrected exposure is available"
            )
        }

        let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds

        if let correctedExposureSeconds, correctedExposureSeconds > 0 {
            return FilmModeTimerActionState(
                targetSeconds: correctedExposureSeconds,
                canStartTimer: true,
                accessibilityLabel: "Start timer from corrected exposure",
                accessibilityHint: "Starts a timer using the film-specific corrected exposure value"
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
