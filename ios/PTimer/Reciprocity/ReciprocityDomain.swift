import Foundation

struct FilmIdentity: Codable, Equatable {
    let id: String
    let kind: FilmIdentityKind
    let canonicalStockName: String
    let manufacturer: String?
    let brandLabel: String?
    let aliases: [String]
    let iso: Int
    let productionStatus: FilmProductionStatus
    let profiles: [ReciprocityProfile]
    let userMetadata: UserEditableMetadata?
}

enum FilmIdentityKind: String, Codable, Equatable {
    case preset
    case custom
    case unknown
}

enum FilmProductionStatus: String, Codable, Equatable {
    case current
    case discontinued
    case unknown
}

struct UserEditableMetadata: Codable, Equatable {
    let displayNameOverride: String?
    let tags: [String]
    let notes: [String]

    init(
        displayNameOverride: String? = nil,
        tags: [String] = [],
        notes: [String] = []
    ) {
        self.displayNameOverride = displayNameOverride
        self.tags = tags
        self.notes = notes
    }
}

struct ReciprocityProfile: Codable, Equatable {
    let id: String
    let name: String
    let source: ReciprocitySourceProvenance
    let rules: [ReciprocityRule]
    let notes: [String]
    let userMetadata: UserEditableMetadata?
    /// Published manufacturer reference points the user can verify
    /// against. Display-only — the calculation policy evaluator does
    /// not consume this field, so source-evidence rows cannot enter
    /// the calculation as table anchors even when the profile keeps a
    /// manufacturer reference table on display.
    let sourceEvidence: [ReciprocitySourceEvidenceRow]

    init(
        id: String,
        name: String,
        source: ReciprocitySourceProvenance,
        rules: [ReciprocityRule],
        notes: [String] = [],
        userMetadata: UserEditableMetadata? = nil,
        sourceEvidence: [ReciprocitySourceEvidenceRow] = []
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.rules = rules
        self.notes = notes
        self.userMetadata = userMetadata
        self.sourceEvidence = sourceEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case rules
        case notes
        case userMetadata
        case sourceEvidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.source = try container.decode(ReciprocitySourceProvenance.self, forKey: .source)
        self.rules = try container.decode([ReciprocityRule].self, forKey: .rules)
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        self.userMetadata = try container.decodeIfPresent(UserEditableMetadata.self, forKey: .userMetadata)
        self.sourceEvidence = try container.decodeIfPresent(
            [ReciprocitySourceEvidenceRow].self,
            forKey: .sourceEvidence
        ) ?? []
    }
}

/// Display-only source-evidence row carried by a `ReciprocityProfile`.
///
/// Carries a manufacturer-published reference point that the presenter
/// renders so users can verify formula-based predictions against the
/// published data. The calculation policy never consumes these rows,
/// so source evidence cannot enter the calculation as a table anchor.
struct ReciprocitySourceEvidenceRow: Codable, Equatable {
    let meteredExposure: MeteredExposureSelector
    let adjustments: [ReciprocityAdjustment]
    let notes: [String]
    /// `true` for rows preserved as published reference only — the
    /// renderer omits the row from formula-graph fitting markers and
    /// prefixes it with `*` in the Source reference block so the user
    /// can tell it is not used as a calculation anchor. Used by ADOX
    /// CMS 20 II for its 1/1000 s +1/2 stop guidance row, which is
    /// preserved as published evidence but does not participate in
    /// the formula fit (the calculation path stays no-correction
    /// across the entire sub-1 s band).
    let isSourceEvidenceOnly: Bool

    init(
        meteredExposure: MeteredExposureSelector,
        adjustments: [ReciprocityAdjustment],
        notes: [String] = [],
        isSourceEvidenceOnly: Bool = false
    ) {
        self.meteredExposure = meteredExposure
        self.adjustments = adjustments
        self.notes = notes
        self.isSourceEvidenceOnly = isSourceEvidenceOnly
    }

