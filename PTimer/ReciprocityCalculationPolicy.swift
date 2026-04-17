import Foundation

enum ReciprocityCalculationBasis: String, Codable, Equatable {
    case exactTablePoint
    case interpolatedWithinTable
    case extrapolatedBeyondTable
    case officialThresholdNoCorrection
    case advisoryOnlyBeyondOfficialRange
    case unsupportedOutOfPolicyRange
    case formulaDerived
}

enum ReciprocitySourceAuthorityImpact: String, Codable, Equatable {
    case currentOfficial
    case archivalOfficial
    case unofficialSecondary
    case userDefined
}

enum ReciprocityCalculationRangeStatus: String, Codable, Equatable {
    case withinStatedRange
    case withinInterpretedRange
    case beyondLastRepresentativePoint
    case beyondPolicyLimit
}

enum ReciprocityCalculationWarningLevel: String, Codable, Equatable {
    case none
    case note
    case caution
    case strongWarning
}

enum ReciprocityTableEstimationFamily: String, Codable, Equatable {
    case logLog
    case stopSpace
}

enum ReciprocityPolicyNoteToken: String, Codable, Equatable {
    case estimatedFromRepresentativeRows
    case exactManufacturerTablePoint
    case thresholdGuidanceOnly
    case advisoryContinuationOnly
    case explicitManufacturerStopSignal
    case beyondOfficialQuantifiedRange
    case beyondRepresentativeTablePoint
    case archivalOfficialSource
    case unofficialSecondarySource
    case userDefinedSource
    case unsupportedByPolicy
}

struct ReciprocityPolicyNote: Codable, Equatable {
    let token: ReciprocityPolicyNoteToken?
    let text: String

    init(token: ReciprocityPolicyNoteToken? = nil, text: String) {
        self.token = token
        self.text = text
    }
}

enum ReciprocityTableRowRole: String, Codable, Equatable {
    case exactMatch
    case lowerBound
    case upperBound
    case representativeAnchor
    case stopSignal
}

struct ReciprocityTableRowReference: Codable, Equatable {
    let rowIndex: Int
    let role: ReciprocityTableRowRole
    let meteredExposure: MeteredExposureSelector
    let correctedTimeSeconds: Double?
    let stopDelta: Double?
    /// A compact annotation copied from the referenced row when a short
    /// secondary payload is useful for policy inspection. This is not meant
    /// to be a fully structured semantic note model.
    let annotationSummary: String?

    init(
        rowIndex: Int,
        role: ReciprocityTableRowRole,
        meteredExposure: MeteredExposureSelector,
        correctedTimeSeconds: Double? = nil,
        stopDelta: Double? = nil,
        annotationSummary: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.role = role
        self.meteredExposure = meteredExposure
        self.correctedTimeSeconds = correctedTimeSeconds
        self.stopDelta = stopDelta
        self.annotationSummary = annotationSummary
    }
}

struct ReciprocityCalculationPolicyResultMetadata: Codable, Equatable {
    let basis: ReciprocityCalculationBasis
    let sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    let rangeStatus: ReciprocityCalculationRangeStatus
    let warningLevel: ReciprocityCalculationWarningLevel
    let estimationFamily: ReciprocityTableEstimationFamily?
    let notes: [ReciprocityPolicyNote]
    let referencedRows: [ReciprocityTableRowReference]?

    init(
        basis: ReciprocityCalculationBasis,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        rangeStatus: ReciprocityCalculationRangeStatus,
        warningLevel: ReciprocityCalculationWarningLevel,
        estimationFamily: ReciprocityTableEstimationFamily? = nil,
        notes: [ReciprocityPolicyNote] = [],
        referencedRows: [ReciprocityTableRowReference]? = nil
    ) {
        self.basis = basis
        self.sourceAuthorityImpact = sourceAuthorityImpact
        self.rangeStatus = rangeStatus
        self.warningLevel = warningLevel
        self.estimationFamily = estimationFamily
        self.notes = notes
        self.referencedRows = referencedRows
    }
}

struct ReciprocityCalculationPolicyResult: Codable, Equatable {
    let meteredExposureSeconds: Double
    let correctedExposureSeconds: Double?
    let metadata: ReciprocityCalculationPolicyResultMetadata

