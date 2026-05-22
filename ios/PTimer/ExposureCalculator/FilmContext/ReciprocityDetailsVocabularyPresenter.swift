import Foundation

/// Pure presenter for the Film Details vocabulary surface: badge text,
/// tone mapping, summary text, summary detail text, status text, and
/// the guidance-explanation fallback. Splitting these out of
/// `FilmModeDetailsPresenter` keeps the per-state wording (no
/// correction / formula-derived / limited guidance / beyond source
/// range / outside guidance / unofficial caveat) in one place so a
/// new film or profile cannot drift the user-facing copy across
/// surfaces.
struct ReciprocityDetailsVocabularyPresenter {

    // MARK: - Reciprocity state

    /// Top-level reciprocity state used by both the Main film row
    /// badge chip and the Details summary block.
    func reciprocityStateDisplayState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeReciprocityStateDisplayState {
        FilmModeReciprocityStateDisplayState(
            badgeText: badgeText(for: bindingState),
            tone: tone(for: bindingState.presentation.badgeStyle),
            infoText: guidanceExplanation(for: bindingState.presentation),
            showsInfoAffordance: true
        )
    }

    /// Both Main (reciprocity badge chip) and Detail (Current Result
    /// status line) read from the same wording set so the same
    /// calculation state never produces two different labels across
    /// surfaces.
    func badgeText(for bindingState: FilmModeReciprocityBindingState) -> String {
        switch bindingState.presentation.category {
        case .noCorrection:
            return "No correction"
        case .formulaDerived:
            return "Formula-derived"
        case .limitedGuidance:
            return "No quantified prediction"
        case .unsupported:
            // Converted formula profiles (formula + source evidence)
            // surface as "Beyond source range" — the canonical wording
            // shared with the Detail status line.
            if bindingState.profile.isConvertedFormulaProfile {
                return "Beyond source range"
            }
            return bindingState.policyResult.correctedExposureSeconds != nil
                ? "Outside guidance"
                : "No corrected value"
        }
    }

    func tone(for badgeStyle: ReciprocityConfidenceBadgeStyle) -> FilmModeReciprocityStateTone {
        switch badgeStyle {
        case .trusted:
            return .trusted
        case .measured:
            return .measured
        case .caution:
            return .caution
        case .limitedGuidance:
            return .limitedGuidance
        case .unsupported:
            return .unsupported
        }
    }

    // MARK: - Summary

    func summaryText(
        for bindingState: FilmModeReciprocityBindingState,
        calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>,
        formatDurationCoarse: (Double) -> String
    ) -> String {
        let metadata = bindingState.policyResult.metadata

        switch metadata.basis {
        case .officialThresholdNoCorrection:
            if case .success(let result) = calculationResult {
                return "No correction at \(formatDurationCoarse(result.resultShutterSeconds))"
            }
            return "No correction in the supported range"
        case .formulaDerived:
            return "Formula-based correction on the active curve"
        case .limitedGuidanceNoQuantifiedPrediction:
            return "Beyond published no-correction range"
        case .unsupportedOutOfPolicyRange:
            return bindingState.profile.isConvertedFormulaProfile
                ? "Beyond source range"
                : "Outside supported reciprocity range"
        }
    }

    func summaryDetailText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        // Unofficial profiles must lead with their authority caveat —
        // the user has to recognize "Not a Kodak-published profile"
        // before trusting the prediction. The caveat takes precedence
        // over the per-state copy below so a formula-derived numeric
        // result does not read like manufacturer guidance just because
        // the calculation produced a value.
        if bindingState.profile.source.authority == .unofficial,
           let caveat = unofficialProfileAuthorityCaveat(for: bindingState.profile) {
            return caveat
        }

