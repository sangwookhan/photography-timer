import Foundation

enum ReciprocityCalculationBasis: String, Codable, Equatable {
    case officialThresholdNoCorrection
    case limitedGuidanceNoQuantifiedPrediction
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
    case beyondLastRepresentativePoint
    case beyondPolicyLimit
}

enum ReciprocityCalculationWarningLevel: String, Codable, Equatable {
    case none
    case note
    case caution
    case strongWarning
}

enum ReciprocityPolicyNoteToken: String, Codable, Equatable {
    case thresholdGuidanceOnly
    case limitedGuidanceContinuationOnly
    case beyondOfficialQuantifiedRange
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

struct ReciprocityResultMetadata: Codable, Equatable {
    let basis: ReciprocityCalculationBasis
    let sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    let rangeStatus: ReciprocityCalculationRangeStatus
    let warningLevel: ReciprocityCalculationWarningLevel
    let notes: [ReciprocityPolicyNote]

    init(
        basis: ReciprocityCalculationBasis,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        rangeStatus: ReciprocityCalculationRangeStatus,
        warningLevel: ReciprocityCalculationWarningLevel,
        notes: [ReciprocityPolicyNote] = []
    ) {
        self.basis = basis
        self.sourceAuthorityImpact = sourceAuthorityImpact
        self.rangeStatus = rangeStatus
        self.warningLevel = warningLevel
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case basis
        case sourceAuthorityImpact
        case rangeStatus
        case warningLevel
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.basis = try container.decode(ReciprocityCalculationBasis.self, forKey: .basis)
        self.sourceAuthorityImpact = try container.decode(
            ReciprocitySourceAuthorityImpact.self,
            forKey: .sourceAuthorityImpact
        )
        self.rangeStatus = try container.decode(ReciprocityCalculationRangeStatus.self, forKey: .rangeStatus)
        self.warningLevel = try container.decode(ReciprocityCalculationWarningLevel.self, forKey: .warningLevel)
        self.notes = try container.decodeIfPresent([ReciprocityPolicyNote].self, forKey: .notes) ?? []
    }
}

/// Tagged-union representation of a reciprocity calculation outcome.
///
/// The three cases encode the (basis, corrected_present) invariant in the
/// type system:
/// - `quantified` always carries a non-Optional `correctedExposureSeconds`.
/// - `limitedGuidance` and `unsupported` lack the field entirely
///   (unsupported may optionally carry a formula-extrapolated value).
enum ReciprocityResult: Equatable {
    case quantified(QuantifiedPayload)
    case limitedGuidance(LimitedGuidancePayload)
    case unsupported(UnsupportedPayload)

    struct QuantifiedPayload: Equatable {
        let meteredExposureSeconds: Double
        let correctedExposureSeconds: Double
        let metadata: ReciprocityResultMetadata

