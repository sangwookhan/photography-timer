import Foundation

enum ReciprocityConfidenceCategory: String, Codable, Equatable {
    case noCorrection
    case formulaDerived
    case limitedGuidance
    case unsupported
}

enum ReciprocityConfidenceLevel: String, Codable, Equatable {
    case high
    case medium
    case low
    case veryLow
    case none
}

enum ReciprocityConfidenceBadgeStyle: String, Codable, Equatable {
    case trusted
    case measured
    case caution
    case limitedGuidance
    case unsupported
}

enum ReciprocityConfidenceWarningEmphasis: String, Codable, Equatable {
    case none
    case note
    case caution
    case strong
}

enum ReciprocityConfidenceResultKind: String, Codable, Equatable {
    case noCorrection
    case formulaDerived
    case limitedGuidance
    case unsupported
}

enum ReciprocityConfidenceExplanationToken: String, Codable, Equatable {
    case thresholdGuidanceOnly
    case formulaDerived
    case currentOfficialSource
    case archivalOfficialSource
    case unofficialSecondarySource
    case userDefinedSource
    case withinStatedRange
    case beyondRepresentativePoint
    case beyondPolicyLimit
    case limitedGuidanceContinuationOnly
    case officialRangeExceeded
    case unsupportedByPolicy
    case calculatedExposureReturned
    case noCalculatedExposureReturned

    var defaultText: String {
        switch self {
        case .thresholdGuidanceOnly:
            return "Uses threshold-only official no-correction guidance."
        case .formulaDerived:
            return "Calculated from a profile formula."
        case .currentOfficialSource:
            return "Based on current official source data."
        case .archivalOfficialSource:
            return "Based on archival official source data."
        case .unofficialSecondarySource:
            return "Based on an unofficial secondary source."
        case .userDefinedSource:
            return "Based on user-supplied reciprocity data."
        case .withinStatedRange:
            return "Falls within the source's stated range."
        case .beyondRepresentativePoint:
            return "Extends beyond the source's last published reference point."
        case .beyondPolicyLimit:
            return "Falls beyond the current policy limit."
        case .limitedGuidanceContinuationOnly:
            return "Only limited guidance is available beyond the no-correction range."
        case .officialRangeExceeded:
            return "The official quantified range has been exceeded."
        case .unsupportedByPolicy:
            return "No supported calculation path is available for this result."
        case .calculatedExposureReturned:
            return "A corrected exposure time was returned."
        case .noCalculatedExposureReturned:
            return "No corrected exposure time was returned."
        }
    }
}

struct ReciprocityConfidencePresentation: Codable, Equatable {
    let category: ReciprocityConfidenceCategory
    let level: ReciprocityConfidenceLevel
    let badgeStyle: ReciprocityConfidenceBadgeStyle
    let warningEmphasis: ReciprocityConfidenceWarningEmphasis
    let resultKind: ReciprocityConfidenceResultKind
    /// Compact presentation text intended for badges or summary UI. This is a
    /// convenience field, not the source of truth for structured meaning.
    let shortLabel: String
    /// Structured presentation-facing explanation categories. These are the
    /// stable contract fields that future UI can key from.
    let explanationTokens: [ReciprocityConfidenceExplanationToken]
    /// Passthrough explanatory text from policy-layer notes when present. These
    /// help with readable fallback output, but are intentionally less stable
    /// than the structured explanation tokens.
    let supportingNotes: [String]
    /// Default fallback explanation text for non-finalized UI. This is a
    /// convenience field derived from `supportingNotes` when available, or from
    /// token defaults when no note text is present.
    let defaultExplanation: String
    let returnsCalculatedExposureTime: Bool

