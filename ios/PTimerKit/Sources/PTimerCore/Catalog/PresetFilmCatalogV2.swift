// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum LaunchPresetFilmCatalogV2 {
    public static let resourceName = "LaunchPresetFilmCatalog.v2"
    public static let resourceExtension = "json"

    public static let films: [FilmIdentity] = {
        do {
            return try LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        } catch {
            assertionFailure("Failed to load bundled launch preset film catalog v2: \(error)")
            return []
        }
    }()

    public static func defaultResourceBundles() -> [Bundle] {
        [.module]
    }
}

public struct LaunchPresetFilmCatalogV2Loader {
    public init() {}
    private let decoder = JSONDecoder()

    public func loadBundledCatalog(
        resourceName: String = LaunchPresetFilmCatalogV2.resourceName,
        resourceExtension: String = LaunchPresetFilmCatalogV2.resourceExtension,
        bundleCandidates: [Bundle] = LaunchPresetFilmCatalogV2.defaultResourceBundles()
    ) throws -> [FilmIdentity] {
        for bundle in bundleCandidates {
            guard let resourceURL = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
                continue
            }

            return try loadCatalog(from: resourceURL)
        }

        throw LaunchPresetFilmCatalogV2LoaderError.missingBundledResource(
            name: resourceName,
            fileExtension: resourceExtension
        )
    }

    public func loadCatalog(from url: URL) throws -> [FilmIdentity] {
        do {
            let data = try Data(contentsOf: url)
            return try loadCatalog(from: data)
        } catch let error as LaunchPresetFilmCatalogV2LoaderError {
            throw error
        } catch {
            throw LaunchPresetFilmCatalogV2LoaderError.unreadableResource(error.localizedDescription)
        }
    }

    public func loadCatalog(from data: Data) throws -> [FilmIdentity] {
        let document: CatalogV2Document

        do {
            document = try decoder.decode(CatalogV2Document.self, from: data)
        } catch let decodingError as DecodingError {
            throw LaunchPresetFilmCatalogV2LoaderError.malformedResource(
                Self.describe(decodingError: decodingError)
            )
        } catch {
            throw LaunchPresetFilmCatalogV2LoaderError.malformedResource(error.localizedDescription)
        }

        try validateLaunchCatalog(document)
        return document.films.map { adaptFilm($0, sources: document.sources) }
    }

    private func validateLaunchCatalog(_ document: CatalogV2Document) throws {
        guard document.schema == "ptimer.catalog.v2", document.schemaVersion == 2 else {
            throw LaunchPresetFilmCatalogV2LoaderError.invalidSchema(
                schema: document.schema,
                schemaVersion: document.schemaVersion
            )
        }

        guard !document.films.isEmpty else {
            throw LaunchPresetFilmCatalogV2LoaderError.emptyCatalog
        }

        var sourceIDs: Set<String> = []
        for sourceID in document.sources.keys {
            let trimmedID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw LaunchPresetFilmCatalogV2LoaderError.invalidSourceIdentifier
            }
            guard sourceIDs.insert(trimmedID).inserted else {
                throw LaunchPresetFilmCatalogV2LoaderError.duplicateSourceIdentifier(trimmedID)
            }
        }

        var filmIDs: Set<String> = []
        var profileIDs: Set<String> = []

        for film in document.films {
            let filmID = film.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filmID.isEmpty else {
                throw LaunchPresetFilmCatalogV2LoaderError.invalidFilmIdentifier
            }
            guard filmIDs.insert(filmID).inserted else {
                throw LaunchPresetFilmCatalogV2LoaderError.duplicateFilmIdentifier(filmID)
            }
            guard film.iso > 0 else {
                throw LaunchPresetFilmCatalogV2LoaderError.invalidFilmISO(filmID: filmID, iso: film.iso)
            }
            guard !film.canonicalStockName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LaunchPresetFilmCatalogV2LoaderError.invalidCanonicalStockName(filmID)
            }

            if film.kind == .preset {
                let primaryCount = film.profiles.filter { $0.role == .primary }.count
                guard primaryCount == 1 else {
                    throw LaunchPresetFilmCatalogV2LoaderError.invalidPrimaryProfileCount(
                        filmID: filmID,
                        count: primaryCount
                    )
                }
            }

            for profile in film.profiles {
                let profileID = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !profileID.isEmpty else {
                    throw LaunchPresetFilmCatalogV2LoaderError.invalidProfileIdentifier(filmID: filmID)
                }
                guard profileIDs.insert(profileID).inserted else {
                    throw LaunchPresetFilmCatalogV2LoaderError.duplicateProfileIdentifier(profileID)
                }
                guard let sourceEntry = document.sources[profile.sourceId],
                      sourceIDs.contains(profile.sourceId) else {
                    throw LaunchPresetFilmCatalogV2LoaderError.unresolvedSourceReference(
                        filmID: filmID,
                        profileID: profileID,
                        sourceID: profile.sourceId
                    )
                }
                try validateCalculationShape(profile, source: sourceEntry, filmID: filmID)
            }
        }
    }

    private func validateCalculationShape(
        _ profile: CatalogV2Profile,
        source: CatalogV2SourceRegistryEntry,
        filmID: String
    ) throws {
        try validateCarrierShape(profile, filmID: filmID)

        switch (profile.model, profile.calculation) {
        case let (.table, .table(calculation)):
            try validateTableCalculation(calculation, profile: profile, filmID: filmID)
        case let (.formula, .formula(calculation)):
            try validateFormulaCalculation(calculation, profile: profile, filmID: filmID)
        case let (.limitedGuidance, .limitedGuidance(calculation)):
            try validateLimitedGuidanceCalculation(calculation, profile: profile, filmID: filmID)
        default:
            throw LaunchPresetFilmCatalogV2LoaderError.invalidRuleShape(
                filmID: filmID,
                profileID: profile.id,
                reason: "calculation block does not match profile model"
            )
        }

        try validatePromotedUnofficialPrimary(profile, source: source, filmID: filmID)
    }

    private func validateCarrierShape(
        _ profile: CatalogV2Profile,
        filmID: String
    ) throws {
        switch profile.model {
        case .table:
            guard profile.referencePoints == nil, profile.referenceRanges == nil else {
                throw invalidShape(
                    filmID: filmID,
                    profileID: profile.id,
                    reason: "table profiles must not carry formula reference carriers"
                )
            }
        case .formula:
            guard profile.evidence == nil else {
                throw invalidShape(
                    filmID: filmID,
                    profileID: profile.id,
                    reason: "formula profiles must not carry table evidence"
                )
            }
        case .limitedGuidance:
            guard profile.evidence == nil,
                  profile.referencePoints == nil,
                  profile.referenceRanges == nil else {
                throw invalidShape(
                    filmID: filmID,
                    profileID: profile.id,
                    reason: "limited-guidance profiles must not carry source-evidence carriers"
                )
            }
        }
    }

    private func validatePromotedUnofficialPrimary(
        _ profile: CatalogV2Profile,
        source: CatalogV2SourceRegistryEntry,
        filmID: String
    ) throws {
        guard profile.role == .primary,
              profile.authority == .community || profile.authority == .unofficial else {
            return
        }

        guard source.authority != .official,
              source.sourceType != .manufacturerPublished,
              source.sourceType != .manufacturerArchive else {
            throw invalidShape(
                filmID: filmID,
                profileID: profile.id,
                reason: "promoted unofficial primary profiles require non-official, non-manufacturer provenance"
            )
        }
        guard source.confidence != .high else {
            throw invalidShape(
                filmID: filmID,
                profileID: profile.id,
                reason: "promoted unofficial primary profiles must not use high-confidence sources"
            )
        }
        guard profile.basis == .practicalCommunityGuidance else {
            throw invalidShape(
                filmID: filmID,
                profileID: profile.id,
                reason: "promoted unofficial primary profiles require practical community guidance basis"
            )
        }
        guard profile.model == .formula else {
            throw invalidShape(
                filmID: filmID,
                profileID: profile.id,
                reason: "promoted unofficial primary profiles require formula calculation"
            )
        }
        guard !(profile.referencePoints ?? []).isEmpty else {
            throw invalidShape(
                filmID: filmID,
                profileID: profile.id,
                reason: "promoted unofficial primary profiles require at least one reference point"
            )
        }
    }

    private func validateTableCalculation(
        _ calculation: CatalogV2TableCalculation,
        profile: CatalogV2Profile,
        filmID: String
    ) throws {
        guard !calculation.anchors.isEmpty else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table profiles require at least one anchor")
        }
        guard calculation.noCorrectionThroughSeconds.isFinite,
              calculation.noCorrectionThroughSeconds >= 0 else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table no-correction boundary must be finite and non-negative")
        }
        guard calculation.sourceRangeThroughSeconds.isFinite,
              calculation.sourceRangeThroughSeconds > calculation.noCorrectionThroughSeconds else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table source range must be finite and above the no-correction boundary")
        }

        var previousMetered: Double?
        var seenMetered: Set<Double> = []
        for anchor in calculation.anchors {
            guard anchor.meteredSeconds.isFinite, anchor.meteredSeconds > 0 else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table anchors require positive finite metered seconds")
            }
            guard anchor.correctedSeconds.isFinite,
                  anchor.correctedSeconds >= anchor.meteredSeconds else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table anchors require corrected seconds greater than or equal to metered seconds")
            }
            if let previousMetered {
                guard anchor.meteredSeconds > previousMetered else {
                    throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table anchors must be strictly ascending by metered seconds")
                }
            }
            guard seenMetered.insert(anchor.meteredSeconds).inserted else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table anchors must not duplicate metered seconds")
            }
            previousMetered = anchor.meteredSeconds
        }

        guard let firstAnchor = calculation.anchors.first,
              calculation.noCorrectionThroughSeconds < firstAnchor.meteredSeconds else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table no-correction boundary must be below the first anchor")
        }
        guard let lastAnchor = calculation.anchors.last,
              calculation.sourceRangeThroughSeconds >= lastAnchor.meteredSeconds else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table source range must cover the last anchor")
        }

        for evidence in profile.evidence ?? [] {
            guard evidence.anchor >= 0, evidence.anchor < calculation.anchors.count else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "table evidence anchor index is out of range")
            }
        }
    }

    private func validateFormulaCalculation(
        _ calculation: CatalogV2FormulaCalculation,
        profile: CatalogV2Profile,
        filmID: String
    ) throws {
        let coefficient = calculation.coefficient ?? 1
        let referenceMeteredSeconds = calculation.referenceMeteredSeconds ?? 1
        let offsetSeconds = calculation.offsetSeconds ?? 0
        guard calculation.exponent.isFinite, calculation.exponent > 0 else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "formula exponent must be positive and finite")
        }
        guard coefficient.isFinite, coefficient > 0 else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "formula coefficient must be positive and finite")
        }
        guard referenceMeteredSeconds.isFinite, referenceMeteredSeconds > 0 else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "formula reference metered seconds must be positive and finite")
        }
        guard offsetSeconds.isFinite,
              calculation.noCorrectionThroughSeconds.isFinite,
              calculation.noCorrectionThroughSeconds >= 0 else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "formula no-correction boundary and offset must be finite")
        }
        if let sourceRange = calculation.sourceRangeThroughSeconds {
            guard sourceRange.isFinite, sourceRange > calculation.noCorrectionThroughSeconds else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "formula source range must be above the no-correction boundary")
            }
        }

        for point in profile.referencePoints ?? [] {
            guard point.meteredSeconds.isFinite, point.meteredSeconds > 0 else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "reference points require positive finite metered seconds")
            }
            if let correctedSeconds = point.correctedSeconds {
                guard correctedSeconds.isFinite, correctedSeconds >= point.meteredSeconds else {
                    throw invalidShape(filmID: filmID, profileID: profile.id, reason: "reference points require corrected seconds greater than or equal to metered seconds")
                }
            }
        }

        try validateReferenceRanges(profile.referenceRanges ?? [], profile: profile, filmID: filmID)
    }

    private func validateLimitedGuidanceCalculation(
        _ calculation: CatalogV2LimitedGuidanceCalculation,
        profile: CatalogV2Profile,
        filmID: String
    ) throws {
        guard calculation.noCorrectionRange.count == 2 else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "limited-guidance noCorrectionRange must contain exactly two values")
        }
        let minimum = calculation.noCorrectionRange[0]
        let maximum = calculation.noCorrectionRange[1]
        guard minimum.isFinite, maximum.isFinite, minimum < maximum else {
            throw invalidShape(filmID: filmID, profileID: profile.id, reason: "limited-guidance noCorrectionRange minimum must be below maximum")
        }

        var previousFromSeconds: Double?
        for guidance in calculation.guidance {
            guard guidance.fromSeconds.isFinite, guidance.fromSeconds >= maximum else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "limited-guidance rows must start at or beyond the no-correction range maximum")
            }
            if let previousFromSeconds {
                guard guidance.fromSeconds >= previousFromSeconds else {
                    throw invalidShape(filmID: filmID, profileID: profile.id, reason: "limited-guidance rows must be sorted")
                }
            }
            previousFromSeconds = guidance.fromSeconds
        }
        try validateReferenceRanges(profile.referenceRanges ?? [], profile: profile, filmID: filmID)
    }

    private func validateReferenceRanges(
        _ ranges: [CatalogV2ReferenceRange],
        profile: CatalogV2Profile,
        filmID: String
    ) throws {
        for range in ranges {
            guard range.fromSeconds.isFinite,
                  range.throughSeconds.isFinite,
                  range.fromSeconds < range.throughSeconds else {
                throw invalidShape(filmID: filmID, profileID: profile.id, reason: "reference ranges require finite fromSeconds below throughSeconds")
            }
        }
    }

    private func invalidShape(
        filmID: String,
        profileID: String,
        reason: String
    ) -> LaunchPresetFilmCatalogV2LoaderError {
        .invalidRuleShape(filmID: filmID, profileID: profileID, reason: reason)
    }

    private func adaptFilm(
        _ film: CatalogV2Film,
        sources: [String: CatalogV2SourceRegistryEntry]
    ) -> FilmIdentity {
        FilmIdentity(
            id: film.id,
            kind: FilmIdentityKind(rawValue: film.kind.rawValue) ?? .unknown,
            canonicalStockName: film.canonicalStockName,
            manufacturer: film.manufacturer,
            brandLabel: film.brandLabel,
            aliases: film.aliases,
            iso: film.iso,
            productionStatus: FilmProductionStatus(rawValue: film.productionStatus.rawValue) ?? .unknown,
            profiles: film.profiles.map { adaptProfile($0, sources: sources) },
            userMetadata: nil
        )
    }

    private func adaptProfile(
        _ profile: CatalogV2Profile,
        sources: [String: CatalogV2SourceRegistryEntry]
    ) -> ReciprocityProfile {
        guard let sourceEntry = sources[profile.sourceId] else {
            preconditionFailure("Catalog v2 validation must resolve every sourceId before adaptation.")
        }

        return ReciprocityProfile(
            id: profile.id,
            name: profile.label,
            source: adaptSource(sourceEntry),
            rules: adaptRules(from: profile),
            notes: profile.notes ?? [],
            userMetadata: nil,
            sourceEvidence: adaptSourceEvidence(from: profile),
            modelBasis: adaptModelBasis(from: profile),
            selectorLabel: profile.selectorLabel
        )
    }

    private func adaptSource(_ source: CatalogV2SourceRegistryEntry) -> ReciprocitySourceProvenance {
        ReciprocitySourceProvenance(
            kind: ReciprocitySourceKind(rawValue: source.sourceType.rawValue) ?? .unknown,
            authority: ReciprocityAuthority(rawValue: source.authority.rawValue) ?? .unknown,
            confidence: ReciprocityConfidence(rawValue: source.confidence.rawValue) ?? .unknown,
            publisher: source.publisher,
            title: source.title,
            citation: source.citation,
            sourceVersion: source.version
        )
    }

    private func adaptModelBasis(from profile: CatalogV2Profile) -> ReciprocityProfileModelBasis? {
        guard let basis = profile.basis else { return nil }

        return ReciprocityProfileModelBasis(
            sourceModel: ReciprocitySourceModel(rawValue: basis.rawValue) ?? .unknown,
            calculationModel: calculationModel(for: profile.model)
        )
    }

    private func calculationModel(for model: CatalogV2ProfileModel) -> ReciprocityCalculationModel {
        switch model {
        case .table:
            return .tableLogLogInterpolation
        case .formula:
            return .guardedFormula
        case .limitedGuidance:
            return .limitedGuidance
        }
    }

    private func adaptRules(from profile: CatalogV2Profile) -> [ReciprocityRule] {
        switch profile.calculation {
        case let .table(calculation):
            return [
                .tableInterpolation(TableInterpolationReciprocityRule(
                    anchors: calculation.anchors.map {
                        TableAnchor(
                            meteredSeconds: $0.meteredSeconds,
                            correctedSeconds: $0.correctedSeconds
                        )
                    },
                    additionalAdjustments: [],
                    notes: calculation.notes ?? [],
                    noCorrectionThroughSeconds: calculation.noCorrectionThroughSeconds,
                    sourceRangeThroughSeconds: calculation.sourceRangeThroughSeconds
                )),
            ]

        case let .formula(calculation):
            return [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        formulaFamily: FormulaFamily(rawValue: calculation.family.rawValue) ?? .modifiedSchwarzschild,
                        coefficientSeconds: calculation.coefficient ?? 1,
                        referenceMeteredTimeSeconds: calculation.referenceMeteredSeconds ?? 1,
                        exponent: calculation.exponent,
                        offsetSeconds: calculation.offsetSeconds ?? 0,
                        noCorrectionThroughSeconds: calculation.noCorrectionThroughSeconds,
                        sourceRangeThroughSeconds: calculation.sourceRangeThroughSeconds
                    ),
                    additionalAdjustments: [],
                    notes: calculation.notes ?? []
                )),
            ]

        case let .limitedGuidance(calculation):
            let noCorrectionRange = ReciprocityTimeRange(
                minimumSeconds: calculation.noCorrectionRange[0],
                maximumSeconds: calculation.noCorrectionRange[1]
            )
            let guidanceAdjustments = calculation.guidance.flatMap { row -> [ReciprocityAdjustment] in
                var adjustments: [ReciprocityAdjustment] = []
                if let colorFilter = row.colorFilter {
                    adjustments.append(.colorFilter(ColorFilterRecommendation(
                        filterName: colorFilter.filterName,
                        note: colorFilter.note
                    )))
                }
                adjustments.append(.note(ReciprocityNote(text: row.message)))
                return adjustments
            }
            return [
                .threshold(ThresholdReciprocityRule(
                    noCorrectionRange: noCorrectionRange,
                    adjustments: [],
                    notes: calculation.notes ?? []
                )),
                .limitedGuidance(LimitedGuidanceReciprocityRule(
                    appliesWhenMetered: calculation.guidance.first.map {
                        ReciprocityTimeRange(minimumSeconds: $0.fromSeconds)
                    },
                    adjustments: guidanceAdjustments,
                    notes: []
                )),
            ]
        }
    }

    private func adaptSourceEvidence(from profile: CatalogV2Profile) -> [ReciprocitySourceEvidenceRow] {
        var rows: [ReciprocitySourceEvidenceRow] = []

        if case let .table(calculation) = profile.calculation {
            rows.append(contentsOf: (profile.evidence ?? []).map { evidence in
                let anchor = calculation.anchors[evidence.anchor]
                let correctedTime = CorrectedTimeMapping(
                        meteredSeconds: anchor.meteredSeconds,
                        correctedSeconds: anchor.correctedSeconds,
                        isApproximate: evidence.approx == true
                    )

                return ReciprocitySourceEvidenceRow(
                    meteredExposure: .exactSeconds(anchor.meteredSeconds),
                    adjustments: adaptAdjustments(from: evidence, correctedTime: correctedTime),
                    notes: evidence.rowNotes ?? [],
                    isSourceEvidenceOnly: evidence.evidenceOnly == true
                )
            })
        }

        rows.append(contentsOf: (profile.referencePoints ?? []).map { point in
            let correctedTime: CorrectedTimeMapping?
            if let correctedSeconds = point.correctedSeconds {
                correctedTime = CorrectedTimeMapping(
                    meteredSeconds: point.meteredSeconds,
                    correctedSeconds: correctedSeconds,
                    isApproximate: point.approx == true
                )
            } else {
                correctedTime = nil
            }

            return ReciprocitySourceEvidenceRow(
                meteredExposure: .exactSeconds(point.meteredSeconds),
                adjustments: adaptAdjustments(from: point, correctedTime: correctedTime),
                notes: point.rowNotes ?? [],
                isSourceEvidenceOnly: point.evidenceOnly == true
            )
        })

        rows.append(contentsOf: (profile.referenceRanges ?? []).map { range in
            ReciprocitySourceEvidenceRow(
                meteredExposure: .range(ReciprocityTimeRange(
                    minimumSeconds: range.fromSeconds,
                    maximumSeconds: range.throughSeconds
                )),
                adjustments: adaptAdjustments(from: range, correctedTime: nil),
                notes: range.rowNotes ?? [],
                isSourceEvidenceOnly: false
            )
        })

        return rows
    }

    private func adaptAdjustments(
        from row: CatalogV2EvidenceFields,
        correctedTime: CorrectedTimeMapping?
    ) -> [ReciprocityAdjustment] {
        var adjustments: [ReciprocityAdjustment] = []
        if let stopDelta = row.stopDelta {
            adjustments.append(.exposure(.stopDelta(StopDeltaAdjustment(stopDelta: stopDelta))))
        }
        if let multiplier = row.multiplier {
            adjustments.append(.exposure(.multiplier(MultiplierAdjustment(factor: multiplier))))
        }
        if let correctedTime {
            adjustments.append(.exposure(.correctedTime(correctedTime)))
        }
        if let colorFilter = row.colorFilter {
            adjustments.append(.colorFilter(ColorFilterRecommendation(filterName: colorFilter)))
        }
        if let development = row.development {
            adjustments.append(.development(DevelopmentAdjustment(instruction: development)))
        }
        if let warning = row.warning {
            adjustments.append(.warning(ReciprocityWarning(
                severity: ReciprocityWarningSeverity(rawValue: warning.severity.rawValue) ?? .caution,
                message: warning.message
            )))
        }
        if let note = row.note {
            adjustments.append(.note(ReciprocityNote(text: note)))
        }
        return adjustments
    }

    private static func describe(decodingError: DecodingError) -> String {
        switch decodingError {
        case let .keyNotFound(key, context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let .typeMismatch(type, context):
            return "Type mismatch for \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "Missing value for \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "Malformed JSON at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error"
        }
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "root"
        }

        return codingPath.enumerated().map { index, key in
            if let intValue = key.intValue {
                return index == 0 ? "[\(intValue)]" : ".[\(intValue)]"
            }

            return index == 0 ? key.stringValue : ".\(key.stringValue)"
        }
        .joined()
        .replacingOccurrences(of: ".[", with: "[")
    }
}

