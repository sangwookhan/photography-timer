import Foundation

struct FilmModeDetailsPresenterInput {
    let bindingState: FilmModeReciprocityBindingState
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let filmModeExposureResultState: FilmModeExposureResultState?
    let formatDuration: (Double) -> String
    let formatDurationCoarse: (Double) -> String
    let formatAxisDuration: (Double) -> String
}

struct FilmModeDetailsPresenter {

    // MARK: - Public entry point

    func makeDetailsDisplayState(
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsDisplayState? {
        let bindingState = input.bindingState

        let sections = compactMapDetailsSections(for: bindingState, input: input)
        let graph = makeFilmModeDetailsGraphDisplayState(for: bindingState, input: input)
        // The legacy `guard !sections.isEmpty` is dropped now that
        // Profile/Formula metadata blocks no longer participate. The
        // sheet is still meaningful via the subtitle, the Current
        // Result block, and the optional graph even when neither
        // evidence nor source-provenance rows are available — e.g.
        // unofficial formula profiles with no published source.
        return FilmModeDetailsDisplayState(
            title: "Reciprocity Details",
            subtitle: filmIdentitySubtitle(for: input.bindingState),
            summary: makeFilmModeDetailsSummaryState(for: bindingState, input: input),
            currentResult: makeFilmModeDetailsCurrentResultState(input: input, graph: graph),
            sections: sections,
            graph: graph,
            legend: legendDisplayState(for: input.bindingState.profile)
        )
    }

    private func filmIdentitySubtitle(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        let trimmedName = bindingState.film.canonicalStockName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        if let label = subtitleAuthorityLabel(for: bindingState.profile.source.authority) {
            return "\(trimmedName) · \(label)"
        }
        return trimmedName
    }

    private func subtitleAuthorityLabel(
        for authority: ReciprocityAuthority
    ) -> String? {
        switch authority {
        case .official:
            return "Official guidance"
        case .unofficial:
            return "Unofficial guidance"
        case .userDefined:
            return "User-defined"
        case .unknown:
            return nil
        }
    }

    // MARK: - Summary

    private func makeFilmModeDetailsSummaryState(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsSummaryState {
        let displayState = reciprocityStateDisplayState(for: bindingState)
        return FilmModeDetailsSummaryState(
            badgeText: displayState.badgeText,
            tone: displayState.tone,
            summaryText: filmModeDetailsSummaryText(for: bindingState, input: input),
            detailText: filmModeDetailsSummaryDetailText(for: bindingState)
        )
    }

    private func filmModeDetailsSummaryText(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> String {
        let metadata = bindingState.policyResult.metadata
        let references = metadata.referencedRows ?? []

        switch metadata.basis {
        case .exactTablePoint:
            if case .success(let result) = input.calculationResult {
                return "Exact at \(input.formatDurationCoarse(result.resultShutterSeconds))"
            }
            return "Exact reference point"
        case .interpolatedWithinTable:
            let bounds = references
                .filter { $0.role == .lowerBound || $0.role == .upperBound }
                .map { meteredExposureReferenceText(for: $0, formatDuration: input.formatDuration) }
            if bounds.count == 2 {
                return "Estimated between \(bounds[0]) and \(bounds[1])"
            }
            return "Estimated within reference data"
        case .extrapolatedBeyondTable:
            if let anchor = references.first(where: { $0.role == .representativeAnchor }) {
                return "Extrapolated beyond \(meteredExposureReferenceText(for: anchor, formatDuration: input.formatDuration)) reference data"
            }
            return "Extrapolated beyond reference data"
        case .officialThresholdNoCorrection:
            if case .success(let result) = input.calculationResult {
                return "No correction at \(input.formatDurationCoarse(result.resultShutterSeconds))"
            }
            return "No correction in the supported range"
        case .formulaDerived:
            return bindingState.profile.isConvertedFormulaProfile
                ? "Reference-backed formula prediction"
                : "Formula-based correction on the active curve"
        case .advisoryOnlyBeyondOfficialRange:
            return "Beyond published no-correction range"
        case .unsupportedOutOfPolicyRange:
            return bindingState.profile.isConvertedFormulaProfile
                ? "Beyond source range"
                : "Outside supported reciprocity range"
        }
    }

    private func filmModeDetailsSummaryDetailText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        switch bindingState.presentation.category {
        case .unsupported:
            if bindingState.policyResult.correctedExposureSeconds != nil {
                if bindingState.profile.isConvertedFormulaProfile {
                    return "Current input is beyond the manufacturer source range. The corrected value is a formula prediction past the published reference."
                }
                return "Current input is outside manufacturer guidance. The corrected value is extrapolated from the formula curve."
            }
            return "Current input is outside the supported range and no quantified corrected point is available."
        case .advisoryOnly:
            return "No official quantified prediction is available beyond this range."
        case .exact, .estimated, .extrapolated:
            return nil
        }
    }

    func reciprocityStateDisplayState(
        for bindingState: FilmModeReciprocityBindingState
    ) -> FilmModeReciprocityStateDisplayState {
        FilmModeReciprocityStateDisplayState(
            badgeText: reciprocityStateBadgeText(for: bindingState),
            tone: reciprocityStateTone(for: bindingState.presentation.badgeStyle),
            infoText: reciprocityGuidanceExplanation(for: bindingState.presentation),
            showsInfoAffordance: true
        )
    }

    private func reciprocityStateBadgeText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String {
        // Both Main (reciprocity badge chip) and Detail (Current
        // Result status line) read from the same wording set so the
        // same calculation state never produces two different labels
        // across surfaces.
        let metadata = bindingState.policyResult.metadata
        let presentation = bindingState.presentation

        if metadata.basis == .officialThresholdNoCorrection {
            return "No correction"
        }

        if metadata.basis == .formulaDerived {
            return "Formula-derived"
        }

        switch presentation.category {
        case .advisoryOnly:
            return "No quantified prediction"
        case .unsupported:
            // Converted formula profiles (formula + source evidence)
            // surface as "Beyond source range" — the
            // canonical wording shared with the Detail status line.
            if bindingState.profile.isConvertedFormulaProfile {
                return "Beyond source range"
            }
            return bindingState.policyResult.correctedExposureSeconds != nil
                ? "Outside guidance"
                : "Unsupported"
        case .exact:
            return "Exact"
        case .estimated:
            return "Estimated"
        case .extrapolated:
            return "Extrapolated"
        }
    }

    private func reciprocityStateTone(
        for badgeStyle: ReciprocityConfidenceBadgeStyle
    ) -> FilmModeReciprocityStateTone {
        switch badgeStyle {
        case .trusted:
            return .trusted
        case .measured:
            return .measured
        case .caution:
            return .caution
        case .advisory:
            return .advisory
        case .unsupported:
            return .unsupported
        }
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

    // MARK: - Current result

    private func makeFilmModeDetailsCurrentResultState(
        input: FilmModeDetailsPresenterInput,
        graph: FilmModeDetailsGraphDisplayState?
    ) -> FilmModeDetailsCurrentResultState {
        let statusText = reciprocityStateStatusText(
            for: input.bindingState,
            graph: graph
        )
        let statusTone = reciprocityStateTone(
            for: input.bindingState.presentation.badgeStyle
        )
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
        let correctedExposureNoteText = correctedExposureDetailText(
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

    /// Short fixed-vocabulary status text used by the Current Result
    /// block. Reuses the Main badge wording so the same calculation
    /// state never reads differently across surfaces.
    ///
    /// For converted formula profiles (Provia 100F today), the
    /// visible-range flags are treated as graph affordances only —
    /// the orange edge triangle and the graph note communicate that
    /// the current value sits outside the visible domain, while the
    /// status text stays anchored to the calculation basis (e.g.
    /// "Beyond source range"). Non-converted table profiles still
    /// surface the visible-range state as status text so users get
    /// at least some hint when the marker isn't drawn at its real
    /// position.
    private func reciprocityStateStatusText(
        for bindingState: FilmModeReciprocityBindingState,
        graph: FilmModeDetailsGraphDisplayState?
    ) -> String {
        if !bindingState.profile.isConvertedFormulaProfile {
            if graph?.isBeyondVisibleRange == true {
                return "Beyond visible graph range"
            }
            if graph?.isBelowVisibleRange == true {
                return "Below visible graph range"
            }
        }
        return reciprocityStateBadgeText(for: bindingState)
    }

    private func correctedExposureDetailText(
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
        case .advisory:
            return correctedExposure.secondaryText
        case .unsupported:
            return correctedExposure.secondaryText
        }
    }

    // MARK: - Sections

    private func compactMapDetailsSections(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> [FilmModeDetailsSectionState] {
        if profileUsesFormula(bindingState.profile) {
            return formulaDetailsSections(for: bindingState, input: input)
        }

        let referenceRows = referenceDetailsRows(for: bindingState, input: input)
        let sourceRows = sourceDetailsRows(for: bindingState.profile)

        return [
            !referenceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Reference", rows: referenceRows)
                : nil,
            !sourceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Sources", rows: sourceRows)
                : nil
        ]
        .compactMap { $0 }
    }

    private func formulaDetailsSections(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> [FilmModeDetailsSectionState] {
        let evidenceSections = sourceEvidenceSections(for: bindingState, input: input)
        let sourceRows = sourceDetailsRows(for: bindingState.profile)

        var sections: [FilmModeDetailsSectionState] = []
        sections.append(contentsOf: evidenceSections)
        if !sourceRows.isEmpty {
            sections.append(FilmModeDetailsSectionState(title: "Sources", rows: sourceRows))
        }
        return sections
    }

    /// Splits manufacturer source-evidence rows into two display
    /// sections so a published reference point and a published
    /// stop-signal boundary never share the same visual category.
    ///
    /// - "Source reference" carries the threshold no-correction band
    ///   and any evidence row that publishes a quantified adjustment
    ///   (e.g. Provia 100F's 240 s +1/3 stop, 2.5G reference).
    /// - "Guidance boundary" carries evidence rows that publish only a
    ///   not-recommended warning (e.g. Provia 100F's 480 s boundary),
    ///   so the boundary never reads as a formula-fitting point.
    ///
    /// Profiles without `sourceEvidence` (HP5 Plus and the rest of
    /// the formula catalog today) produce neither section, preserving
    /// their existing layout.
    private func sourceEvidenceSections(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> [FilmModeDetailsSectionState] {
        let evidence = bindingState.profile.sourceEvidence
        guard !evidence.isEmpty else {
            return []
        }

        var referenceLines: [[String]] = []
        var boundaryLines: [[String]] = []

        for rule in bindingState.profile.rules {
            if case let .threshold(thresholdRule) = rule {
                referenceLines.append(
                    sourceReferenceThresholdColumns(
                        for: thresholdRule,
                        formatDuration: input.formatDuration
                    )
                )
            }
        }

        for evidenceRow in evidence {
            guard let columns = compactReferenceColumns(
                meteredExposure: evidenceRow.meteredExposure,
                adjustments: evidenceRow.adjustments,
                input: input
            ) else {
                continue
            }
            if sourceEvidenceRowIsGuidanceBoundary(evidenceRow) {
                boundaryLines.append(columns)
            } else {
                referenceLines.append(columns)
            }
        }

        var sections: [FilmModeDetailsSectionState] = []
        if !referenceLines.isEmpty {
            sections.append(
                FilmModeDetailsSectionState(
                    title: "Source reference",
                    rows: [
                        FilmModeDetailsRowState(
                            title: "",
                            value: formattedReferenceBlock(from: referenceLines),
                            style: .referenceBlock
                        )
                    ]
                )
            )
        }
        if !boundaryLines.isEmpty {
            sections.append(
                FilmModeDetailsSectionState(
                    title: "Guidance boundary",
                    rows: [
                        FilmModeDetailsRowState(
                            title: "",
                            value: formattedReferenceBlock(from: boundaryLines),
                            style: .referenceBlock
                        )
                    ]
                )
            )
        }
        return sections
    }

    private func sourceEvidenceRowIsGuidanceBoundary(
        _ row: ReciprocitySourceEvidenceRow
    ) -> Bool {
        let hasNotRecommendedWarning = row.adjustments.contains { adjustment in
            if case let .warning(warning) = adjustment, warning.severity == .notRecommended {
                return true
            }
            return false
        }
        let hasExposureAdjustment = row.adjustments.contains { adjustment in
            if case .exposure = adjustment { return true }
            return false
        }
        return hasNotRecommendedWarning && !hasExposureAdjustment
    }

    private func referenceDetailsRows(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> [FilmModeDetailsRowState] {
        if let formulaReference = formulaReferenceRows(for: bindingState), !formulaReference.isEmpty {
            return formulaReference
        }

        let tableReference = tableReferenceRows(for: bindingState, input: input)
        if !tableReference.isEmpty {
            return tableReference
        }

        return manufacturerNoDataReferenceRows(for: bindingState)
    }

    private func formulaReferenceRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState]? {
        guard let formulaRule = bindingState.profile.rules.first(where: {
            if case .formula = $0 { return true }
            return false
        }),
        case let .formula(rule) = formulaRule else {
            return nil
        }

        return [
            FilmModeDetailsRowState(
                title: "",
                value: userFacingFormulaReferenceText(for: rule.formula),
                style: .formulaExpression
            )
        ]
    }

    private func tableReferenceRows(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> [FilmModeDetailsRowState] {
        var lines: [[String]] = []

        for rule in bindingState.profile.rules {
            switch rule {
            case .threshold(let thresholdRule):
                lines.append(compactThresholdReferenceColumns(for: thresholdRule, formatDuration: input.formatDuration))
            case .table(let tableRule):
                lines.append(contentsOf: tableRule.entries.compactMap {
                    compactTableEntryReferenceColumns(for: $0, input: input)
                })
            case .advisory(let advisoryRule):
                if let columns = compactAdvisoryRuleColumns(for: advisoryRule, formatDuration: input.formatDuration) {
                    lines.append(columns)
                }
            case .formula:
                continue
            }
        }

        guard !lines.isEmpty else {
            return []
        }

        return [
            FilmModeDetailsRowState(
                title: "",
                value: formattedReferenceBlock(from: lines),
                style: .referenceBlock
            )
        ]
    }

    private func manufacturerNoDataReferenceRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState] {
        if bindingState.presentation.category == .advisoryOnly || bindingState.presentation.category == .unsupported {
            return [
                FilmModeDetailsRowState(
                    title: "",
                    value: "Manufacturer does not publish quantified reciprocity data",
                    style: .referenceBlock
                )
            ]
        }

        return []
    }

    /// Sources rows are rendered as an unlabeled list (one item per
    /// row) so the section reads like "Fujifilm · FUJICHROME PROVIA
    /// 100F — Long exposure guide / Provia 100F support page"
    /// without an extra Reference / Citation subdivision.
    private func sourceDetailsRows(for profile: ReciprocityProfile) -> [FilmModeDetailsRowState] {
        let source = profile.source
        var rows: [FilmModeDetailsRowState] = []

        let referenceComponents = [
            normalizedDetailText(source.publisher),
            normalizedDetailText(source.title),
            normalizedDetailText(source.sourceVersion).map { "Version \($0)" }
        ]
        .compactMap { $0 }

        if !referenceComponents.isEmpty {
            rows.append(
                FilmModeDetailsRowState(
                    title: "",
                    value: referenceComponents.joined(separator: " · ")
                )
            )
        }

        if let citationText = normalizedDetailText(source.citation) {
            rows.append(
                FilmModeDetailsRowState(
                    title: "",
                    value: citationText,
                    destinationURL: parseUsableURL(citationText)
                )
            )
        }

        return rows
    }

    private func legendDisplayState(
        for profile: ReciprocityProfile
    ) -> FilmModeDetailsLegendState? {
        let ruleAdjustments = profile.rules.flatMap { rule -> [ReciprocityAdjustment] in
            switch rule {
            case let .threshold(thresholdRule):
                return thresholdRule.adjustments
            case let .formula(formulaRule):
                return formulaRule.additionalAdjustments
            case let .table(tableRule):
                return tableRule.entries.flatMap(\.adjustments)
            case let .advisory(advisoryRule):
                return advisoryRule.adjustments
            }
        }
        let evidenceAdjustments = profile.sourceEvidence.flatMap(\.adjustments)
        let adjustments = ruleAdjustments + evidenceAdjustments
        let presentations = ReciprocitySecondaryGuidanceFormatter.format(adjustments)
        guard !presentations.isEmpty else { return nil }

        var lines: [String] = []

        let colorValues = presentations
            .filter { $0.kind == .colorCorrection }
            .compactMap(\.valueText)
        if !colorValues.isEmpty,
           let line = colorCorrectionLegendLine(for: colorValues) {
            lines.append(line)
        }

        if presentations.contains(where: { $0.kind == .developmentAdjustment }) {
            lines.append("Development adjustment: Dev -10% means adjust development time by -10%.")
        }

        if presentations.contains(where: { $0.kind == .warning && $0.severity == .stop }) {
            lines.append("Warning: Not recommended marks a manufacturer stop-signal.")
        }

        guard !lines.isEmpty else { return nil }
        return FilmModeDetailsLegendState(lines: lines)
    }

    private func colorCorrectionLegendLine(for filterNames: [String]) -> String? {
        if let kodakName = filterNames.first(where: { $0.uppercased().hasPrefix("CC") }) {
            let channelDescription = colorChannelDescription(for: trailingChannelLetter(of: kodakName))
            return "Color correction: \(kodakName) = color-compensating \(channelDescription) filtration."
        }

        let trailingLetters = Set(filterNames.compactMap(trailingChannelLetter))
        if trailingLetters.count == 1, let letter = trailingLetters.first {
            let description = colorChannelDescription(for: letter)
            return "Color correction: \(letter) = \(description) filtration."
        }

        return nil
    }

    private func trailingChannelLetter(of filterName: String) -> String? {
        guard let last = filterName.last,
              last.isLetter else { return nil }
        return String(last).uppercased()
    }

    private func colorChannelDescription(for channel: String?) -> String {
        switch channel?.uppercased() {
        case "M":
            return "magenta"
        case "G":
            return "green"
        case "B":
            return "blue"
        case "Y":
            return "yellow"
        case "C":
            return "cyan"
        case "R":
            return "red"
        default:
            return "color"
        }
    }

    // MARK: - Graph

    private func makeFilmModeDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsGraphDisplayState? {
        guard case .success(let result) = input.calculationResult,
              result.resultShutterSeconds > 0 else {
            return nil
        }

        let currentMeteredExposureSeconds = result.resultShutterSeconds
        let currentPoint = graphCurrentPoint(for: bindingState, input: input)

        if let formulaGraph = formulaDetailsGraphDisplayState(
            for: bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            input: input
        ) {
            return formulaGraph
        }

        return tableDetailsGraphDisplayState(
            for: bindingState,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            input: input
        )
    }

    private func formulaDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsGraphDisplayState? {
        // The formula curve is the same reference regardless of where
        // the current input lands: no-correction range, supported
        // formula range, or formula-extrapolated outside guidance.
        // The graph stays visible whenever a graphable formula
        // exists; the current-point marker style and the shaded
        // regions separate the three states.
        guard let formulaRule = bindingState.profile.rules.compactMap({ rule -> FormulaReciprocityRule? in
            guard case let .formula(formulaRule) = rule else {
                return nil
            }
            return formulaRule
        }).first else {
            return nil
        }

        let sourceReferenceMarkers = formulaGraphSourceReferenceMarkers(
            for: bindingState.profile,
            formatDuration: input.formatDuration
        )
        let notRecommendedBoundarySeconds = formulaGraphNotRecommendedBoundarySeconds(
            for: bindingState.profile
        )

        let tierSelection = selectFormulaGraphScaleTier(
            formulaRule: formulaRule,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint,
            sourceReferenceMarkers: sourceReferenceMarkers,
            notRecommendedBoundarySeconds: notRecommendedBoundarySeconds
        )
        let tier = tierSelection.tier
        let isBelowVisibleRange = isCurrentInputBelowTier(
            tier: tier,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint
        )

        let sourcePoints = formulaGraphSourcePoints(
            for: formulaRule,
            profile: bindingState.profile,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            tierUpperBoundSeconds: tier.upperBoundSeconds
        )
        guard sourcePoints.count >= 2 else {
            return nil
        }

        let supportedUpperBoundSeconds = formulaRule.meteredRange?.maximumSeconds
        let noCorrectionRangeUpperBoundSeconds = profileThresholdUpperBounds(in: bindingState.profile)
            .filter { $0 > 0 }
            .max()

        let descriptionLines = formulaGraphDescriptionLines(
            for: bindingState,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            isBelowVisibleRange: isBelowVisibleRange
        )
        let formulaDisplayText = userFacingFormulaReferenceText(for: formulaRule.formula)
        let beyondSourceRangeStartSeconds = formulaGraphBeyondSourceRangeStartSeconds(
            profile: bindingState.profile,
            supportedUpperBoundSeconds: supportedUpperBoundSeconds
        )

        // Only fall back to the "current input as x-position only" view
        // when the unsupported result truly carries no numeric corrected
        // exposure. Formula-extrapolated unsupported numeric results
        // plot a real (x, y) point so the user can see the value on
        // the curve.
        let usesCurrentInputGuideOnly = bindingState.presentation.category == .unsupported
            && currentPoint == nil

        return FilmModeDetailsGraphDisplayState(
            kind: .formula,
            title: "Reference Graph",
            sourcePoints: sourcePoints,
            currentPoint: currentPoint,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            usesCurrentInputGuideOnly: usesCurrentInputGuideOnly,
            caption: formulaGraphCaption(
                for: bindingState,
                noCorrectionRangeUpperBoundSeconds: noCorrectionRangeUpperBoundSeconds
            ),
            unsupportedExplanation: graphUnsupportedExplanation(for: bindingState),
            xAxisLabel: "Adjusted shutter",
            yAxisLabel: "Corrected exposure",
            xAxisTicks: tierAxisTicks(for: tier),
            yAxisTicks: tierAxisTicks(for: tier),
            supportedRangeUpperBoundSeconds: supportedUpperBoundSeconds,
            unsupportedRegionStartSeconds: unsupportedRegionStartSeconds(
                supportedUpperBoundSeconds: supportedUpperBoundSeconds,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                isUnsupported: bindingState.presentation.category == .unsupported
            ),
            noCorrectionRangeUpperBoundSeconds: noCorrectionRangeUpperBoundSeconds,
            sourceReferenceMarkers: sourceReferenceMarkers,
            notRecommendedBoundarySeconds: notRecommendedBoundarySeconds,
            beyondSourceRangeStartSeconds: beyondSourceRangeStartSeconds,
            formulaDisplayText: formulaDisplayText,
            descriptionLines: descriptionLines,
            scaleTier: tier,
            isBeyondVisibleRange: tierSelection.isBeyondVisibleRange,
            isBelowVisibleRange: isBelowVisibleRange,
            xRange: tier.range,
            yRange: tier.range
        )
    }

    /// `true` when the current input would draw at the plot's left
    /// edge instead of its real position because at least one of its
    /// coordinates is below the active tier's lower bound (1 s).
    /// Triggered by no-correction inputs faster than 1 s (e.g. a
    /// 1/30 s metered exposure with corrected == metered) so the
    /// view can skip the marker rather than letting it impersonate
    /// a 1 s reading.
    private func isCurrentInputBelowTier(
        tier: FilmModeDetailsGraphScaleTier,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?
    ) -> Bool {
        let lower = tier.lowerBoundSeconds
        if currentMeteredExposureSeconds > 0,
           currentMeteredExposureSeconds < lower {
            return true
        }
        if let currentPoint {
            if currentPoint.point.meteredExposureSeconds > 0,
               currentPoint.point.meteredExposureSeconds < lower {
                return true
            }
            if currentPoint.point.correctedExposureSeconds > 0,
               currentPoint.point.correctedExposureSeconds < lower {
                return true
            }
        }
        return false
    }

    /// Picks the smallest scale tier that still contains every value
    /// the formula graph will plot: curve endpoints, current point,
    /// source-reference markers, and the not-recommended boundary.
    /// Returns the tier together with an overflow flag for the rare
    /// case where the relevant maximum exceeds the `t3` upper bound.
    private func selectFormulaGraphScaleTier(
        formulaRule: FormulaReciprocityRule,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        sourceReferenceMarkers: [FilmModeDetailsGraphSourceReference],
        notRecommendedBoundarySeconds: Double?
    ) -> (tier: FilmModeDetailsGraphScaleTier, isBeyondVisibleRange: Bool) {
        var maxValue: Double = 1

        let curveUpper = [
            formulaRule.meteredRange?.maximumSeconds,
            currentMeteredExposureSeconds
        ]
        .compactMap { $0 }
        .filter { $0 > 0 }
        .max() ?? 0
        if curveUpper > 0 {
            maxValue = max(maxValue, curveUpper)
            if let curveUpperCorrected = formulaCorrectedExposureSeconds(
                for: formulaRule.formula,
                meteredExposureSeconds: curveUpper
            ) {
                maxValue = max(maxValue, curveUpperCorrected)
            }
        }

        if let currentPoint {
            maxValue = max(maxValue, currentPoint.point.meteredExposureSeconds)
            maxValue = max(maxValue, currentPoint.point.correctedExposureSeconds)
        }

        for marker in sourceReferenceMarkers {
            maxValue = max(maxValue, marker.point.meteredExposureSeconds)
            maxValue = max(maxValue, marker.point.correctedExposureSeconds)
        }

        if let notRecommendedBoundarySeconds {
            maxValue = max(maxValue, notRecommendedBoundarySeconds)
        }

        return (
            tier: FilmModeDetailsGraphScalePolicy.selectTier(maxPlottedSeconds: maxValue),
            isBeyondVisibleRange: FilmModeDetailsGraphScalePolicy.isBeyondVisibleRange(
                maxPlottedSeconds: maxValue
            )
        )
    }

    /// Returns the tier's predefined tick set filtered to the values
    /// inside the tier's domain. Used for both axes; both render
    /// duration values, so they share one tick layout.
    private func tierAxisTicks(
        for tier: FilmModeDetailsGraphScaleTier
    ) -> [FilmModeDetailsGraphAxisTick] {
        tier.axisTicks
    }

    /// Produces open-ring markers for manufacturer source-evidence
    /// rows that publish a quantified exposure adjustment (e.g.
    /// Provia 100F's 240 s +1/3 stop reference). Rows whose only
    /// adjustment is a `notRecommended` warning are intentionally
    /// excluded so a stop-signal boundary never reads as a formula
    /// fitting point. Each marker carries an adjacent text label
    /// (e.g. "240s") so the user reads the published metered value
    /// directly off the graph.
    private func formulaGraphSourceReferenceMarkers(
        for profile: ReciprocityProfile,
        formatDuration: (Double) -> String
    ) -> [FilmModeDetailsGraphSourceReference] {
        profile.sourceEvidence.compactMap { row -> FilmModeDetailsGraphSourceReference? in
            guard case let .exactSeconds(meteredExposureSeconds) = row.meteredExposure,
                  meteredExposureSeconds > 0,
                  !sourceEvidenceRowIsGuidanceBoundary(row) else {
                return nil
            }
            guard let correctedExposureSeconds = sourceEvidenceCorrectedExposureSeconds(
                meteredExposureSeconds: meteredExposureSeconds,
                adjustments: row.adjustments
            ), correctedExposureSeconds > 0 else {
                return nil
            }
            return FilmModeDetailsGraphSourceReference(
                point: FilmModeDetailsGraphPoint(
                    meteredExposureSeconds: meteredExposureSeconds,
                    correctedExposureSeconds: correctedExposureSeconds
                ),
                label: sourceReferenceMarkerLabel(
                    meteredExposureSeconds: meteredExposureSeconds,
                    formatDuration: formatDuration
                )
            )
        }
    }

    /// Marker label for a source-reference point. Prefers the bare
    /// "{seconds}s" form for whole-second values so Provia 100F's
    /// 240 s reference reads as "240s" on the graph; falls back to
    /// the standard duration formatter for fractional values.
    private func sourceReferenceMarkerLabel(
        meteredExposureSeconds: Double,
        formatDuration: (Double) -> String
    ) -> String {
        let rounded = meteredExposureSeconds.rounded()
        if abs(meteredExposureSeconds - rounded) < 1e-6, rounded > 0, rounded < 1e9 {
            return "\(Int(rounded))s"
        }
        return formatDuration(meteredExposureSeconds)
    }

    private func formulaGraphNotRecommendedBoundarySeconds(
        for profile: ReciprocityProfile
    ) -> Double? {
        for row in profile.sourceEvidence {
            guard case let .exactSeconds(seconds) = row.meteredExposure,
                  seconds > 0,
                  sourceEvidenceRowIsGuidanceBoundary(row) else {
                continue
            }
            return seconds
        }
        return nil
    }

    private func sourceEvidenceCorrectedExposureSeconds(
        meteredExposureSeconds: Double,
        adjustments: [ReciprocityAdjustment]
    ) -> Double? {
        // Prefer the published correctedTime when the row carries
        // both forms: Kodak (and several other manufacturers) publish
        // the stop delta as a rounded quick-reference alongside a
        // separately-published corrected time, and those two values
        // can disagree by up to a third of a stop (e.g. Tri-X 400's
        // 10 sec row publishes "+2 stops" and "50 sec" even though
        // +2 stops literally derives to 40 sec). Returning the
        // stop-delta derivation here would plot the source-reference
        // marker at the wrong y-coordinate.
        var stopAdjustment: StopDeltaAdjustment?
        var multiplierAdjustment: MultiplierAdjustment?
        for adjustment in adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }
            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return mapping.correctedSeconds
            case .stopDelta(let value):
                if stopAdjustment == nil { stopAdjustment = value }
            case .multiplier(let value):
                if multiplierAdjustment == nil { multiplierAdjustment = value }
            }
        }
        if let stopAdjustment {
            return meteredExposureSeconds * pow(2, stopAdjustment.stopDelta)
        }
        if let multiplierAdjustment {
            return meteredExposureSeconds * multiplierAdjustment.factor
        }
        return nil
    }

    /// Returns at most one short, state-aware note for the formula
    /// graph. The marker/region legend already names each visible
    /// element, so the note is reserved for the cases that need a
    /// brief sentence: outside the visible range, and the formula
    /// extrapolating past the published source range.
    private func formulaGraphDescriptionLines(
        for bindingState: FilmModeReciprocityBindingState,
        isBeyondVisibleRange: Bool,
        isBelowVisibleRange: Bool
    ) -> [String] {
        if isBeyondVisibleRange {
            return ["Current result is beyond the visible graph range."]
        }
        if isBelowVisibleRange {
            return ["Current result is below the visible graph range."]
        }
        if bindingState.presentation.category == .unsupported,
           bindingState.profile.isConvertedFormulaProfile {
            return ["Formula-derived result outside published source range."]
        }
        return []
    }

    /// Metered-exposure x at which the published manufacturer source
    /// range ends for a converted formula profile. Drives the
    /// persistent pink shading on the formula graph so the user can
    /// always see which region of the curve is the formula's
    /// extrapolation past the published reference.
    private func formulaGraphBeyondSourceRangeStartSeconds(
        profile: ReciprocityProfile,
        supportedUpperBoundSeconds: Double?
    ) -> Double? {
        guard profile.isConvertedFormulaProfile else {
            return nil
        }
        return supportedUpperBoundSeconds
    }

    /// State-aware caption for the formula graph. Branches on the
    /// current basis so the headline matches the shaded region the
    /// user sees: no-correction inputs read as identity-line guidance,
    /// numeric outside-guidance reads as extrapolation, supported
    /// formula inputs read as on the active curve.
    ///
    /// Caption strings omit a trailing period to match the rest of
    /// the graph caption surface, which renders as banner text.
    private func formulaGraphCaption(
        for bindingState: FilmModeReciprocityBindingState,
        noCorrectionRangeUpperBoundSeconds: Double?
    ) -> String {
        let basis = bindingState.policyResult.metadata.basis
        if basis == .officialThresholdNoCorrection,
           noCorrectionRangeUpperBoundSeconds != nil {
            return "Adjusted shutter equals corrected exposure within the no-correction range"
        }

        if bindingState.presentation.category == .unsupported,
           bindingState.policyResult.correctedExposureSeconds != nil {
            return "Formula curve extrapolated past the manufacturer-supported boundary"
        }

        return "Adjusted shutter vs corrected exposure on the active formula curve"
    }

    private func tableDetailsGraphDisplayState(
        for bindingState: FilmModeReciprocityBindingState,
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsGraphDisplayState? {
        let sourcePoints = bindingState.profile.rules.flatMap { rule -> [FilmModeDetailsGraphPoint] in
            guard case let .table(tableRule) = rule else {
                return []
            }

            return tableRule.entries.compactMap(tableGraphSourcePoint(for:))
        }
        .sorted { $0.meteredExposureSeconds < $1.meteredExposureSeconds }

        guard sourcePoints.count >= 2 else {
            return nil
        }

        guard let ranges = graphRanges(
            sourcePoints: sourcePoints,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint?.point
        ) else {
            return nil
        }

        let supportedUpperBoundSeconds = sourcePoints.map(\.meteredExposureSeconds).max()

        return FilmModeDetailsGraphDisplayState(
            kind: .table,
            title: "Reference Graph",
            sourcePoints: sourcePoints,
            currentPoint: currentPoint,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            usesCurrentInputGuideOnly: bindingState.presentation.category == .unsupported,
            caption: "Adjusted shutter vs corrected exposure from reference anchors",
            unsupportedExplanation: graphUnsupportedExplanation(for: bindingState),
            xAxisLabel: "Adjusted shutter",
            yAxisLabel: "Corrected exposure",
            xAxisTicks: graphAxisTicks(for: ranges.xRange, formatAxisDuration: input.formatAxisDuration),
            yAxisTicks: graphAxisTicks(for: ranges.yRange, formatAxisDuration: input.formatAxisDuration),
            supportedRangeUpperBoundSeconds: supportedUpperBoundSeconds,
            unsupportedRegionStartSeconds: unsupportedRegionStartSeconds(
                supportedUpperBoundSeconds: supportedUpperBoundSeconds,
                currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                isUnsupported: bindingState.presentation.category == .unsupported
            ),
            xRange: ranges.xRange,
            yRange: ranges.yRange
        )
    }

    private func graphCurrentPoint(
        for bindingState: FilmModeReciprocityBindingState,
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsGraphCurrentPoint? {
        guard case .success(let result) = input.calculationResult,
              result.resultShutterSeconds > 0 else {
            return nil
        }

        // In the no-correction range the corrected exposure equals
        // the adjusted shutter. Plot the identity point with the
        // dedicated `.noCorrection` style so it does not read as a
        // formula prediction. Formula-backed films land here when the
        // input drops below the no-correction threshold.
        if bindingState.policyResult.metadata.basis == .officialThresholdNoCorrection {
            return FilmModeDetailsGraphCurrentPoint(
                point: FilmModeDetailsGraphPoint(
                    meteredExposureSeconds: result.resultShutterSeconds,
                    correctedExposureSeconds: result.resultShutterSeconds
                ),
                style: .noCorrection
            )
        }

        guard let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds,
              correctedExposureSeconds > 0,
              bindingState.presentation.returnsCalculatedExposureTime else {
            return nil
        }

        let style: FilmModeDetailsGraphCurrentPointStyle
        switch bindingState.presentation.category {
        case .exact:
            style = .exact
        case .estimated:
            // Formula-derived results map to .estimated category. Use
            // the formula-specific marker so the legend shows "on
            // formula curve" rather than the table-estimation diamond.
            style = bindingState.policyResult.metadata.basis == .formulaDerived
                ? .formulaDerived
                : .estimated
        case .extrapolated:
            style = .extrapolated
        case .unsupported:
            // Formula-extrapolated unsupported numeric — render with the
            // extrapolated marker so the user reads it as outside the
            // supported range without losing the on-curve placement.
            style = .extrapolated
        case .advisoryOnly:
            return nil
        }

        return FilmModeDetailsGraphCurrentPoint(
            point: FilmModeDetailsGraphPoint(
                meteredExposureSeconds: result.resultShutterSeconds,
                correctedExposureSeconds: correctedExposureSeconds
            ),
            style: style
        )
    }

    private func formulaGraphSourcePoints(
        for rule: FormulaReciprocityRule,
        profile: ReciprocityProfile,
        currentMeteredExposureSeconds: Double,
        tierUpperBoundSeconds: Double
    ) -> [FilmModeDetailsGraphPoint] {
        // Anchor the formula curve to the formula's own supported
        // zone. When a threshold rule defines a no-correction range
        // (e.g. Provia 100F's 0…128 s), the curve must not extend
        // through that range or it reads as the active prediction
        // there. The view shades the no-correction region separately
        // so the zone left of the curve reads as policy-controlled.
        let thresholdCandidates = profileThresholdUpperBounds(in: profile)
        let lowerBoundCandidates: [Double?] = [
            rule.meteredRange?.minimumSeconds,
            thresholdCandidates.min(),
            // Legacy fallback for formula profiles that carry neither
            // an explicit meteredRange nor a threshold rule. Keeps the
            // curve at 1 s when both anchors above are nil.
            (rule.meteredRange?.minimumSeconds == nil && thresholdCandidates.isEmpty) ? 1 : nil
        ]
        // When no explicit meteredRange is defined, use a canonical practical range
        // so the graph shows a stable reference viewport rather than auto-scaling
        // tightly around the current input.
        let canonicalUpperBoundSeconds: Double = 120
        let upperBoundCandidates = [
            rule.meteredRange?.maximumSeconds,
            canonicalUpperBoundSeconds,
            currentMeteredExposureSeconds
        ]

        let positiveLowerBound = lowerBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()
        let positiveUpperBound = upperBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()

        guard let lowerBound = positiveLowerBound,
              let upperBound = positiveUpperBound else {
            return []
        }

        // Clamp the curve's upper sample to the active tier so the
        // formula does not produce off-screen samples that distort
        // the y-range or push the curve into multi-day territory.
        // Likewise floor the lower sample at the tier lower bound
        // (1 s) so no sample sits at the left-edge clamp position
        // pretending to be a 1 s value.
        let tierClampedUpperBound = min(upperBound, tierUpperBoundSeconds)
        let tierClampedLowerBound = max(lowerBound, FilmModeDetailsGraphScaleTier.t1.lowerBoundSeconds)
        let clampedLowerBound = min(tierClampedLowerBound, tierClampedUpperBound)
        let clampedUpperBound = max(tierClampedLowerBound, tierClampedUpperBound)
        let sampleCount = 24

        return (0..<sampleCount).compactMap { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let meteredExposureSeconds = logInterpolatedValue(
                minimum: clampedLowerBound,
                maximum: clampedUpperBound,
                progress: progress
            )

            guard let correctedExposureSeconds = formulaCorrectedExposureSeconds(
                for: rule.formula,
                meteredExposureSeconds: meteredExposureSeconds
            ),
            correctedExposureSeconds.isFinite,
            correctedExposureSeconds > 0 else {
                return nil
            }

            return FilmModeDetailsGraphPoint(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds
            )
        }
    }

    private func tableGraphSourcePoint(
        for entry: ReciprocityTableEntry
    ) -> FilmModeDetailsGraphPoint? {
        guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure,
              meteredExposureSeconds > 0,
              let correctedExposureSeconds = correctedExposureSeconds(for: entry),
              correctedExposureSeconds > 0 else {
            return nil
        }

        return FilmModeDetailsGraphPoint(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds
        )
    }

    private func correctedExposureSeconds(for entry: ReciprocityTableEntry) -> Double? {
        for adjustment in entry.adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }

            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return mapping.correctedSeconds
            case .stopDelta(let adjustment):
                guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure else {
                    continue
                }
                return meteredExposureSeconds * pow(2, adjustment.stopDelta)
            case .multiplier(let adjustment):
                guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure else {
                    continue
                }
                return meteredExposureSeconds * adjustment.factor
            }
        }

        return nil
    }

    private func profileThresholdUpperBounds(in profile: ReciprocityProfile) -> [Double] {
        profile.rules.compactMap { rule -> Double? in
            guard case let .threshold(thresholdRule) = rule else {
                return nil
            }
            return thresholdRule.noCorrectionRange.maximumSeconds
        }
    }

    private func formulaCorrectedExposureSeconds(
        for formula: ReciprocityFormula,
        meteredExposureSeconds: Double
    ) -> Double? {
        guard meteredExposureSeconds.isFinite,
              meteredExposureSeconds > 0 else {
            return nil
        }

        switch formula.kind {
        case .exponentPower:
            let coefficient = formula.coefficient ?? 1
            let offsetSeconds = formula.offsetSeconds ?? 0
            return (coefficient * pow(meteredExposureSeconds, formula.exponent)) + offsetSeconds
        }
    }

    private func graphRanges(
        sourcePoints: [FilmModeDetailsGraphPoint],
        currentMeteredExposureSeconds: Double,
        currentPoint: FilmModeDetailsGraphPoint?
    ) -> (xRange: ClosedRange<Double>, yRange: ClosedRange<Double>)? {
        let allPlottedPoints = currentPoint.map { sourcePoints + [$0] } ?? sourcePoints
        let xValues = (allPlottedPoints.map(\.meteredExposureSeconds) + [currentMeteredExposureSeconds])
            .filter { $0 > 0 && $0.isFinite }
        let yValues = allPlottedPoints.map(\.correctedExposureSeconds).filter { $0 > 0 && $0.isFinite }

        guard let minimumX = xValues.min(),
              let maximumX = xValues.max(),
              let minimumY = yValues.min(),
              let maximumY = yValues.max() else {
            return nil
        }

        return (
            xRange: expandedGraphDomain(minimum: minimumX, maximum: maximumX),
            yRange: expandedGraphDomain(minimum: minimumY, maximum: maximumY)
        )
    }

    private func graphAxisTicks(
        for range: ClosedRange<Double>,
        formatAxisDuration: (Double) -> String
    ) -> [FilmModeDetailsGraphAxisTick] {
        let lowerExponent = Int(floor(log10(range.lowerBound)))
        let upperExponent = Int(ceil(log10(range.upperBound)))

        let candidates = (lowerExponent...upperExponent).map { exponent in
            pow(10, Double(exponent))
        }
        .filter { range.contains($0) }

        let tickValues: [Double]
        if candidates.count <= 4 {
            tickValues = candidates
        } else {
            tickValues = [candidates.first, candidates[candidates.count / 2], candidates.last]
                .compactMap { $0 }
        }

        return tickValues.map {
            FilmModeDetailsGraphAxisTick(
                value: $0,
                label: formatAxisDuration($0)
            )
        }
    }

    private func unsupportedRegionStartSeconds(
        supportedUpperBoundSeconds: Double?,
        currentMeteredExposureSeconds: Double,
        isUnsupported: Bool
    ) -> Double? {
        guard isUnsupported,
              let supportedUpperBoundSeconds,
              currentMeteredExposureSeconds > supportedUpperBoundSeconds else {
            return nil
        }

        return supportedUpperBoundSeconds
    }

    private func graphUnsupportedExplanation(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        guard bindingState.presentation.category == .unsupported else {
            return nil
        }

        // Distinguish "outside guidance with a numeric extrapolation
        // available" from "outside guidance with no value at all".
        // Same copy in both cases would mask the timer-start
        // affordance for the numeric path.
        if bindingState.policyResult.correctedExposureSeconds != nil {
            if bindingState.profile.isConvertedFormulaProfile {
                return "Current input is beyond the manufacturer source range. The plotted value is a formula prediction past the published reference and should be verified."
            }
            return "Current input is outside manufacturer guidance. The plotted value is extrapolated from the formula curve and should be verified."
        }

        return "Current input is outside the supported range. No quantified corrected point is available."
    }

    private func expandedGraphDomain(
        minimum: Double,
        maximum: Double
    ) -> ClosedRange<Double> {
        let safeMinimum = max(minimum, 0.000_001)
        let safeMaximum = max(maximum, safeMinimum)

        if safeMinimum == safeMaximum {
            return (safeMinimum / 2)...(safeMaximum * 2)
        }

        let minimumLog = log10(safeMinimum)
        let maximumLog = log10(safeMaximum)
        let padding = max((maximumLog - minimumLog) * 0.08, 0.12)

        return pow(10, minimumLog - padding)...pow(10, maximumLog + padding)
    }

    private func logInterpolatedValue(
        minimum: Double,
        maximum: Double,
        progress: Double
    ) -> Double {
        let minimumLog = log10(minimum)
        let maximumLog = log10(maximum)
        return pow(10, minimumLog + ((maximumLog - minimumLog) * progress))
    }

    // MARK: - Formatting and text helpers

    private func limitationNoteText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        let metadata = bindingState.policyResult.metadata

        switch bindingState.presentation.category {
        case .advisoryOnly, .unsupported:
            return normalizedDetailText(reciprocityGuidanceExplanation(for: bindingState.presentation))
        case .extrapolated:
            return normalizedDetailText(
                metadata.notes.first(where: shouldPreferLimitationNote(_:))?.text
                    ?? bindingState.presentation.defaultExplanation
            )
        case .exact, .estimated:
            if metadata.rangeStatus == .beyondLastRepresentativePoint
                || metadata.warningLevel == .caution
                || metadata.warningLevel == .strongWarning {
                return normalizedDetailText(
                    metadata.notes.first(where: shouldPreferLimitationNote(_:))?.text
                        ?? bindingState.presentation.defaultExplanation
                )
            }

            return nil
        }
    }

    private func profileNoteText(for profile: ReciprocityProfile) -> String? {
        if let note = normalizedDetailText(profile.notes.first) {
            return note
        }

        for rule in profile.rules {
            if let note = normalizedDetailText(firstNote(in: rule)) {
                return note
            }
        }

        return nil
    }

    private func shouldPreferLimitationNote(_ note: ReciprocityPolicyNote) -> Bool {
        switch note.token {
        case .advisoryContinuationOnly,
             .explicitManufacturerStopSignal,
             .beyondOfficialQuantifiedRange,
             .beyondRepresentativeTablePoint,
             .unsupportedByPolicy:
            return true
        case .none,
             .estimatedFromRepresentativeRows,
             .exactManufacturerTablePoint,
             .thresholdGuidanceOnly,
             .archivalOfficialSource,
             .unofficialSecondarySource,
             .userDefinedSource:
            return false
        }
    }

    private func meteredExposureReferenceText(
        for row: ReciprocityTableRowReference,
        formatDuration: (Double) -> String
    ) -> String {
        switch row.meteredExposure {
        case .exactSeconds(let seconds):
            return formatDuration(seconds)
        case .range(let range):
            let minimum = formatDuration(range.minimumSeconds)

            if let maximumSeconds = range.maximumSeconds {
                return "\(minimum)-\(formatDuration(maximumSeconds))"
            }

            return "\(minimum)+"
        }
    }

    private func normalizedDetailText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func profileUsesFormula(_ profile: ReciprocityProfile) -> Bool {
        profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        })
    }