    init(
        category: ReciprocityConfidenceCategory,
        level: ReciprocityConfidenceLevel,
        badgeStyle: ReciprocityConfidenceBadgeStyle,
        warningEmphasis: ReciprocityConfidenceWarningEmphasis,
        resultKind: ReciprocityConfidenceResultKind,
        shortLabel: String,
        explanationTokens: [ReciprocityConfidenceExplanationToken],
        supportingNotes: [String],
        defaultExplanation: String,
        returnsCalculatedExposureTime: Bool
    ) {
        let validationError = Self.validationError(
            category: category,
            badgeStyle: badgeStyle,
            resultKind: resultKind,
            explanationTokens: explanationTokens,
            returnsCalculatedExposureTime: returnsCalculatedExposureTime
        )
        precondition(validationError == nil, validationError ?? "Invalid reciprocity confidence presentation.")

        self.category = category
        self.level = level
        self.badgeStyle = badgeStyle
        self.warningEmphasis = warningEmphasis
        self.resultKind = resultKind
        self.shortLabel = shortLabel
        self.explanationTokens = explanationTokens
        self.supportingNotes = supportingNotes
        self.defaultExplanation = defaultExplanation
        self.returnsCalculatedExposureTime = returnsCalculatedExposureTime
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case level
        case badgeStyle
        case warningEmphasis
        case resultKind
        case shortLabel
        case explanationTokens
        case supportingNotes
        case defaultExplanation
        case returnsCalculatedExposureTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let category = try container.decode(ReciprocityConfidenceCategory.self, forKey: .category)
        let level = try container.decode(ReciprocityConfidenceLevel.self, forKey: .level)
        let badgeStyle = try container.decode(ReciprocityConfidenceBadgeStyle.self, forKey: .badgeStyle)
        let warningEmphasis = try container.decode(ReciprocityConfidenceWarningEmphasis.self, forKey: .warningEmphasis)
        let resultKind = try container.decode(ReciprocityConfidenceResultKind.self, forKey: .resultKind)
        let shortLabel = try container.decode(String.self, forKey: .shortLabel)
        let explanationTokens = try container.decode(
            [ReciprocityConfidenceExplanationToken].self,
            forKey: .explanationTokens
        )
        let supportingNotes = try container.decode([String].self, forKey: .supportingNotes)
        let defaultExplanation = try container.decode(String.self, forKey: .defaultExplanation)
        let returnsCalculatedExposureTime = try container.decode(Bool.self, forKey: .returnsCalculatedExposureTime)

        if let validationError = Self.validationError(
            category: category,
            badgeStyle: badgeStyle,
            resultKind: resultKind,
            explanationTokens: explanationTokens,
            returnsCalculatedExposureTime: returnsCalculatedExposureTime
        ) {
            throw DecodingError.dataCorruptedError(
                forKey: .resultKind,
                in: container,
                debugDescription: validationError
            )
        }

        self.category = category
        self.level = level
        self.badgeStyle = badgeStyle
        self.warningEmphasis = warningEmphasis
        self.resultKind = resultKind
        self.shortLabel = shortLabel
        self.explanationTokens = explanationTokens
        self.supportingNotes = supportingNotes
        self.defaultExplanation = defaultExplanation
        self.returnsCalculatedExposureTime = returnsCalculatedExposureTime
    }

    private static func validationError(
        category: ReciprocityConfidenceCategory,
        badgeStyle: ReciprocityConfidenceBadgeStyle,
        resultKind: ReciprocityConfidenceResultKind,
        explanationTokens: [ReciprocityConfidenceExplanationToken],
        returnsCalculatedExposureTime: Bool
    ) -> String? {
        guard resultKind == expectedResultKind(for: category) else {
            return "resultKind must remain aligned with category."
        }

        switch category {
        case .limitedGuidance:
            guard badgeStyle != .unsupported else {
                return "limitedGuidance presentation must remain distinct from unsupported styling."
            }
            guard !returnsCalculatedExposureTime else {
                return "limitedGuidance presentation must not imply a calculated exposure time."
            }
        case .unsupported:
            guard badgeStyle == .unsupported else {
                return "unsupported presentation must use unsupported badge styling."
            }
            // Unsupported classifies the result as outside
            // manufacturer-supported guidance, not as unavailable. A
            // formula-backed profile may still hand back a numeric
            // corrected exposure; presenters mark such values as
            // approximate / outside guidance.
        case .noCorrection, .formulaDerived:
            break
        }

        if returnsCalculatedExposureTime && explanationTokens.contains(.noCalculatedExposureReturned) {
            return "Presentation cannot both return and omit a calculated exposure time."
        }

        if !returnsCalculatedExposureTime && explanationTokens.contains(.calculatedExposureReturned) {
            return "Presentation cannot advertise a calculated exposure time when none was returned."
        }

        return nil
    }