    private enum CodingKeys: String, CodingKey {
        case meteredExposure
        case adjustments
        case notes
        case isSourceEvidenceOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meteredExposure = try container.decode(MeteredExposureSelector.self, forKey: .meteredExposure)
        self.adjustments = try container.decode([ReciprocityAdjustment].self, forKey: .adjustments)
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        self.isSourceEvidenceOnly = try container.decodeIfPresent(Bool.self, forKey: .isSourceEvidenceOnly) ?? false
    }
}

extension ReciprocityProfile {
    /// `true` when the profile mixes a formula rule with at least
    /// one manufacturer-published source-evidence row. Such profiles
    /// were converted from a manufacturer reference table to a formula
    /// prediction while preserving the published reference, which lets
    /// presentation surfaces use "Beyond source range" language for
    /// inputs past the published reference without affecting
    /// source-less formula profiles (HP5 Plus etc.).
    var isConvertedFormulaProfile: Bool {
        let hasFormulaRule = rules.contains { rule in
            if case .formula = rule { return true }
            return false
        }
        return hasFormulaRule && !sourceEvidence.isEmpty
    }
}

struct ReciprocitySourceProvenance: Codable, Equatable {
    let kind: ReciprocitySourceKind
    let authority: ReciprocityAuthority
    let confidence: ReciprocityConfidence
    let publisher: String
    let title: String?
    let citation: String?
    let sourceVersion: String?

    init(
        kind: ReciprocitySourceKind,
        authority: ReciprocityAuthority,
        confidence: ReciprocityConfidence = .unknown,
        publisher: String,
        title: String? = nil,
        citation: String? = nil,
        sourceVersion: String? = nil
    ) {
        self.kind = kind
        self.authority = authority
        self.confidence = confidence
        self.publisher = publisher
        self.title = title
        self.citation = citation
        self.sourceVersion = sourceVersion
    }
}

enum ReciprocitySourceKind: String, Codable, Equatable {
    case manufacturerPublished
    case manufacturerArchive
    case thirdPartyPublication
    case userDefined
    case unknown
}

enum ReciprocityAuthority: String, Codable, Equatable {
    case official
    case unofficial
    case userDefined
    case unknown
}

enum ReciprocityConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
    case unknown
}

enum ReciprocityRule: Codable, Equatable {
    case threshold(ThresholdReciprocityRule)
    case formula(FormulaReciprocityRule)
    case limitedGuidance(LimitedGuidanceReciprocityRule)

    var kind: ReciprocityRuleKind {
        switch self {
        case .threshold:
            return .threshold
        case .formula:
            return .formula
        case .limitedGuidance:
            return .limitedGuidance
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case threshold
        case formula
        case limitedGuidance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ReciprocityRuleKind.self, forKey: .kind)

        switch kind {
        case .threshold:
            self = .threshold(try container.decode(ThresholdReciprocityRule.self, forKey: .threshold))
        case .formula:
            self = .formula(try container.decode(FormulaReciprocityRule.self, forKey: .formula))
        case .limitedGuidance:
            self = .limitedGuidance(
                try container.decode(LimitedGuidanceReciprocityRule.self, forKey: .limitedGuidance)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .threshold(rule):
            try container.encode(rule, forKey: .threshold)
        case let .formula(rule):
            try container.encode(rule, forKey: .formula)
        case let .limitedGuidance(rule):
            try container.encode(rule, forKey: .limitedGuidance)
        }
    }
}

enum ReciprocityRuleKind: String, Codable, Equatable {
    case threshold
    case formula
    case limitedGuidance
}

struct ThresholdReciprocityRule: Codable, Equatable {
    let noCorrectionRange: ReciprocityTimeRange
    let adjustments: [ReciprocityAdjustment]
    let notes: [String]