public enum LaunchPresetFilmCatalogV2LoaderError: Error, Equatable {
    case missingBundledResource(name: String, fileExtension: String)
    case unreadableResource(String)
    case malformedResource(String)
    case emptyCatalog
    case invalidSchema(schema: String, schemaVersion: Int)
    case invalidSourceIdentifier
    case duplicateSourceIdentifier(String)
    case invalidFilmIdentifier
    case duplicateFilmIdentifier(String)
    case invalidCanonicalStockName(String)
    case invalidProfileIdentifier(filmID: String)
    case duplicateProfileIdentifier(String)
    case unresolvedSourceReference(filmID: String, profileID: String, sourceID: String)
    case invalidPrimaryProfileCount(filmID: String, count: Int)
    case invalidFilmISO(filmID: String, iso: Int)
    case invalidRuleShape(filmID: String, profileID: String, reason: String)
}

extension LaunchPresetFilmCatalogV2LoaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingBundledResource(name, fileExtension):
            return "Bundled launch preset film catalog v2 resource '\(name).\(fileExtension)' was not found."
        case let .unreadableResource(reason):
            return "Bundled launch preset film catalog v2 resource could not be read: \(reason)"
        case let .malformedResource(reason):
            return "Bundled launch preset film catalog v2 resource is malformed: \(reason)"
        case .emptyCatalog:
            return "Bundled launch preset film catalog v2 is empty."
        case let .invalidSchema(schema, schemaVersion):
            return "Bundled launch preset film catalog v2 has unsupported schema '\(schema)' version \(schemaVersion)."
        case .invalidSourceIdentifier:
            return "Bundled launch preset film catalog v2 contains a source with an empty identifier."
        case let .duplicateSourceIdentifier(identifier):
            return "Bundled launch preset film catalog v2 contains a duplicate source identifier '\(identifier)'."
        case .invalidFilmIdentifier:
            return "Bundled launch preset film catalog v2 contains a film with an empty identifier."
        case let .duplicateFilmIdentifier(identifier):
            return "Bundled launch preset film catalog v2 contains a duplicate film identifier '\(identifier)'."
        case let .invalidCanonicalStockName(filmID):
            return "Bundled launch preset film catalog v2 contains an empty canonical stock name for film '\(filmID)'."
        case let .invalidProfileIdentifier(filmID):
            return "Bundled launch preset film catalog v2 film '\(filmID)' contains a profile with an empty identifier."
        case let .duplicateProfileIdentifier(identifier):
            return "Bundled launch preset film catalog v2 contains a duplicate profile identifier '\(identifier)'."
        case let .unresolvedSourceReference(filmID, profileID, sourceID):
            return "Bundled launch preset film catalog v2 film '\(filmID)' profile '\(profileID)' references missing source '\(sourceID)'."
        case let .invalidPrimaryProfileCount(filmID, count):
            return "Bundled launch preset film catalog v2 film '\(filmID)' has \(count) primary profiles; launch scope requires exactly one."
        case let .invalidFilmISO(filmID, iso):
            return "Bundled launch preset film catalog v2 film '\(filmID)' has non-positive ISO \(iso); launch scope requires a positive box-speed ISO."
        case let .invalidRuleShape(filmID, profileID, reason):
            return "Bundled launch preset film catalog v2 film '\(filmID)' profile '\(profileID)' has an unsupported reciprocity rule shape: \(reason)."
        }
    }
}

