import Foundation
import PTimerCore
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

    /// Coarse variant used by the corrected-exposure summary card on
    /// both Main and Detail surfaces. Sub-day values fall through to
    /// the fine formatter; longer values coarsen so the user reads
    /// "≈1mo" instead of "30d" and "≈68y" instead of "24,855d".
    ///
    /// Bucket layout:
    /// - `< 1 d` → fine formatter (sub-second / clock notation / `Nd HH:MM:SS`)
    /// - `1 d–29 d` → `"<N>d"`
    /// - `30 d–364 d` → `"≈<N>mo"` or `"≈<N>mo <R>d"`
    /// - `365 d+` → `"≈<N>y"` (year-only; raw day counts never resurface)
    ///
    /// The month/year buckets use 30-day months and 365-day years as
    /// fixed approximations and prefix the value with `≈` because
    /// month and year boundaries are not aligned to calendar months.
    func formatReciprocityDurationCoarse(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)
        let roundedSeconds = Int(safeSeconds.rounded())
        let secondsPerDay = 86_400

        guard roundedSeconds >= secondsPerDay else {
            return formatReciprocityDuration(safeSeconds)
        }

        let days = roundedSeconds / secondsPerDay

        if days >= 365 {
            let years = days / 365
            return "≈\(years)y"
        }

        if days >= 30 {
            let months = days / 30
            let remainderDays = days - months * 30
            if remainderDays == 0 {
                return "≈\(months)mo"
            }
            return "≈\(months)mo \(remainderDays)d"
        }

        return "\(days)d"
    }

    /// Secondary "seconds" string for the dual-duration display
    /// (PTIMER-172). The Main and Detail film-mode cards render a
    /// clock value (e.g. `24:40`, `02:29:43`) as the primary; this
    /// produces the matching whole-seconds value (`1480s`, `8983s`)
    /// so a long exposure can be compared against manufacturer source
    /// rows, which are usually written in seconds (`90s`, `1800s`, …).
    ///
    /// Returns `nil` below one minute — where the primary already
    /// reads as concise seconds, so a second seconds value would be
    /// redundant — and at one day and above, where the primary leaves
    /// clock notation for the coarse `Nd` / `≈Nmo` / `≈Ny` buckets and
    /// a raw seconds count is no longer a useful source-table
    /// comparison. Whole-second rounding matches the clock primary,
    /// which also rounds to whole seconds at this scale. `approximate`
    /// carries the primary's `≈` marker onto the seconds value when the
    /// primary is approximate (outside-guidance numeric results).
    func formatReciprocitySecondsComparison(
        _ seconds: TimeInterval,
        approximate: Bool
    ) -> String? {
        let safeSeconds = max(seconds, 0)
        let roundedSeconds = Int(safeSeconds.rounded())
        let secondsPerDay = 86_400

        guard roundedSeconds >= 60, roundedSeconds < secondsPerDay else {
            return nil
        }

        return approximate ? "≈\(roundedSeconds)s" : "\(roundedSeconds)s"
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
    /// text via `formatReciprocityDurationCoarse`; limited-guidance
    /// and unsupported forms fall back to guidance text drawn from the
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
            // Outside-guidance numeric results render as approximate
            // ("≈") so the user reads them differently from published
            // manufacturer guidance. The coarse formatter may have
            // already prefixed the value with "≈" (month/year
            // coarsening), so guard against doubling the marker.
            let isOutsideManufacturerGuidance = bindingState.presentation.category == .unsupported
            let formattedDuration = formatReciprocityDurationCoarse(correctedExposureSeconds)
            let primaryText: String
            if isOutsideManufacturerGuidance, !formattedDuration.hasPrefix("≈") {
                primaryText = "≈\(formattedDuration)"
            } else {
                primaryText = formattedDuration
            }
            // PTIMER-172: when the primary reads as a clock value
            // (one minute up to one day), the result row carries the
            // matching whole-seconds value as a subdued same-row seconds
            // comparison so the exposure can be compared against
            // source-table rows written in seconds. Below one minute the
            // primary already
            // reads as concise seconds and the helper returns `nil`, so
            // `secondaryText` stays empty. The approximation marker
            // tracks the primary so an `≈01:47:03` reads `≈6423s`.
            let secondaryText = formatReciprocitySecondsComparison(
                correctedExposureSeconds,
                approximate: primaryText.hasPrefix("≈")
            ) ?? ""
            return FilmModeCorrectedExposureDisplayState(
                kind: .quantified,
                correctedExposureSeconds: correctedExposureSeconds,
                primaryText: primaryText,
                secondaryText: secondaryText,
                usesNumericExposure: true
            )
        }

        switch bindingState.presentation.category {
        case .limitedGuidance:
            return FilmModeCorrectedExposureDisplayState(
                kind: .limitedGuidance,
                correctedExposureSeconds: nil,
                primaryText: "No corrected value",
                secondaryText: "No official quantified prediction is available for this metered exposure.",
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
        case .noCorrection, .formulaDerived:
            // A quantified path should have provided a corrected exposure.
            return FilmModeCorrectedExposureDisplayState(
                kind: .limitedGuidance,
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
    /// enables the timer — including the unsupported path that carries
    /// a formula prediction outside the source range, where the action
    /// state additionally flags itself as outside manufacturer guidance
    /// so the button can render with a warning treatment without losing
    /// the start affordance.
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
            let outsideGuidanceHint: String
            if bindingState.profile.usesTableInterpolation {
                outsideGuidanceHint = "Starts a timer using a value extrapolated beyond the published source table"
            } else if bindingState.profile.isConvertedFormulaProfile {
                outsideGuidanceHint = "Starts a timer using a formula prediction beyond the manufacturer source range"
            } else {
                outsideGuidanceHint = "Starts a timer using a formula prediction outside the supported range"
            }
            let hint = isOutsideManufacturerGuidance
                ? outsideGuidanceHint
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
        case .limitedGuidance:
            disabledHint = "Timer unavailable because this corrected result is non-quantified"
        case .unsupported:
            disabledHint = "Timer unavailable because this corrected result is unsupported"
        case .noCorrection, .formulaDerived:
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