    var hasCalculatedExposureTime: Bool {
        correctedExposureSeconds != nil
    }

    private enum CodingKeys: String, CodingKey {
        case meteredExposureSeconds
        case correctedExposureSeconds
        case hasCalculatedExposureTime
        case metadata
    }

    init(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double?,
        metadata: ReciprocityCalculationPolicyResultMetadata
    ) {
        self.meteredExposureSeconds = meteredExposureSeconds
        self.correctedExposureSeconds = correctedExposureSeconds
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let meteredExposureSeconds = try container.decode(Double.self, forKey: .meteredExposureSeconds)
        let correctedExposureSeconds = try container.decodeIfPresent(Double.self, forKey: .correctedExposureSeconds)
        let hasCalculatedExposureTime = try container.decode(Bool.self, forKey: .hasCalculatedExposureTime)
        let metadata = try container.decode(ReciprocityCalculationPolicyResultMetadata.self, forKey: .metadata)
        let derivedHasCalculatedExposureTime = correctedExposureSeconds != nil

        guard hasCalculatedExposureTime == derivedHasCalculatedExposureTime else {
            throw DecodingError.dataCorruptedError(
                forKey: .hasCalculatedExposureTime,
                in: container,
                debugDescription: "hasCalculatedExposureTime must match the presence of correctedExposureSeconds."
            )
        }

        self.init(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: metadata
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meteredExposureSeconds, forKey: .meteredExposureSeconds)
        try container.encodeIfPresent(correctedExposureSeconds, forKey: .correctedExposureSeconds)
        try container.encode(hasCalculatedExposureTime, forKey: .hasCalculatedExposureTime)
        try container.encode(metadata, forKey: .metadata)
    }
}

struct ReciprocityCalculationPolicyEvaluator {
    private let comparisonTolerance = 0.000_001

    func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityCalculationPolicyResult {
        let sourceAuthorityImpact = mapSourceAuthorityImpact(from: profile.source)
        let context = ReciprocityPolicyEvaluationContext(
            sourceAuthorityImpact: sourceAuthorityImpact
        )

        for rule in profile.rules {
            guard case let .table(tableRule) = rule else {
                continue
            }

            if let result = evaluateExactTableMatch(
                tableRule: tableRule,
                meteredExposureSeconds: meteredExposureSeconds,
                context: context
            ) {
                return result
            }
        }

        for rule in profile.rules {
            guard case let .threshold(thresholdRule) = rule else {
                continue
            }

            if thresholdRule.noCorrectionRange.contains(meteredExposureSeconds) {
                return makeThresholdNoCorrectionResult(
                    meteredExposureSeconds: meteredExposureSeconds,
                    thresholdRule: thresholdRule,
                    context: context
                )
            }
        }

        for rule in profile.rules {
            guard case let .table(tableRule) = rule else {
                continue
            }

            if let result = evaluateEstimatedTableResult(
                tableRule: tableRule,
                meteredExposureSeconds: meteredExposureSeconds,
                context: context
            ) {
                return result
            }
        }

        for rule in profile.rules {
            guard case let .advisory(advisoryRule) = rule else {
                continue
            }

            let applies = advisoryRule.appliesWhenMetered?.contains(meteredExposureSeconds) ?? true
            if applies {
                return makeAdvisoryOnlyResult(
                    meteredExposureSeconds: meteredExposureSeconds,
                    advisoryRule: advisoryRule,
                    context: context
                )
            }
        }

        return makeUnsupportedResult(
            meteredExposureSeconds: meteredExposureSeconds,
            sourceAuthorityImpact: sourceAuthorityImpact,
            notes: [
                ReciprocityPolicyNote(
                    token: .unsupportedByPolicy,
                    text: "No supported reciprocity policy path matched this metered exposure."
                )
            ]
        )
    }

