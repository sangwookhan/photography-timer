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
