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
        let validationError = Self.validationError(
            basis: basis,
            estimationFamily: estimationFamily
        )
        precondition(validationError == nil, validationError ?? "Invalid reciprocity calculation policy metadata.")

        self.basis = basis
        self.sourceAuthorityImpact = sourceAuthorityImpact
        self.rangeStatus = rangeStatus
        self.warningLevel = warningLevel
        self.estimationFamily = estimationFamily
        self.notes = notes
        self.referencedRows = referencedRows
    }

    private enum CodingKeys: String, CodingKey {
        case basis
        case sourceAuthorityImpact
        case rangeStatus
        case warningLevel
        case estimationFamily
        case notes
        case referencedRows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let basis = try container.decode(ReciprocityCalculationBasis.self, forKey: .basis)
        let sourceAuthorityImpact = try container.decode(
            ReciprocitySourceAuthorityImpact.self,
            forKey: .sourceAuthorityImpact
        )
        let rangeStatus = try container.decode(ReciprocityCalculationRangeStatus.self, forKey: .rangeStatus)
        let warningLevel = try container.decode(ReciprocityCalculationWarningLevel.self, forKey: .warningLevel)
        let estimationFamily = try container.decodeIfPresent(
            ReciprocityTableEstimationFamily.self,
            forKey: .estimationFamily
        )
        let notes = try container.decodeIfPresent([ReciprocityPolicyNote].self, forKey: .notes) ?? []
        let referencedRows = try container.decodeIfPresent(
            [ReciprocityTableRowReference].self,
            forKey: .referencedRows
        )

        if let validationError = Self.validationError(
            basis: basis,
            estimationFamily: estimationFamily
        ) {
            throw DecodingError.dataCorruptedError(
                forKey: .estimationFamily,
                in: container,
                debugDescription: validationError
            )
        }

        self.basis = basis
        self.sourceAuthorityImpact = sourceAuthorityImpact
        self.rangeStatus = rangeStatus
        self.warningLevel = warningLevel
        self.estimationFamily = estimationFamily
        self.notes = notes
        self.referencedRows = referencedRows
    }

    private static func validationError(
        basis: ReciprocityCalculationBasis,
        estimationFamily: ReciprocityTableEstimationFamily?
    ) -> String? {
        switch basis {
        case .exactTablePoint, .officialThresholdNoCorrection,
             .advisoryOnlyBeyondOfficialRange, .unsupportedOutOfPolicyRange:
            guard estimationFamily == nil else {
                return "\(basis.rawValue) must not carry an estimation family."
            }
        case .interpolatedWithinTable, .extrapolatedBeyondTable:
            guard estimationFamily != nil else {
                return "\(basis.rawValue) must carry an estimation family."
            }
        case .formulaDerived:
            break
        }

        return nil
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
        let validationError = Self.validationError(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: metadata
        )
        precondition(validationError == nil, validationError ?? "Invalid reciprocity calculation policy result.")

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

        if let validationError = Self.validationError(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: metadata
        ) {
            throw DecodingError.dataCorruptedError(
                forKey: .metadata,
                in: container,
                debugDescription: validationError
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

    private static func validationError(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double?,
        metadata: ReciprocityCalculationPolicyResultMetadata
    ) -> String? {
        switch metadata.basis {
        case .officialThresholdNoCorrection:
            guard let correctedExposureSeconds else {
                return "officialThresholdNoCorrection must return a corrected exposure time."
            }

            guard abs(correctedExposureSeconds - meteredExposureSeconds) < 0.000_001 else {
                return "officialThresholdNoCorrection must return corrected exposure equal to metered exposure."
            }
        case .advisoryOnlyBeyondOfficialRange:
            guard correctedExposureSeconds == nil else {
                return "advisoryOnlyBeyondOfficialRange must not return a corrected exposure time."
            }
        case .unsupportedOutOfPolicyRange:
            guard correctedExposureSeconds == nil else {
                return "unsupportedOutOfPolicyRange must not return a corrected exposure time."
            }
        case .interpolatedWithinTable, .extrapolatedBeyondTable:
            guard correctedExposureSeconds != nil else {
                return "\(metadata.basis.rawValue) must return a corrected exposure time."
            }
        case .exactTablePoint, .formulaDerived:
            break
        }

        return nil
    }
}

private extension ReciprocityCalculationPolicyResultMetadata {
    static func exact(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        Self(
            basis: .exactTablePoint,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .withinStatedRange,
            warningLevel: warningLevel(for: .exactTablePoint, sourceAuthorityImpact: sourceAuthorityImpact),
            notes: notes,
            referencedRows: referencedRows
        )
    }

    static func interpolated(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        estimationFamily: ReciprocityTableEstimationFamily,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        Self(
            basis: .interpolatedWithinTable,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .withinInterpretedRange,
            warningLevel: warningLevel(for: .interpolatedWithinTable, sourceAuthorityImpact: sourceAuthorityImpact),
            estimationFamily: estimationFamily,
            notes: notes,
            referencedRows: referencedRows
        )
    }

    static func extrapolated(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        estimationFamily: ReciprocityTableEstimationFamily,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        Self(
            basis: .extrapolatedBeyondTable,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .beyondLastRepresentativePoint,
            warningLevel: warningLevel(for: .extrapolatedBeyondTable, sourceAuthorityImpact: sourceAuthorityImpact),
            estimationFamily: estimationFamily,
            notes: notes,
            referencedRows: referencedRows
        )
    }

    static func thresholdNoCorrection(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            basis: .officialThresholdNoCorrection,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .withinStatedRange,
            warningLevel: warningLevel(for: .officialThresholdNoCorrection, sourceAuthorityImpact: sourceAuthorityImpact),
            notes: notes
        )
    }

    static func advisoryOnly(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            basis: .advisoryOnlyBeyondOfficialRange,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .beyondLastRepresentativePoint,
            warningLevel: warningLevel(for: .advisoryOnlyBeyondOfficialRange, sourceAuthorityImpact: sourceAuthorityImpact),
            notes: notes
        )
    }

    static func unsupported(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]? = nil
    ) -> Self {
        Self(
            basis: .unsupportedOutOfPolicyRange,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .beyondPolicyLimit,
            warningLevel: .strongWarning,
            notes: notes,
            referencedRows: referencedRows
        )
    }

    static func formula(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            basis: .formulaDerived,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .withinStatedRange,
            warningLevel: warningLevel(for: .formulaDerived, sourceAuthorityImpact: sourceAuthorityImpact),
            notes: notes
        )
    }

    private static func warningLevel(
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
}

