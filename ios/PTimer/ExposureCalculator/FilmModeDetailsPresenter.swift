import Foundation

struct FilmModeDetailsPresenterInput {
    let bindingState: FilmModeReciprocityBindingState
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let filmModeExposureResultState: FilmModeExposureResultState?
    /// Profile/model picker state owned by the view model. `nil` for
    /// single-profile films so no picker renders (PTIMER-159).
    let modelSelection: FilmModeDetailsModelSelectionState?
    let formatDuration: (Double) -> String
    let formatDurationCoarse: (Double) -> String
    let formatAxisDuration: (Double) -> String
    /// Whole-seconds source-table comparison for a clock-band value
    /// (PTIMER-172). Returns `nil` outside the clock band (below one
    /// minute, one day and above), where no secondary seconds value is
    /// shown. Defaults to a no-op so call sites that predate the
    /// dual-duration display (presenter unit tests) compile unchanged.
    let formatSecondsComparison: (Double) -> String?

    /// `modelSelection` and `formatSecondsComparison` carry defaults so
    /// call sites that predate the PTIMER-159 picker and the PTIMER-172
    /// dual-duration display (presenter unit tests) compile unchanged.
    init(
        bindingState: FilmModeReciprocityBindingState,
        calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>,
        filmModeExposureResultState: FilmModeExposureResultState?,
        modelSelection: FilmModeDetailsModelSelectionState? = nil,
        formatDuration: @escaping (Double) -> String,
        formatDurationCoarse: @escaping (Double) -> String,
        formatAxisDuration: @escaping (Double) -> String,
        formatSecondsComparison: @escaping (Double) -> String? = { _ in nil }
    ) {
        self.bindingState = bindingState
        self.calculationResult = calculationResult
        self.filmModeExposureResultState = filmModeExposureResultState
        self.modelSelection = modelSelection
        self.formatDuration = formatDuration
        self.formatDurationCoarse = formatDurationCoarse
        self.formatAxisDuration = formatAxisDuration
        self.formatSecondsComparison = formatSecondsComparison
    }
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
    private let modelMetadata: ReciprocityModelMetadataPresenter
    private let modelComparison: ReciprocityModelComparisonPresenter

    init(
        vocabulary: ReciprocityDetailsVocabularyPresenter = ReciprocityDetailsVocabularyPresenter(),
        reference: FilmModeDetailsReferencePresenter = FilmModeDetailsReferencePresenter(),
        graph: FilmModeDetailsGraphPresenter = FilmModeDetailsGraphPresenter(),
        legend: FilmModeDetailsLegendPresenter = FilmModeDetailsLegendPresenter(),
        modelMetadata: ReciprocityModelMetadataPresenter = ReciprocityModelMetadataPresenter(),
        modelComparison: ReciprocityModelComparisonPresenter = ReciprocityModelComparisonPresenter()
    ) {
        self.vocabulary = vocabulary
        self.reference = reference
        self.graph = graph
        self.legend = legend
        self.modelMetadata = modelMetadata
        self.modelComparison = modelComparison
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
            modelSelection: input.modelSelection,
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
        // Shared Calculation Basis section. Renders the equation
        // text between the graph and the textual interpretation
        // (custom-profile metadata / source / range). Limited to
        // profiles whose basis is a single formula expression —
        // the presenter returns `nil` for non-formula profiles so
        // the section disappears entirely. Inserted at index 0 so
        // it sits ahead of the custom-profile metadata in the
        // section stack the view renders below the graph.
        if let basisSection = calculationBasisSection(
            for: input.bindingState.profile
        ) {
            sections.insert(basisSection, at: 0)
        }

        // App-derived / fitted comparison (PTIMER-159). Gated to
        // explicitly app-derived alternate models (e.g. Fomapan 100's
        // app-derived formula) so it never leaks onto non-app-derived
        // profiles that merely carry source anchors — source-backed
        // table/graph models, or converted-formula profiles (e.g.
        // Provia). Kept separate from the source-only
        // reference sections and inserted ahead of "Sources" so that
        // citation footer stays last.
        if AlternateReciprocityModels.isAppDerivedModel(id: input.bindingState.profile.id),
           let comparisonSection = modelComparison.comparisonSection(
            for: input.bindingState.profile,
            formatDuration: input.formatDuration
        ) {
            if let sourcesIndex = sections.firstIndex(where: { $0.title == "Sources" }) {
                sections.insert(comparisonSection, at: sourcesIndex)
            } else {
                sections.append(comparisonSection)
            }
        }

        // Active reciprocity model metadata (PTIMER-159). Inserted last
        // at index 0 so it leads the post-graph section stack for every
        // film, giving the user the active profile/model identity before
        // any source or comparison detail.
        sections.insert(
            modelMetadata.metadataSection(
                film: input.bindingState.film,
                profile: input.bindingState.profile
            ),
            at: 0
        )
        return sections
    }