private struct CatalogV2Document: Decodable {
    let schema: String
    let schemaVersion: Int
    let catalogVersion: String
    let license: String
    let copyright: String
    let sources: [String: CatalogV2SourceRegistryEntry]
    let films: [CatalogV2Film]
}

private struct CatalogV2SourceRegistryEntry: Decodable {
    let publisher: String
    let title: String?
    let citation: String?
    let sourceType: CatalogV2SourceType
    let authority: CatalogV2SourceAuthority
    let confidence: CatalogV2Confidence
    let version: String?
    let links: CatalogV2SourceLinks?

    private enum CodingKeys: String, CodingKey {
        case publisher
        case title
        case citation
        case sourceType
        case authority
        case confidence
        case version
        case links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.publisher = try container.decode(String.self, forKey: .publisher)
        self.title = try container.decodeOptionalRejectingNull(String.self, forKey: .title)
        self.citation = try container.decodeOptionalRejectingNull(String.self, forKey: .citation)
        self.sourceType = try container.decode(CatalogV2SourceType.self, forKey: .sourceType)
        self.authority = try container.decode(CatalogV2SourceAuthority.self, forKey: .authority)
        self.confidence = try container.decode(CatalogV2Confidence.self, forKey: .confidence)
        self.version = try container.decodeOptionalRejectingNull(String.self, forKey: .version)
        self.links = try container.decodeOptionalRejectingNull(CatalogV2SourceLinks.self, forKey: .links)
    }
}

