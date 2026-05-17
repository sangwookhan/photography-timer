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

/// Tagged-union representation of a reciprocity calculation outcome.
///
/// The three cases encode the (basis, corrected_present) invariant in the
/// type system:
/// - `quantified` always carries a non-Optional `correctedExposureSeconds`.
/// - `advisoryOnly` and `unsupported` lack the field entirely.
///
/// This eliminates the runtime `didReturnCalculatedTime` ↔ corrected-Optional
/// pairing check that the previous struct-shaped representation
/// enforced in its decoder.
enum ReciprocityResult: Equatable {
    case quantified(QuantifiedPayload)
    case advisoryOnly(AdvisoryOnlyPayload)
    case unsupported(UnsupportedPayload)

    struct QuantifiedPayload: Equatable {
        let meteredExposureSeconds: Double
        let correctedExposureSeconds: Double
        let metadata: ReciprocityCalculationPolicyResultMetadata

        init(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            metadata: ReciprocityCalculationPolicyResultMetadata
        ) {
            let validationError = ReciprocityResult.quantifiedValidationError(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: metadata
            )
            precondition(validationError == nil, validationError ?? "Invalid quantified reciprocity result.")

            self.meteredExposureSeconds = meteredExposureSeconds
            self.correctedExposureSeconds = correctedExposureSeconds
            self.metadata = metadata
        }
    }

    struct AdvisoryOnlyPayload: Equatable {
        let meteredExposureSeconds: Double
        let metadata: ReciprocityCalculationPolicyResultMetadata

        init(
            meteredExposureSeconds: Double,
            metadata: ReciprocityCalculationPolicyResultMetadata
        ) {
            precondition(
                metadata.basis == .advisoryOnlyBeyondOfficialRange,
                "advisoryOnly payload must carry advisoryOnlyBeyondOfficialRange basis."
            )

            self.meteredExposureSeconds = meteredExposureSeconds
            self.metadata = metadata
        }
    }

    struct UnsupportedPayload: Equatable {
        let meteredExposureSeconds: Double
        /// Optional formula-extrapolated corrected exposure seconds. Present
        /// only when a formula-backed profile can still produce a numeric
        /// value beyond the manufacturer-supported boundary; absent for
        /// table-only or threshold-only unsupported results. The presenter
        /// must mark numeric values as approximate / outside manufacturer
        /// guidance — they are calculation-derived, never published guidance.
        let correctedExposureSeconds: Double?
        let metadata: ReciprocityCalculationPolicyResultMetadata

        init(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double? = nil,
            metadata: ReciprocityCalculationPolicyResultMetadata
        ) {
            precondition(
                metadata.basis == .unsupportedOutOfPolicyRange,
                "unsupported payload must carry unsupportedOutOfPolicyRange basis."
            )

            self.meteredExposureSeconds = meteredExposureSeconds
            self.correctedExposureSeconds = correctedExposureSeconds
            self.metadata = metadata
        }
    }

    fileprivate static func quantifiedValidationError(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        metadata: ReciprocityCalculationPolicyResultMetadata
    ) -> String? {
        switch metadata.basis {
        case .officialThresholdNoCorrection:
            guard abs(correctedExposureSeconds - meteredExposureSeconds) < 0.000_001 else {
                return "officialThresholdNoCorrection must return corrected exposure equal to metered exposure."
            }
        case .advisoryOnlyBeyondOfficialRange:
            return "advisoryOnlyBeyondOfficialRange must not be carried by a quantified payload."
        case .unsupportedOutOfPolicyRange:
            return "unsupportedOutOfPolicyRange must not be carried by a quantified payload."
        case .exactTablePoint,
             .interpolatedWithinTable,
             .extrapolatedBeyondTable,
             .formulaDerived:
            break
        }

        return nil
    }
}

extension ReciprocityResult {
    /// Metered exposure seconds — present in every case.
    var meteredExposureSeconds: Double {
        switch self {
        case let .quantified(payload):
            return payload.meteredExposureSeconds
        case let .advisoryOnly(payload):
            return payload.meteredExposureSeconds
        case let .unsupported(payload):
            return payload.meteredExposureSeconds
        }
    }

    /// Convenience accessor matching the legacy struct field. Returns
    /// the quantified case's corrected exposure, the unsupported case's
    /// optional formula-extrapolated value when present, or `nil` for
    /// advisory and value-less unsupported results.
    var correctedExposureSeconds: Double? {
        switch self {
        case let .quantified(payload):
            return payload.correctedExposureSeconds
        case let .unsupported(payload):
            return payload.correctedExposureSeconds
        case .advisoryOnly:
            return nil
        }
    }