private extension ReciprocityCalculationPolicyResult {
    static func exact(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: .exact(
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes,
                referencedRows: referencedRows
            )
        )
    }

    static func interpolated(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        estimationFamily: ReciprocityTableEstimationFamily,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: .interpolated(
                sourceAuthorityImpact: sourceAuthorityImpact,
                estimationFamily: estimationFamily,
                notes: notes,
                referencedRows: referencedRows
            )
        )
    }

    static func extrapolated(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        estimationFamily: ReciprocityTableEstimationFamily,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: .extrapolated(
                sourceAuthorityImpact: sourceAuthorityImpact,
                estimationFamily: estimationFamily,
                notes: notes,
                referencedRows: referencedRows
            )
        )
    }

    static func thresholdNoCorrection(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: meteredExposureSeconds,
            metadata: .thresholdNoCorrection(
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes
            )
        )
    }

    static func advisoryOnly(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: nil,
            metadata: .advisoryOnly(
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes
            )
        )
    }

    static func unsupported(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]? = nil
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: nil,
            metadata: .unsupported(
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes,
                referencedRows: referencedRows
            )
        )
    }

    static func formula(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            metadata: .formula(
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes
            )
        )
    }
}

struct ReciprocityCalculationPolicyEvaluator {
    private let comparisonTolerance = 0.000_001