private struct CatalogV2SourceLinks: Decodable {
    let landingPageUrl: String?
    let downloadUrl: String?
    let archiveUrl: String?
    let accessedDate: String?

    private enum CodingKeys: String, CodingKey {
        case landingPageUrl
        case downloadUrl
        case archiveUrl
        case accessedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.landingPageUrl = try container.decodeOptionalRejectingNull(String.self, forKey: .landingPageUrl)
        self.downloadUrl = try container.decodeOptionalRejectingNull(String.self, forKey: .downloadUrl)
        self.archiveUrl = try container.decodeOptionalRejectingNull(String.self, forKey: .archiveUrl)
        self.accessedDate = try container.decodeOptionalRejectingNull(String.self, forKey: .accessedDate)
    }
}

private struct CatalogV2Film: Decodable {
    let id: String
    let canonicalStockName: String
    let manufacturer: String
    let brandLabel: String
    let aliases: [String]
    let iso: Int
    let kind: CatalogV2FilmKind
    let productionStatus: CatalogV2ProductionStatus
    let profiles: [CatalogV2Profile]
}

private struct CatalogV2Profile: Decodable {
    let id: String
    let label: String
    let selectorLabel: String?
    let role: CatalogV2ProfileRole
    let authority: CatalogV2ProfileAuthority
    let basis: CatalogV2ProfileBasis?
    let sourceId: String
    let model: CatalogV2ProfileModel
    let calculation: CatalogV2Calculation
    let evidence: [CatalogV2TableEvidence]?
    let referencePoints: [CatalogV2ReferencePoint]?
    let referenceRanges: [CatalogV2ReferenceRange]?
    let notes: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case selectorLabel
        case role
        case authority
        case basis
        case sourceId
        case model
        case calculation
        case evidence
        case referencePoints
        case referenceRanges
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.label = try container.decode(String.self, forKey: .label)
        self.selectorLabel = try container.decodeOptionalRejectingNull(String.self, forKey: .selectorLabel)
        self.role = try container.decode(CatalogV2ProfileRole.self, forKey: .role)
        self.authority = try container.decode(CatalogV2ProfileAuthority.self, forKey: .authority)
        self.basis = try container.decodeOptionalRejectingNull(CatalogV2ProfileBasis.self, forKey: .basis)
        self.sourceId = try container.decode(String.self, forKey: .sourceId)
        self.model = try container.decode(CatalogV2ProfileModel.self, forKey: .model)
        switch model {
        case .table:
            self.calculation = .table(try container.decode(CatalogV2TableCalculation.self, forKey: .calculation))
        case .formula:
            self.calculation = .formula(try container.decode(CatalogV2FormulaCalculation.self, forKey: .calculation))
        case .limitedGuidance:
            self.calculation = .limitedGuidance(
                try container.decode(CatalogV2LimitedGuidanceCalculation.self, forKey: .calculation)
            )
        }
        self.evidence = try container.decodeOptionalRejectingNull([CatalogV2TableEvidence].self, forKey: .evidence)
        self.referencePoints = try container.decodeOptionalRejectingNull(
            [CatalogV2ReferencePoint].self,
            forKey: .referencePoints
        )
        self.referenceRanges = try container.decodeOptionalRejectingNull(
            [CatalogV2ReferenceRange].self,
            forKey: .referenceRanges
        )
        self.notes = try container.decodeOptionalRejectingNull([String].self, forKey: .notes)
    }
}