    /// Metadata block — present in every case.
    var metadata: ReciprocityCalculationPolicyResultMetadata {
        switch self {
        case let .quantified(payload):
            return payload.metadata
        case let .advisoryOnly(payload):
            return payload.metadata
        case let .unsupported(payload):
            return payload.metadata
        }
    }

    /// Convenience flag matching the legacy struct field. True when a
    /// numeric corrected exposure was returned — either from a quantified
    /// path, or from a formula-backed unsupported payload that carries a
    /// formula-extrapolated value.
    var hasCalculatedExposureTime: Bool {
        switch self {
        case .quantified:
            return true
        case let .unsupported(payload):
            return payload.correctedExposureSeconds != nil
        case .advisoryOnly:
            return false
        }
    }
}

// MARK: - Codable

extension ReciprocityResult: Codable {
    private enum DiscriminatorKeys: String, CodingKey {
        case kind
        case payload
    }

    private enum LegacyKeys: String, CodingKey {
        case meteredExposureSeconds
        case correctedExposureSeconds
        case hasCalculatedExposureTime
        case metadata
    }

    private enum Kind: String, Codable {
        case quantified
        case advisoryOnly
        case unsupported
    }

    private struct QuantifiedPayloadDTO: Codable {
        let meteredExposureSeconds: Double
        let correctedExposureSeconds: Double
        let metadata: ReciprocityCalculationPolicyResultMetadata
    }

    private struct AdvisoryOnlyPayloadDTO: Codable {
        let meteredExposureSeconds: Double
        let metadata: ReciprocityCalculationPolicyResultMetadata
    }

    private struct UnsupportedPayloadDTO: Codable {
        let meteredExposureSeconds: Double
        // Optional so older snapshots that predate formula-extrapolated
        // unsupported numeric values decode unchanged.
        let correctedExposureSeconds: Double?
        let metadata: ReciprocityCalculationPolicyResultMetadata

        init(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double?,
            metadata: ReciprocityCalculationPolicyResultMetadata
        ) {
            self.meteredExposureSeconds = meteredExposureSeconds
            self.correctedExposureSeconds = correctedExposureSeconds
            self.metadata = metadata
        }

        private enum CodingKeys: String, CodingKey {
            case meteredExposureSeconds
            case correctedExposureSeconds
            case metadata
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.meteredExposureSeconds = try container.decode(Double.self, forKey: .meteredExposureSeconds)
            self.correctedExposureSeconds = try container.decodeIfPresent(Double.self, forKey: .correctedExposureSeconds)
            self.metadata = try container.decode(
                ReciprocityCalculationPolicyResultMetadata.self,
                forKey: .metadata
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(meteredExposureSeconds, forKey: .meteredExposureSeconds)
            try container.encodeIfPresent(correctedExposureSeconds, forKey: .correctedExposureSeconds)
            try container.encode(metadata, forKey: .metadata)
        }
    }

    init(from decoder: Decoder) throws {
        let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorKeys.self)

