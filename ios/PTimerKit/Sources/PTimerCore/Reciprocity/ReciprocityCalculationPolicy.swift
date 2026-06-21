// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ReciprocityCalculationBasis: String, Codable, Equatable {
    case officialThresholdNoCorrection
    case limitedGuidanceNoQuantifiedPrediction
    case unsupportedOutOfPolicyRange
    case formulaDerived
    /// PTIMER-159: corrected exposure produced by log-log interpolation
    /// of a manufacturer reciprocity table (e.g. Fomapan 100). Distinct
    /// from `.formulaDerived` so presentation can label it honestly as
    /// table-derived rather than formula-derived.
    case tableLogLogDerived
}

public enum ReciprocitySourceAuthorityImpact: String, Codable, Equatable {
    case currentOfficial
    case archivalOfficial
    case unofficialSecondary
    case userDefined
}

public enum ReciprocityCalculationRangeStatus: String, Codable, Equatable {
    case withinStatedRange
    case beyondLastRepresentativePoint
    case beyondPolicyLimit
}

public enum ReciprocityCalculationWarningLevel: String, Codable, Equatable {
    case none
    case note
    case caution
    case strongWarning
}

public enum ReciprocityPolicyNoteToken: String, Codable, Equatable {
    case thresholdGuidanceOnly
    case limitedGuidanceContinuationOnly
    case beyondOfficialQuantifiedRange
    case archivalOfficialSource
    case unofficialSecondarySource
    case userDefinedSource
    case unsupportedByPolicy
}

public struct ReciprocityPolicyNote: Codable, Equatable {
    public let token: ReciprocityPolicyNoteToken?
    public let text: String

    public init(token: ReciprocityPolicyNoteToken? = nil, text: String) {
        self.token = token
        self.text = text
    }
}

public struct ReciprocityResultMetadata: Codable, Equatable {
    public let basis: ReciprocityCalculationBasis
    public let sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    public let rangeStatus: ReciprocityCalculationRangeStatus
    public let warningLevel: ReciprocityCalculationWarningLevel
    public let notes: [ReciprocityPolicyNote]