private enum CatalogV2Calculation {
    case table(CatalogV2TableCalculation)
    case formula(CatalogV2FormulaCalculation)
    case limitedGuidance(CatalogV2LimitedGuidanceCalculation)
}

private struct CatalogV2TableCalculation: Decodable {
    let interpolation: CatalogV2TableInterpolation
    let noCorrectionThroughSeconds: Double
    let sourceRangeThroughSeconds: Double
    let anchors: [CatalogV2TableAnchor]
    let notes: [String]?

    private enum CodingKeys: String, CodingKey {
        case kind
        case interpolation
        case noCorrectionThroughSeconds
        case sourceRangeThroughSeconds
        case anchors
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.rejectCalculationKindIfPresent()
        self.interpolation = try container.decode(CatalogV2TableInterpolation.self, forKey: .interpolation)
        self.noCorrectionThroughSeconds = try container.decode(Double.self, forKey: .noCorrectionThroughSeconds)
        self.sourceRangeThroughSeconds = try container.decode(Double.self, forKey: .sourceRangeThroughSeconds)
        self.anchors = try container.decode([CatalogV2TableAnchor].self, forKey: .anchors)
        self.notes = try container.decodeOptionalRejectingNull([String].self, forKey: .notes)
    }
}

private struct CatalogV2FormulaCalculation: Decodable {
    let family: CatalogV2FormulaFamily
    let coefficient: Double?
    let referenceMeteredSeconds: Double?
    let exponent: Double
    let offsetSeconds: Double?
    let noCorrectionThroughSeconds: Double
    let sourceRangeThroughSeconds: Double?
    let notes: [String]?