        switch bindingState.presentation.category {
        case .unsupported:
            if bindingState.policyResult.correctedExposureSeconds != nil {
                if bindingState.profile.isConvertedFormulaProfile {
                    return "Current input is beyond the manufacturer source range. The corrected value is a formula prediction past the published reference."
                }
                return "Current input is outside manufacturer guidance. The corrected value is a formula prediction outside the supported range."
            }
            return "Current input is outside the supported range and no quantified corrected point is available."
        case .limitedGuidance:
            return "No official quantified prediction is available beyond this range."
        case .noCorrection, .formulaDerived:
            return nil
        }
    }

    /// First non-empty profile-level note for an unofficial-authority
    /// profile (e.g. Portra 400 unofficial's "Unofficial practical
    /// approximation. Not a Kodak-published profile."). Used as the
    /// Details summary detail line so the lower-authority warning is
    /// visible right under the badge without depending on the
    /// calculation state.
    func unofficialProfileAuthorityCaveat(for profile: ReciprocityProfile) -> String? {
        for note in profile.notes {
            if let normalized = normalizedDetailText(note) {
                return normalized
            }
        }
        return nil
    }

    // MARK: - Subtitle authority label

    /// Authority label rendered under the film name in the Details
    /// subtitle. Reuses the same wording the main film row produces so
    /// the user never sees one label on the row and a different label
    /// for the same profile in the Details sheet. Details adds the
    /// "User-defined" fallback that the main row deliberately suppresses.
    func subtitleAuthorityLabel(for authority: ReciprocityAuthority) -> String? {
        if let alignedLabel = FilmSelectionModel.filmRowAuthorityLabel(forAuthority: authority) {
            return alignedLabel
        }
        switch authority {
        case .userDefined:
            return "User-defined"
        case .official, .unofficial, .unknown:
            return nil
        }
    }

    // MARK: - Status text

    /// Short fixed-vocabulary status text used by the Current Result
    /// block. Reuses the Main badge wording so the same calculation
    /// state never reads differently across surfaces.
    ///
    /// Status describes the calculation/policy state only. The
    /// visible-graph-range condition is a viewport affordance — the
    /// orange edge triangle and the graph description line already
    /// communicate that the current value sits outside the visible
    /// domain. For every formula-backed profile (converted formula
    /// profiles like Provia 100F *and* unofficial practical formula
    /// profiles like Portra 400 unofficial), the status text stays
    /// anchored to the calculation basis (e.g. "Formula-derived",
    /// "Beyond source range") so an unofficial-formula result is not
    /// silently relabeled as a viewport state when its corrected
    /// exposure overflows the graph's t3 ceiling. Non-formula (Kodak
    /// limited-guidance) profiles do not render a graph at all
    /// (`FilmDetailsGraphKindInvariantTests`), so the visible-range
    /// branch never fires for them — the early-return below only
    /// matters as a defensive guard against future profile shapes.
    func statusText(
        for bindingState: FilmModeReciprocityBindingState,
        graph: FilmModeDetailsGraphDisplayState?
    ) -> String {
        if !profileUsesFormula(bindingState.profile) {
            if graph?.isBeyondVisibleRange == true {
                return "Beyond visible graph range"
            }
            if graph?.isBelowVisibleRange == true {
                return "Below visible graph range"
            }
        }
        return badgeText(for: bindingState)
    }

    // MARK: - Corrected exposure note

    /// Detail text rendered under the Corrected Exposure value when
    /// the value is non-numeric (limited-guidance / unsupported /
    /// no-film). Numeric values render without a note.
    func correctedExposureDetailText(
        for correctedExposure: FilmModeCorrectedExposureDisplayState
    ) -> String? {
        guard !correctedExposure.usesNumericExposure else {
            return nil
        }

        switch correctedExposure.kind {
        case .noFilmSelected:
            return correctedExposure.secondaryText
        case .quantified:
            return correctedExposure.secondaryText
        case .limitedGuidance:
            return correctedExposure.secondaryText
        case .unsupported:
            return correctedExposure.secondaryText
        }
    }

    // MARK: - Guidance explanation fallback

    func guidanceExplanation(for presentation: ReciprocityConfidencePresentation) -> String {
        let explanation = presentation.supportingNotes.first ?? presentation.defaultExplanation
        let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedExplanation.isEmpty else {
            return "See reciprocity guidance"
        }

        return trimmedExplanation
    }

    // MARK: - Helpers

    private func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        })
    }

    private func normalizedDetailText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