        if let kind = try discriminatorContainer.decodeIfPresent(Kind.self, forKey: .kind) {
            // New tagged format.
            switch kind {
            case .quantified:
                let payload = try discriminatorContainer.decode(QuantifiedPayloadDTO.self, forKey: .payload)
                if let validationError = ReciprocityResult.quantifiedValidationError(
                    meteredExposureSeconds: payload.meteredExposureSeconds,
                    correctedExposureSeconds: payload.correctedExposureSeconds,
                    metadata: payload.metadata
                ) {
                    throw DecodingError.dataCorruptedError(
                        forKey: .payload,
                        in: discriminatorContainer,
                        debugDescription: validationError
                    )
                }
                self = .quantified(
                    QuantifiedPayload(
                        meteredExposureSeconds: payload.meteredExposureSeconds,
                        correctedExposureSeconds: payload.correctedExposureSeconds,
                        metadata: payload.metadata
                    )
                )
            case .advisoryOnly:
                let payload = try discriminatorContainer.decode(AdvisoryOnlyPayloadDTO.self, forKey: .payload)
                guard payload.metadata.basis == .advisoryOnlyBeyondOfficialRange else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .payload,
                        in: discriminatorContainer,
                        debugDescription: "advisoryOnly payload must carry advisoryOnlyBeyondOfficialRange basis."
                    )
                }
                self = .advisoryOnly(
                    AdvisoryOnlyPayload(
                        meteredExposureSeconds: payload.meteredExposureSeconds,
                        metadata: payload.metadata
                    )
                )
            case .unsupported:
                let payload = try discriminatorContainer.decode(UnsupportedPayloadDTO.self, forKey: .payload)
                guard payload.metadata.basis == .unsupportedOutOfPolicyRange else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .payload,
                        in: discriminatorContainer,
                        debugDescription: "unsupported payload must carry unsupportedOutOfPolicyRange basis."
                    )
                }
                self = .unsupported(
                    UnsupportedPayload(
                        meteredExposureSeconds: payload.meteredExposureSeconds,
                        correctedExposureSeconds: payload.correctedExposureSeconds,
                        metadata: payload.metadata
                    )
                )
            }
            return
        }

        // Legacy 7-field format. Reconstruct enum case from
        // (metadata.basis, correctedExposureSeconds presence).
        let legacyContainer = try decoder.container(keyedBy: LegacyKeys.self)
        let meteredExposureSeconds = try legacyContainer.decode(Double.self, forKey: .meteredExposureSeconds)
        let correctedExposureSeconds = try legacyContainer.decodeIfPresent(Double.self, forKey: .correctedExposureSeconds)
        let hasCalculatedExposureTime = try legacyContainer.decode(Bool.self, forKey: .hasCalculatedExposureTime)
        let metadata = try legacyContainer.decode(ReciprocityCalculationPolicyResultMetadata.self, forKey: .metadata)

        guard hasCalculatedExposureTime == (correctedExposureSeconds != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .hasCalculatedExposureTime,
                in: legacyContainer,
                debugDescription: "hasCalculatedExposureTime must match the presence of correctedExposureSeconds."
            )
        }

        switch metadata.basis {
        case .advisoryOnlyBeyondOfficialRange:
            guard correctedExposureSeconds == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .correctedExposureSeconds,
                    in: legacyContainer,
                    debugDescription: "advisoryOnlyBeyondOfficialRange must not return a corrected exposure time."
                )
            }
            self = .advisoryOnly(
                AdvisoryOnlyPayload(
                    meteredExposureSeconds: meteredExposureSeconds,
                    metadata: metadata
                )
            )
        case .unsupportedOutOfPolicyRange:
            // Unsupported results may optionally carry a formula-
            // extrapolated corrected exposure when the active formula
            // can produce a value beyond the manufacturer-supported
            // boundary. Older snapshots decode with the field nil.
            self = .unsupported(
                UnsupportedPayload(
                    meteredExposureSeconds: meteredExposureSeconds,
                    correctedExposureSeconds: correctedExposureSeconds,
                    metadata: metadata
                )
            )
        case .exactTablePoint,
             .interpolatedWithinTable,
             .extrapolatedBeyondTable,
             .officialThresholdNoCorrection,
             .formulaDerived:
            guard let correctedExposureSeconds else {
                throw DecodingError.dataCorruptedError(
                    forKey: .correctedExposureSeconds,
                    in: legacyContainer,
                    debugDescription: "\(metadata.basis.rawValue) must return a corrected exposure time."
                )
            }
            if let validationError = ReciprocityResult.quantifiedValidationError(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: metadata
            ) {
                throw DecodingError.dataCorruptedError(
                    forKey: .metadata,
                    in: legacyContainer,
                    debugDescription: validationError
                )
            }
            self = .quantified(
                QuantifiedPayload(
                    meteredExposureSeconds: meteredExposureSeconds,
                    correctedExposureSeconds: correctedExposureSeconds,
                    metadata: metadata
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DiscriminatorKeys.self)

        switch self {
        case let .quantified(payload):
            try container.encode(Kind.quantified, forKey: .kind)
            try container.encode(
                QuantifiedPayloadDTO(
                    meteredExposureSeconds: payload.meteredExposureSeconds,
                    correctedExposureSeconds: payload.correctedExposureSeconds,
                    metadata: payload.metadata
                ),
                forKey: .payload
            )
        case let .advisoryOnly(payload):
            try container.encode(Kind.advisoryOnly, forKey: .kind)
            try container.encode(
                AdvisoryOnlyPayloadDTO(
                    meteredExposureSeconds: payload.meteredExposureSeconds,
                    metadata: payload.metadata
                ),
                forKey: .payload
            )
        case let .unsupported(payload):
            try container.encode(Kind.unsupported, forKey: .kind)
            try container.encode(
                UnsupportedPayloadDTO(
                    meteredExposureSeconds: payload.meteredExposureSeconds,
                    correctedExposureSeconds: payload.correctedExposureSeconds,
                    metadata: payload.metadata
                ),
                forKey: .payload
            )
        }
    }
}