    private enum CodingKeys: String, CodingKey {
        case kind
        case family
        case coefficient
        case referenceMeteredSeconds
        case exponent
        case offsetSeconds
        case noCorrectionThroughSeconds
        case sourceRangeThroughSeconds
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.rejectCalculationKindIfPresent()
        self.family = try container.decode(CatalogV2FormulaFamily.self, forKey: .family)
        self.coefficient = try container.decodeOptionalRejectingNull(Double.self, forKey: .coefficient)
        self.referenceMeteredSeconds = try container.decodeOptionalRejectingNull(
            Double.self,
            forKey: .referenceMeteredSeconds
        )
        self.exponent = try container.decode(Double.self, forKey: .exponent)
        self.offsetSeconds = try container.decodeOptionalRejectingNull(Double.self, forKey: .offsetSeconds)
        self.noCorrectionThroughSeconds = try container.decode(Double.self, forKey: .noCorrectionThroughSeconds)
        self.sourceRangeThroughSeconds = try container.decodeOptionalRejectingNull(
            Double.self,
            forKey: .sourceRangeThroughSeconds
        )
        self.notes = try container.decodeOptionalRejectingNull([String].self, forKey: .notes)
    }
}

private struct CatalogV2LimitedGuidanceCalculation: Decodable {
    let noCorrectionRange: [Double]
    let guidance: [CatalogV2GuidanceRow]
    let notes: [String]?