    public init(
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

    public init(from decoder: Decoder) throws {
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
///   (unsupported may optionally carry a formula prediction outside
///   the source range).
public enum ReciprocityResult: Equatable {
    case quantified(QuantifiedPayload)
    case limitedGuidance(LimitedGuidancePayload)
    case unsupported(UnsupportedPayload)

    public struct QuantifiedPayload: Equatable {
        public let meteredExposureSeconds: Double
        public let correctedExposureSeconds: Double
        public let metadata: ReciprocityResultMetadata

        public init(
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

    public struct LimitedGuidancePayload: Equatable {
        public let meteredExposureSeconds: Double
        public let metadata: ReciprocityResultMetadata

        public init(
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

    public struct UnsupportedPayload: Equatable {
        public let meteredExposureSeconds: Double
        /// Optional formula prediction (outside the source range) in
        /// corrected-exposure seconds. Present only when a formula-backed
        /// profile can still produce a numeric value beyond the
        /// manufacturer-supported boundary; absent for
        /// threshold-only or limited-guidance-only unsupported results. The
        /// presenter must mark numeric values as approximate / outside
        /// manufacturer guidance — they are calculation-derived, never
        /// published guidance.
        public let correctedExposureSeconds: Double?
        public let metadata: ReciprocityResultMetadata

        public init(
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
        case .formulaDerived, .tableLogLogDerived:
            break
        }

        return nil
    }
}

extension ReciprocityResult {
    /// Metered exposure seconds — present in every case.
    public var meteredExposureSeconds: Double {
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
    /// optional formula prediction outside the source range when
    /// present, or `nil` for limited-guidance and value-less unsupported
    /// results.
    public var correctedExposureSeconds: Double? {
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
    public var metadata: ReciprocityResultMetadata {
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
    /// formula prediction outside the source range.
    public var hasCalculatedExposureTime: Bool {
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

    static func tableLogLog(
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        Self(
            basis: .tableLogLogDerived,
            sourceAuthorityImpact: sourceAuthorityImpact,
            rangeStatus: .withinStatedRange,
            warningLevel: warningLevel(for: .tableLogLogDerived, sourceAuthorityImpact: sourceAuthorityImpact),
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
        case .formulaDerived, .tableLogLogDerived:
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

    static func tableLogLog(
        meteredExposureSeconds: Double,
        correctedExposureSeconds: Double,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        notes: [ReciprocityPolicyNote]
    ) -> Self {
        .quantified(
            QuantifiedPayload(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                metadata: .tableLogLog(
                    sourceAuthorityImpact: sourceAuthorityImpact,
                    notes: notes
                )
            )
        )
    }
}

public struct ReciprocityCalculationPolicyEvaluator {
    public init() {}

    /// Evaluation order is part of the policy contract:
    /// formula rules win when present (they own their no-correction
    /// and source-range guards via the shared
    /// `ReciprocityFormula` contract), then threshold-only
    /// no-correction guidance, then limited-guidance continuation,
    /// and finally unsupported.
    public func evaluate(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityResult {
        let sourceAuthorityImpact = mapSourceAuthorityImpact(from: profile.source)
        let assembler = ResultAssembler(sourceAuthorityImpact: sourceAuthorityImpact)
        return evaluateRuleSelection(
            profile: profile,
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
            },
            tableInterpolationRules: profile.rules.compactMap {
                guard case let .tableInterpolation(rule) = $0 else {
                    return nil
                }
                return rule
            }
        )

        if let formulaRule = selector.formulaRules.first {
            return evaluateFormulaRule(
                rule: formulaRule,
                meteredExposureSeconds: meteredExposureSeconds,
                assembler: assembler
            )
        }

        if let tableRule = selector.tableInterpolationRules.first {
            return evaluateTableInterpolationRule(
                rule: tableRule,
                meteredExposureSeconds: meteredExposureSeconds,
                assembler: assembler
            )
        }

        if let thresholdRule = selector.thresholdRule(for: meteredExposureSeconds) {
            return assembler.thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                thresholdRule: thresholdRule
            )
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

    private func evaluateFormulaRule(
        rule: FormulaReciprocityRule,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityResult {
        switch rule.formula.evaluate(meteredExposureSeconds: meteredExposureSeconds) {
        case .noCorrection:
            return assembler.formulaNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                formulaRule: rule
            )
        case let .withinSourceRange(corrected):
            return assembler.formula(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: corrected,
                formulaRule: rule
            )
        case let .beyondSourceRange(corrected):
            return assembler.unsupportedFormulaOutsideSourceRange(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: corrected,
                formulaRule: rule
            )
        case .invalidInput:
            // Bad metered input (NaN, infinity, ≤ 0). Surface as
            // unsupported rather than silently returning the metered
            // value — PTIMER-84 user input must not hide as
            // "no correction needed".
            return assembler.unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Metered exposure is not a positive finite number; no reciprocity correction can be computed."
                    ),
                ]
            )
        case .invalidFormula:
            // Formula parameters violate the safe-formula contract.
            // Distinct from `.invalidInput` and `.unsafeShorteningFormula`
            // because this is a data error in the formula itself —
            // PTIMER-84 custom-profile validation depends on this
            // staying visible.
            return assembler.unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Formula parameters violate the safe-formula contract; the corrected exposure cannot be computed."
                    ),
                ]
            )
        case .formulaOutputUnusable:
            // Formula produced NaN / non-positive output even
            // though parameters and input look valid. Surface as
            // unsupported with a runtime explanation distinct from
            // the parameter-validation case.
            return assembler.unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Formula produced a non-finite or non-positive output for this metered exposure."
                    ),
                ]
            )
        case .unsafeShorteningFormula:
            // Runtime safety handoff: the formula would shorten the
            // exposure here, so the policy substitutes the identity
            // (no-correction) result instead. Distinct from data
            // errors above — this is the catalog's universal
            // "Tc ≥ Tm" guarantee at work.
            return assembler.invariantClampedNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds
            )
        }
    }

    private func evaluateTableInterpolationRule(
        rule: TableInterpolationReciprocityRule,
        meteredExposureSeconds: Double,
        assembler: ResultAssembler
    ) -> ReciprocityResult {
        switch rule.evaluate(meteredExposureSeconds: meteredExposureSeconds) {
        case .noCorrection:
            // Reuse the no-correction shape so the badge / identity
            // graph point read the same as every other no-correction path.
            return assembler.invariantClampedNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds
            )
        case let .withinSourceRange(corrected):
            return assembler.tableLogLog(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: corrected,
                rule: rule
            )
        case let .beyondSourceRange(corrected):
            // Past the published table: keep a computed value, presented
            // as "Beyond source range" (never a value-less unsupported).
            return assembler.tableOutsideSourceRange(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: corrected,
                rule: rule
            )
        case .invalidInput:
            return assembler.unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Metered exposure is not a positive finite number; no reciprocity correction can be computed."
                    ),
                ]
            )
        case .invalidRule:
            return assembler.unsupported(
                meteredExposureSeconds: meteredExposureSeconds,
                notes: [
                    ReciprocityPolicyNote(
                        token: .unsupportedByPolicy,
                        text: "Table anchors violate the safe-table contract; the corrected exposure cannot be computed."
                    ),
                ]
            )
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
        let tableInterpolationRules: [TableInterpolationReciprocityRule]

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
        init(thresholdRules: [ThresholdReciprocityRule], formulaRules: [FormulaReciprocityRule], limitedGuidanceRules: [LimitedGuidanceReciprocityRule], tableInterpolationRules: [TableInterpolationReciprocityRule]) {
            self.thresholdRules = thresholdRules
            self.formulaRules = formulaRules
            self.limitedGuidanceRules = limitedGuidanceRules
            self.tableInterpolationRules = tableInterpolationRules
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

        /// Synthesizes a no-correction result for a formula rule
        /// whose `noCorrectionThroughSeconds` guard fired. Reuses the
        /// `officialThresholdNoCorrection` basis so downstream
        /// display code reads the same shape — "No correction" badge,
        /// identity current point on the graph — without needing to
        /// special-case a formula-owned guard.
        func formulaNoCorrection(
            meteredExposureSeconds: Double,
            formulaRule: FormulaReciprocityRule
        ) -> ReciprocityResult {
            let boundary = formulaRule.formula.noCorrectionThroughSeconds
            // Detect epsilon-encoded open boundaries (e.g. Acros II's
            // 119.999999): the manufacturer's semantic is "Tm <
            // integer s no correction, Tm ≥ integer s formula", so the
            // note reads as "< X sec", not the rounded inclusive
            // "≤ X sec" form.
            let comparison = noCorrectionBoundaryComparisonText(for: boundary)
            return .thresholdNoCorrection(
                meteredExposureSeconds: meteredExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(
                        token: .thresholdGuidanceOnly,
                        text: "Reciprocity correction is not applied within the formula's no-correction range (\(comparison))."
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

        /// Quantified result from log-log interpolation of a
        /// manufacturer reciprocity table within its published range
        /// (PTIMER-159). Carries the `.tableLogLogDerived` basis so the
        /// presentation labels it honestly (not "Formula-derived").
        func tableLogLog(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            rule: TableInterpolationReciprocityRule
        ) -> ReciprocityResult {
            let noteText = rule.notes.first
                ?? "Calculated by log-log interpolation of the manufacturer reciprocity table."

            return .tableLogLog(
                meteredExposureSeconds: meteredExposureSeconds,
                correctedExposureSeconds: correctedExposureSeconds,
                sourceAuthorityImpact: sourceAuthorityImpact,
                notes: [
                    ReciprocityPolicyNote(text: noteText),
                ] + sourceAuthorityNotes
            )
        }

        /// Beyond the published table the model keeps a computed value
        /// (a log-log extrapolation of the last segment) rather than
        /// dead-ending; it carries the "Beyond source range" presentation
        /// the same way a formula prediction past its source range does.
        func tableOutsideSourceRange(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            rule: TableInterpolationReciprocityRule
        ) -> ReciprocityResult {
            // Source-neutral wording: the table model serves both the
            // official FOMA table and unofficial community tables
            // (Ohzart), so the boundary note must not claim manufacturer
            // authority. Wording only — the classification and tokens
            // below are unchanged.
            let boundaryText =
                "Source table ends at \(formatBoundarySeconds(rule.sourceRangeThroughSeconds))."

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
                        text: "Beyond the published table — value is a log-log extrapolation past the published source range."
                    ),
                ]
            )
        }

        /// Returns an unsupported result whose corrected exposure is a
        /// formula prediction outside the manufacturer-supported source
        /// range. The new shared formula model always produces a value
        /// past its `sourceRangeThroughSeconds`; the unsupported
        /// classification carries the strong-warning presentation while
        /// preserving the predicted corrected exposure.
        func unsupportedFormulaOutsideSourceRange(
            meteredExposureSeconds: Double,
            correctedExposureSeconds: Double,
            formulaRule: FormulaReciprocityRule
        ) -> ReciprocityResult {
            let boundaryText: String
            if let upper = formulaRule.formula.sourceRangeThroughSeconds {
                boundaryText = "Manufacturer source range ends at \(formatBoundarySeconds(upper))."
            } else {
                boundaryText = "Manufacturer source range does not cover this metered exposure."
            }

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
                        text: "Outside manufacturer source range — value is a formula prediction outside the published source range."
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

        /// Produces the comparison-operator phrase used for the
        /// no-correction-band note. Returns "< X sec" when the stored
        /// boundary is an epsilon-encoded open boundary (the
        /// manufacturer's semantic is "no correction strictly below
        /// integer X sec; the formula picks up at exactly X sec",
        /// e.g. Acros II's 119.999999 → "< 120 sec"). Otherwise returns
        /// "≤ X sec" — the inclusive case where the boundary value
        /// itself is part of the no-correction band.
        private func noCorrectionBoundaryComparisonText(for value: Double) -> String {
            let ceiling = ceil(value)
            let gap = ceiling - value
            if gap > 0, gap < 1e-3 {
                return "< \(formatBoundarySeconds(ceiling))"
            }
            return "≤ \(formatBoundarySeconds(value))"
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
        init(sourceAuthorityImpact: ReciprocitySourceAuthorityImpact) {
            self.sourceAuthorityImpact = sourceAuthorityImpact
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
