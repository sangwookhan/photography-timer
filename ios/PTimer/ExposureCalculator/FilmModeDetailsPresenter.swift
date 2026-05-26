import Foundation

struct FilmModeDetailsPresenterInput {
    let bindingState: FilmModeReciprocityBindingState
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let filmModeExposureResultState: FilmModeExposureResultState?
    let formatDuration: (Double) -> String
    let formatDurationCoarse: (Double) -> String
    let formatAxisDuration: (Double) -> String
}

/// Orchestration-level presenter for the Film Details sheet.
///
/// Responsibility split:
/// - Vocabulary / badge / status / tone /
///   summary text live in `ReciprocityDetailsVocabularyPresenter`.
/// - The Reference / Source reference / Guidance boundary / Sources
///   sections live in `FilmModeDetailsReferencePresenter`.
/// - The formula graph (curve, viewport, current marker, source
///   markers, axis ticks, captions) lives in
///   `FilmModeDetailsGraphPresenter`.
/// - The legend block lives in `FilmModeDetailsLegendPresenter`.
///
/// This type composes those presenters into the
/// `FilmModeDetailsDisplayState` consumed by the view layer. It
/// owns no per-state wording or geometry of its own — it only
/// decides which collaborators contribute to a given binding state.
struct FilmModeDetailsPresenter {

    private let vocabulary: ReciprocityDetailsVocabularyPresenter
    private let reference: FilmModeDetailsReferencePresenter
    private let graph: FilmModeDetailsGraphPresenter
    private let legend: FilmModeDetailsLegendPresenter

    init(
        vocabulary: ReciprocityDetailsVocabularyPresenter = ReciprocityDetailsVocabularyPresenter(),
        reference: FilmModeDetailsReferencePresenter = FilmModeDetailsReferencePresenter(),
        graph: FilmModeDetailsGraphPresenter = FilmModeDetailsGraphPresenter(),
        legend: FilmModeDetailsLegendPresenter = FilmModeDetailsLegendPresenter()
    ) {
        self.vocabulary = vocabulary
        self.reference = reference
        self.graph = graph
        self.legend = legend
    }

    // MARK: - Public entry points

    func makeDetailsDisplayState(
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsDisplayState? {
        let bindingState = input.bindingState
        let sections = detailsSections(for: input)
        let graphState = graph.graphDisplayState(
            for: FilmModeDetailsGraphPresenter.Input(
                bindingState: bindingState,
                calculationResult: input.calculationResult,
                formatDuration: input.formatDuration
            )
        )
        // The legacy `guard !sections.isEmpty` is dropped now that
        // Profile/Formula metadata blocks no longer participate. The
        // sheet is still meaningful via the subtitle, the Current
        // Result block, and the optional graph even when neither
        // evidence nor source-provenance rows are available — e.g.
        // unofficial formula profiles with no published source.
        return FilmModeDetailsDisplayState(
            title: "Reciprocity Details",
            subtitle: filmIdentitySubtitle(for: bindingState),
            summary: detailsSummaryState(for: input),
            currentResult: currentResultState(for: input, graph: graphState),
            sections: sections,
            graph: graphState,
            legend: legend.legendDisplayState(for: bindingState.profile)
        )
    }

    func reciprocityStateDisplayState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeReciprocityStateDisplayState {
        vocabulary.reciprocityStateDisplayState(for: bindingState)
    }

    // MARK: - Sections

    private func detailsSections(
        for input: FilmModeDetailsPresenterInput
    ) -> [FilmModeDetailsSectionState] {
        let referenceInput = FilmModeDetailsReferencePresenter.Input(
            bindingState: input.bindingState,
            formatDuration: input.formatDuration,
            formatDurationCoarse: input.formatDurationCoarse
        )

        var sections: [FilmModeDetailsSectionState] = profileUsesFormula(input.bindingState.profile)
            ? reference.formulaSections(for: referenceInput)
            : reference.limitedGuidanceSections(for: referenceInput)

        // User-defined profile metadata lives in a dedicated
        // section so the top result card carries only the per-shot
        // output (Adjusted / Corrected / Status), matching the
        // preset Details hierarchy. Placed first among the
        // post-graph sections so the user reads the profile
        // identity before any (currently empty) Source / Guidance
        // subsections.
        if let customSection = vocabulary.customProfileSection(
            film: input.bindingState.film,
            profile: input.bindingState.profile
        ) {
            sections.insert(customSection, at: 0)
        }
        return sections
    }

    // MARK: - Summary

    private func detailsSummaryState(
        for input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsSummaryState {
        let bindingState = input.bindingState
        let stateDisplay = vocabulary.reciprocityStateDisplayState(for: bindingState)
        return FilmModeDetailsSummaryState(
            badgeText: stateDisplay.badgeText,
            tone: stateDisplay.tone,
            summaryText: vocabulary.summaryText(
                for: bindingState,
                calculationResult: input.calculationResult,
                formatDurationCoarse: input.formatDurationCoarse
            ),
            detailText: vocabulary.summaryDetailText(for: bindingState)
        )
    }

    // MARK: - Current result

    private func currentResultState(
        for input: FilmModeDetailsPresenterInput,
        graph: FilmModeDetailsGraphDisplayState?
    ) -> FilmModeDetailsCurrentResultState {
        let statusText = vocabulary.statusText(for: input.bindingState, graph: graph)
        let statusTone = vocabulary.tone(for: input.bindingState.presentation.badgeStyle)

        guard let filmModeExposureResultState = input.filmModeExposureResultState else {
            return FilmModeDetailsCurrentResultState(
                layout: .comparison,
                adjustedShutter: FilmModeDetailsCurrentResultValueState(
                    title: "Adjusted Shutter",
                    valueText: "Unavailable",
                    detailText: nil,
                    emphasizesValue: false
                ),
                correctedExposure: FilmModeDetailsCurrentResultValueState(
                    title: "Corrected Exposure",
                    valueText: "Unavailable",
                    detailText: nil,
                    emphasizesValue: false
                ),
                statusText: statusText,
                statusTone: statusTone
            )
        }

        // Every case uses the same comparison-card layout so the
        // user reads Adjusted / Corrected / Status in one shape.
        let correctedExposureNoteText = vocabulary.correctedExposureDetailText(
            for: filmModeExposureResultState.correctedExposure
        )

        return FilmModeDetailsCurrentResultState(
            layout: .comparison,
            adjustedShutter: FilmModeDetailsCurrentResultValueState(
                title: "Adjusted Shutter",
                valueText: input.formatDurationCoarse(
                    filmModeExposureResultState.adjustedShutterSeconds
                ),
                detailText: nil,
                emphasizesValue: false
            ),
            correctedExposure: FilmModeDetailsCurrentResultValueState(
                title: "Corrected Exposure",
                valueText: filmModeExposureResultState.correctedExposure.correctedExposureSeconds
                    .map { input.formatDurationCoarse($0) }
                    ?? filmModeExposureResultState.correctedExposure.primaryText,
                detailText: correctedExposureNoteText,
                emphasizesValue: filmModeExposureResultState.correctedExposure.usesNumericExposure
            ),
            statusText: statusText,
            statusTone: statusTone
        )
    }

    // MARK: - Subtitle

    private func filmIdentitySubtitle(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        let trimmedName = bindingState.film.canonicalStockName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        if let label = vocabulary.subtitleAuthorityLabel(for: bindingState.profile.source.authority) {
            return "\(trimmedName) · \(label)"
        }
        return trimmedName
    }

    // MARK: - Helpers

    private func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        })
    }
}