    private func evaluateExactTableMatch(
        tableRule: TableReciprocityRule,
        meteredExposureSeconds: Double,
        context: ReciprocityPolicyEvaluationContext
    ) -> ReciprocityCalculationPolicyResult? {
        for (index, entry) in tableRule.entries.enumerated() {
            guard entry.meteredExposure.matches(meteredExposureSeconds, tolerance: comparisonTolerance) else {
                continue
            }

            if let stopSignalNote = stopSignalNote(for: entry) {
                return makeUnsupportedResult(
                    meteredExposureSeconds: meteredExposureSeconds,
                    sourceAuthorityImpact: context.sourceAuthorityImpact,
                    notes: [
                        stopSignalNote,
                        ReciprocityPolicyNote(
                            token: .unsupportedByPolicy,
                            text: "Explicit manufacturer stop signals override generic extrapolation allowance."
                        )
                    ],
                    referencedRows: [
                        makeRowReference(
                            entry: entry,
                            rowIndex: index,
                            role: .stopSignal
                        )
                    ]
                )
            }

            let rowReference = makeRowReference(
                entry: entry,
                rowIndex: index,
                role: .exactMatch
            )

            guard let correctedExposureSeconds = correctedExposureSeconds(
                for: entry,
                meteredExposureSeconds: meteredExposureSeconds
            ) else {
                continue
            }

            return ReciprocityCalculationPolicyResult(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .exactTablePoint,
                    sourceAuthorityImpact: context.sourceAuthorityImpact,
                    rangeStatus: .withinStatedRange,
                    warningLevel: warningLevel(
                        for: .exactTablePoint,
                        sourceAuthorityImpact: context.sourceAuthorityImpact
                    ),
                    notes: exactMatchNotes(for: context.sourceAuthorityImpact),
                    referencedRows: [rowReference]
                )
            )
        }