    init(
        noCorrectionRange: ReciprocityTimeRange,
        adjustments: [ReciprocityAdjustment] = [],
        notes: [String] = []
    ) {
        self.noCorrectionRange = noCorrectionRange
        self.adjustments = adjustments
        self.notes = notes
    }
}

struct FormulaReciprocityRule: Codable, Equatable {
    let meteredRange: ReciprocityTimeRange?
    let formula: ReciprocityFormula
    let additionalAdjustments: [ReciprocityAdjustment]
    let notes: [String]
    /// `true` (default) when the formula can still produce a numeric
    /// value past its `meteredRange.maximumSeconds`; the result is
    /// reclassified as unsupported but carries the formula prediction
    /// outside the source range as an actionable corrected exposure.
    ///
    /// `false` when the manufacturer publishes the upper bound as a
    /// hard stop signal — exceeding it returns an unsupported result
    /// with no corrected exposure value, regardless of whether the
    /// formula itself could still compute one. ADOX CMS 20 II uses
    /// this for its `>= 100 s` "Not recommended" boundary.
    let extrapolateBeyondMaximum: Bool

    init(
        meteredRange: ReciprocityTimeRange? = nil,
        formula: ReciprocityFormula,
        additionalAdjustments: [ReciprocityAdjustment] = [],
        notes: [String] = [],
        extrapolateBeyondMaximum: Bool = true
    ) {
        self.meteredRange = meteredRange
        self.formula = formula
        self.additionalAdjustments = additionalAdjustments
        self.notes = notes
        self.extrapolateBeyondMaximum = extrapolateBeyondMaximum
    }

    private enum CodingKeys: String, CodingKey {
        case meteredRange
        case formula
        case additionalAdjustments
        case notes
        case extrapolateBeyondMaximum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meteredRange = try container.decodeIfPresent(ReciprocityTimeRange.self, forKey: .meteredRange)
        self.formula = try container.decode(ReciprocityFormula.self, forKey: .formula)
        self.additionalAdjustments = try container.decodeIfPresent(
            [ReciprocityAdjustment].self,
            forKey: .additionalAdjustments
        ) ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        self.extrapolateBeyondMaximum = try container.decodeIfPresent(
            Bool.self,
            forKey: .extrapolateBeyondMaximum
        ) ?? true
    }
}

/// Limited-guidance rule used by official-source profiles that publish
/// only qualitative guidance past a no-correction threshold (e.g.
/// Kodak Portra / Ektar / Ektachrome). The rule never yields a
/// quantified corrected exposure; presentation surfaces the result as
/// "No quantified prediction".
struct LimitedGuidanceReciprocityRule: Codable, Equatable {
    let appliesWhenMetered: ReciprocityTimeRange?
    let adjustments: [ReciprocityAdjustment]
    let notes: [String]

    init(
        appliesWhenMetered: ReciprocityTimeRange? = nil,
        adjustments: [ReciprocityAdjustment] = [],
        notes: [String] = []
    ) {
        self.appliesWhenMetered = appliesWhenMetered
        self.adjustments = adjustments
        self.notes = notes
    }
}

struct ReciprocityTimeRange: Codable, Equatable {
    // Validation-facing semantics are inclusive at both ends.
    // A missing maximum means the range continues upward from minimumSeconds.
    let minimumSeconds: Double
    let maximumSeconds: Double?

    init(minimumSeconds: Double, maximumSeconds: Double? = nil) {
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
    }
}

struct ReciprocityFormula: Codable, Equatable {
    let kind: ReciprocityFormulaKind
    let exponent: Double
    // Reserved for future formula variants. The current exponent-power
    // validation sample does not require these fields.
    let coefficient: Double?
    let offsetSeconds: Double?
    let equation: String?

    init(
        kind: ReciprocityFormulaKind = .exponentPower,
        exponent: Double,
        coefficient: Double? = nil,
        offsetSeconds: Double? = nil,
        equation: String? = nil
    ) {
        self.kind = kind
        self.exponent = exponent
        self.coefficient = coefficient
        self.offsetSeconds = offsetSeconds
        self.equation = equation
    }
}

enum ReciprocityFormulaKind: String, Codable, Equatable {
    case exponentPower
}

enum MeteredExposureSelector: Codable, Equatable {
    case exactSeconds(Double)
    case range(ReciprocityTimeRange)