    /// Wraps `CalculationBasisPresenter.calculationBasisText` in a
    /// detail section so the view layer renders it through the
    /// same row/section chrome it uses for every other Details
    /// block. The single row carries the formula equation in the
    /// `.formulaExpression` style so the superscript exponent
    /// matches the legacy in-graph rendering the custom path
    /// retired.
    ///
    /// Scoped to user-defined (custom) profiles so the dedupe
    /// pairs cleanly with the graph-header formula suppression:
    /// preset / unofficial profiles keep their existing in-graph
    /// formula header and do not gain a duplicate basis section.
    private func calculationBasisSection(
        for profile: ReciprocityProfile
    ) -> FilmModeDetailsSectionState? {
        guard profile.source.authority == .userDefined else { return nil }
        guard let basisText = CalculationBasisPresenter
            .calculationBasisText(for: profile) else {
            return nil
        }
        return FilmModeDetailsSectionState(
            title: "Calculation basis",
            rows: [
                FilmModeDetailsRowState(
                    title: "",
                    value: basisText,
                    style: .formulaExpression
                ),
            ]
        )
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
        let statusTone = vocabulary.tone(for: input.bindingState)

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
                // PTIMER-172: surface the matching whole-seconds value
                // under the clock primary for source-table comparison.
                detailText: input.formatSecondsComparison(
                    filmModeExposureResultState.adjustedShutterSeconds
                ),
                emphasizesValue: false
            ),
            correctedExposure: FilmModeDetailsCurrentResultValueState(
                title: "Corrected Exposure",
                valueText: filmModeExposureResultState.correctedExposure.correctedExposureSeconds
                    .map { input.formatDurationCoarse($0) }
                    ?? filmModeExposureResultState.correctedExposure.primaryText,
                // For a quantified result the note text is nil, so the
                // free slot carries the seconds comparison (PTIMER-172);
                // non-quantified results keep their guidance note.
                detailText: correctedExposureNoteText
                    ?? filmModeExposureResultState.correctedExposure.correctedExposureSeconds
                        .flatMap(input.formatSecondsComparison),
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

        guard let label = subtitleModelLabel(for: bindingState.profile) else {
            return trimmedName
        }
        return "\(trimmedName) · \(label)"
    }

    /// Concise, model-aware subtitle label (PTIMER-159). Non-default
    /// alternate models (app-derived formula, unofficial practical) and
    /// the log-log table model name themselves, so the app-derived model
    /// never reads as plain "Official guidance". Every other catalog
    /// profile keeps the concise authority label so single-model films
    /// are not saddled with their verbose internal profile names.
    private func subtitleModelLabel(for profile: ReciprocityProfile) -> String? {
        if AlternateReciprocityModels.profile(withID: profile.id) != nil {
            return profile.source.authority == .unofficial
                ? "Unofficial practical"
                : profile.name
        }
        if profile.effectiveModelBasis.calculationModel == .tableLogLogInterpolation {
            return profile.name
        }
        return FilmSelectionModel.filmRowAuthorityLabel(forAuthority: profile.source.authority)
    }

    // MARK: - Helpers

    /// Profiles that compute a quantified curve (a formula or a
    /// log-log table) render the "Source reference" + graph sections;
    /// limited-guidance profiles render the qualitative reference block.
    private func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            switch $0 {
            case .formula, .tableInterpolation:
                return true
            case .threshold, .limitedGuidance:
                return false
            }
        })
    }

}