        return nil
    }

    private func evaluateEstimatedTableResult(
        tableRule: TableReciprocityRule,
        meteredExposureSeconds: Double,
        context: ReciprocityPolicyEvaluationContext
    ) -> ReciprocityCalculationPolicyResult? {
        let quantifiedPoints = tableRule.entries.enumerated().compactMap { offset, entry in
            quantifiedPoint(entry: entry, rowIndex: offset)
        }
        .sorted { $0.meteredExposureSeconds < $1.meteredExposureSeconds }

        guard quantifiedPoints.count >= 2 else {
            return nil
        }

        if let lowerIndex = quantifiedPoints.lastIndex(where: { $0.meteredExposureSeconds < meteredExposureSeconds }),
           let upperIndex = quantifiedPoints.firstIndex(where: { $0.meteredExposureSeconds > meteredExposureSeconds }) {
            let lowerBound = quantifiedPoints[lowerIndex]
            let upperBound = quantifiedPoints[upperIndex]
            guard let estimationFamily = estimationFamily(lowerBound: lowerBound, upperBound: upperBound) else {
                return nil
            }

            let correctedExposureSeconds = estimatedCorrectedExposureSeconds(
                meteredExposureSeconds: meteredExposureSeconds,
                lowerBound: lowerBound,
                upperBound: upperBound,
                estimationFamily: estimationFamily
            )

            return ReciprocityCalculationPolicyResult(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .interpolatedWithinTable,
                    sourceAuthorityImpact: context.sourceAuthorityImpact,
                    rangeStatus: .withinInterpretedRange,
                    warningLevel: warningLevel(
                        for: .interpolatedWithinTable,
                        sourceAuthorityImpact: context.sourceAuthorityImpact
                    ),
                    estimationFamily: estimationFamily,
                    notes: interpolatedNotes(for: context.sourceAuthorityImpact),
                    referencedRows: [
                        lowerBound.rowReference(role: .lowerBound),
                        upperBound.rowReference(role: .upperBound)
                    ]
                )
            )
        }

        guard let lastQuantifiedPoint = quantifiedPoints.last,
              meteredExposureSeconds > lastQuantifiedPoint.meteredExposureSeconds,
              quantifiedPoints.count >= 2 else {
            return nil
        }

        if let stopSignalBoundary = firstStopSignalBoundary(
            in: tableRule,
            after: lastQuantifiedPoint.meteredExposureSeconds
        ),
           meteredExposureSeconds >= stopSignalBoundary.meteredExposureSeconds {
            return makeUnsupportedResult(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: context.sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .explicitManufacturerStopSignal,
                        text: "An explicit stop-signal row limits extrapolation beyond \(formattedSeconds(stopSignalBoundary.meteredExposureSeconds))."
                    ),
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Explicit manufacturer stop signals override generic extrapolation allowance."
                    )
                ],
                referencedRows: [stopSignalBoundary.rowReference(role: .stopSignal)]
            )
        }

        let extrapolationLimit = nextOrderOfMagnitudeLimit(
            from: lastQuantifiedPoint.meteredExposureSeconds
        )

        guard meteredExposureSeconds < extrapolationLimit else {
            return makeUnsupportedResult(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: context.sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .beyondRepresentativeTablePoint,
                        text: "Quantified extrapolation is limited to less than \(formattedSeconds(extrapolationLimit))."
                    ),
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "This metered exposure is beyond the current extrapolation policy limit."
                    )
                ]
            )
        }

        let lowerAnchor = quantifiedPoints[quantifiedPoints.count - 2]
        let upperAnchor = quantifiedPoints[quantifiedPoints.count - 1]
        guard let estimationFamily = estimationFamily(lowerBound: lowerAnchor, upperBound: upperAnchor) else {
            return nil
        }

        let correctedExposureSeconds = estimatedCorrectedExposureSeconds(
            meteredExposureSeconds: meteredExposureSeconds,
            lowerBound: lowerAnchor,
            upperBound: upperAnchor,
            estimationFamily: estimationFamily
        )

        return ReciprocityCalculationPolicyResult(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: ReciprocityCalculationPolicyResultMetadata(
                basis: .extrapolatedBeyondTable,
                sourceAuthorityImpact: context.sourceAuthorityImpact,
                rangeStatus: .beyondLastRepresentativePoint,
                warningLevel: warningLevel(
                    for: .extrapolatedBeyondTable,
                    sourceAuthorityImpact: context.sourceAuthorityImpact
                ),
                estimationFamily: estimationFamily,
                notes: extrapolatedNotes(for: context.sourceAuthorityImpact),
                referencedRows: [
                    lowerAnchor.rowReference(role: .representativeAnchor),
                    upperAnchor.rowReference(role: .representativeAnchor)
                ]
            )
        )
    }

    private func makeThresholdNoCorrectionResult(
        meteredExposureSeconds: Double,
        thresholdRule: ThresholdReciprocityRule,
        context: ReciprocityPolicyEvaluationContext
    ) -> ReciprocityCalculationPolicyResult {
        let noteText = thresholdRule.notes.first ?? "No correction is required within the stated official threshold range."

        return ReciprocityCalculationPolicyResult(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: meteredExposureSeconds,
            metadata: ReciprocityCalculationPolicyResultMetadata(
                basis: .officialThresholdNoCorrection,
                sourceAuthorityImpact: context.sourceAuthorityImpact,
                rangeStatus: .withinStatedRange,
                warningLevel: warningLevel(
                    for: .officialThresholdNoCorrection,
                    sourceAuthorityImpact: context.sourceAuthorityImpact
                ),
                notes: [
                    ReciprocityPolicyNote(
                        token: .thresholdGuidanceOnly,
                        text: noteText
                    )
                ] + sourceAuthorityNotes(for: context.sourceAuthorityImpact)
            )
        )
    }

    private func makeAdvisoryOnlyResult(
        meteredExposureSeconds: Double,
        advisoryRule: AdvisoryReciprocityRule,
        context: ReciprocityPolicyEvaluationContext
    ) -> ReciprocityCalculationPolicyResult {
        let noteText = advisoryRule.adjustments.compactMap(advisoryNoteText(from:)).first
            ?? advisoryRule.notes.first
            ?? "Only advisory reciprocity guidance is available beyond the official quantified range."

        return ReciprocityCalculationPolicyResult(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: nil,
            metadata: ReciprocityCalculationPolicyResultMetadata(
                basis: .advisoryOnlyBeyondOfficialRange,
                sourceAuthorityImpact: context.sourceAuthorityImpact,
                rangeStatus: .beyondLastRepresentativePoint,
                warningLevel: warningLevel(
                    for: .advisoryOnlyBeyondOfficialRange,
                    sourceAuthorityImpact: context.sourceAuthorityImpact
                ),
                notes: [
                    ReciprocityPolicyNote(
                        token: .advisoryContinuationOnly,
                        text: "Only advisory continuation is available for this metered exposure."
                    ),
                    ReciprocityPolicyNote(
                        token: .beyondOfficialQuantifiedRange,
                        text: noteText
                    )
                ] + sourceAuthorityNotes(for: context.sourceAuthorityImpact)
            )
        )
    }

    private func makeUnsupportedResult(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]? = nil
    ) -> ReciprocityCalculationPolicyResult {
        ReciprocityCalculationPolicyResult(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: nil,
            metadata: ReciprocityCalculationPolicyResultMetadata(
                basis: .unsupportedOutOfPolicyRange,
                sourceAuthorityImpact: sourceAuthorityImpact,
                rangeStatus: .beyondPolicyLimit,
                warningLevel: .strongWarning,
                notes: notes + sourceAuthorityNotes(for: sourceAuthorityImpact),
                referencedRows: referencedRows
            )
        )
    }

    private func quantifiedPoint(
        entry: ReciprocityTableEntry,
        rowIndex: Int
    ) -> QuantifiedTablePoint? {
        guard case let .exactSeconds(meteredExposureSeconds) = entry.meteredExposure else {
            return nil
        }

        if stopSignalNote(for: entry) != nil {
            return nil
        }

        if let correctedTimeSeconds = directCorrectedTimeSeconds(for: entry) {
            return QuantifiedTablePoint(
                rowIndex: rowIndex,
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedTimeSeconds,
                estimationFamily: .logLog,
                stopDelta: stopDelta(for: entry),
                annotationSummary: annotationSummary(for: entry)
            )
        }

        if let stopDelta = stopDelta(for: entry) {
            return QuantifiedTablePoint(
                rowIndex: rowIndex,
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: meteredExposureSeconds * pow(2.0, stopDelta),
                estimationFamily: .stopSpace,
                stopDelta: stopDelta,
                annotationSummary: annotationSummary(for: entry)
            )
        }

        return nil
    }

    private func makeRowReference(
        entry: ReciprocityTableEntry,
        rowIndex: Int,
        role: ReciprocityTableRowRole
    ) -> ReciprocityTableRowReference {
        ReciprocityTableRowReference(
            rowIndex: rowIndex,
            role: role,
            meteredExposure: entry.meteredExposure,
            correctedTimeSeconds: directCorrectedTimeSeconds(for: entry),
            stopDelta: stopDelta(for: entry),
            annotationSummary: annotationSummary(for: entry)
        )
    }

    private func correctedExposureSeconds(
        for entry: ReciprocityTableEntry,
        meteredExposureSeconds: Double
    ) -> Double? {
        if let correctedTimeSeconds = directCorrectedTimeSeconds(for: entry) {
            return correctedTimeSeconds
        }

        if let stopDelta = stopDelta(for: entry) {
            return meteredExposureSeconds * pow(2.0, stopDelta)
        }

        return nil
    }

    private func directCorrectedTimeSeconds(for entry: ReciprocityTableEntry) -> Double? {
        for adjustment in entry.adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }

            if case let .correctedTime(mapping) = exposureAdjustment {
                return mapping.correctedSeconds
            }
        }

        return nil
    }

    private func stopDelta(for entry: ReciprocityTableEntry) -> Double? {
        for adjustment in entry.adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }

            switch exposureAdjustment {
            case let .stopDelta(value):
                return value.stopDelta
            case let .multiplier(value):
                guard value.factor > 0 else {
                    return nil
                }

                return log2(value.factor)
            case .correctedTime:
                continue
            }
        }

        return nil
    }

    private func annotationSummary(for entry: ReciprocityTableEntry) -> String? {
        if let warningMessage = warningMessage(for: entry) {
            return warningMessage
        }

        for adjustment in entry.adjustments {
            switch adjustment {
            case let .colorFilter(recommendation):
                return recommendation.filterName
            case let .note(note):
                return note.text
            default:
                continue
            }
        }

        return entry.notes.first
    }

    private func warningMessage(for entry: ReciprocityTableEntry) -> String? {
        for adjustment in entry.adjustments {
            guard case let .warning(warning) = adjustment else {
                continue
            }

            return warning.message
        }

        return nil
    }

    private func stopSignalNote(for entry: ReciprocityTableEntry) -> ReciprocityPolicyNote? {
        for adjustment in entry.adjustments {
            guard case let .warning(warning) = adjustment else {
                continue
            }

            if warning.severity == .notRecommended {
                return ReciprocityPolicyNote(
                    token: .explicitManufacturerStopSignal,
                    text: warning.message
                )
            }
        }

        return nil
    }

    private func advisoryNoteText(from adjustment: ReciprocityAdjustment) -> String? {
        guard case let .note(note) = adjustment else {
            return nil
        }

        return note.text
    }

    private func estimationFamily(
        lowerBound: QuantifiedTablePoint,
        upperBound: QuantifiedTablePoint
    ) -> ReciprocityTableEstimationFamily? {
        guard lowerBound.estimationFamily == upperBound.estimationFamily else {
            return nil
        }

        return lowerBound.estimationFamily
    }

    private func estimatedCorrectedExposureSeconds(
        meteredExposureSeconds: Double,
        lowerBound: QuantifiedTablePoint,
        upperBound: QuantifiedTablePoint,
        estimationFamily: ReciprocityTableEstimationFamily
    ) -> Double {
        switch estimationFamily {
        case .logLog:
            let slope = log(upperBound.correctedExposureSeconds / lowerBound.correctedExposureSeconds)
                / log(upperBound.meteredExposureSeconds / lowerBound.meteredExposureSeconds)
            return lowerBound.correctedExposureSeconds
                * pow(meteredExposureSeconds / lowerBound.meteredExposureSeconds, slope)
        case .stopSpace:
            let lowerStopDelta = lowerBound.stopDelta ?? 0
            let upperStopDelta = upperBound.stopDelta ?? 0
            let intervalStops = log2(upperBound.meteredExposureSeconds / lowerBound.meteredExposureSeconds)
            let progressStops = log2(meteredExposureSeconds / lowerBound.meteredExposureSeconds)
            let interpolatedStopDelta = lowerStopDelta
                + ((upperStopDelta - lowerStopDelta) * (progressStops / intervalStops))
            return meteredExposureSeconds * pow(2.0, interpolatedStopDelta)
        }
    }

    private func nextOrderOfMagnitudeLimit(from meteredExposureSeconds: Double) -> Double {
        pow(10.0, floor(log10(meteredExposureSeconds)) + 1)
    }

    private func firstStopSignalBoundary(
        in tableRule: TableReciprocityRule,
        after meteredExposureSeconds: Double
    ) -> QuantifiedTableBoundary? {
        for (index, entry) in tableRule.entries.enumerated() {
            guard stopSignalNote(for: entry) != nil,
                  case let .exactSeconds(rowSeconds) = entry.meteredExposure,
                  rowSeconds > meteredExposureSeconds else {
                continue
            }

            return QuantifiedTableBoundary(
                rowIndex: index,
                meteredExposureSeconds: rowSeconds,
                meteredExposure: entry.meteredExposure,
                annotationSummary: annotationSummary(for: entry)
            )
        }

        return nil
    }

    private func exactMatchNotes(
        for sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> [ReciprocityPolicyNote] {
        [
            ReciprocityPolicyNote(
                token: .exactManufacturerTablePoint,
                text: "Returned from an explicit representative table point."
            )
        ] + sourceAuthorityNotes(for: sourceAuthorityImpact)
    }

    private func interpolatedNotes(
        for sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> [ReciprocityPolicyNote] {
        [
            ReciprocityPolicyNote(
                token: .estimatedFromRepresentativeRows,
                text: "Interpolated between original representative table rows."
            )
        ] + sourceAuthorityNotes(for: sourceAuthorityImpact)
    }

    private func extrapolatedNotes(
        for sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> [ReciprocityPolicyNote] {
        [
            ReciprocityPolicyNote(
                token: .estimatedFromRepresentativeRows,
                text: "Extrapolated from the original representative table rows."
            ),
            ReciprocityPolicyNote(
                token: .beyondRepresentativeTablePoint,
                text: "Result extends beyond the last quantified representative point within the current policy limit."
            )
        ] + sourceAuthorityNotes(for: sourceAuthorityImpact)
    }

    private func sourceAuthorityNotes(
        for sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> [ReciprocityPolicyNote] {
        switch sourceAuthorityImpact {
        case .currentOfficial:
            return []
        case .archivalOfficial:
            return [
                ReciprocityPolicyNote(
                    token: .archivalOfficialSource,
                    text: "Result is based on archival official reciprocity data."
                )
            ]
        case .unofficialSecondary:
            return [
                ReciprocityPolicyNote(
                    token: .unofficialSecondarySource,
                    text: "Result is based on an unofficial secondary reciprocity source."
                )
            ]
        case .userDefined:
            return [
                ReciprocityPolicyNote(
                    token: .userDefinedSource,
                    text: "Result is based on user-defined reciprocity data."
                )
            ]
        }
    }

    private func warningLevel(
        for basis: ReciprocityCalculationBasis,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> ReciprocityCalculationWarningLevel {
        switch basis {
        case .exactTablePoint, .officialThresholdNoCorrection:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return .none
            case .archivalOfficial:
                return .note
            case .unofficialSecondary, .userDefined:
                return .caution
            }
        case .interpolatedWithinTable:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return .note
            case .archivalOfficial, .unofficialSecondary, .userDefined:
                return .caution
            }
        case .extrapolatedBeyondTable:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return .caution
            case .archivalOfficial, .unofficialSecondary, .userDefined:
                return .strongWarning
            }
        case .advisoryOnlyBeyondOfficialRange:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return .note
            case .archivalOfficial, .unofficialSecondary, .userDefined:
                return .caution
            }
        case .unsupportedOutOfPolicyRange:
            return .strongWarning
        case .formulaDerived:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return .none
            case .archivalOfficial:
                return .note
            case .unofficialSecondary, .userDefined:
                return .caution
            }
        }
    }

    private func mapSourceAuthorityImpact(
        from source: ReciprocitySourceProvenance
    ) -> ReciprocitySourceAuthorityImpact {
        switch source.kind {
        case .manufacturerPublished:
            return .currentOfficial
        case .manufacturerArchive:
            return .archivalOfficial
        case .thirdPartyPublication:
            return .unofficialSecondary
        case .userDefined:
            return .userDefined
        case .unknown:
            switch source.authority {
            case .official:
                return .currentOfficial
            case .unofficial:
                return .unofficialSecondary
            case .userDefined:
                return .userDefined
            case .unknown:
                return .unofficialSecondary
            }
        }
    }

    private func formattedSeconds(_ value: Double) -> String {
        if abs(value.rounded() - value) < comparisonTolerance {
            return "\(Int(value.rounded())) sec"
        }

        return String(format: "%.3f sec", value)
    }
}