    private static func expectedResultKind(
        for category: ReciprocityConfidenceCategory
    ) -> ReciprocityConfidenceResultKind {
        switch category {
        case .noCorrection:
            return .noCorrection
        case .formulaDerived:
            return .formulaDerived
        case .limitedGuidance:
            return .limitedGuidance
        case .unsupported:
            return .unsupported
        }
    }
}

private extension ReciprocityConfidencePresentation {
    struct Payload {
        let level: ReciprocityConfidenceLevel
        let warningEmphasis: ReciprocityConfidenceWarningEmphasis
        let shortLabel: String
        let explanationTokens: [ReciprocityConfidenceExplanationToken]
        let supportingNotes: [String]
        let defaultExplanation: String
        let returnsCalculatedExposureTime: Bool
    }

    static func noCorrection(payload: Payload) -> Self {
        Self(
            category: .noCorrection,
            level: payload.level,
            badgeStyle: badgeStyle(for: .noCorrection, level: payload.level),
            warningEmphasis: payload.warningEmphasis,
            resultKind: .noCorrection,
            shortLabel: payload.shortLabel,
            explanationTokens: payload.explanationTokens,
            supportingNotes: payload.supportingNotes,
            defaultExplanation: payload.defaultExplanation,
            returnsCalculatedExposureTime: payload.returnsCalculatedExposureTime
        )
    }

    static func formulaDerived(payload: Payload) -> Self {
        Self(
            category: .formulaDerived,
            level: payload.level,
            badgeStyle: badgeStyle(for: .formulaDerived, level: payload.level),
            warningEmphasis: payload.warningEmphasis,
            resultKind: .formulaDerived,
            shortLabel: payload.shortLabel,
            explanationTokens: payload.explanationTokens,
            supportingNotes: payload.supportingNotes,
            defaultExplanation: payload.defaultExplanation,
            returnsCalculatedExposureTime: payload.returnsCalculatedExposureTime
        )
    }

    static func limitedGuidance(payload: Payload) -> Self {
        Self(
            category: .limitedGuidance,
            level: .none,
            badgeStyle: .limitedGuidance,
            warningEmphasis: payload.warningEmphasis,
            resultKind: .limitedGuidance,
            shortLabel: payload.shortLabel,
            explanationTokens: payload.explanationTokens,
            supportingNotes: payload.supportingNotes,
            defaultExplanation: payload.defaultExplanation,
            returnsCalculatedExposureTime: false
        )
    }

    static func unsupported(payload: Payload) -> Self {
        Self(
            category: .unsupported,
            level: .none,
            badgeStyle: .unsupported,
            warningEmphasis: payload.warningEmphasis,
            resultKind: .unsupported,
            shortLabel: payload.shortLabel,
            explanationTokens: payload.explanationTokens,
            supportingNotes: payload.supportingNotes,
            defaultExplanation: payload.defaultExplanation,
            returnsCalculatedExposureTime: payload.returnsCalculatedExposureTime
        )
    }

    private static func badgeStyle(
        for category: ReciprocityConfidenceCategory,
        level: ReciprocityConfidenceLevel
    ) -> ReciprocityConfidenceBadgeStyle {
        switch category {
        case .unsupported:
            return .unsupported
        case .limitedGuidance:
            return .limitedGuidance
        case .formulaDerived:
            switch level {
            case .high, .medium:
                return .measured
            case .low, .veryLow, .none:
                return .caution
            }
        case .noCorrection:
            switch level {
            case .high:
                return .trusted
            case .medium:
                return .measured
            case .low, .veryLow, .none:
                return .caution
            }
        }
    }
}