    /// Evaluation order is part of the policy contract:
    /// exact table rows first, then threshold-only no-correction guidance,
    /// then quantified table estimation, then advisory-only continuation,
    /// and finally unsupported.
    func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityCalculationPolicyResult {
        let sourceAuthorityImpact = mapSourceAuthorityImpact(from: profile.source)
        let assembler = ResultAssembler(sourceAuthorityImpact: sourceAuthorityImpact)
        let selector = Selection(
            tableSelectors: profile.rules.compactMap {
                guard case let .table(tableRule) = $0 else {
                    return nil
                }

                return TableSelector(tableRule: tableRule, comparisonTolerance: comparisonTolerance)
            },
            thresholdRules: profile.rules.compactMap {
                guard case let .threshold(thresholdRule) = $0 else {
                    return nil
                }

                return thresholdRule
            },
            formulaRules: profile.rules.compactMap {
                guard case let .formula(formulaRule) = $0 else {
                    return nil
                }

                return formulaRule
            },
            advisoryRules: profile.rules.compactMap {
                guard case let .advisory(advisoryRule) = $0 else {
                    return nil
                }

                return advisoryRule
            }
        )
        let estimator = Estimation()

        for tableSelector in selector.tableSelectors {
            if let result = evaluateExactTableMatch(
                selection: tableSelector,
                meteredExposureSeconds: meteredExposureSeconds,
                assembler: assembler,
                estimator: estimator
            ) {
                return result
            }
        }

        if let thresholdRule = selector.thresholdRule(for: meteredExposureSeconds) {
            return assembler.thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                thresholdRule: thresholdRule
            )
        }

        for tableSelector in selector.tableSelectors {
            if let result = evaluateEstimatedTableResult(
                selection: tableSelector,
                thresholdRules: selector.thresholdRules,
                meteredExposureSeconds: meteredExposureSeconds,
                assembler: assembler,
                estimator: estimator
            ) {
                return result
            }
        }

        if let result = evaluateFormulaResult(
            selection: selector,
            meteredExposureSeconds: meteredExposureSeconds,
            assembler: assembler
        ) {
            return result
        }

        if let advisoryRule = selector.advisoryRule(for: meteredExposureSeconds) {
            return assembler.advisoryOnly(
                meteredExposureSeconds: meteredExposureSeconds,
                advisoryRule: advisoryRule
            )
        }

