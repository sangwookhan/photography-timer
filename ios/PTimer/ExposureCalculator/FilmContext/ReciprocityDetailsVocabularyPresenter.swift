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
            tone: tone(for: bindingState),
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
            // Photographer-authored profiles read as "Custom formula"
            // (method/authority wording) so the badge does not look
            // like the warning copy used for official profiles.
            if bindingState.profile.source.authority == .userDefined {
                return "Custom formula"
            }
            // The official log-log table model is table-derived, not a
            // closed-form formula (PTIMER-159).
            if bindingState.policyResult.metadata.basis == .tableLogLogDerived {
                return "Table-derived"
            }
            return "Formula-derived"
        case .limitedGuidance:
            return "No quantified prediction"
        case .unsupported:
            // Source-range-backed profiles (converted formula + source
            // evidence, or the log-log table model) surface as "Beyond
            // source range" — the canonical wording shared with the
            // Detail status line.
            if bindingState.profile.presentsBeyondSourceRange
                || bindingState.profile.source.authority == .userDefined {
                return "Beyond source range"
            }
            return bindingState.policyResult.correctedExposureSeconds != nil
                ? "Outside guidance"
                : "No corrected value"
        }
    }

    /// Tone mapping used by the Main badge chip and the Detail
    /// status line. The base mapping comes from the
    /// presentation's `badgeStyle`, but a custom (userDefined)
    /// formula in its normal source range is downgraded from
    /// `.caution` (orange) to `.measured` (blue) so the user does
    /// not see a warning treatment for normal custom-profile use.
    /// Beyond-source-range or other unsupported states keep their
    /// stronger tone.
    func tone(for bindingState: FilmModeReciprocityBindingState) -> FilmModeReciprocityStateTone {
        let baseTone = tone(for: bindingState.presentation.badgeStyle)
        guard bindingState.profile.source.authority == .userDefined,
              bindingState.presentation.category == .formulaDerived,
              baseTone == .caution else {
            return baseTone
        }
        return .measured
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
        case .tableLogLogDerived:
            return "Log-log interpolation of the official table"
        case .limitedGuidanceNoQuantifiedPrediction:
            return "Beyond published no-correction range"
        case .unsupportedOutOfPolicyRange:
            return bindingState.profile.presentsBeyondSourceRange
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
        // Custom (user-defined) profiles render their provenance
        // as a dedicated section *below* the graph (see
        // `FilmModeDetailsPresenter.customProfileSection`), not as
        // detail text in the top result card. The top card stays
        // focused on adjusted shutter / corrected exposure /
        // status, matching the preset Details hierarchy.
        if bindingState.profile.source.authority == .userDefined {
            return nil
        }

        switch bindingState.presentation.category {
        case .unsupported:
            if bindingState.policyResult.correctedExposureSeconds != nil {
                if bindingState.profile.usesTableInterpolation {
                    return "Current input is beyond the published source table. The corrected value is extrapolated past the official anchors."
                }
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

    // MARK: - Custom provenance

    /// Structured provenance section for a `.userDefined`-
    /// authority profile. Renders below the graph as a regular
    /// Details section card (one row per fact) so the top result
    /// card stays focused on Adjusted / Corrected / Status,
    /// matching the preset Details hierarchy.
    ///
    /// Returns `nil` for non-userDefined profiles or when nothing
    /// useful can be derived (e.g. a malformed custom profile).
    func customProfileSection(
        film: FilmIdentity,
        profile: ReciprocityProfile
    ) -> FilmModeDetailsSectionState? {
        guard profile.source.authority == .userDefined else { return nil }

        // The formula itself is already shown as the Reciprocity
        // Graph title (the canonical display position for a custom
        // profile's formula). Repeating it as a row here would
        // print the same expression twice on the Details sheet, so
        // this section carries only the surrounding provenance —
        // Source / Range / Notes / Reference URL — that the graph
        // does not already convey.
        var rows: [FilmModeDetailsRowState] = []
        if let sourceType = profile.userMetadata?.customSourceType
            ?? film.userMetadata?.customSourceType {
            rows.append(FilmModeDetailsRowState(
                title: "Source",
                value: sourceType.displayLabel
            ))
        }
        let rangeLines = customRangeLines(profile: profile)
        if !rangeLines.isEmpty {
            rows.append(FilmModeDetailsRowState(
                title: "Range",
                value: rangeLines.joined(separator: "\n")
            ))
        }
        let trimmedNotes = collectedCustomNotes(film: film, profile: profile)
        if !trimmedNotes.isEmpty {
            rows.append(FilmModeDetailsRowState(
                title: "Notes",
                value: trimmedNotes.joined(separator: "\n")
            ))
        }
        if let urlString = profile.userMetadata?.referenceURL
            ?? film.userMetadata?.referenceURL,
           !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let destination = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
            rows.append(FilmModeDetailsRowState(
                title: "Reference",
                value: urlString,
                destinationURL: destination
            ))
        }
        guard !rows.isEmpty else { return nil }
        return FilmModeDetailsSectionState(title: "Custom profile", rows: rows)
    }

    private func collectedCustomNotes(
        film: FilmIdentity,
        profile: ReciprocityProfile
    ) -> [String] {
        let profileNotes = profile.userMetadata?.notes ?? []
        let filmNotes = film.userMetadata?.notes ?? []
        return (profileNotes + filmNotes).compactMap { note in
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Multi-line summary for a `.userDefined`-authority profile.
    /// Each line is a single fact (source type, formula, range,
    /// note) so the Details sheet renders a scannable provenance
    /// block. Returns `nil` only when nothing useful can be
    /// derived — the caller falls back to the per-state copy.
    ///
    /// Remains available for timer identity snapshots and tests
    /// but is no longer rendered in the Details sheet's top
    /// card — see `customProfileSection` for the in-sheet
    /// rendering.
    func customProvenanceText(
        film: FilmIdentity,
        profile: ReciprocityProfile
    ) -> String? {
        var lines: [String] = []
        if let sourceType = profile.userMetadata?.customSourceType
            ?? film.userMetadata?.customSourceType {
            lines.append("Source: \(sourceType.displayLabel)")
        }
        if let formulaText = TimerStartComposer.customProfileFormulaText(profile: profile) {
            lines.append("Formula: \(formulaText)")
        }
        // The new wording reads as standalone facts ("No correction
        // through 1s", "Source range through 4m"), so they are
        // appended directly without a "Range:" prefix — each line
        // already names the concept it carries.
        lines.append(contentsOf: customRangeLines(profile: profile))
        let profileNotes = profile.userMetadata?.notes ?? []
        let filmNotes = film.userMetadata?.notes ?? []
        for note in (profileNotes + filmNotes) {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(trimmed)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Two-line Range wording for the custom-profile Details
    /// section. Returns each line as a standalone fact so the view
    /// can either join them with a newline (Details Range row) or
    /// append them directly to a wider provenance summary
    /// (`customProvenanceText`). Empty when no formula or threshold
    /// rule supplies a no-correction boundary.
    ///
    /// Wording:
    /// - `No correction through 1s`
    /// - `Source range through 4m`  (finite source range), or
    /// - `Source range unlimited`   (formula extrapolates upward
    ///   without bound)
    func customRangeLines(profile: ReciprocityProfile) -> [String] {
        // The shared formula carries the no-correction and
        // source-range boundaries on itself. Prefer the formula's
        // fields; fall back to a threshold rule only when one is
        // present (some preset shapes may surface through this
        // branch).
        let formulaRule = profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            if case .formula(let f) = rule { return f }
            return nil
        }.first
        let thresholdMax = profile.rules.compactMap { rule -> Double? in
            if case .threshold(let t) = rule { return t.noCorrectionRange.maximumSeconds }
            return nil
        }.first
        let noCorrection = formulaRule?.formula.noCorrectionThroughSeconds ?? thresholdMax
        guard let noCorrection else { return [] }

        var lines: [String] = []
        lines.append("No correction through \(Self.formatSeconds(noCorrection))")
        if let sourceRangeThrough = formulaRule?.formula.sourceRangeThroughSeconds {
            lines.append("Source range through \(Self.formatSeconds(sourceRangeThrough))")
        } else if formulaRule != nil {
            // Formula profiles without a finite source range
            // extrapolate without bound — the Details surface
            // should still surface this fact so the user reads the
            // confidence boundary rather than its absence.
            lines.append("Source range unlimited")
        }
        return lines
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            if minutes == minutes.rounded() {
                return "\(Int(minutes))m"
            }
            return String(format: "%.1fm", minutes)
        }
        if seconds == seconds.rounded() {
            return "\(Int(seconds))s"
        }
        return String(format: "%.1fs", seconds)
    }

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