        init(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            metadata: ReciprocityResultMetadata
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

    struct LimitedGuidancePayload: Equatable {
        let meteredExposureSeconds: Double
        let metadata: ReciprocityResultMetadata

        init(
            meteredExposureSeconds: Double,
            metadata: ReciprocityResultMetadata
        ) {
            precondition(
                metadata.basis == .limitedGuidanceNoQuantifiedPrediction,
                "limitedGuidance payload must carry limitedGuidanceNoQuantifiedPrediction basis."
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
        /// threshold-only or limited-guidance-only unsupported results. The
        /// presenter must mark numeric values as approximate / outside
        /// manufacturer guidance — they are calculation-derived, never
        /// published guidance.
        let correctedExposureSeconds: Double?
        let metadata: ReciprocityResultMetadata

        init(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double? = nil,
            metadata: ReciprocityResultMetadata
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
        metadata: ReciprocityResultMetadata
    ) -> String? {
        switch metadata.basis {
        case .officialThresholdNoCorrection:
            guard abs(correctedExposureSeconds - meteredExposureSeconds) < 0.000_001 else {
                return "officialThresholdNoCorrection must return corrected exposure equal to metered exposure."
            }
        case .limitedGuidanceNoQuantifiedPrediction:
            return "limitedGuidanceNoQuantifiedPrediction must not be carried by a quantified payload."
        case .unsupportedOutOfPolicyRange:
            return "unsupportedOutOfPolicyRange must not be carried by a quantified payload."
        case .formulaDerived:
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
        case let .limitedGuidance(payload):
            return payload.meteredExposureSeconds
        case let .unsupported(payload):
            return payload.meteredExposureSeconds
        }
    }

    /// Convenience accessor matching the legacy struct field. Returns
    /// the quantified case's corrected exposure, the unsupported case's
    /// optional formula-extrapolated value when present, or `nil` for
    /// limited-guidance and value-less unsupported results.
    var correctedExposureSeconds: Double? {
        switch self {
        case let .quantified(payload):
            return payload.correctedExposureSeconds
        case let .unsupported(payload):
            return payload.correctedExposureSeconds
        case .limitedGuidance:
            return nil
        }
    }

    /// Metadata block — present in every case.
    var metadata: ReciprocityResultMetadata {
        switch self {
        case let .quantified(payload):
            return payload.metadata
        case let .limitedGuidance(payload):
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
        case .limitedGuidance:
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

    private enum Kind: String, Codable {
        case quantified
        case limitedGuidance
        case unsupported
    }

    private struct QuantifiedPayloadDTO: Codable {
        let meteredExposureSeconds: Double
        let correctedExposureSeconds: Double
        let metadata: ReciprocityResultMetadata
    }

    private struct LimitedGuidancePayloadDTO: Codable {
        let meteredExposureSeconds: Double
        let metadata: ReciprocityResultMetadata
    }

    private struct UnsupportedPayloadDTO: Codable {
        let meteredExposureSeconds: Double
        let correctedExposureSeconds: Double?
        let metadata: ReciprocityResultMetadata

        init(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double?,
            metadata: ReciprocityResultMetadata
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
                ReciprocityResultMetadata.self,
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
        let kind = try discriminatorContainer.decode(Kind.self, forKey: .kind)

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
        case .limitedGuidance:
            let payload = try discriminatorContainer.decode(LimitedGuidancePayloadDTO.self, forKey: .payload)
            guard payload.metadata.basis == .limitedGuidanceNoQuantifiedPrediction else {
                throw DecodingError.dataCorruptedError(
                    forKey: .payload,
                    in: discriminatorContainer,
                    debugDescription:
                        "limitedGuidance payload must carry limitedGuidanceNoQuantifiedPrediction basis."
                )
            }
            self = .limitedGuidance(
                LimitedGuidancePayload(
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
        case let .limitedGuidance(payload):
            try container.encode(Kind.limitedGuidance, forKey: .kind)
            try container.encode(
                LimitedGuidancePayloadDTO(
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

private extension ReciprocityResultMetadata {
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

    static func limitedGuidance(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            basis: .limitedGuidanceNoQuantifiedPrediction,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .beyondLastRepresentativePoint,
            warningLevel: warningLevel(
                for: .limitedGuidanceNoQuantifiedPrediction,
                sourceAuthorityImpact: sourceAuthorityImpact
            ),
            notes: notes
        )
    }

    static func unsupported(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            basis: .unsupportedOutOfPolicyRange,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .beyondPolicyLimit,
            warningLevel: .strongWarning,
            notes: notes
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
        case .officialThresholdNoCorrection:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return .none
            case .archivalOfficial:
                return .note
            case .unofficialSecondary, .userDefined:
                return .caution
            }
        case .limitedGuidanceNoQuantifiedPrediction:
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

    static func limitedGuidance(
        meteredExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        .limitedGuidance(
            LimitedGuidancePayload(
                meteredExposureSeconds: meteredExposureSeconds,
                metadata: .limitedGuidance(
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
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        .unsupported(
            UnsupportedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .unsupported(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes
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
    /// converted formula profile carries an explicit
    /// `threshold.noCorrectionRange: 0…1s` companion to its
    /// formula rule, so this default does not change those results.
    /// It activates for profiles that omit both — today, the
    /// `UnofficialPracticalProfiles` registry's Portra 400 entry.
    ///
    /// Profiles that publish explicit sub-1s correction (e.g. a
    /// formula with `meteredRange.minimumSeconds < 1`) opt out of
    /// the default; their published data takes precedence.
    private let defaultFormulaNoCorrectionUpperBoundSeconds: Double = 1.0

    /// Evaluation order is part of the policy contract:
    /// threshold-only no-correction guidance first, then the default
    /// formula no-correction handoff for formula-only profiles below
    /// their practical domain, then formula evaluation, then
    /// limited-guidance continuation, and finally unsupported. The
    /// result is then passed through `clampToCorrectionInvariant` so
    /// the public guarantee `corrected >= adjusted` holds for every
    /// rule path.
    func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityResult {
        let sourceAuthorityImpact = mapSourceAuthorityImpact(from: profile.source)
        let assembler = ResultAssembler(sourceAuthorityImpact: sourceAuthorityImpact)
        let rawResult = evaluateRuleSelection(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds,
            assembler: assembler
        )
        return clampToCorrectionInvariant(
            result: rawResult,
            meteredExposureSeconds: meteredExposureSeconds,
            assembler: assembler
        )
    }

    private func evaluateRuleSelection(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityResult {
        let selector = Selection(
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
            limitedGuidanceRules: profile.rules.compactMap {
                guard case let .limitedGuidance(rule) = $0 else {
                    return nil
                }

                return rule
            }
        )

        if let thresholdRule = selector.thresholdRule(for: meteredExposureSeconds) {
            return assembler.thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                thresholdRule: thresholdRule
            )
        }

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

        if let limitedGuidanceRule = selector.limitedGuidanceRule(for: meteredExposureSeconds) {
            return assembler.limitedGuidance(
                meteredExposureSeconds: meteredExposureSeconds,
                limitedGuidanceRule: limitedGuidanceRule
            )
        }

        return assembler.unsupported(
            meteredExposureSeconds: meteredExposureSeconds,
            notes: [
                ReciprocityPolicyNote(
                    token: .unsupportedByPolicy,
                    text: "No supported reciprocity policy path matched this metered exposure."
                ),
            ]
        )
    }

    /// Tolerance for the correction invariant comparison. Floating-
    /// point identity cases (formula at exactly Tm=1 with P≈1) can
    /// land microscopically below the metered value; treating those
    /// as violations would falsely clamp valid formula prediction.
    private let correctionInvariantTolerance: Double = 1e-6

    /// Universal correction invariant: a reciprocity correction must
    /// never shorten the adjusted shutter. When the rule-pipeline
    /// produces a result whose `corrected < metered`, the value is
    /// reclassified as a no-correction handoff. This is the global
    /// safety net on top of `evaluateDefaultFormulaNoCorrection`'s
    /// narrower domain check.
    ///
    /// Results without a numeric corrected exposure (limited-guidance
    /// and value-less unsupported) pass through untouched — there is
    /// no value to compare against.
    private func clampToCorrectionInvariant(
        result: ReciprocityResult,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityResult {
        guard meteredExposureSeconds > 0,
              meteredExposureSeconds.isFinite else {
            return result
        }
        guard let corrected = result.correctedExposureSeconds,
              corrected.isFinite else {
            return result
        }
        guard corrected < meteredExposureSeconds - correctionInvariantTolerance else {
            return result
        }
        return assembler.invariantClampedNoCorrection(
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    /// Synthesizes a no-correction handoff for formula-only profiles
    /// whose practical formula domain starts at 1s (the catalog's
    /// long-exposure convention) but which do not carry an explicit
    /// threshold rule covering sub-1s metered exposures.
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
                let extrapolatedSeconds: Double?
                if boundedFormulaRule.extrapolateBeyondMaximum {
                    extrapolatedSeconds = formulaCorrectedExposureSeconds(
                        for: boundedFormulaRule.formula,
                        meteredExposureSeconds: meteredExposureSeconds
                    ).flatMap { value -> Double? in
                        guard value.isFinite, value > 0 else { return nil }
                        return value
                    }
                } else {
                    extrapolatedSeconds = nil
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
}

private extension ReciprocityCalculationPolicyEvaluator {
    struct Selection {
        let thresholdRules: [ThresholdReciprocityRule]
        let formulaRules: [FormulaReciprocityRule]
        let limitedGuidanceRules: [LimitedGuidanceReciprocityRule]

        func thresholdRule(for meteredExposureSeconds: Double) -> ThresholdReciprocityRule? {
            thresholdRules.first { $0.noCorrectionRange.contains(meteredExposureSeconds) }
        }

        func limitedGuidanceRule(
            for meteredExposureSeconds: Double
        ) -> LimitedGuidanceReciprocityRule? {
            limitedGuidanceRules.first {
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
                    ),
                ] + sourceAuthorityNotes
            )
        }

        /// Synthesizes a no-correction result for a formula-only
        /// profile below the evaluator's default formula domain.
        /// Mirrors `thresholdNoCorrection` (same basis, identity
        /// corrected exposure) so downstream display code reads the
        /// same shape — "No correction" badge, identity current
        /// point on the graph — without needing to special-case a
        /// synthesized handoff.
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
                    ),
                ] + sourceAuthorityNotes
            )
        }

        /// Universal-invariant fallback: a quantified result whose
        /// corrected exposure would be shorter than the adjusted
        /// shutter is reclassified to no-correction (corrected
        /// equals metered).
        func invariantClampedNoCorrection(
            meteredExposureSeconds: Double
        ) -> ReciprocityResult {
            .thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .thresholdGuidanceOnly,
                        text: "Reciprocity correction cannot shorten the adjusted shutter. Treating as No correction."
                    ),
                ] + sourceAuthorityNotes
            )
        }

        func limitedGuidance(
            meteredExposureSeconds: Double,
            limitedGuidanceRule: LimitedGuidanceReciprocityRule
        ) -> ReciprocityResult {
            let noteText = limitedGuidanceRule.adjustments
                .compactMap(Self.limitedGuidanceNoteText(from:)).first
                ?? limitedGuidanceRule.notes.first
                ?? "Manufacturer publishes only qualitative guidance beyond the no-correction range."

            return .limitedGuidance(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .limitedGuidanceContinuationOnly,
                        text: "Only limited guidance is available for this metered exposure."
                    ),
                    ReciprocityPolicyNote(
                        token: .beyondOfficialQuantifiedRange,
                        text: noteText
                    ),
                ] + sourceAuthorityNotes
            )
        }

        func unsupported(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double? = nil,
            notes: [ReciprocityPolicyNote]
        ) -> ReciprocityResult {
            .unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: notes + sourceAuthorityNotes
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
                    ReciprocityPolicyNote(text: noteText),
                ] + sourceAuthorityNotes
            )
        }

        /// Returns an unsupported result whose corrected exposure is
        /// formula-extrapolated past the manufacturer-supported boundary
        /// (or `nil` when the formula cannot produce a finite value).
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
                ? "Outside manufacturer guidance — value extrapolated from the published calculation curve."
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
                    ),
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
                    ),
                ]
            case .unofficialSecondary:
                return [
                    ReciprocityPolicyNote(
                        token: .unofficialSecondarySource,
                        text: "Result is based on an unofficial secondary reciprocity source."
                    ),
                ]
            case .userDefined:
                return [
                    ReciprocityPolicyNote(
                        token: .userDefinedSource,
                        text: "Result is based on user-defined reciprocity data."
                    ),
                ]
            }
        }

        private static func limitedGuidanceNoteText(from adjustment: ReciprocityAdjustment) -> String? {
            guard case let .note(note) = adjustment else {
                return nil
            }

            return note.text
        }
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
