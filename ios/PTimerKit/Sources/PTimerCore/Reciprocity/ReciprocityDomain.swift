// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Boundary policy for the no-correction band.
///
/// A profile whose source says "no correction through `T`" must
/// treat a UI input nominally equal to `T` as no correction even
/// when Base Shutter / ND stop arithmetic produces a value a few
/// percent above `T`. For a `0.1 s` (nominal 1/10 s) boundary the
/// adjusted shutter can land near `0.102 s`; a strict `<= 0.1`
/// comparison would misclassify it as table-derived.
///
/// A small relative tolerance keeps the boundary robust for
/// shutter/stop-derived values while staying well below the next
/// meaningful step: `0.1 × 1.10 = 0.11 s` admits the nominal
/// `~0.102 s` with margin yet leaves `0.12 s` and `0.15 s`
/// corrected. The tolerance is relative, so it never widens a band
/// anywhere near `1 s` for a `0.1 s` threshold.
///
/// Used by the **table** evaluator only. The formula evaluator keeps
/// a strict boundary because formula films (e.g. Acros II) encode an
/// exact-epsilon `noCorrectionThroughSeconds` that a tolerance would
/// break.
public enum ReciprocityNoCorrectionBoundary {
    /// Relative tolerance applied above `noCorrectionThroughSeconds`
    /// when classifying an input as no correction.
    public static let relativeTolerance = 0.10

    /// Whether `meteredSeconds` falls within the no-correction band
    /// for the given threshold, including the boundary tolerance.
    public static func isWithinNoCorrection(
        meteredSeconds: Double,
        throughSeconds: Double
    ) -> Bool {
        meteredSeconds <= throughSeconds * (1 + relativeTolerance)
    }
}

public struct FilmIdentity: Codable, Equatable {
    public let id: String
    public let kind: FilmIdentityKind
    public let canonicalStockName: String
    public let manufacturer: String?
    public let brandLabel: String?
    public let aliases: [String]
    public let iso: Int
    public let productionStatus: FilmProductionStatus
    public let profiles: [ReciprocityProfile]
    public let userMetadata: UserEditableMetadata?

    public init(
        id: String,
        kind: FilmIdentityKind,
        canonicalStockName: String,
        manufacturer: String? = nil,
        brandLabel: String? = nil,
        aliases: [String],
        iso: Int,
        productionStatus: FilmProductionStatus,
        profiles: [ReciprocityProfile],
        userMetadata: UserEditableMetadata? = nil
    ) {
        self.id = id
        self.kind = kind
        self.canonicalStockName = canonicalStockName
        self.manufacturer = manufacturer
        self.brandLabel = brandLabel
        self.aliases = aliases
        self.iso = iso
        self.productionStatus = productionStatus
        self.profiles = profiles
        self.userMetadata = userMetadata
    }
}

public enum FilmIdentityKind: String, Codable, Equatable {
    case preset
    case custom
    case unknown
}

public enum FilmProductionStatus: String, Codable, Equatable {
    case current
    case discontinued
    case unknown
}

public struct UserEditableMetadata: Codable, Equatable {
    public let displayNameOverride: String?
    public let tags: [String]
    public let notes: [String]
    /// User-supplied classification of a custom (`.userDefined`-
    /// authority) profile's origin. Optional so preset films and
    /// legacy user metadata decode unchanged. The calculation
    /// policy never reads this field — it is descriptive metadata
    /// surfaced in the selector subtitle, Film Details, and timer
    /// identity snapshot so a custom profile cannot be mistaken for
    /// manufacturer data.
    public let customSourceType: CustomProfileSourceType?
    /// Photographer-entered manufacturer string for a custom film
    /// (e.g. `"Kodak"`).
    /// Stored separately from `FilmIdentity.manufacturer` because
    /// the latter drives the selector's manufacturer-grouping pass;
    /// custom films must stay in the dedicated "Custom films"
    /// section regardless of what the photographer typed.
    public let customManufacturer: String?
    /// Optional reference URL the photographer can attach so a
    /// later edit recalls the formula's source. Additive Optional
    /// field — older `UserEditableMetadata` payloads decode
    /// unchanged.
    public let referenceURL: String?
    /// PTIMER-180: optional id of a custom **table** film this
    /// (custom **formula**) profile was created from / linked to.
    /// Display-only — comparison / error / provenance hint. The
    /// calculation policy never reads it; a Custom Formula computes
    /// only from its formula parameters. Additive Optional field so
    /// older payloads decode unchanged. The link is set at
    /// Create-Formula time and is never used to recalculate the
    /// formula when the linked table changes.
    public let referenceTableFilmID: String?

    public init(
        displayNameOverride: String? = nil,
        tags: [String] = [],
        notes: [String] = [],
        customSourceType: CustomProfileSourceType? = nil,
        customManufacturer: String? = nil,
        referenceURL: String? = nil,
        referenceTableFilmID: String? = nil
    ) {
        self.displayNameOverride = displayNameOverride
        self.tags = tags
        self.notes = notes
        self.customSourceType = customSourceType
        self.customManufacturer = customManufacturer
        self.referenceURL = referenceURL
        self.referenceTableFilmID = referenceTableFilmID
    }