private struct ReciprocityPolicyEvaluationContext {
    let sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
}

private struct QuantifiedTablePoint {
    let rowIndex: Int
    let meteredExposureSeconds: Double
    let correctedExposureSeconds: Double
    let estimationFamily: ReciprocityTableEstimationFamily
    let stopDelta: Double?
    let annotationSummary: String?

    func rowReference(role: ReciprocityTableRowRole) -> ReciprocityTableRowReference {
        ReciprocityTableRowReference(
            rowIndex: rowIndex,
            role: role,
            meteredExposure: .exactSeconds(meteredExposureSeconds),
            correctedTimeSeconds: estimationFamily == .logLog ? correctedExposureSeconds : nil,
            stopDelta: stopDelta,
            annotationSummary: annotationSummary
        )
    }
}

private struct QuantifiedTableBoundary {
    let rowIndex: Int
    let meteredExposureSeconds: Double
    let meteredExposure: MeteredExposureSelector
    let annotationSummary: String?

    func rowReference(role: ReciprocityTableRowRole) -> ReciprocityTableRowReference {
        ReciprocityTableRowReference(
            rowIndex: rowIndex,
            role: role,
            meteredExposure: meteredExposure,
            annotationSummary: annotationSummary
        )
    }
}

private extension ReciprocityTimeRange {
    func contains(_ seconds: Double) -> Bool {
        guard seconds >= minimumSeconds else {
            return false
        }

        guard let maximumSeconds else {
            return true
        }

        return seconds <= maximumSeconds
    }
}

private extension MeteredExposureSelector {
    func matches(_ seconds: Double, tolerance: Double) -> Bool {
        switch self {
        case let .exactSeconds(value):
            return abs(value - seconds) < tolerance
        case let .range(range):
            return range.contains(seconds)
        }
    }
}