    private enum CodingKeys: String, CodingKey {
        case kind
        case exactSeconds
        case range
    }

    private enum SelectorKind: String, Codable {
        case exactSeconds
        case range
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SelectorKind.self, forKey: .kind)

        switch kind {
        case .exactSeconds:
            self = .exactSeconds(try container.decode(Double.self, forKey: .exactSeconds))
        case .range:
            self = .range(try container.decode(ReciprocityTimeRange.self, forKey: .range))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .exactSeconds(value):
            try container.encode(SelectorKind.exactSeconds, forKey: .kind)
            try container.encode(value, forKey: .exactSeconds)
        case let .range(value):
            try container.encode(SelectorKind.range, forKey: .kind)
            try container.encode(value, forKey: .range)
        }
    }
}

enum ReciprocityAdjustment: Codable, Equatable {
    case exposure(ExposureAdjustment)
    case colorFilter(ColorFilterRecommendation)
    case development(DevelopmentAdjustment)
    case warning(ReciprocityWarning)
    case note(ReciprocityNote)

    private enum CodingKeys: String, CodingKey {
        case kind
        case exposure
        case colorFilter
        case development
        case warning
        case note
    }

    private enum AdjustmentKind: String, Codable {
        case exposure
        case colorFilter
        case development
        case warning
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AdjustmentKind.self, forKey: .kind)

        switch kind {
        case .exposure:
            self = .exposure(try container.decode(ExposureAdjustment.self, forKey: .exposure))
        case .colorFilter:
            self = .colorFilter(try container.decode(ColorFilterRecommendation.self, forKey: .colorFilter))
        case .development:
            self = .development(try container.decode(DevelopmentAdjustment.self, forKey: .development))
        case .warning:
            self = .warning(try container.decode(ReciprocityWarning.self, forKey: .warning))
        case .note:
            self = .note(try container.decode(ReciprocityNote.self, forKey: .note))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .exposure(value):
            try container.encode(AdjustmentKind.exposure, forKey: .kind)
            try container.encode(value, forKey: .exposure)
        case let .colorFilter(value):
            try container.encode(AdjustmentKind.colorFilter, forKey: .kind)
            try container.encode(value, forKey: .colorFilter)
        case let .development(value):
            try container.encode(AdjustmentKind.development, forKey: .kind)
            try container.encode(value, forKey: .development)
        case let .warning(value):
            try container.encode(AdjustmentKind.warning, forKey: .kind)
            try container.encode(value, forKey: .warning)
        case let .note(value):
            try container.encode(AdjustmentKind.note, forKey: .kind)
            try container.encode(value, forKey: .note)
        }
    }
}

enum ExposureAdjustment: Codable, Equatable {
    case correctedTime(CorrectedTimeMapping)
    case stopDelta(StopDeltaAdjustment)
    case multiplier(MultiplierAdjustment)

    private enum CodingKeys: String, CodingKey {
        case kind
        case correctedTime
        case stopDelta
        case multiplier
    }

    private enum ExposureKind: String, Codable {
        case correctedTime
        case stopDelta
        case multiplier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ExposureKind.self, forKey: .kind)

        switch kind {
        case .correctedTime:
            self = .correctedTime(try container.decode(CorrectedTimeMapping.self, forKey: .correctedTime))
        case .stopDelta:
            self = .stopDelta(try container.decode(StopDeltaAdjustment.self, forKey: .stopDelta))
        case .multiplier:
            self = .multiplier(try container.decode(MultiplierAdjustment.self, forKey: .multiplier))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .correctedTime(value):
            try container.encode(ExposureKind.correctedTime, forKey: .kind)
            try container.encode(value, forKey: .correctedTime)
        case let .stopDelta(value):
            try container.encode(ExposureKind.stopDelta, forKey: .kind)
            try container.encode(value, forKey: .stopDelta)
        case let .multiplier(value):
            try container.encode(ExposureKind.multiplier, forKey: .kind)
            try container.encode(value, forKey: .multiplier)
        }
    }
}