    private enum CodingKeys: String, CodingKey {
        case displayNameOverride
        case tags
        case notes
        case customSourceType
        case customManufacturer
        case referenceURL
        case referenceTableFilmID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayNameOverride = try container.decodeIfPresent(String.self, forKey: .displayNameOverride)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        self.customSourceType = try container.decodeIfPresent(
            CustomProfileSourceType.self,
            forKey: .customSourceType
        )
        self.customManufacturer = try container.decodeIfPresent(String.self, forKey: .customManufacturer)
        self.referenceURL = try container.decodeIfPresent(String.self, forKey: .referenceURL)
        self.referenceTableFilmID = try container.decodeIfPresent(String.self, forKey: .referenceTableFilmID)
    }
}

public struct ReciprocityProfile: Codable, Equatable {
    public let id: String
    public let name: String
    public let source: ReciprocitySourceProvenance
    public let rules: [ReciprocityRule]
    public let notes: [String]
    public let userMetadata: UserEditableMetadata?
    /// Published manufacturer reference points the user can verify
    /// against. Display-only — the calculation policy evaluator does
    /// not consume this field, so source-evidence rows cannot enter
    /// the calculation as table anchors even when the profile keeps a
    /// manufacturer reference table on display.
    public let sourceEvidence: [ReciprocitySourceEvidenceRow]
    /// PTIMER-163 vocabulary distinguishing the manufacturer's source
    /// data shape (`sourceModel`) from the app's calculation strategy
    /// (`calculationModel`). Optional so older preset entries and
    /// PTIMER-84 custom profiles decode unchanged; `effectiveModelBasis`
    /// returns a conservative inferred value when this field is absent.
    /// The runtime calculation policy does NOT read this field — it
    /// is descriptive catalog metadata, not a calculation discriminator.
    public let modelBasis: ReciprocityProfileModelBasis?
    /// Optional short label for the compact model selectors (PTIMER-159).
    /// When present it is preferred over the heuristic label derived from
    /// authority / calculation; source-named unofficial / community /
    /// custom models (e.g. a future "Ohzart" practical table) should set
    /// it so the segmented control reads the source name rather than a
    /// generic "Unofficial". It is NOT a source title or URL — those stay
    /// in `source` / the Sources section. Optional so every existing
    /// catalog and custom profile decodes unchanged (Fomapan/Portra keep
    /// their derived labels).
    public let selectorLabel: String?

    public init(
        id: String,
        name: String,
        source: ReciprocitySourceProvenance,
        rules: [ReciprocityRule],
        notes: [String] = [],
        userMetadata: UserEditableMetadata? = nil,
        sourceEvidence: [ReciprocitySourceEvidenceRow] = [],
        modelBasis: ReciprocityProfileModelBasis? = nil,
        selectorLabel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.rules = rules
        self.notes = notes
        self.userMetadata = userMetadata
        self.sourceEvidence = sourceEvidence
        self.modelBasis = modelBasis
        self.selectorLabel = selectorLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case rules
        case notes
        case userMetadata
        case sourceEvidence
        case modelBasis
        case selectorLabel
    }

    public init(from decoder: Decoder) throws {
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
        self.modelBasis = try container.decodeIfPresent(
            ReciprocityProfileModelBasis.self,
            forKey: .modelBasis
        )
        self.selectorLabel = try container.decodeIfPresent(String.self, forKey: .selectorLabel)
    }
}

/// Display-only source-evidence row carried by a `ReciprocityProfile`.
///
/// Carries a manufacturer-published reference point that the presenter
/// renders so users can verify formula-based predictions against the
/// published data. The calculation policy never consumes these rows,
/// so source evidence cannot enter the calculation as a table anchor.
public struct ReciprocitySourceEvidenceRow: Codable, Equatable {
    public let meteredExposure: MeteredExposureSelector
    public let adjustments: [ReciprocityAdjustment]
    public let notes: [String]
    /// `true` for rows preserved as published reference only — the
    /// renderer omits the row from formula-graph fitting markers and
    /// prefixes it with `*` in the Source reference block so the user
    /// can tell it is not used as a calculation anchor. Used by ADOX
    /// CMS 20 II for its 1/1000 s +1/2 stop guidance row, which is
    /// preserved as published evidence but does not participate in
    /// the formula fit (the calculation path stays no-correction
    /// across the entire sub-1 s band).
    public let isSourceEvidenceOnly: Bool