    private enum CodingKeys: String, CodingKey {
        case kind
        case noCorrectionRange
        case guidance
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.rejectCalculationKindIfPresent()
        self.noCorrectionRange = try container.decode([Double].self, forKey: .noCorrectionRange)
        self.guidance = try container.decode([CatalogV2GuidanceRow].self, forKey: .guidance)
        self.notes = try container.decodeOptionalRejectingNull([String].self, forKey: .notes)
    }
}

private struct CatalogV2TableAnchor: Decodable {
    let meteredSeconds: Double
    let correctedSeconds: Double
}

private struct CatalogV2GuidanceRow: Decodable {
    let fromSeconds: Double
    let colorFilter: CatalogV2GuidanceColorFilter?
    let message: String

    private enum CodingKeys: String, CodingKey {
        case fromSeconds
        case colorFilter
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fromSeconds = try container.decode(Double.self, forKey: .fromSeconds)
        self.colorFilter = try container.decodeOptionalRejectingNull(
            CatalogV2GuidanceColorFilter.self,
            forKey: .colorFilter
        )
        self.message = try container.decode(String.self, forKey: .message)
    }
}

private struct CatalogV2GuidanceColorFilter: Decodable {
    let filterName: String
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case filterName
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.filterName = try container.decode(String.self, forKey: .filterName)
        self.note = try container.decodeOptionalRejectingNull(String.self, forKey: .note)
    }
}

private protocol CatalogV2EvidenceFields {
    var stopDelta: Double? { get }
    var multiplier: Double? { get }
    var colorFilter: String? { get }
    var development: String? { get }
    var warning: CatalogV2Warning? { get }
    var note: String? { get }
    var rowNotes: [String]? { get }
}

private struct CatalogV2TableEvidence: Decodable, CatalogV2EvidenceFields {
    let anchor: Int
    let stopDelta: Double?
    let multiplier: Double?
    let colorFilter: String?
    let development: String?
    let warning: CatalogV2Warning?
    let note: String?
    let rowNotes: [String]?
    let approx: Bool?
    let evidenceOnly: Bool?

    private enum CodingKeys: String, CodingKey {
        case anchor
        case stopDelta
        case multiplier
        case colorFilter
        case development
        case warning
        case note
        case rowNotes
        case approx
        case evidenceOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.anchor = try container.decode(Int.self, forKey: .anchor)
        self.stopDelta = try container.decodeOptionalRejectingNull(Double.self, forKey: .stopDelta)
        self.multiplier = try container.decodeOptionalRejectingNull(Double.self, forKey: .multiplier)
        self.colorFilter = try container.decodeOptionalRejectingNull(String.self, forKey: .colorFilter)
        self.development = try container.decodeOptionalRejectingNull(String.self, forKey: .development)
        self.warning = try container.decodeOptionalRejectingNull(CatalogV2Warning.self, forKey: .warning)
        self.note = try container.decodeOptionalRejectingNull(String.self, forKey: .note)
        self.rowNotes = try container.decodeOptionalRejectingNull([String].self, forKey: .rowNotes)
        self.approx = try container.decodeOptionalRejectingNull(Bool.self, forKey: .approx)
        self.evidenceOnly = try container.decodeOptionalRejectingNull(Bool.self, forKey: .evidenceOnly)
    }
}