struct CorrectedTimeMapping: Codable, Equatable {
    let meteredSeconds: Double?
    let correctedSeconds: Double
    /// `true` when `correctedSeconds` should be displayed as a rounded
    /// approximation of an irrational conversion — typically a
    /// fractional-stop derivation `metered × 2^stopDelta` on a row
    /// whose source published only the stop delta. Multiplier-derived
    /// corrected times (`metered × multiplier`) are exact arithmetic
    /// and are *not* marked, even though they too are catalog-derived.
    /// The presenter prefixes flagged values with "≈" so the user can
    /// tell rounded values from published or exactly-converted ones at
    /// a glance. `false` for source-published rows and for exact-
    /// arithmetic catalog conversions.
    let isApproximate: Bool

    init(
        meteredSeconds: Double? = nil,
        correctedSeconds: Double,
        isApproximate: Bool = false
    ) {
        self.meteredSeconds = meteredSeconds
        self.correctedSeconds = correctedSeconds
        self.isApproximate = isApproximate
    }

    private enum CodingKeys: String, CodingKey {
        case meteredSeconds
        case correctedSeconds
        case isApproximate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meteredSeconds = try container.decodeIfPresent(Double.self, forKey: .meteredSeconds)
        correctedSeconds = try container.decode(Double.self, forKey: .correctedSeconds)
        // `isApproximate` is omitted from existing catalog fixtures
        // so missing keys decode to `false` (source-published).
        isApproximate = try container.decodeIfPresent(Bool.self, forKey: .isApproximate) ?? false
    }
}

struct StopDeltaAdjustment: Codable, Equatable {
    let stopDelta: Double
}

struct MultiplierAdjustment: Codable, Equatable {
    let factor: Double
}

struct ColorFilterRecommendation: Codable, Equatable {
    let filterName: String
    let note: String?
}

struct DevelopmentAdjustment: Codable, Equatable {
    let instruction: String
    let note: String?
}

struct ReciprocityWarning: Codable, Equatable {
    let severity: ReciprocityWarningSeverity
    let message: String
}

enum ReciprocityWarningSeverity: String, Codable, Equatable {
    case caution
    case notRecommended
}

struct ReciprocityNote: Codable, Equatable {
    let text: String
}

// Unofficial practical profiles defined separately from the launch preset catalog.
// The launch catalog enforces exactly one official manufacturer profile per film identity.
// Profiles in this registry are lower-authority supplementary data for future UI exposure.
enum UnofficialPracticalProfiles {

    // Unofficial practical approximation profile for Kodak Portra 400.
    //
    // This profile is separate from the official primary profile
    // "kodak-portra-official-threshold" in the launch preset catalog and must never
    // replace or shadow it.
    //
    static func profile(forFilmID filmID: String) -> ReciprocityProfile? {
        switch filmID {
        case "kodak-portra-400": return kodakPortra400UnofficialPractical
        default: return nil
        }
    }

    // `publisher` is the documented "source pending verification" marker
    // (DomainSchema §4): supplementary unofficial profiles whose source
    // has not yet been verified leave `publisher` empty so the
    // presenter does not surface a Sources section that would imply an
    // external citation. The unofficial-authority subtitle plus the
    // caveat note carry the user-facing disclosure.
    static let kodakPortra400UnofficialPractical = ReciprocityProfile(
        id: "kodak-portra-400-unofficial-practical",
        name: "Unofficial practical approximation",
        source: ReciprocitySourceProvenance(
            kind: .thirdPartyPublication,
            authority: .unofficial,
            confidence: .low,
            publisher: "",
            title: nil,
            citation: nil,
            sourceVersion: nil
        ),
        rules: [
            .formula(FormulaReciprocityRule(
                formula: ReciprocityFormula(
                    kind: .exponentPower,
                    exponent: 1.34,
                    equation: "Tc = Tm^P"
                )
            )),
        ],
        notes: [
            "Unofficial practical approximation. Not a Kodak-published profile.",
            "Formula: Tc = Tm^1.34. Source pending verification.",
        ]
    )
}