    public init(
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

    public init(from decoder: Decoder) throws {
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
    /// no-source-range formula profiles (HP5 Plus etc.).
    public var isConvertedFormulaProfile: Bool {
        let hasFormulaRule = rules.contains { rule in
            if case .formula = rule { return true }
            return false
        }
        return hasFormulaRule
            && !sourceEvidence.isEmpty
            && source.authority == .official
            && (source.kind == .manufacturerPublished || source.kind == .manufacturerArchive)
    }

    /// `true` when the profile evaluates via the log-log table model
    /// (PTIMER-159).
    public var usesTableInterpolation: Bool {
        rules.contains { rule in
            if case .tableInterpolation = rule { return true }
            return false
        }
    }

    /// `true` for profiles that carry a published source-range boundary
    /// they can exceed — converted formula profiles and table profiles.
    /// Presentation reads "Beyond source range" for inputs past the
    /// boundary on these profiles (and never on no-source-range profiles).
    public var presentsBeyondSourceRange: Bool {
        isConvertedFormulaProfile || usesTableInterpolation
    }

    /// PTIMER-163 vocabulary view of the profile. Returns the
    /// explicitly declared `modelBasis` when the catalog entry sets
    /// one; otherwise infers a conservative basis from the rules and
    /// `sourceEvidence` so older entries (and PTIMER-84 custom
    /// profiles) behave as if the basis had always been present.
    /// Descriptive only — the calculation policy evaluator does not
    /// branch on this value.
    public var effectiveModelBasis: ReciprocityProfileModelBasis {
        modelBasis ?? inferredModelBasis
    }

    private var inferredModelBasis: ReciprocityProfileModelBasis {
        let hasFormulaRule = rules.contains { rule in
            if case .formula = rule { return true }
            return false
        }
        let hasLimitedGuidanceRule = rules.contains { rule in
            if case .limitedGuidance = rule { return true }
            return false
        }
        let hasTableInterpolationRule = rules.contains { rule in
            if case .tableInterpolation = rule { return true }
            return false
        }

        let calculationModel: ReciprocityCalculationModel
        if hasTableInterpolationRule {
            calculationModel = .tableLogLogInterpolation
        } else if hasFormulaRule {
            calculationModel = .guardedFormula
        } else if hasLimitedGuidanceRule {
            calculationModel = .limitedGuidance
        } else {
            calculationModel = .unsupported
        }

        let sourceModel: ReciprocitySourceModel
        switch source.kind {
        case .userDefined:
            sourceModel = .userDefined
        case .thirdPartyPublication:
            sourceModel = .practicalCommunityGuidance
        case .manufacturerPublished, .manufacturerArchive:
            if hasTableInterpolationRule {
                // A table-interpolation rule is, by construction, a
                // manufacturer published table.
                sourceModel = .manufacturerTable
            } else if hasFormulaRule {
                // A formula rule paired with manufacturer reference
                // rows is a table-origin source converted to a
                // derived guarded formula; a bare formula rule is a
                // manufacturer-published formula (Ilford-style).
                sourceModel = sourceEvidence.isEmpty
                    ? .manufacturerFormula
                    : .manufacturerTable
            } else if hasLimitedGuidanceRule {
                sourceModel = .manufacturerLimitedGuidance
            } else {
                sourceModel = .unknown
            }
        case .unknown:
            sourceModel = .unknown
        }

        return ReciprocityProfileModelBasis(
            sourceModel: sourceModel,
            calculationModel: calculationModel
        )
    }
}

/// How the manufacturer / data source actually publishes reciprocity
/// guidance for the film stock. PTIMER-163 introduced this enum so the
/// catalog can preserve the source data shape (formula / table / range
/// / limited guidance) independently of the calculation strategy the
/// app uses for that profile (`ReciprocityCalculationModel`).
///
/// Display / catalog vocabulary only — the calculation policy
/// evaluator never reads this value. Custom (`userDefined`) and
/// older catalog entries decode unchanged because the field is
/// optional on `ReciprocityProfile`.
public enum ReciprocitySourceModel: String, Codable, Equatable, CaseIterable {
    /// Source publishes a closed-form reciprocity formula (e.g.
    /// Ilford / Harman exponent rule).
    case manufacturerFormula
    /// Source publishes a discrete reciprocity correction table —
    /// metered/corrected anchor rows the app may convert to a
    /// derived formula for calculation (e.g. Kodak Tri-X 400,
    /// Fomapan 100 Classic).
    case manufacturerTable
    /// Source combines a published table with a published correction
    /// GRAPH the anchors were sampled from (e.g. Kodak Tri-X 400's
    /// E-31/F-4017 graph + table). Distinct from `manufacturerTable`
    /// so Details can say "Manufacturer graph/table" for the
    /// graph-extended anchor set and the app-derived formula fitted
    /// to it, while the published-rows-only model keeps reading
    /// "Manufacturer table" (PTIMER-168 follow-up). Display / catalog
    /// vocabulary only, like every case in this enum.
    case manufacturerGraphTable
    /// Source publishes a corrected value as a range (e.g. Rollei
    /// RETRO 80S's "1 to 2 sec" row).
    case manufacturerRangeGuidance
    /// Source publishes only qualitative guidance — no quantified
    /// corrected exposure (e.g. Kodak Portra / Ektar / Ektachrome).
    case manufacturerLimitedGuidance
    /// Practical / community guidance — explicitly NOT manufacturer
    /// authority (paired with unofficial / third-party provenance).
    case practicalCommunityGuidance
    /// User-defined / custom profile authored through the PTIMER-84
    /// custom formula editor.
    case userDefined
    /// Source shape is not declared. Reserved fallback so a future
    /// entry can decode without committing to a more specific value.
    case unknown
}

/// How the app calculates a corrected exposure for the profile,
/// distinct from the source model (`ReciprocitySourceModel`).
///
/// The calculation policy still reads `ReciprocityRule` to evaluate;
/// this enum is catalog vocabulary that lets the entry say "source
/// published a table, app uses a guarded formula" without re-deriving
/// the answer from rule shape.
public enum ReciprocityCalculationModel: String, Codable, Equatable, CaseIterable {
    /// PTIMER-160 guarded reciprocity formula
    /// (`ReciprocityFormula`).
    case guardedFormula
    /// Quantified prediction is intentionally unavailable above the
    /// no-correction threshold (the profile carries a
    /// limited-guidance rule).
    case limitedGuidance
    /// Calculation is intentionally unsupported above the
    /// no-correction threshold — neither a quantified prediction nor
    /// limited guidance applies.
    case unsupported
    /// Reserved placeholder for a future discrete table-lookup
    /// calculation strategy. PTIMER-163 did NOT implement it; the
    /// launch catalog loader still rejects this value. Distinct from
    /// `.tableLogLogInterpolation` below, which IS implemented.
    case tableLookup
    /// PTIMER-159: official manufacturer table converted to a corrected
    /// exposure by piecewise log-log interpolation between published
    /// anchors (e.g. Fomapan 100's 1/10/100 sec rows). The user-facing
    /// label is "Log-log table interpolation" — never a bare "lookup".
    case tableLogLogInterpolation
}

/// Catalog-level vocabulary describing how reciprocity is sourced and
/// calculated for a profile. PTIMER-163 introduced this struct so the
/// catalog can distinguish the source data shape from the calculation
/// strategy without changing calculation behavior.
public struct ReciprocityProfileModelBasis: Codable, Equatable {
    public let sourceModel: ReciprocitySourceModel
    public let calculationModel: ReciprocityCalculationModel

    public init(
        sourceModel: ReciprocitySourceModel,
        calculationModel: ReciprocityCalculationModel
    ) {
        self.sourceModel = sourceModel
        self.calculationModel = calculationModel
    }
}

public struct ReciprocitySourceProvenance: Codable, Equatable {
    public let kind: ReciprocitySourceKind
    public let authority: ReciprocityAuthority
    public let confidence: ReciprocityConfidence
    public let publisher: String
    public let title: String?
    public let citation: String?
    public let sourceVersion: String?

    public init(
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

public enum ReciprocitySourceKind: String, Codable, Equatable {
    case manufacturerPublished
    case manufacturerArchive
    case thirdPartyPublication
    case userDefined
    case unknown
}

public enum ReciprocityAuthority: String, Codable, Equatable {
    case official
    case unofficial
    case userDefined
    case unknown
}

public enum ReciprocityConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
    case unknown
}

/// Reciprocity rule kinds a profile can declare. PTIMER-160's shared
/// guarded formula model lives inside the `.formula` case via
/// `FormulaReciprocityRule.formula` (a `ReciprocityFormula` value
/// that carries its own `formulaFamily` discriminator).
///
/// `FormulaFamily` is the FORMULA RULE's internal discriminator and
/// does not narrow `ReciprocityProfile` to formula-only. If a future
/// ticket re-introduces a table-interpolation profile, it can extend
/// this enum with a new rule case and the profile validator + decoder
/// alongside; PTIMER-160's scope is limited to defining the formula
/// model and does not close that door.
public enum ReciprocityRule: Codable, Equatable {
    case threshold(ThresholdReciprocityRule)
    case formula(FormulaReciprocityRule)
    case limitedGuidance(LimitedGuidanceReciprocityRule)
    case tableInterpolation(TableInterpolationReciprocityRule)

    public var kind: ReciprocityRuleKind {
        switch self {
        case .threshold:
            return .threshold
        case .formula:
            return .formula
        case .limitedGuidance:
            return .limitedGuidance
        case .tableInterpolation:
            return .tableInterpolation
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case threshold
        case formula
        case limitedGuidance
        case tableInterpolation
    }

    public init(from decoder: Decoder) throws {
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
        case .tableInterpolation:
            self = .tableInterpolation(
                try container.decode(TableInterpolationReciprocityRule.self, forKey: .tableInterpolation)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .threshold(rule):
            try container.encode(rule, forKey: .threshold)
        case let .formula(rule):
            try container.encode(rule, forKey: .formula)
        case let .limitedGuidance(rule):
            try container.encode(rule, forKey: .limitedGuidance)
        case let .tableInterpolation(rule):
            try container.encode(rule, forKey: .tableInterpolation)
        }
    }
}

public enum ReciprocityRuleKind: String, Codable, Equatable {
    case threshold
    case formula
    case limitedGuidance
    case tableInterpolation
}

public struct ThresholdReciprocityRule: Codable, Equatable {
    public let noCorrectionRange: ReciprocityTimeRange
    public let adjustments: [ReciprocityAdjustment]
    public let notes: [String]

    public init(
        noCorrectionRange: ReciprocityTimeRange,
        adjustments: [ReciprocityAdjustment] = [],
        notes: [String] = []
    ) {
        self.noCorrectionRange = noCorrectionRange
        self.adjustments = adjustments
        self.notes = notes
    }
}

public struct FormulaReciprocityRule: Codable, Equatable {
    public let formula: ReciprocityFormula
    public let additionalAdjustments: [ReciprocityAdjustment]
    public let notes: [String]

    public init(
        formula: ReciprocityFormula,
        additionalAdjustments: [ReciprocityAdjustment] = [],
        notes: [String] = []
    ) {
        self.formula = formula
        self.additionalAdjustments = additionalAdjustments
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case formula
        case additionalAdjustments
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formula = try container.decode(ReciprocityFormula.self, forKey: .formula)
        self.additionalAdjustments = try container.decodeIfPresent(
            [ReciprocityAdjustment].self,
            forKey: .additionalAdjustments
        ) ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

/// Limited-guidance rule used by official-source profiles that publish
/// only qualitative guidance past a no-correction threshold (e.g.
/// Kodak Portra / Ektar / Ektachrome). The rule never yields a
/// quantified corrected exposure; presentation surfaces the result as
/// "No quantified prediction".
public struct LimitedGuidanceReciprocityRule: Codable, Equatable {
    public let appliesWhenMetered: ReciprocityTimeRange?
    public let adjustments: [ReciprocityAdjustment]
    public let notes: [String]

    public init(
        appliesWhenMetered: ReciprocityTimeRange? = nil,
        adjustments: [ReciprocityAdjustment] = [],
        notes: [String] = []
    ) {
        self.appliesWhenMetered = appliesWhenMetered
        self.adjustments = adjustments
        self.notes = notes
    }
}

/// One published anchor in a manufacturer reciprocity table: a metered
/// exposure mapped to its published corrected exposure (PTIMER-159).
public struct TableAnchor: Codable, Equatable {
    public let meteredSeconds: Double
    public let correctedSeconds: Double

    public init(
        meteredSeconds: Double,
        correctedSeconds: Double
    ) {
        self.meteredSeconds = meteredSeconds
        self.correctedSeconds = correctedSeconds
    }
}

/// PTIMER-159 calculation rule: convert a manufacturer reciprocity
/// TABLE into a corrected exposure by piecewise log-log interpolation
/// between published `anchors` (e.g. Fomapan 100's 1s→2s, 10s→80s,
/// 100s→1600s). Distinct from `FormulaReciprocityRule`, which evaluates
/// a closed-form curve. The evaluator (`evaluate(meteredExposureSeconds:)`)
/// lives in `TableInterpolationModel.swift`.
///
/// - `noCorrectionThroughSeconds`: at or below this metered exposure the
///   rule returns `Tc = Tm` (identity), matching the table's lower band.
/// - `anchors`: ascending, published metered→corrected points. Interpolation
///   passes through them exactly.
/// - `sourceRangeThroughSeconds`: the published table's upper bound (the
///   last anchor's metered value). Inputs above it still compute a value by
///   extrapolating the last log-log segment, classified beyond source range.
public struct TableInterpolationReciprocityRule: Codable, Equatable {
    public let anchors: [TableAnchor]
    public let additionalAdjustments: [ReciprocityAdjustment]
    public let notes: [String]
    public let noCorrectionThroughSeconds: Double
    public let sourceRangeThroughSeconds: Double

    public init(
        anchors: [TableAnchor],
        additionalAdjustments: [ReciprocityAdjustment] = [],
        notes: [String] = [],
        noCorrectionThroughSeconds: Double,
        sourceRangeThroughSeconds: Double
    ) {
        self.anchors = anchors
        self.additionalAdjustments = additionalAdjustments
        self.notes = notes
        self.noCorrectionThroughSeconds = noCorrectionThroughSeconds
        self.sourceRangeThroughSeconds = sourceRangeThroughSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case anchors
        case additionalAdjustments
        case notes
        case noCorrectionThroughSeconds
        case sourceRangeThroughSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.anchors = try container.decode([TableAnchor].self, forKey: .anchors)
        self.additionalAdjustments = try container.decodeIfPresent(
            [ReciprocityAdjustment].self,
            forKey: .additionalAdjustments
        ) ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        self.noCorrectionThroughSeconds = try container.decode(
            Double.self,
            forKey: .noCorrectionThroughSeconds
        )
        self.sourceRangeThroughSeconds = try container.decode(
            Double.self,
            forKey: .sourceRangeThroughSeconds
        )
    }
}

public struct ReciprocityTimeRange: Codable, Equatable {
    // Validation-facing semantics are inclusive at both ends.
    // A missing maximum means the range continues upward from minimumSeconds.
    public let minimumSeconds: Double
    public let maximumSeconds: Double?

    public init(minimumSeconds: Double, maximumSeconds: Double? = nil) {
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
    }
}

/// Mathematical family a reciprocity formula belongs to.
///
/// PTIMER-160 ships only `.modifiedSchwarzschild`; PTIMER-162 will
/// add the next family. Downstream consumers MUST switch on this
/// enum exhaustively (no `default` branch) so adding a future case
/// surfaces as a compile error rather than a silent fall-through.
public enum FormulaFamily: String, Codable, Equatable, CaseIterable {
    case modifiedSchwarzschild
}

/// Shared guarded reciprocity formula model.
///
/// Display form (Modified Schwarzschild family):
///
/// ```
/// Tc = a × (Tm / Tref)^p + b
/// ```
///
/// Domain mapping:
/// - `a` = `coefficientSeconds` (scale coefficient)
/// - `Tref` = `referenceMeteredTimeSeconds`
/// - `p` = `exponent`
/// - `b` = `offsetSeconds`
///
/// Guards owned by the formula:
/// - `Tm <= noCorrectionThroughSeconds` → `Tc = Tm` (identity).
/// - `Tm >  noCorrectionThroughSeconds` → formula evaluation.
/// - `sourceRangeThroughSeconds` is the source / fitting confidence
///   boundary. It is **not** a calculation stop — the formula keeps
///   producing values past it; the presentation layer classifies
///   them as beyond the source / fitting range.
///
/// Shared contract referenced by PTIMER-84 (custom profile
/// lifecycle), PTIMER-159 (Details verification UI), PTIMER-161
/// (table-converted formula refit), and PTIMER-162 (next formula
/// family). Custom and shipped formula profiles both use this struct
/// so downstream surfaces only have one shape to consume.
public struct ReciprocityFormula: Codable, Equatable {
    /// Required. See `FormulaFamily` for current scope. The custom
    /// decoder rejects missing or unknown values so a future family
    /// cannot silently fall through.
    public let formulaFamily: FormulaFamily
    /// Scale coefficient `a` (in seconds). At `Tm = Tref` the power
    /// term equals `a`, so the corrected exposure is `a + b` — the
    /// offset is always added on top. Default `1` is the neutral
    /// coefficient; `a` is NOT the corrected time when `b ≠ 0`.
    public let coefficientSeconds: Double
    /// Reference metered time `Tref` used to scale the input. Default
    /// `1s` reduces `Tc = a × (Tm / Tref)^p + b` to the legacy power
    /// form `Tc = a × Tm^p + b`.
    public let referenceMeteredTimeSeconds: Double
    /// Exponent `p` driving curve steepness. Required.
    public let exponent: Double
    /// Constant offset `b` (in seconds) added after the power term.
    /// Default `0` (no offset).
    public let offsetSeconds: Double
    /// Upper bound (inclusive) of the no-correction band. At or
    /// below this metered exposure the formula returns `Tc = Tm`.
    public let noCorrectionThroughSeconds: Double
    /// Upper bound (inclusive) of the manufacturer-supported source
    /// / fitting range. Inputs strictly above this value still
    /// compute a corrected exposure; the presentation layer
    /// classifies them as beyond source range. `nil` means the
    /// formula carries no published source boundary and every
    /// formula-domain input stays classified as within the stated
    /// range.
    public let sourceRangeThroughSeconds: Double?

    /// `formulaFamily` defaults to `.modifiedSchwarzschild` for
    /// Swift-side construction convenience only (test fixtures,
    /// in-code factories). The serialized form has no such default —
    /// `init(from:)` `decode`s the field so a missing or unknown
    /// value throws.
    public init(
        formulaFamily: FormulaFamily = .modifiedSchwarzschild,
        coefficientSeconds: Double = 1,
        referenceMeteredTimeSeconds: Double = 1,
        exponent: Double,
        offsetSeconds: Double = 0,
        noCorrectionThroughSeconds: Double,
        sourceRangeThroughSeconds: Double? = nil
    ) {
        self.formulaFamily = formulaFamily
        self.coefficientSeconds = coefficientSeconds
        self.referenceMeteredTimeSeconds = referenceMeteredTimeSeconds
        self.exponent = exponent
        self.offsetSeconds = offsetSeconds
        self.noCorrectionThroughSeconds = noCorrectionThroughSeconds
        self.sourceRangeThroughSeconds = sourceRangeThroughSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case formulaFamily
        case coefficientSeconds
        case referenceMeteredTimeSeconds
        case exponent
        case offsetSeconds
        case noCorrectionThroughSeconds
        case sourceRangeThroughSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `formulaFamily` is required in the on-disk schema. Decoding
        // intentionally throws when missing or unknown so an unknown
        // future family value cannot be silently demoted to
        // `.modifiedSchwarzschild`. PTIMER-162 will add a new case;
        // every shipped JSON entry is migrated in lock-step.
        self.formulaFamily = try container.decode(FormulaFamily.self, forKey: .formulaFamily)
        self.coefficientSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .coefficientSeconds
        ) ?? 1
        self.referenceMeteredTimeSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .referenceMeteredTimeSeconds
        ) ?? 1
        self.exponent = try container.decode(Double.self, forKey: .exponent)
        self.offsetSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .offsetSeconds
        ) ?? 0
        self.noCorrectionThroughSeconds = try container.decode(
            Double.self,
            forKey: .noCorrectionThroughSeconds
        )
        self.sourceRangeThroughSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .sourceRangeThroughSeconds
        )
    }
}

extension ReciprocityFormula {
    /// Outcome of a single formula evaluation.
    public enum EvaluationResult: Equatable {
        /// `Tm` sat inside the no-correction band. `Tc = Tm`.
        case noCorrection
        /// Formula produced a finite, positive corrected exposure
        /// inside the source / fitting range.
        case withinSourceRange(correctedExposureSeconds: Double)
        /// Formula produced a finite, positive corrected exposure
        /// beyond `sourceRangeThroughSeconds`. Same arithmetic as
        /// `withinSourceRange`; the case difference exists so the
        /// confidence presentation can flag it without re-deriving
        /// the boundary.
        case beyondSourceRange(correctedExposureSeconds: Double)
        /// Metered exposure input is not a positive finite number.
        /// PTIMER-84 user-defined inputs flow through here; the
        /// policy evaluator surfaces it as an unsupported result so
        /// a bad input does not masquerade as "no correction
        /// needed".
        case invalidInput
        /// Formula parameters violate the safe-formula contract
        /// (non-finite, non-positive coefficient or reference,
        /// negative no-correction boundary, source range below the
        /// no-correction boundary). Distinct from `invalidInput`
        /// because the formula itself is malformed — the policy
        /// must surface this as an unsupported / data-error result,
        /// never as a silent no-correction handoff. Critical for
        /// PTIMER-84 custom profile validation feedback.
        case invalidFormula
        /// Formula output is non-finite or non-positive (e.g. NaN
        /// from a pathological combination of valid-looking
        /// parameters). The policy surfaces this as unsupported.
        case formulaOutputUnusable
        /// Formula output is finite but would shorten the exposure
        /// (`Tc < Tm`). A reciprocity correction must never make
        /// the adjusted shutter shorter; the policy hands off to
        /// no-correction so the user gets `Tc = Tm` rather than a
        /// dangerous shortened value. This is a runtime safety net,
        /// NOT a parameter validation error.
        case unsafeShorteningFormula
    }

    /// `true` when every formula parameter satisfies the safe-
    /// formula contract:
    ///
    /// - `coefficientSeconds`, `referenceMeteredTimeSeconds`,
    ///   `exponent`, `offsetSeconds`, `noCorrectionThroughSeconds`
    ///   are finite.
    /// - `coefficientSeconds > 0` and
    ///   `referenceMeteredTimeSeconds > 0` so the power term stays
    ///   defined for every positive metered exposure.
    /// - `noCorrectionThroughSeconds >= 0`.
    /// - `sourceRangeThroughSeconds`, when set, is finite and
    ///   strictly greater than `noCorrectionThroughSeconds` so the
    ///   formula has a non-empty source range above the
    ///   no-correction band.
    public var hasValidParameters: Bool {
        guard coefficientSeconds.isFinite, coefficientSeconds > 0 else { return false }
        guard referenceMeteredTimeSeconds.isFinite, referenceMeteredTimeSeconds > 0 else { return false }
        guard exponent.isFinite else { return false }
        guard offsetSeconds.isFinite else { return false }
        guard noCorrectionThroughSeconds.isFinite, noCorrectionThroughSeconds >= 0 else { return false }
        if let upper = sourceRangeThroughSeconds {
            guard upper.isFinite, upper > noCorrectionThroughSeconds else { return false }
        }
        return true
    }

    /// Single shared evaluator. Encapsulates the guarded math so the
    /// runtime evaluator, the graph sampler, and the verification
    /// presenters all see identical numeric output.
    ///
    /// - `Tm <= noCorrectionThroughSeconds` → `noCorrection` (identity
    ///   handled by the caller; `meteredExposureSeconds` is the
    ///   corrected exposure).
    /// - `Tm > noCorrectionThroughSeconds` → family-specific
    ///   arithmetic. Modified Schwarzschild produces
    ///   `Tc = a × (Tm / Tref)^p + b`.
    /// - The unsafe-formula safety net rejects any output where
    ///   `Tc < Tm` so a reciprocity correction can never shorten the
    ///   adjusted shutter inside the formula range.
    ///
    /// The `switch` on `formulaFamily` is intentionally exhaustive
    /// with no `default` branch: PTIMER-162 will add a new family
    /// `case` and the compiler must surface the omission here rather
    /// than silently falling back to Modified Schwarzschild.
    public func evaluate(meteredExposureSeconds: Double) -> EvaluationResult {
        // Bad input flows to a distinct case so the policy can
        // surface it as unsupported instead of silently returning
        // "no correction needed" — important for PTIMER-84 custom
        // formulas where a user input mistake must not hide as a
        // benign result.
        guard meteredExposureSeconds.isFinite,
              meteredExposureSeconds > 0 else {
            return .invalidInput
        }
        // Bad formula parameters surface as `.invalidFormula` so
        // PTIMER-84's editor / catalog validation can distinguish a
        // malformed formula from a runtime safety handoff.
        guard hasValidParameters else {
            return .invalidFormula
        }
        // Strict, inclusive boundary. The formula evaluator must NOT
        // apply the nominal-shutter tolerance: formula films such as
        // Acros II encode an exact-epsilon boundary
        // (`noCorrectionThroughSeconds = 119.999999`) so that exactly
        // 120 s starts the corrected range, and the guard contract
        // requires any input strictly above the threshold to leave the
        // no-correction band. The tolerance lives only in the table
        // evaluator (see `ReciprocityNoCorrectionBoundary`).
        if meteredExposureSeconds <= noCorrectionThroughSeconds {
            return .noCorrection
        }

        let corrected: Double
        switch formulaFamily {
        case .modifiedSchwarzschild:
            let scaled = meteredExposureSeconds / referenceMeteredTimeSeconds
            let powered = pow(scaled, exponent)
            corrected = coefficientSeconds * powered + offsetSeconds
        }

        guard corrected.isFinite, corrected > 0 else {
            return .formulaOutputUnusable
        }
        // Safety net: a reciprocity correction must never shorten
        // the adjusted shutter. This is distinct from
        // `.invalidFormula` — the parameters are individually valid,
        // but their combination would produce `Tc < Tm` at this
        // input. The policy hands off to no-correction so the user
        // gets `Tc = Tm` rather than a dangerous shortened value.
        // Tolerance matches the legacy clamp.
        guard corrected >= meteredExposureSeconds - 1e-6 else {
            return .unsafeShorteningFormula
        }
        if let upper = sourceRangeThroughSeconds,
           meteredExposureSeconds > upper {
            return .beyondSourceRange(correctedExposureSeconds: corrected)
        }
        return .withinSourceRange(correctedExposureSeconds: corrected)
    }
}

public enum MeteredExposureSelector: Codable, Equatable {
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SelectorKind.self, forKey: .kind)

        switch kind {
        case .exactSeconds:
            self = .exactSeconds(try container.decode(Double.self, forKey: .exactSeconds))
        case .range:
            self = .range(try container.decode(ReciprocityTimeRange.self, forKey: .range))
        }
    }

