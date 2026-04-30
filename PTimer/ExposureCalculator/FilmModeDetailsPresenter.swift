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
        guard !sections.isEmpty else {
            return nil
        }

        return FilmModeDetailsDisplayState(
            title: "Reciprocity Details",
            summary: makeFilmModeDetailsSummaryState(for: bindingState, input: input),
            currentResult: makeFilmModeDetailsCurrentResultState(input: input),
            sections: sections,
            graph: makeFilmModeDetailsGraphDisplayState(for: bindingState, input: input)
        )
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
            return "Formula-based correction on the active curve"
        case .advisoryOnlyBeyondOfficialRange:
            return "Beyond published no-correction range"
        case .unsupportedOutOfPolicyRange:
            return "Outside supported reciprocity range"
        }
    }

    private func filmModeDetailsSummaryDetailText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        switch bindingState.presentation.category {
        case .unsupported:
            return "Current input is outside the supported range and no quantified corrected point is available."
        case .advisoryOnly:
            return "No published quantified correction is available beyond this range."
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
        let metadata = bindingState.policyResult.metadata
        let presentation = bindingState.presentation

        if metadata.basis == .officialThresholdNoCorrection {
            return "No correction"
        }

        if metadata.basis == .formulaDerived {
            return "Formula-based"
        }

        switch presentation.category {
        case .advisoryOnly:
            return "No quantified correction"
        case .unsupported:
            return "Unsupported"
        case .exact, .estimated, .extrapolated:
            return presentation.shortLabel
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
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsCurrentResultState {
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
                )
            )
        }

        let layout = detailsCurrentResultLayout(input: input)
        let correctedExposureNoteText: String?
        if layout == .compactValue {
            correctedExposureNoteText = "Adjusted shutter equals corrected exposure."
        } else {
            correctedExposureNoteText = correctedExposureDetailText(
                for: filmModeExposureResultState.correctedExposure
            )
        }

        return FilmModeDetailsCurrentResultState(
            layout: layout,
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
            )
        )
    }

    private func detailsCurrentResultLayout(
        input: FilmModeDetailsPresenterInput
    ) -> FilmModeDetailsCurrentResultLayout {
        switch input.bindingState.policyResult.metadata.basis {
        case .officialThresholdNoCorrection:
            return .compactValue
        case .advisoryOnlyBeyondOfficialRange:
            return .compactPair
        case .exactTablePoint,
             .interpolatedWithinTable,
             .extrapolatedBeyondTable,
             .formulaDerived,
             .unsupportedOutOfPolicyRange:
            return .comparison
        }
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

        let profileRows = profileDetailsRows(for: bindingState)
        let referenceRows = referenceDetailsRows(for: bindingState, input: input)
        let sourceRows = sourceDetailsRows(for: bindingState.profile)

        return [
            !profileRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Profile", rows: profileRows)
                : nil,
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
        let profileRows = profileDetailsRows(for: bindingState)
        let formulaRows = formulaReferenceRows(for: bindingState) ?? []
        let sourceRows = sourceDetailsRows(for: bindingState.profile)

        return [
            !profileRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Profile", rows: profileRows)
                : nil,
            !formulaRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Formula", rows: formulaRows)
                : nil,
            !sourceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Sources", rows: sourceRows)
                : nil
        ]
        .compactMap { $0 }
    }

    private func profileDetailsRows(
        for bindingState: FilmModeReciprocityBindingState
    ) -> [FilmModeDetailsRowState] {
        var rows: [FilmModeDetailsRowState] = []
        if let profileText = profileSummaryText(for: bindingState) {
            rows.append(FilmModeDetailsRowState(title: "Profile", value: profileText))
        }
        if let authorityText = profileAuthorityText(for: bindingState.profile) {
            rows.append(FilmModeDetailsRowState(title: "Authority", value: authorityText))
        }
        return rows
    }

    private func profileAuthorityText(for profile: ReciprocityProfile) -> String? {
        switch profile.source.authority {
        case .official:
            return "Official manufacturer guidance"
        case .unofficial:
            return "Unofficial practical approximation"
        case .userDefined, .unknown:
            return nil
        }
    }

    private func profileSummaryText(
        for bindingState: FilmModeReciprocityBindingState
    ) -> String? {
        if bindingState.profile.rules.contains(where: {
            if case .table = $0 { return true }
            return false
        }) {
            return "Reference table"
        }

        if bindingState.profile.rules.contains(where: {
            if case .formula = $0 { return true }
            return false
        }) {
            return "Formula-based guidance"
        }

        if bindingState.presentation.category == .advisoryOnly || bindingState.presentation.category == .unsupported {
            return "No quantified manufacturer data"
        }

        return nil
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
            case .formula, .advisory:
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

    private func sourceDetailsRows(for profile: ReciprocityProfile) -> [FilmModeDetailsRowState] {
        let source = profile.source

        let referenceComponents = [
            normalizedDetailText(source.publisher),
            normalizedDetailText(source.title),
            normalizedDetailText(source.sourceVersion).map { "Version \($0)" }
        ]
            .compactMap { $0 }

        let referenceRow = referenceComponents.isEmpty
            ? nil
            : FilmModeDetailsRowState(
                title: "Reference",
                value: referenceComponents.joined(separator: " · ")
            )

        let citationText = normalizedDetailText(source.citation)
        let citationURL = citationText.flatMap(parseUsableURL(_:))
        let citationRow: FilmModeDetailsRowState? = {
            guard let citationText else {
                return nil
            }

            return FilmModeDetailsRowState(
                title: "Citation",
                value: citationText,
                destinationURL: citationURL
            )
        }()

        return [referenceRow, citationRow].compactMap { $0 }
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
        guard bindingState.policyResult.metadata.basis != .officialThresholdNoCorrection else {
            return nil
        }

        guard let formulaRule = bindingState.profile.rules.compactMap({ rule -> FormulaReciprocityRule? in
            guard case let .formula(formulaRule) = rule else {
                return nil
            }
            return formulaRule
        }).first else {
            return nil
        }

        let sourcePoints = formulaGraphSourcePoints(
            for: formulaRule,
            profile: bindingState.profile,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds
        )
        guard sourcePoints.count >= 2 else {
            return nil
        }

        let ranges = graphRanges(
            sourcePoints: sourcePoints,
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            currentPoint: currentPoint?.point
        )
        guard let ranges else {
            return nil
        }

        let supportedUpperBoundSeconds = formulaRule.meteredRange?.maximumSeconds

        return FilmModeDetailsGraphDisplayState(
            kind: .formula,
            title: "Reference Graph",
            sourcePoints: sourcePoints,
            currentPoint: currentPoint.map {
                FilmModeDetailsGraphCurrentPoint(
                    point: $0.point,
                    style: .formulaDerived
                )
            },
            currentMeteredExposureSeconds: currentMeteredExposureSeconds,
            usesCurrentInputGuideOnly: bindingState.presentation.category == .unsupported,
            caption: "Adjusted shutter vs corrected exposure on the active formula curve",
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
              let correctedExposureSeconds = bindingState.policyResult.correctedExposureSeconds,
              result.resultShutterSeconds > 0,
              correctedExposureSeconds > 0 else {
            return nil
        }

        if bindingState.policyResult.metadata.basis == .officialThresholdNoCorrection {
            return nil
        }

        guard bindingState.presentation.returnsCalculatedExposureTime else {
            return nil
        }

        let style: FilmModeDetailsGraphCurrentPointStyle
        switch bindingState.presentation.category {
        case .exact:
            style = .exact
        case .estimated:
            style = .estimated
        case .extrapolated:
            style = .extrapolated
        case .advisoryOnly, .unsupported:
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
        currentMeteredExposureSeconds: Double
    ) -> [FilmModeDetailsGraphPoint] {
        let thresholdCandidates = profileThresholdUpperBounds(in: profile)
        let lowerBoundCandidates = [
            rule.meteredRange?.minimumSeconds,
            thresholdCandidates.min(),
            currentMeteredExposureSeconds / 4,
            1
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
            .min()
        let positiveUpperBound = upperBoundCandidates
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()

        guard let lowerBound = positiveLowerBound,
              let upperBound = positiveUpperBound else {
            return []
        }

        let clampedLowerBound = min(lowerBound, upperBound)
        let clampedUpperBound = max(lowerBound, upperBound)
        let domain = expandedGraphDomain(
            minimum: clampedLowerBound,
            maximum: clampedUpperBound
        )
        let sampleCount = 24

        return (0..<sampleCount).compactMap { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let meteredExposureSeconds = logInterpolatedValue(
                minimum: domain.lowerBound,
                maximum: domain.upperBound,
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
        let formattedExponent = formatCompactNumber(formula.exponent)

        switch formula.kind {
        case .exponentPower:
            if let equation = normalizedDetailText(formula.equation),
               let substitutedEquation = substituteFormulaPlaceholder(
                in: equation,
                placeholder: "P",
                replacement: formattedExponent
               ) {
                return substitutedEquation
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

    private func compactTableEntryReferenceColumns(
        for entry: ReciprocityTableEntry,
        input: FilmModeDetailsPresenterInput
    ) -> [String]? {
        let meteredText = meteredExposureSelectorText(entry.meteredExposure, formatDuration: input.formatDuration)

        let exposureText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .exposure(exposureAdjustment) = adjustment else {
                return nil
            }

            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return input.formatDuration(mapping.correctedSeconds)
            case .stopDelta(let adjustment):
                return formattedStopDelta(adjustment.stopDelta)
            case .multiplier(let adjustment):
                return "\(formatCompactNumber(adjustment.factor))x"
            }
        }.first

        let developmentText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .development(development) = adjustment else {
                return nil
            }

            return compactDevelopmentReferenceText(from: development.instruction)
        }.first

        let detailColumns = [exposureText, developmentText].compactMap { $0 }
        guard !detailColumns.isEmpty else {
            return nil
        }

        return [meteredText] + detailColumns
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

        let exposureText = entry.adjustments.compactMap { adjustment -> String? in
            guard case let .exposure(exposureAdjustment) = adjustment else {
                return nil
            }

            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return input.formatDuration(mapping.correctedSeconds)
            case .stopDelta(let adjustment):
                return formattedStopDelta(adjustment.stopDelta)
            case .multiplier(let adjustment):
                return "\(formatCompactNumber(adjustment.factor))x"
            }
        }.first

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