    private func firstNote(in rule: ReciprocityRule) -> String? {
        switch rule {
        case .threshold(let threshold):
            return threshold.notes.first
        case .formula(let formula):
            return formula.notes.first
        case .table(let table):
            return table.notes.first ?? table.entries.lazy.compactMap(\.notes.first).first
        case .advisory(let advisory):
            return advisory.notes.first
        }
    }

    // MARK: - Reference block formatting

    private func userFacingFormulaReferenceText(for formula: ReciprocityFormula) -> String {
        let formattedExponent = formatFormulaExponent(formula.exponent)

        switch formula.kind {
        case .exponentPower:
            if let equation = normalizedDetailText(formula.equation) {
                if let substitutedEquation = substituteFormulaPlaceholder(
                    in: equation,
                    placeholder: "P",
                    replacement: formattedExponent
                ) {
                    return substitutedEquation
                }
                // Profiles whose equation does not parameterize the
                // exponent (e.g. constant-multiplier forms) render
                // verbatim. Falling through to "Tc = Tm^N" here would
                // misrepresent a formula like "Tc = √2 × Tm" as
                // "Tc = Tm^1".
                return equation
            }

            return "Tc = Tm^\(formattedExponent)"
        }
    }

    private func substituteFormulaPlaceholder(
        in equation: String,
        placeholder: String,
        replacement: String
    ) -> String? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: placeholder) + "\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(equation.startIndex..., in: equation)
        guard regex.firstMatch(in: equation, range: range) != nil else {
            return nil
        }

        return regex.stringByReplacingMatches(
            in: equation,
            range: range,
            withTemplate: replacement
        )
    }

    private func compactThresholdReferenceColumns(
        for rule: ThresholdReciprocityRule,
        formatDuration: (Double) -> String
    ) -> [String] {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return ["<= \(formatDuration(upperBound))", "No correction"]
        }

        if let upperBound {
            return ["\(formatDuration(lowerBound))-\(formatDuration(upperBound))", "No correction"]
        }

        return [">= \(formatDuration(lowerBound))", "No correction"]
    }

    /// Threshold row formatter for the formula "Source reference"
    /// section. Mirrors `compactThresholdReferenceColumns` but uses
    /// the user-facing "No correction range" wording from the design
    /// so the row reads as a published reference band rather than a
    /// single boundary. The table-based "Reference" path keeps the
    /// shorter "No correction" label.
    private func sourceReferenceThresholdColumns(
        for rule: ThresholdReciprocityRule,
        formatDuration: (Double) -> String
    ) -> [String] {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return [
                sourceReferenceThresholdUpperBoundLabel(
                    for: upperBound,
                    formatDuration: formatDuration
                ),
                "No correction range",
            ]
        }

        if let upperBound {
            return ["\(formatDuration(lowerBound))-\(formatDuration(upperBound))", "No correction range"]
        }

        return [">= \(formatDuration(lowerBound))", "No correction range"]
    }

    /// Upper-bound label for the Source reference threshold row.
    /// Threshold rules that sit one ε below a round value (e.g. Acros
    /// II's 119.999999, used so the +1/2 stop formula fires at
    /// exactly 120 s) render as strict "< 120s" rather than the
    /// literal "<= 119.999999s". Rules whose upper bound is the round
    /// value itself (Provia 100F's 128 s, Velvia 50's 1 s) keep the
    /// inclusive "<= X" wording so the boundary value still reads as
    /// no-correction.
    private func sourceReferenceThresholdUpperBoundLabel(
        for upperBound: Double,
        formatDuration: (Double) -> String
    ) -> String {
        let ceiling = ceil(upperBound)
        let gap = ceiling - upperBound
        if gap > 0, gap < 1e-3 {
            return "< \(formatDuration(ceiling))"
        }
        return "<= \(formatDuration(upperBound))"
    }

    private func compactTableEntryReferenceColumns(
        for entry: ReciprocityTableEntry,
        input: FilmModeDetailsPresenterInput
    ) -> [String]? {
        compactReferenceColumns(
            meteredExposure: entry.meteredExposure,
            adjustments: entry.adjustments,
            input: input
        )
    }

    /// Shared formatter behind both the table-rule reference block and
    /// the source-evidence reference block. Keeps the metered-exposure
    /// + secondary-guidance layout identical so users see a consistent
    /// reference block whether the profile is table-driven or
    /// formula-backed with manufacturer reference points.
    private func compactReferenceColumns(
        meteredExposure: MeteredExposureSelector,
        adjustments: [ReciprocityAdjustment],
        input: FilmModeDetailsPresenterInput
    ) -> [String]? {
        let meteredText = meteredExposureSelectorText(meteredExposure, formatDuration: input.formatDuration)

        // Combined stop/multiplier · correctedTime cell. When a row
        // carries both a stopDelta (or multiplier) and a correctedTime
        // — as Kodak's TRI-X / T-MAX tables and the FOMA / ADOX
        // multiplier tables do — both facts are shown together so
        // neither half of the published source is hidden. correctedTime
        // values flagged `isApproximate` — rounded fractional-stop
        // derivations like T-MAX 100 1 sec — are prefixed with "≈".
        // Multiplier-derived corrected times are exact arithmetic and
        // render without the marker.
        let exposureText = combinedExposureColumn(
            adjustments: adjustments,
            input: input
        )

        let developmentText = adjustments.compactMap { adjustment -> String? in
            guard case let .development(development) = adjustment else {
                return nil
            }

            return compactDevelopmentReferenceText(from: development.instruction)
        }.first

        // PTIMER-119 follow-up: surface color filter notation and stop-signal warnings
        // alongside the source-row metered text so the reference table preserves the
        // mapping between metered exposure and secondary guidance.
        let colorCorrectionText = adjustments.compactMap { adjustment -> String? in
            guard case let .colorFilter(filter) = adjustment else { return nil }
            return filter.filterName
        }.first

        let stopSignalText: String? = adjustments.contains { adjustment in
            if case let .warning(warning) = adjustment, warning.severity == .notRecommended {
                return true
            }
            return false
        } ? "Not recommended" : nil

        if let exposureText {
            // Existing rule: development beats color correction when both exist on
            // the same entry (the launch catalog never mixes them today; preference
            // is documented to keep behavior deterministic).
            let secondaryText = developmentText ?? colorCorrectionText
            let detailColumns = [exposureText, secondaryText].compactMap { $0 }
            return [meteredText] + detailColumns
        }

        // Warning-only entries (Velvia 50's "64 sec is not recommended.") have no
        // exposure adjustment; surface them with the metered row so the user can
        // see WHICH metered exposure the source flags.
        if let stopSignalText {
            return [meteredText, stopSignalText]
        }

        return nil
    }

    /// PTIMER-119 follow-up: advisory rules (e.g. Ektachrome E100's CC10R at 10s+)
    /// expose published reference guidance for a metered range. Surface them in the
    /// Reference data block so the user sees WHICH metered exposure the guidance
    /// applies to, instead of hiding the rule.
    private func compactAdvisoryRuleColumns(
        for rule: AdvisoryReciprocityRule,
        formatDuration: (Double) -> String
    ) -> [String]? {
        guard let appliesRange = rule.appliesWhenMetered else { return nil }
        let meteredText = meteredExposureSelectorText(.range(appliesRange), formatDuration: formatDuration)

        if let colorRow = rule.adjustments.compactMap({ adjustment -> (String, String?)? in
            guard case let .colorFilter(filter) = adjustment else { return nil }
            return (filter.filterName, filter.note)
        }).first {
            let trimmedNote = colorRow.1?.trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String
            if let trimmedNote, !trimmedNote.isEmpty {
                value = "\(colorRow.0) — \(trimmedNote)"
            } else {
                value = colorRow.0
            }
            return [meteredText, "Color correction", value]
        }

        if rule.adjustments.contains(where: { adjustment in
            if case let .warning(warning) = adjustment, warning.severity == .notRecommended {
                return true
            }
            return false
        }) {
            return [meteredText, "Not recommended"]
        }

        if let developmentRow = rule.adjustments.compactMap({ adjustment -> String? in
            guard case let .development(development) = adjustment else { return nil }
            return development.instruction
        }).first {
            return [meteredText, "Development adjustment", developmentRow]
        }

        return nil
    }

    /// Combined "stop or multiplier · corrected time" column.
    ///
    /// The reference table's value column is intentionally compact; on
    /// rows where the source publishes (or the catalog stores) both a
    /// stop/multiplier directive and a corrected-time mapping, the user
    /// benefits from seeing both — the stop/multiplier names what the
    /// source said, and the corrected time names the resulting exposure
    /// value the photographer will actually use.
    ///
    /// - When only one form is present, returns that form alone.
    /// - When both are present, joins them with `" · "`.
    /// - When the corrected time is `isApproximate` (a rounded display
    ///   of an irrational fractional-stop derivation), prefixes its
    ///   formatted value with `"≈"`. Multiplier-derived corrected
    ///   times are exact arithmetic and are not marked.
    private func combinedExposureColumn(
        adjustments: [ReciprocityAdjustment],
        input: FilmModeDetailsPresenterInput
    ) -> String? {
        var stopOrMultiplierText: String?
        var correctedTimeText: String?

        for adjustment in adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else { continue }
            switch exposureAdjustment {
            case .correctedTime(let mapping):
                let formatted = input.formatDuration(mapping.correctedSeconds)
                correctedTimeText = mapping.isApproximate ? "≈\(formatted)" : formatted
            case .stopDelta(let adjustment):
                if stopOrMultiplierText == nil {
                    stopOrMultiplierText = formattedStopDelta(adjustment.stopDelta)
                }
            case .multiplier(let adjustment):
                if stopOrMultiplierText == nil {
                    stopOrMultiplierText = "\(formatCompactNumber(adjustment.factor))x"
                }
            }
        }

        switch (stopOrMultiplierText, correctedTimeText) {
        case let (.some(stop), .some(corrected)):
            return "\(stop) · \(corrected)"
        case let (.some(stop), .none):
            return stop
        case let (.none, .some(corrected)):
            return corrected
        case (.none, .none):
            return nil
        }
    }

    private func compactDevelopmentReferenceText(from instruction: String) -> String {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([+-]?\d+%)\s+development$"#

        if let range = trimmedInstruction.range(of: pattern, options: .regularExpression) {
            let matched = String(trimmedInstruction[range])
            let percentage = matched.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: .regularExpression
            )
            return "Dev \(percentage)"
        }

        return trimmedInstruction
    }

    private func formattedReferenceBlock(from lines: [[String]]) -> String {
        let columnCount = lines.map(\.count).max() ?? 0
        let spacing = "    "
        let widths = (0..<max(columnCount - 1, 0)).map { columnIndex in
            lines
                .compactMap { $0.indices.contains(columnIndex) ? $0[columnIndex] : nil }
                .map(\.count)
                .max() ?? 0
        }

        return lines.map { columns in
            columns.enumerated().map { index, column in
                guard index < widths.count else {
                    return column
                }

                let paddingWidth = max(widths[index] - column.count, 0)
                return column + String(repeating: " ", count: paddingWidth) + spacing
            }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        }
        .joined(separator: "\n")
    }

    private func thresholdReferenceText(
        for rule: ThresholdReciprocityRule,
        formatDuration: (Double) -> String
    ) -> String {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return "No correction at \(formatDuration(upperBound)) or less"
        }

        if let upperBound {
            return "No correction from \(formatDuration(lowerBound)) to \(formatDuration(upperBound))"
        }

        return "No correction at \(formatDuration(lowerBound)) or more"
    }

    private func tableEntryReferenceText(
        for entry: ReciprocityTableEntry,
        input: FilmModeDetailsPresenterInput
    ) -> String? {
        let meteredText = meteredExposureSelectorText(entry.meteredExposure, formatDuration: input.formatDuration)

        // Combine stop/multiplier and corrected time the same way the
        // compact column path does (see `combinedExposureColumn`) so
        // both formatters surface both facts when a row carries both.
        let exposureText = combinedExposureColumn(
            adjustments: entry.adjustments,
            input: input
        )

        let developmentText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .development(development) = adjustment else {
                return nil
            }

            return development.instruction
        }.first

        if let exposureText {
            return developmentText.map { "\(meteredText) -> \(exposureText) (\($0))" }
                ?? "\(meteredText) -> \(exposureText)"
        }

        if let developmentText {
            return "\(meteredText) -> \(developmentText)"
        }

        return nil
    }

    private func meteredExposureSelectorText(
        _ selector: MeteredExposureSelector,
        formatDuration: (Double) -> String
    ) -> String {
        switch selector {
        case .exactSeconds(let seconds):
            return formatDuration(seconds)
        case .range(let range):
            let lower = formatDuration(range.minimumSeconds)
            if let maximumSeconds = range.maximumSeconds {
                return "\(lower)-\(formatDuration(maximumSeconds))"
            }
            return "\(lower)+"
        }
    }

    private func formattedStopDelta(_ value: Double) -> String {
        let absolute = abs(value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let magnitude = formatter.string(from: NSNumber(value: absolute)) ?? String(absolute)
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(magnitude) stop" + (abs(absolute - 1) < ExposureCalculator.stabilityEpsilon ? "" : "s")
    }

    /// Formats a formula exponent with up to four decimal digits so
    /// graph-displayed equations preserve the published precision
    /// (e.g. Provia 100F's `1.3676`). Compact decimals — like HP5
    /// Plus's `1.31` — stay short because trailing zeros are
    /// stripped by `minimumFractionDigits = 0`.
    private func formatFormulaExponent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    private func formatCompactNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 10 ? 1 : 2
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private func formatMultiplier(_ value: Double) -> String {
        formatCompactNumber(value)
    }

    private func parseUsableURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }
}