    public func encode(to encoder: Encoder) throws {
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

public enum ReciprocityAdjustment: Codable, Equatable {
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public enum ExposureAdjustment: Codable, Equatable {
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public struct CorrectedTimeMapping: Codable, Equatable {
    public let meteredSeconds: Double?
    public let correctedSeconds: Double
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
    public let isApproximate: Bool

    public init(
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meteredSeconds = try container.decodeIfPresent(Double.self, forKey: .meteredSeconds)
        correctedSeconds = try container.decode(Double.self, forKey: .correctedSeconds)
        // `isApproximate` is omitted from existing catalog fixtures
        // so missing keys decode to `false` (source-published).
        isApproximate = try container.decodeIfPresent(Bool.self, forKey: .isApproximate) ?? false
    }
}

public struct StopDeltaAdjustment: Codable, Equatable {
    public let stopDelta: Double

    public init(stopDelta: Double) {
        self.stopDelta = stopDelta
    }
}

public struct MultiplierAdjustment: Codable, Equatable {
    public let factor: Double

    public init(factor: Double) {
        self.factor = factor
    }
}

public struct ColorFilterRecommendation: Codable, Equatable {
    public let filterName: String
    public let note: String?

    public init(filterName: String, note: String? = nil) {
        self.filterName = filterName
        self.note = note
    }
}

public struct DevelopmentAdjustment: Codable, Equatable {
    public let instruction: String
    public let note: String?

    public init(instruction: String, note: String? = nil) {
        self.instruction = instruction
        self.note = note
    }
}

public struct ReciprocityWarning: Codable, Equatable {
    public let severity: ReciprocityWarningSeverity
    public let message: String

    public init(severity: ReciprocityWarningSeverity, message: String) {
        self.severity = severity
        self.message = message
    }
}

public enum ReciprocityWarningSeverity: String, Codable, Equatable {
    case caution
    case notRecommended
}

public struct ReciprocityNote: Codable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

// Unofficial practical profiles defined separately from the launch preset catalog.
// The launch catalog enforces exactly one official manufacturer profile per film identity.
// Profiles in this registry are lower-authority supplementary data for future UI exposure.
public enum UnofficialPracticalProfiles {

    // Unofficial practical approximation profile for Kodak Portra 400.
    //
    // This profile is separate from the official primary profile
    // "kodak-portra-official-threshold" in the launch preset catalog and must never
    // replace or shadow it.
    //
    public static func profile(forFilmID filmID: String) -> ReciprocityProfile? {
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
    public static let kodakPortra400UnofficialPractical = ReciprocityProfile(
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
                    formulaFamily: .modifiedSchwarzschild,
                    exponent: 1.34,
                    // Open-boundary semantic: the unofficial 1 s
                    // long-exposure threshold reads as "no correction
                    // strictly below 1 s; Tm = 1 s itself activates
                    // the formula". The `.999_999` epsilon encodes
                    // that source-defined open boundary.
                    noCorrectionThroughSeconds: 0.999_999
                )
            )),
        ],
        notes: [
            "Unofficial practical approximation. Not a Kodak-published profile.",
            "Formula: Tc = Tm^1.34. Source pending verification.",
        ]
    )
}