        return assembler.unsupported(
            meteredExposureSeconds: meteredExposureSeconds,
            notes: [
                ReciprocityPolicyNote(
                    token: .unsupportedByPolicy,
                    text: "No supported reciprocity policy path matched this metered exposure."
                )
            ]
        )
    }

    private func evaluateExactTableMatch(
        selection: TableSelector,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler,
        estimator: Estimation
    ) -> ReciprocityCalculationPolicyResult? {
        guard let match = selection.exactMatch(for: meteredExposureSeconds) else {
            return nil
        }

        if let stopSignalNote = stopSignalNote(for: match.entry) {
            return assembler.unsupportedStopSignal(
                meteredExposureSeconds: meteredExposureSeconds,
                stopSignalNote: stopSignalNote,
                stopSignalBoundary: QuantifiedTableBoundary(
                    rowIndex: match.rowIndex,
                    meteredExposureSeconds: meteredExposureSeconds,
                    meteredExposure: match.entry.meteredExposure,
                    annotationSummary: annotationSummary(for: match.entry)
                )
            )
        }

        guard let correctedExposureSeconds = estimator.correctedExposureSeconds(
            for: match.entry,
            meteredExposureSeconds: meteredExposureSeconds
        ) else {
            return nil
        }

        return assembler.exact(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            notes: exactMatchNotes(for: assembler.sourceAuthorityImpact),
            referencedRows: [
                makeRowReference(
                    entry: match.entry,
                    rowIndex: match.rowIndex,
                    role: .exactMatch
                )
            ]
        )
    }

    private func evaluateEstimatedTableResult(
        selection: TableSelector,
        thresholdRules: [ThresholdReciprocityRule],
        meteredExposureSeconds: Double,
        assembler: ResultAssembler,
        estimator: Estimation
    ) -> ReciprocityCalculationPolicyResult? {
        let quantifiedPoints = selection.quantifiedPoints

        guard quantifiedPoints.count >= 2 else {
            return nil
        }

        if let segment = selection.boundingSegment(for: meteredExposureSeconds) {
            return assembleEstimatedTableResult(
                meteredExposureSeconds: meteredExposureSeconds,
                segment: segment,
                assembler: assembler,
                estimator: estimator
            )
        }

        // Handles the gap between a no-correction threshold and the first quantified table point.
        // Reuses the first two quantified table points as downward extrapolation anchors.
        // No synthetic table rows or fake referencedRows are created.
        if let firstPoint = quantifiedPoints.first,
           quantifiedPoints.count >= 2,
           meteredExposureSeconds < firstPoint.meteredExposureSeconds,
           thresholdRules.contains(where: { rule in
               guard let thresholdMax = rule.noCorrectionRange.maximumSeconds else { return false }
               return meteredExposureSeconds > thresholdMax && thresholdMax < firstPoint.meteredExposureSeconds
           }) {
            return assembleEstimatedTableResult(
                meteredExposureSeconds: meteredExposureSeconds,
                segment: .extrapolated(lowerAnchor: quantifiedPoints[0], upperAnchor: quantifiedPoints[1]),
                assembler: assembler,
                estimator: estimator
            )
        }

        guard let lastQuantifiedPoint = quantifiedPoints.last,
              meteredExposureSeconds > lastQuantifiedPoint.meteredExposureSeconds,
              quantifiedPoints.count >= 2 else {
            return nil
        }

        if let stopSignalBoundary = selection.stopSignalBoundary(
            after: lastQuantifiedPoint.meteredExposureSeconds
        ),
           meteredExposureSeconds >= stopSignalBoundary.meteredExposureSeconds {
            return assembler.unsupportedStopSignal(
                meteredExposureSeconds: meteredExposureSeconds,
                stopSignalNote: ReciprocityPolicyNote(
                    token: .explicitManufacturerStopSignal,
                    text: "An explicit stop-signal row limits extrapolation beyond \(formattedSeconds(stopSignalBoundary.meteredExposureSeconds))."
                ),
                stopSignalBoundary: stopSignalBoundary
            )
        }

        let lowerAnchor = quantifiedPoints[quantifiedPoints.count - 2]
        let upperAnchor = quantifiedPoints[quantifiedPoints.count - 1]

        return assembleEstimatedTableResult(
            meteredExposureSeconds: meteredExposureSeconds,
            segment: .extrapolated(
                lowerAnchor: lowerAnchor,
                upperAnchor: upperAnchor
            ),
            assembler: assembler,
            estimator: estimator
        )
    }

    private func evaluateFormulaResult(
        selection: Selection,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityCalculationPolicyResult? {
        guard let formulaRule = selection.formulaRule(for: meteredExposureSeconds) else {
            if let boundedFormulaRule = selection.firstFormulaRuleExceeded(by: meteredExposureSeconds) {
                return assembler.unsupportedFormulaBoundary(
                    meteredExposureSeconds: meteredExposureSeconds,
                    formulaRule: boundedFormulaRule
                )
            }

            return nil
        }

        guard let correctedExposureSeconds = formulaCorrectedExposureSeconds(
            for: formulaRule.formula,
            meteredExposureSeconds: meteredExposureSeconds
        ) else {
            return nil
        }

        return assembler.formula(
            meteredExposureSeconds: meteredExposureSeconds,
            correctedExposureSeconds: correctedExposureSeconds,
            formulaRule: formulaRule
        )
    }

    private func assembleEstimatedTableResult(
        meteredExposureSeconds: Double,
        segment: EstimableSegment,
        assembler: ResultAssembler,
        estimator: Estimation
    ) -> ReciprocityCalculationPolicyResult? {
        guard let estimate = estimator.estimate(
            meteredExposureSeconds: meteredExposureSeconds,
            segment: segment
        ) else {
            return nil
        }

        switch segment.kind {
        case .interpolated:
            return assembler.interpolated(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: estimate.correctedExposureSeconds,
                estimationFamily: estimate.family,
                referencedRows: segment.referencedRows,
                notes: interpolatedNotes(for: assembler.sourceAuthorityImpact)
            )
        case .extrapolated:
            return assembler.extrapolated(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: estimate.correctedExposureSeconds,
                estimationFamily: estimate.family,
                referencedRows: segment.referencedRows,
                notes: extrapolatedNotes(for: assembler.sourceAuthorityImpact)
            )
        }
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

    private func formulaCorrectedExposureSeconds(
        for formula: ReciprocityFormula,
        meteredExposureSeconds: Double
    ) -> Double? {
        guard meteredExposureSeconds >= 0 else {
            return nil
        }

        switch formula.kind {
        case .exponentPower:
            let coefficient = formula.coefficient ?? 1
            let offsetSeconds = formula.offsetSeconds ?? 0
            return (coefficient * pow(meteredExposureSeconds, formula.exponent)) + offsetSeconds
        }
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
                text: "Low-confidence result extrapolated from the original representative table rows."
            ),
            ReciprocityPolicyNote(
                token: .beyondRepresentativeTablePoint,
                text: "Result extends beyond the last quantified representative point and should be verified with testing."
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

private extension ReciprocityCalculationPolicyEvaluator {
    struct Selection {
        let tableSelectors: [TableSelector]
        let thresholdRules: [ThresholdReciprocityRule]
        let formulaRules: [FormulaReciprocityRule]
        let advisoryRules: [AdvisoryReciprocityRule]

        func thresholdRule(for meteredExposureSeconds: Double) -> ThresholdReciprocityRule? {
            thresholdRules.first { $0.noCorrectionRange.contains(meteredExposureSeconds) }
        }

        func advisoryRule(for meteredExposureSeconds: Double) -> AdvisoryReciprocityRule? {
            advisoryRules.first {
                $0.appliesWhenMetered?.contains(meteredExposureSeconds) ?? true
            }
        }

        func formulaRule(for meteredExposureSeconds: Double) -> FormulaReciprocityRule? {
            formulaRules.first {
                $0.meteredRange?.contains(meteredExposureSeconds) ?? true
            }
        }

        func firstFormulaRuleExceeded(by meteredExposureSeconds: Double) -> FormulaReciprocityRule? {
            formulaRules.first {
                guard let range = $0.meteredRange,
                      let maximumSeconds = range.maximumSeconds else {
                    return false
                }

                return meteredExposureSeconds > maximumSeconds
            }
        }
    }

    struct ResultAssembler {
        let sourceAuthorityImpact: ReciprocitySourceAuthorityImpact

        func exact(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            notes: [ReciprocityPolicyNote],
            referencedRows: [ReciprocityTableRowReference]
        ) -> ReciprocityCalculationPolicyResult {
            .exact(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes,
                referencedRows: referencedRows
            )
        }

        func interpolated(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            estimationFamily: ReciprocityTableEstimationFamily,
            referencedRows: [ReciprocityTableRowReference],
            notes: [ReciprocityPolicyNote]
        ) -> ReciprocityCalculationPolicyResult {
            .interpolated(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                estimationFamily: estimationFamily,
                notes: notes,
                referencedRows: referencedRows
            )
        }

        func extrapolated(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            estimationFamily: ReciprocityTableEstimationFamily,
            referencedRows: [ReciprocityTableRowReference],
            notes: [ReciprocityPolicyNote]
        ) -> ReciprocityCalculationPolicyResult {
            .extrapolated(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                estimationFamily: estimationFamily,
                notes: notes,
                referencedRows: referencedRows
            )
        }

        func thresholdNoCorrection(
            meteredExposureSeconds: Double,
            thresholdRule: ThresholdReciprocityRule
        ) -> ReciprocityCalculationPolicyResult {
            let noteText = thresholdRule.notes.first
                ?? "No correction is required within the stated official threshold range."

            return .thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .thresholdGuidanceOnly,
                        text: noteText
                    )
                ] + sourceAuthorityNotes
            )
        }

        func advisoryOnly(
            meteredExposureSeconds: Double,
            advisoryRule: AdvisoryReciprocityRule
        ) -> ReciprocityCalculationPolicyResult {
            let noteText = advisoryRule.adjustments.compactMap(Self.advisoryNoteText(from:)).first
                ?? advisoryRule.notes.first
                ?? "Only advisory reciprocity guidance is available beyond the official quantified range."

            return .advisoryOnly(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .advisoryContinuationOnly,
                        text: "Only advisory continuation is available for this metered exposure."
                    ),
                    ReciprocityPolicyNote(
                        token: .beyondOfficialQuantifiedRange,
                        text: noteText
                    )
                ] + sourceAuthorityNotes
            )
        }

        func unsupported(
            meteredExposureSeconds: Double,
            notes: [ReciprocityPolicyNote],
            referencedRows: [ReciprocityTableRowReference]? = nil
        ) -> ReciprocityCalculationPolicyResult {
            .unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes + sourceAuthorityNotes,
                referencedRows: referencedRows
            )
        }

        func unsupportedStopSignal(
            meteredExposureSeconds: Double,
            stopSignalNote: ReciprocityPolicyNote,
            stopSignalBoundary: QuantifiedTableBoundary
        ) -> ReciprocityCalculationPolicyResult {
            unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    stopSignalNote,
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Explicit manufacturer stop signals override generic extrapolation allowance."
                    )
                ],
                referencedRows: [stopSignalBoundary.rowReference(role: .stopSignal)]
            )
        }

        func formula(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            formulaRule: FormulaReciprocityRule
        ) -> ReciprocityCalculationPolicyResult {
            let noteText = formulaRule.notes.first
                ?? "Calculated from a reciprocity formula profile."

            return .formula(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(text: noteText)
                ] + sourceAuthorityNotes
            )
        }

        func unsupportedFormulaBoundary(
            meteredExposureSeconds: Double,
            formulaRule: FormulaReciprocityRule
        ) -> ReciprocityCalculationPolicyResult {
            let boundaryText: String
            if let maximumSeconds = formulaRule.meteredRange?.maximumSeconds {
                boundaryText = "Formula guidance is defined only through \(formatBoundarySeconds(maximumSeconds))."
            } else {
                boundaryText = "Formula guidance does not cover this metered exposure."
            }

            return unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .beyondOfficialQuantifiedRange,
                        text: boundaryText
                    ),
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "This metered exposure is beyond the explicit formula policy boundary."
                    )
                ]
            )
        }

        private func formatBoundarySeconds(_ value: Double) -> String {
            if abs(value.rounded() - value) < 0.000_001 {
                return "\(Int(value.rounded())) sec"
            }

            return String(format: "%.3f sec", value)
        }

        private var sourceAuthorityNotes: [ReciprocityPolicyNote] {
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

        private static func advisoryNoteText(from adjustment: ReciprocityAdjustment) -> String? {
            guard case let .note(note) = adjustment else {
                return nil
            }

            return note.text
        }
    }

    struct TableSelector {
        let tableRule: TableReciprocityRule
        let comparisonTolerance: Double
        let quantifiedPoints: [QuantifiedTablePoint]

        init(tableRule: TableReciprocityRule, comparisonTolerance: Double) {
            self.tableRule = tableRule
            self.comparisonTolerance = comparisonTolerance
            self.quantifiedPoints = tableRule.entries.enumerated().compactMap { offset, entry in
                Self.quantifiedPoint(entry: entry, rowIndex: offset)
            }
            .sorted { $0.meteredExposureSeconds < $1.meteredExposureSeconds }
        }

        func exactMatch(for meteredExposureSeconds: Double) -> (rowIndex: Int, entry: ReciprocityTableEntry)? {
            for (index, entry) in tableRule.entries.enumerated() {
                guard entry.meteredExposure.matches(meteredExposureSeconds, tolerance: comparisonTolerance) else {
                    continue
                }

                return (index, entry)
            }

            return nil
        }

        func boundingSegment(for meteredExposureSeconds: Double) -> EstimableSegment? {
            guard let lowerIndex = quantifiedPoints.lastIndex(where: { $0.meteredExposureSeconds < meteredExposureSeconds }),
                  let upperIndex = quantifiedPoints.firstIndex(where: { $0.meteredExposureSeconds > meteredExposureSeconds }) else {
                return nil
            }

            return .interpolated(
                lowerBound: quantifiedPoints[lowerIndex],
                upperBound: quantifiedPoints[upperIndex]
            )
        }

        func stopSignalBoundary(after meteredExposureSeconds: Double) -> QuantifiedTableBoundary? {
            for (index, entry) in tableRule.entries.enumerated() {
                guard Self.stopSignalNote(for: entry) != nil,
                      case let .exactSeconds(rowSeconds) = entry.meteredExposure,
                      rowSeconds > meteredExposureSeconds else {
                    continue
                }

                return QuantifiedTableBoundary(
                    rowIndex: index,
                    meteredExposureSeconds: rowSeconds,
                    meteredExposure: entry.meteredExposure,
                    annotationSummary: Self.annotationSummary(for: entry)
                )
            }

            return nil
        }

        private static func quantifiedPoint(
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

        static func directCorrectedTimeSeconds(for entry: ReciprocityTableEntry) -> Double? {
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

        static func stopDelta(for entry: ReciprocityTableEntry) -> Double? {
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

        private static func annotationSummary(for entry: ReciprocityTableEntry) -> String? {
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

        private static func warningMessage(for entry: ReciprocityTableEntry) -> String? {
            for adjustment in entry.adjustments {
                guard case let .warning(warning) = adjustment else {
                    continue
                }

                return warning.message
            }

            return nil
        }

        private static func stopSignalNote(for entry: ReciprocityTableEntry) -> ReciprocityPolicyNote? {
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
    }

    struct Estimation {
        func correctedExposureSeconds(
            for entry: ReciprocityTableEntry,
            meteredExposureSeconds: Double
        ) -> Double? {
            if let correctedTimeSeconds = TableSelector.directCorrectedTimeSeconds(for: entry) {
                return correctedTimeSeconds
            }

            if let stopDelta = TableSelector.stopDelta(for: entry) {
                return meteredExposureSeconds * pow(2.0, stopDelta)
            }

            return nil
        }

        func estimate(
            meteredExposureSeconds: Double,
            segment: EstimableSegment
        ) -> EstimatedExposure? {
            guard segment.lowerBound.estimationFamily == segment.upperBound.estimationFamily else {
                return nil
            }

            let family = segment.lowerBound.estimationFamily
            let correctedExposureSeconds: Double

            switch family {
            case .logLog:
                let slope = log(segment.upperBound.correctedExposureSeconds / segment.lowerBound.correctedExposureSeconds)
                    / log(segment.upperBound.meteredExposureSeconds / segment.lowerBound.meteredExposureSeconds)
                correctedExposureSeconds = segment.lowerBound.correctedExposureSeconds
                    * pow(meteredExposureSeconds / segment.lowerBound.meteredExposureSeconds, slope)
            case .stopSpace:
                let lowerStopDelta = segment.lowerBound.stopDelta ?? 0
                let upperStopDelta = segment.upperBound.stopDelta ?? 0
                let intervalStops = log2(segment.upperBound.meteredExposureSeconds / segment.lowerBound.meteredExposureSeconds)
                let progressStops = log2(meteredExposureSeconds / segment.lowerBound.meteredExposureSeconds)
                let interpolatedStopDelta = lowerStopDelta
                    + ((upperStopDelta - lowerStopDelta) * (progressStops / intervalStops))
                correctedExposureSeconds = meteredExposureSeconds * pow(2.0, interpolatedStopDelta)
            }

            return EstimatedExposure(
                correctedExposureSeconds: correctedExposureSeconds,
                family: family
            )
        }
    }
}

private struct EstimatedExposure {
    let correctedExposureSeconds: Double
    let family: ReciprocityTableEstimationFamily
}

private struct EstimableSegment {
    enum Kind {
        case interpolated
        case extrapolated
    }

    let kind: Kind
    let lowerBound: QuantifiedTablePoint
    let upperBound: QuantifiedTablePoint
    let referencedRows: [ReciprocityTableRowReference]

    static func interpolated(
        lowerBound: QuantifiedTablePoint,
        upperBound: QuantifiedTablePoint
    ) -> Self {
        Self(
            kind: .interpolated,
            lowerBound: lowerBound,
            upperBound: upperBound,
            referencedRows: [
                lowerBound.rowReference(role: .lowerBound),
                upperBound.rowReference(role: .upperBound)
            ]
        )
    }

    static func extrapolated(
        lowerAnchor: QuantifiedTablePoint,
        upperAnchor: QuantifiedTablePoint
    ) -> Self {
        Self(
            kind: .extrapolated,
            lowerBound: lowerAnchor,
            upperBound: upperAnchor,
            referencedRows: [
                lowerAnchor.rowReference(role: .representativeAnchor),
                upperAnchor.rowReference(role: .representativeAnchor)
            ]
        )
    }
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