/// Maps calculation-layer result metadata into presentation-facing confidence
/// structure. This type intentionally consumes only policy output and does not
/// inspect raw domain rules or re-run calculation-policy decisions.
struct ReciprocityConfidencePresentationMapper {
    func map(
        result: ReciprocityResult
    ) -> ReciprocityConfidencePresentation {
        let payload = payload(for: result)

        switch result.metadata.basis {
        case .officialThresholdNoCorrection:
            return .noCorrection(payload: payload)
        case .formulaDerived:
            return .formulaDerived(payload: payload)
        case .limitedGuidanceNoQuantifiedPrediction:
            return .limitedGuidance(payload: payload)
        case .unsupportedOutOfPolicyRange:
            return .unsupported(payload: payload)
        }
    }

    private func payload(
        for result: ReciprocityResult
    ) -> ReciprocityConfidencePresentation.Payload {
        let explanationTokens = explanationTokens(for: result)
        let supportingNotes = result.metadata.notes.map(\.text)

        return ReciprocityConfidencePresentation.Payload(
            level: defaultLevel(
                for: result.metadata.basis,
                sourceAuthorityImpact: result.metadata.sourceAuthorityImpact
            ),
            warningEmphasis: warningEmphasis(for: result.metadata.warningLevel),
            shortLabel: shortLabel(
                for: result.metadata.basis,
                sourceAuthorityImpact: result.metadata.sourceAuthorityImpact
            ),
            explanationTokens: explanationTokens,
            supportingNotes: supportingNotes,
            defaultExplanation: fallbackExplanation(
                explanationTokens: explanationTokens,
                supportingNotes: supportingNotes
            ),
            returnsCalculatedExposureTime: result.hasCalculatedExposureTime
        )
    }