// MARK: - Legacy-shape serialization adapter

extension ReciprocityResult {
    /// Encodes this result using the pre-migration 7-field layout
    /// (`meteredExposureSeconds`, `correctedExposureSeconds` (omitted when
    /// nil), `hasCalculatedExposureTime`, `metadata`).
    ///
    /// Used by baseline tests to confirm compatibility with the legacy
    /// serialized shape. Production code paths
    /// should use the standard `Encodable` conformance, which writes the
    /// new tagged-union format.
    func legacyShapeEncoded(using encoder: JSONEncoder) throws -> Data {
        try encoder.encode(LegacyShapeAdapter(result: self))
    }

    private struct LegacyShapeAdapter: Encodable {
        let result: ReciprocityResult

        private enum CodingKeys: String, CodingKey {
            case meteredExposureSeconds
            case correctedExposureSeconds
            case hasCalculatedExposureTime
            case metadata
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(result.meteredExposureSeconds, forKey: .meteredExposureSeconds)
            try container.encodeIfPresent(result.correctedExposureSeconds, forKey: .correctedExposureSeconds)
            try container.encode(result.hasCalculatedExposureTime, forKey: .hasCalculatedExposureTime)
            try container.encode(result.metadata, forKey: .metadata)
        }
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

private extension ReciprocityResult {
    static func exact(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]
    ) -> Self {
        .quantified(
            QuantifiedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .exact(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes,
                    referencedRows: referencedRows
                )
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
        .quantified(
            QuantifiedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .interpolated(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    estimationFamily: estimationFamily,
                    notes: notes,
                    referencedRows: referencedRows
                )
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
        .quantified(
            QuantifiedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .extrapolated(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    estimationFamily: estimationFamily,
                    notes: notes,
                    referencedRows: referencedRows
                )
            )
        )
    }

    static func thresholdNoCorrection(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        .quantified(
            QuantifiedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: meteredExposureSeconds,
                metadata: .thresholdNoCorrection(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes
                )
            )
        )
    }

    static func advisoryOnly(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        .advisoryOnly(
            AdvisoryOnlyPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                metadata: .advisoryOnly(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes
                )
            )
        )
    }

    static func unsupported(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double? = nil,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote],
        referencedRows: [ReciprocityTableRowReference]? = nil
    ) -> Self {
        .unsupported(
            UnsupportedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .unsupported(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes,
                    referencedRows: referencedRows
                )
            )
        )
    }

    static func formula(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        .quantified(
            QuantifiedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .formula(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes
                )
            )
        )
    }
}

struct ReciprocityCalculationPolicyEvaluator {
    private let comparisonTolerance = 0.000_001

    /// Default upper bound (in seconds) for the synthesized no-correction
    /// handoff applied to formula-only profiles that lack an explicit
    /// threshold rule and an explicit `meteredRange.minimumSeconds`.
    ///
    /// Practical long-exposure formulas (e.g. `Tc = Tm^P` curve fits)
    /// are only valid above their published domain. Applying such a
    /// formula to a sub-1s metered exposure produces a corrected time
    /// shorter than the adjusted shutter, which violates the
    /// fundamental reciprocity invariant: a reciprocity correction
    /// can never shorten the exposure. The catalog convention for
    /// the long-exposure films that ship with PTimer is that
    /// reciprocity correction starts at 1 sec — every official
    /// converted formula profile (Provia 100F, T-MAX 100/400,
    /// Tri-X 400, Acros II, Velvia 50/100, Ilford HP5 Plus, Delta
    /// 100/400/3200, Pan F Plus, FP4 Plus, XP2 Super) carries an
    /// explicit `threshold.noCorrectionRange: 0…1s` companion to its
    /// formula rule, so this default does not change those results.
    /// It activates for profiles that omit both — today, the
    /// `UnofficialPracticalProfiles` registry's Portra 400 entry.
    ///
    /// Profiles that publish explicit sub-1s correction (e.g. a
    /// formula with `meteredRange.minimumSeconds < 1` or a table
    /// entry below 1s) opt out of the default; their published data
    /// takes precedence.
    private let defaultFormulaNoCorrectionUpperBoundSeconds: Double = 1.0