private struct CatalogV2ReferencePoint: Decodable, CatalogV2EvidenceFields {
    let meteredSeconds: Double
    let correctedSeconds: Double?
    let stopDelta: Double?
    let multiplier: Double?
    let colorFilter: String?
    let development: String?
    let warning: CatalogV2Warning?
    let note: String?
    let rowNotes: [String]?
    let approx: Bool?
    let evidenceOnly: Bool?

    private enum CodingKeys: String, CodingKey {
        case meteredSeconds
        case correctedSeconds
        case stopDelta
        case multiplier
        case colorFilter
        case development
        case warning
        case note
        case rowNotes
        case approx
        case evidenceOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meteredSeconds = try container.decode(Double.self, forKey: .meteredSeconds)
        self.correctedSeconds = try container.decodeOptionalRejectingNull(Double.self, forKey: .correctedSeconds)
        self.stopDelta = try container.decodeOptionalRejectingNull(Double.self, forKey: .stopDelta)
        self.multiplier = try container.decodeOptionalRejectingNull(Double.self, forKey: .multiplier)
        self.colorFilter = try container.decodeOptionalRejectingNull(String.self, forKey: .colorFilter)
        self.development = try container.decodeOptionalRejectingNull(String.self, forKey: .development)
        self.warning = try container.decodeOptionalRejectingNull(CatalogV2Warning.self, forKey: .warning)
        self.note = try container.decodeOptionalRejectingNull(String.self, forKey: .note)
        self.rowNotes = try container.decodeOptionalRejectingNull([String].self, forKey: .rowNotes)
        self.approx = try container.decodeOptionalRejectingNull(Bool.self, forKey: .approx)
        self.evidenceOnly = try container.decodeOptionalRejectingNull(Bool.self, forKey: .evidenceOnly)
    }
}

private struct CatalogV2ReferenceRange: Decodable, CatalogV2EvidenceFields {
    let fromSeconds: Double
    let throughSeconds: Double
    let stopDelta: Double?
    let multiplier: Double?
    let colorFilter: String?
    let development: String?
    let warning: CatalogV2Warning?
    let note: String?
    let rowNotes: [String]?

    private enum CodingKeys: String, CodingKey {
        case fromSeconds
        case throughSeconds
        case stopDelta
        case multiplier
        case colorFilter
        case development
        case warning
        case note
        case rowNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fromSeconds = try container.decode(Double.self, forKey: .fromSeconds)
        self.throughSeconds = try container.decode(Double.self, forKey: .throughSeconds)
        self.stopDelta = try container.decodeOptionalRejectingNull(Double.self, forKey: .stopDelta)
        self.multiplier = try container.decodeOptionalRejectingNull(Double.self, forKey: .multiplier)
        self.colorFilter = try container.decodeOptionalRejectingNull(String.self, forKey: .colorFilter)
        self.development = try container.decodeOptionalRejectingNull(String.self, forKey: .development)
        self.warning = try container.decodeOptionalRejectingNull(CatalogV2Warning.self, forKey: .warning)
        self.note = try container.decodeOptionalRejectingNull(String.self, forKey: .note)
        self.rowNotes = try container.decodeOptionalRejectingNull([String].self, forKey: .rowNotes)
    }
}

private struct CatalogV2Warning: Decodable {
    let severity: CatalogV2WarningSeverity
    let message: String
}

private enum CatalogV2SourceType: String, Decodable {
    case manufacturerPublished
    case manufacturerArchive
    case thirdPartyPublication
    case userDefined
    case unknown
}

private enum CatalogV2SourceAuthority: String, Decodable {
    case official
    case unofficial
    case userDefined
    case unknown
}

private enum CatalogV2Confidence: String, Decodable {
    case high
    case medium
    case low
    case unknown
}

private enum CatalogV2FilmKind: String, Decodable {
    case preset
    case custom
    case unknown
}

private enum CatalogV2ProductionStatus: String, Decodable {
    case current
    case discontinued
    case unknown
}

private enum CatalogV2ProfileRole: String, Decodable {
    case primary
    case alternate
    case derived
}

private enum CatalogV2ProfileAuthority: String, Decodable {
    case official
    case appDerived
    case community
    case unofficial
    case userDefined
}

private enum CatalogV2ProfileBasis: String, Decodable {
    case manufacturerFormula
    case manufacturerTable
    case manufacturerGraphTable
    case manufacturerRangeGuidance
    case manufacturerLimitedGuidance
    case practicalCommunityGuidance
}

private enum CatalogV2ProfileModel: String, Decodable {
    case formula
    case table
    case limitedGuidance
}

private enum CatalogV2TableInterpolation: String, Decodable {
    case logLog
}

private enum CatalogV2FormulaFamily: String, Decodable {
    case modifiedSchwarzschild
}

private enum CatalogV2WarningSeverity: String, Decodable {
    case caution
    case notRecommended
}

private extension KeyedDecodingContainer {
    func decodeOptionalRejectingNull<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Explicit null is not accepted in catalog v2 optional fields."
            )
        }
        return try decode(T.self, forKey: key)
    }

    func rejectCalculationKindIfPresent() throws {
        guard let key = Key(stringValue: "kind"), contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Catalog v2 uses profile.model as the only calculation discriminator."
        )
    }
}