    /// Current default mapping only. Confidence tuning may evolve without
    /// changing the surrounding presentation contract.
    private func defaultLevel(
        for basis: ReciprocityCalculationBasis,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> ReciprocityConfidenceLevel {
        switch basis {
        case .officialThresholdNoCorrection, .formulaDerived:
            switch sourceAuthorityImpact {
            case .currentOfficial:
                return basis == .formulaDerived ? .medium : .high
            case .archivalOfficial:
                return .medium
            case .unofficialSecondary:
                return .low
            case .userDefined:
                return .veryLow
            }
        case .limitedGuidanceNoQuantifiedPrediction:
            return .none
        case .unsupportedOutOfPolicyRange:
            return .none
        }
    }

    private func warningEmphasis(
        for warningLevel: ReciprocityCalculationWarningLevel
    ) -> ReciprocityConfidenceWarningEmphasis {
        switch warningLevel {
        case .none:
            return .none
        case .note:
            return .note
        case .caution:
            return .caution
        case .strongWarning:
            return .strong
        }
    }

    private func shortLabel(
        for basis: ReciprocityCalculationBasis,
        sourceAuthorityImpact: ReciprocitySourceAuthorityImpact
    ) -> String {
        let prefix: String

        switch sourceAuthorityImpact {
        case .currentOfficial:
            prefix = ""
        case .archivalOfficial:
            prefix = "Archival "
        case .unofficialSecondary:
            prefix = "Secondary "
        case .userDefined:
            prefix = "Custom "
        }

        switch basis {
        case .officialThresholdNoCorrection:
            return prefix.isEmpty ? "No correction" : "\(prefix)no correction"
        case .limitedGuidanceNoQuantifiedPrediction:
            return prefix.isEmpty ? "No quantified prediction" : "\(prefix)limited guidance"
        case .unsupportedOutOfPolicyRange:
            return "Outside guidance"
        case .formulaDerived:
            return prefix.isEmpty ? "Formula-derived" : "\(prefix)formula"
        }
    }

    private func fallbackExplanation(
        explanationTokens: [ReciprocityConfidenceExplanationToken],
        supportingNotes: [String]
    ) -> String {
        guard supportingNotes.isEmpty else {
            return supportingNotes.joined(separator: " ")
        }

        return explanationTokens.map(\.defaultText).joined(separator: " ")
    }

    private func explanationTokens(
        for result: ReciprocityResult
    ) -> [ReciprocityConfidenceExplanationToken] {
        var tokens: [ReciprocityConfidenceExplanationToken] = []

        appendBasisToken(from: result.metadata.basis, to: &tokens)
        appendSourceToken(from: result.metadata.sourceAuthorityImpact, to: &tokens)
        appendRangeToken(from: result.metadata.rangeStatus, to: &tokens)

        for note in result.metadata.notes {
            guard let mappedToken = explanationToken(from: note.token) else {
                continue
            }

            appendUnique(mappedToken, to: &tokens)
        }

        appendUnique(
            result.hasCalculatedExposureTime ? .calculatedExposureReturned : .noCalculatedExposureReturned,
            to: &tokens
        )

        return tokens
    }

    private func appendBasisToken(
        from basis: ReciprocityCalculationBasis,
        to tokens: inout [ReciprocityConfidenceExplanationToken]
    ) {
        switch basis {
        case .officialThresholdNoCorrection:
            appendUnique(.thresholdGuidanceOnly, to: &tokens)
        case .limitedGuidanceNoQuantifiedPrediction:
            appendUnique(.limitedGuidanceContinuationOnly, to: &tokens)
        case .unsupportedOutOfPolicyRange:
            appendUnique(.unsupportedByPolicy, to: &tokens)
        case .formulaDerived:
            appendUnique(.formulaDerived, to: &tokens)
        }
    }

    private func appendSourceToken(
        from sourceAuthorityImpact: ReciprocitySourceAuthorityImpact,
        to tokens: inout [ReciprocityConfidenceExplanationToken]
    ) {
        switch sourceAuthorityImpact {
        case .currentOfficial:
            appendUnique(.currentOfficialSource, to: &tokens)
        case .archivalOfficial:
            appendUnique(.archivalOfficialSource, to: &tokens)
        case .unofficialSecondary:
            appendUnique(.unofficialSecondarySource, to: &tokens)
        case .userDefined:
            appendUnique(.userDefinedSource, to: &tokens)
        }
    }

    private func appendRangeToken(
        from rangeStatus: ReciprocityCalculationRangeStatus,
        to tokens: inout [ReciprocityConfidenceExplanationToken]
    ) {
        switch rangeStatus {
        case .withinStatedRange:
            appendUnique(.withinStatedRange, to: &tokens)
        case .beyondLastRepresentativePoint:
            appendUnique(.beyondRepresentativePoint, to: &tokens)
        case .beyondPolicyLimit:
            appendUnique(.beyondPolicyLimit, to: &tokens)
        }
    }

    private func explanationToken(
        from policyToken: ReciprocityPolicyNoteToken?
    ) -> ReciprocityConfidenceExplanationToken? {
        switch policyToken {
        case .thresholdGuidanceOnly:
            return .thresholdGuidanceOnly
        case .limitedGuidanceContinuationOnly:
            return .limitedGuidanceContinuationOnly
        case .beyondOfficialQuantifiedRange:
            return .officialRangeExceeded
        case .archivalOfficialSource:
            return .archivalOfficialSource
        case .unofficialSecondarySource:
            return .unofficialSecondarySource
        case .userDefinedSource:
            return .userDefinedSource
        case .unsupportedByPolicy:
            return .unsupportedByPolicy
        case .none:
            return nil
        }
    }

    private func appendUnique(
        _ token: ReciprocityConfidenceExplanationToken,
        to tokens: inout [ReciprocityConfidenceExplanationToken]
    ) {
        guard !tokens.contains(token) else {
            return
        }

        tokens.append(token)
    }
}

extension ReciprocityResult {
    var confidencePresentation: ReciprocityConfidencePresentation {
        ReciprocityConfidencePresentationMapper().map(result: self)
    }
}