    /// Evaluation order is part of the policy contract:
    /// exact table rows first, then threshold-only no-correction guidance,
    /// then the default formula no-correction handoff for formula-only
    /// profiles below their practical domain, then quantified table
    /// estimation, then formula extrapolation, then advisory-only
    /// continuation, and finally unsupported.
    func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityResult {
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
                formulaSelection: selector,
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

        // Default no-correction handoff for formula profiles that
        // lack an explicit threshold rule and an explicit
        // sub-1s formula domain. Without this step, a practical
        // long-exposure formula (e.g. `Tc = Tm^1.34`) applied to a
        // sub-1s metered exposure would return a corrected time
        // shorter than the adjusted shutter — a reciprocity
        // correction can never shorten the exposure. The check runs
        // after table estimation so explicit sub-1s table coverage
        // (e.g. a Foma-style profile with a table entry below 1s)
        // continues to take precedence.
        if let result = evaluateDefaultFormulaNoCorrection(
            selection: selector,
            meteredExposureSeconds: meteredExposureSeconds,
            assembler: assembler
        ) {
            return result
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
        formulaSelection: Selection,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler,
        estimator: Estimation
    ) -> ReciprocityResult? {
        guard let match = selection.exactMatch(for: meteredExposureSeconds) else {
            return nil
        }

        if let stopSignalNote = stopSignalNote(for: match.entry) {
            // When the same profile carries a formula rule, prefer the
            // formula-extrapolated numeric value at the manufacturer
            // stop-signal boundary so the result remains actionable.
            // The stop-signal row stays as `referencedRows` evidence;
            // the classification stays unsupported / outside guidance.
            let extrapolatedSeconds = formulaSelection.formulaRules
                .lazy
                .compactMap { rule -> Double? in
                    guard let value = self.formulaCorrectedExposureSeconds(
                        for: rule.formula,
                        meteredExposureSeconds: meteredExposureSeconds
                    ),
                    value.isFinite,
                    value > 0 else {
                        return nil
                    }
                    return value
                }
                .first

            return assembler.unsupportedStopSignal(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: extrapolatedSeconds,
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
    ) -> ReciprocityResult? {
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

    /// Synthesizes a no-correction handoff for formula-only profiles
    /// whose practical formula domain starts at 1s (the catalog's
    /// long-exposure convention) but which do not carry an explicit
    /// threshold rule covering sub-1s metered exposures. Returns nil
    /// when the profile has no formula rule, when the metered exposure
    /// is at or above the default upper bound, or when at least one
    /// formula rule opts into pre-default-bound correction by
    /// declaring `meteredRange.minimumSeconds` below the default.
    private func evaluateDefaultFormulaNoCorrection(
        selection: Selection,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityResult? {
        let defaultUpperBound = defaultFormulaNoCorrectionUpperBoundSeconds
        guard meteredExposureSeconds < defaultUpperBound,
              meteredExposureSeconds > 0 else {
            return nil
        }
        guard !selection.formulaRules.isEmpty else {
            return nil
        }
        // If any formula rule explicitly opts into pre-default-bound
        // correction (e.g. `meteredRange.minimumSeconds = 0.5`), the
        // profile is publishing sub-1s data; honor that instead of
        // overriding it with the default no-correction handoff.
        let anyFormulaOptsIntoSubDefaultCorrection = selection.formulaRules.contains { rule in
            guard let minimum = rule.meteredRange?.minimumSeconds else {
                return false
            }
            return minimum < defaultUpperBound
        }
        guard !anyFormulaOptsIntoSubDefaultCorrection else {
            return nil
        }
        return assembler.defaultFormulaNoCorrection(
            meteredExposureSeconds: meteredExposureSeconds,
            defaultUpperBoundSeconds: defaultUpperBound
        )
    }

    private func evaluateFormulaResult(
        selection: Selection,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityResult? {
        guard let formulaRule = selection.formulaRule(for: meteredExposureSeconds) else {
            if let boundedFormulaRule = selection.firstFormulaRuleExceeded(by: meteredExposureSeconds) {
                let extrapolatedSeconds = formulaCorrectedExposureSeconds(
                    for: boundedFormulaRule.formula,
                    meteredExposureSeconds: meteredExposureSeconds
                ).flatMap { value -> Double? in
                    guard value.isFinite, value > 0 else { return nil }
                    return value
                }

                return assembler.unsupportedFormulaExtrapolation(
                    meteredExposureSeconds: meteredExposureSeconds,
                    correctedExposureSeconds: extrapolatedSeconds,
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
    ) -> ReciprocityResult? {
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

        /// Returns the formula rule whose supported range contains the
        /// metered exposure. The upper bound (`meteredRange.maximumSeconds`)
        /// is treated as **exclusive** here so it can serve as the
        /// manufacturer's not-recommended boundary marker: at the
        /// boundary the result must already be reported as outside
        /// supported guidance even if the formula can still compute a
        /// numeric extrapolation. Lower bounds remain inclusive so
        /// threshold ↔ formula handoff at the no-correction boundary
        /// stays seamless.
        func formulaRule(for meteredExposureSeconds: Double) -> FormulaReciprocityRule? {
            formulaRules.first {
                guard let range = $0.meteredRange else {
                    return true
                }
                guard meteredExposureSeconds >= range.minimumSeconds else {
                    return false
                }
                guard let maximumSeconds = range.maximumSeconds else {
                    return true
                }
                return meteredExposureSeconds < maximumSeconds
            }
        }

        /// First formula rule whose supported boundary the metered
        /// exposure has reached or exceeded. Drives the formula-
        /// extrapolated unsupported path: the formula can still compute
        /// a value, but the result is presented as outside manufacturer
        /// guidance.
        func firstFormulaRuleExceeded(by meteredExposureSeconds: Double) -> FormulaReciprocityRule? {
            formulaRules.first {
                guard let range = $0.meteredRange,
                      let maximumSeconds = range.maximumSeconds else {
                    return false
                }

                return meteredExposureSeconds >= maximumSeconds
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
        ) -> ReciprocityResult {
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
        ) -> ReciprocityResult {
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
        ) -> ReciprocityResult {
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
        ) -> ReciprocityResult {
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

        /// Synthesizes a no-correction result for a formula-only
        /// profile below the evaluator's default formula domain.
        /// Mirrors `thresholdNoCorrection` (same basis, identity
        /// corrected exposure) so downstream display code reads the
        /// same shape — "No correction" badge, identity current
        /// point on the graph — without needing to special-case a
        /// synthesized handoff. The note text records that the
        /// no-correction handoff was inferred from the absence of
        /// an explicit sub-default-bound rule rather than read off a
        /// published threshold.
        func defaultFormulaNoCorrection(
            meteredExposureSeconds: Double,
            defaultUpperBoundSeconds: Double
        ) -> ReciprocityResult {
            let boundaryText = formatBoundarySeconds(defaultUpperBoundSeconds)
            return .thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .thresholdGuidanceOnly,
                        text: "Reciprocity correction is not applied below the practical formula domain (default \(boundaryText))."
                    )
                ] + sourceAuthorityNotes
            )
        }

        func advisoryOnly(
            meteredExposureSeconds: Double,
            advisoryRule: AdvisoryReciprocityRule
        ) -> ReciprocityResult {
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
            correctedExposureSeconds: Double? = nil,
            notes: [ReciprocityPolicyNote],
            referencedRows: [ReciprocityTableRowReference]? = nil
        ) -> ReciprocityResult {
            .unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes + sourceAuthorityNotes,
                referencedRows: referencedRows
            )
        }

        func unsupportedStopSignal(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double? = nil,
            stopSignalNote: ReciprocityPolicyNote,
            stopSignalBoundary: QuantifiedTableBoundary
        ) -> ReciprocityResult {
            unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
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
        ) -> ReciprocityResult {
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

        /// Returns an unsupported result whose corrected exposure is
        /// formula-extrapolated past the manufacturer-supported boundary
        /// (or `nil` when the formula cannot produce a finite value).
        ///
        /// "Unsupported" classifies the result as outside manufacturer
        /// guidance, not as unavailable. When the active formula can
        /// still produce a numeric corrected exposure past its
        /// supported range, the value flows through here so callers
        /// can surface it as approximate / outside guidance.
        func unsupportedFormulaExtrapolation(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double?,
            formulaRule: FormulaReciprocityRule
        ) -> ReciprocityResult {
            let boundaryText: String
            if let maximumSeconds = formulaRule.meteredRange?.maximumSeconds {
                boundaryText = "Manufacturer guidance ends at \(formatBoundarySeconds(maximumSeconds))."
            } else {
                boundaryText = "Manufacturer guidance does not cover this metered exposure."
            }

            let policyText = correctedExposureSeconds != nil
                ? "Outside manufacturer guidance — value extrapolated from the published formula curve."
                : "This metered exposure is beyond the explicit formula policy boundary."

            return unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .beyondOfficialQuantifiedRange,
                        text: boundaryText
                    ),
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: policyText
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
