import Foundation

public enum LaunchPresetFilmCatalog {
    public static let resourceName = "LaunchPresetFilmCatalog"
    public static let resourceExtension = "json"

    public static let films: [FilmIdentity] = {
        do {
            return try LaunchPresetFilmCatalogLoader().loadBundledCatalog()
        } catch {
            assertionFailure("Failed to load bundled launch preset film catalog: \(error)")
            return []
        }
    }()

    public static func defaultResourceBundles() -> [Bundle] {
        [.module]
    }
}

public struct LaunchPresetFilmCatalogLoader {
    public init() {}
    private let decoder = JSONDecoder()

    public func loadBundledCatalog(
        resourceName: String = LaunchPresetFilmCatalog.resourceName,
        resourceExtension: String = LaunchPresetFilmCatalog.resourceExtension,
        bundleCandidates: [Bundle] = LaunchPresetFilmCatalog.defaultResourceBundles()
    ) throws -> [FilmIdentity] {
        for bundle in bundleCandidates {
            guard let resourceURL = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
                continue
            }

            return try loadCatalog(from: resourceURL)
        }

        throw LaunchPresetFilmCatalogLoaderError.missingBundledResource(
            name: resourceName,
            fileExtension: resourceExtension
        )
    }

    public func loadCatalog(from url: URL) throws -> [FilmIdentity] {
        do {
            let data = try Data(contentsOf: url)
            return try loadCatalog(from: data)
        } catch let error as LaunchPresetFilmCatalogLoaderError {
            throw error
        } catch {
            throw LaunchPresetFilmCatalogLoaderError.unreadableResource(error.localizedDescription)
        }
    }

    public func loadCatalog(from data: Data) throws -> [FilmIdentity] {
        let films: [FilmIdentity]

        do {
            films = try decoder.decode([FilmIdentity].self, from: data)
        } catch let decodingError as DecodingError {
            throw LaunchPresetFilmCatalogLoaderError.malformedResource(
                Self.describe(decodingError: decodingError)
            )
        } catch {
            throw LaunchPresetFilmCatalogLoaderError.malformedResource(error.localizedDescription)
        }

        try validateLaunchCatalog(films)
        return films
    }

    private func validateLaunchCatalog(_ films: [FilmIdentity]) throws {
        guard !films.isEmpty else {
            throw LaunchPresetFilmCatalogLoaderError.emptyCatalog
        }

        var seenIdentifiers: Set<String> = []
        var seenCanonicalStockNames: Set<String> = []

        for film in films {
            let filmID = film.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filmID.isEmpty else {
                throw LaunchPresetFilmCatalogLoaderError.invalidFilmIdentifier
            }

            guard seenIdentifiers.insert(filmID).inserted else {
                throw LaunchPresetFilmCatalogLoaderError.duplicateFilmIdentifier(filmID)
            }

            let canonicalStockName = film.canonicalStockName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonicalStockName.isEmpty else {
                throw LaunchPresetFilmCatalogLoaderError.invalidCanonicalStockName(filmID)
            }

            guard seenCanonicalStockNames.insert(canonicalStockName).inserted else {
                throw LaunchPresetFilmCatalogLoaderError.duplicateCanonicalStockName(canonicalStockName)
            }

            guard film.kind == .preset else {
                throw LaunchPresetFilmCatalogLoaderError.invalidFilmKind(filmID)
            }

            guard film.productionStatus == .current else {
                throw LaunchPresetFilmCatalogLoaderError.invalidProductionStatus(filmID)
            }

            guard film.iso > 0 else {
                throw LaunchPresetFilmCatalogLoaderError.invalidFilmISO(filmID: filmID, iso: film.iso)
            }

            guard film.profiles.count == 1, let profile = film.profiles.first else {
                throw LaunchPresetFilmCatalogLoaderError.invalidPrimaryProfileCount(
                    filmID: filmID,
                    count: film.profiles.count
                )
            }

            guard isOfficialManufacturerPrimary(profile)
                || isPromotedUnofficialPracticalPrimary(profile, filmID: filmID) else {
                throw LaunchPresetFilmCatalogLoaderError.invalidPrimaryProfileSource(filmID)
            }

            try validateProfileShape(profile, filmID: filmID)
        }
    }

    private func isOfficialManufacturerPrimary(_ profile: ReciprocityProfile) -> Bool {
        profile.source.kind == .manufacturerPublished
            && profile.source.authority == .official
    }

    private func isPromotedUnofficialPracticalPrimary(
        _ profile: ReciprocityProfile,
        filmID: String
    ) -> Bool {
        guard filmID == "rollei-retro-400s",
              profile.id == "rollei-retro-400s-unofficial-practical",
              profile.source.kind == .thirdPartyPublication,
              profile.source.authority == .unofficial,
              profile.source.confidence == .medium,
              profile.source.publisher.contains("Lafitte"),
              profile.source.title?.isEmpty == false,
              profile.source.citation?.isEmpty == false,
              profile.modelBasis == ReciprocityProfileModelBasis(
                sourceModel: .practicalCommunityGuidance,
                calculationModel: .guardedFormula
              ),
              profile.rules.count == 1,
              case let .formula(formulaRule) = profile.rules[0],
              formulaRule.additionalAdjustments.isEmpty,
              formulaRule.formula.formulaFamily == .modifiedSchwarzschild,
              isEffectivelyEqual(formulaRule.formula.coefficientSeconds, 1),
              isEffectivelyEqual(formulaRule.formula.referenceMeteredTimeSeconds, 1),
              isEffectivelyEqual(formulaRule.formula.exponent, 1.62),
              isEffectivelyEqual(formulaRule.formula.offsetSeconds, 0),
              isEffectivelyEqual(formulaRule.formula.noCorrectionThroughSeconds, 1),
              isEffectivelyEqual(formulaRule.formula.sourceRangeThroughSeconds ?? .nan, 15)
        else {
            return false
        }

        let evidence = profile.sourceEvidence.compactMap { row -> (metered: Double, corrected: Double)? in
            guard case let .exactSeconds(metered) = row.meteredExposure else { return nil }
            let corrected = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            guard let corrected else { return nil }
            return (metered, corrected)
        }

        let expectedEvidence = [(5.0, 13.5), (10.0, 41.0), (15.0, 80.0)]
        guard evidence.count == expectedEvidence.count else { return false }
        return zip(evidence, expectedEvidence).allSatisfy { actual, expected in
            isEffectivelyEqual(actual.metered, expected.0)
                && isEffectivelyEqual(actual.corrected, expected.1)
        }
    }

    private func isEffectivelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    /// Enforces the post-PTIMER-160 allow-list at load time so a
    /// malformed catalog cannot ship a rule combination the
    /// calculation policy no longer supports. The bundled catalog is
    /// official everywhere except the single PTIMER-122 promoted
    /// unofficial practical primary that is allow-listed above, so
    /// this validator enumerates the shipped shapes:
    ///
    /// - formula only (the formula owns its no-correction and source
    ///   range guards via the shared `ReciprocityFormula` contract;
    ///   no companion threshold rule is needed)
    /// - threshold + limited-guidance (no formula rule)
    /// - table interpolation only
    ///
    /// Any other combination — bare limited-guidance, formula +
    /// limited-guidance, formula + threshold, an empty rule list —
    /// is rejected with `.invalidRuleShape` so the failure surfaces
    /// as a load-time error rather than a soft warning.
    private func validateProfileShape(_ profile: ReciprocityProfile, filmID: String) throws {
        guard !profile.rules.isEmpty else {
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "rule list is empty"
            )
        }

        var hasThreshold = false
        var hasFormula = false
        var hasLimitedGuidance = false
        var hasTableInterpolation = false
        for rule in profile.rules {
            switch rule {
            case .threshold:
                hasThreshold = true
            case .formula:
                hasFormula = true
            case .limitedGuidance:
                hasLimitedGuidance = true
            case .tableInterpolation:
                hasTableInterpolation = true
            }
        }

        // A table-interpolation profile owns its own no-correction band
        // and source range, so it stands alone — no companion formula,
        // threshold, or limited-guidance rule (PTIMER-159).
        if hasTableInterpolation {
            guard !hasFormula, !hasLimitedGuidance, !hasThreshold else {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "table-interpolation profiles must not carry a companion formula, threshold, or limited-guidance rule"
                )
            }
            try validateTableInterpolationParameters(profile, filmID: filmID)
            try validateExplicitModelBasis(
                profile,
                filmID: filmID,
                hasFormula: hasFormula,
                hasLimitedGuidance: hasLimitedGuidance,
                hasTableInterpolation: hasTableInterpolation
            )
            return
        }

        if hasFormula && hasLimitedGuidance {
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "formula and limited-guidance rules cannot coexist"
            )
        }

        if hasFormula {
            if hasThreshold {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "formula profiles must not carry a companion threshold rule (the formula owns its no-correction guard)"
                )
            }
            try validateFormulaParameters(profile, filmID: filmID)
            try validateExplicitModelBasis(
                profile,
                filmID: filmID,
                hasFormula: hasFormula,
                hasLimitedGuidance: hasLimitedGuidance
            )
            return
        }

        guard hasLimitedGuidance else {
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "profile must declare either a formula rule or a threshold + limited-guidance pair"
            )
        }

        guard hasThreshold else {
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "limited-guidance profiles must be paired with a threshold rule"
            )
        }

        if !profile.sourceEvidence.isEmpty {
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "limited-guidance profiles cannot carry sourceEvidence rows"
            )
        }

        try validateExplicitModelBasis(
            profile,
            filmID: filmID,
            hasFormula: hasFormula,
            hasLimitedGuidance: hasLimitedGuidance
        )
    }

    /// PTIMER-163 sanity check: when a profile declares an explicit
    /// `modelBasis`, both halves of the basis must line up with what
    /// the launch catalog actually ships.
    ///
    /// - `calculationModel` must match the rule shape. `.unsupported`
    ///   and `.tableLookup` have no implemented rule shape on the
    ///   launch catalog today and are rejected so the metadata cannot
    ///   advertise behavior the evaluator does not provide.
    /// - `sourceModel` must be manufacturer-shape on the launch
    ///   catalog (the loader already enforces
    ///   `manufacturerPublished` + `official` source provenance).
    ///   `practicalCommunityGuidance`, `userDefined`, and explicit
    ///   `unknown` would mislabel official manufacturer data and are
    ///   rejected; entries with an unknown source shape must omit
    ///   `modelBasis` and rely on `effectiveModelBasis`.
    private func validateExplicitModelBasis(
        _ profile: ReciprocityProfile,
        filmID: String,
        hasFormula: Bool,
        hasLimitedGuidance: Bool,
        hasTableInterpolation: Bool = false
    ) throws {
        guard let basis = profile.modelBasis else { return }

        switch basis.calculationModel {
        case .guardedFormula:
            guard hasFormula else {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "modelBasis.calculationModel = guardedFormula requires a formula rule"
                )
            }
        case .tableLogLogInterpolation:
            guard hasTableInterpolation else {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "modelBasis.calculationModel = tableLogLogInterpolation requires a table-interpolation rule"
                )
            }
        case .limitedGuidance:
            guard hasLimitedGuidance else {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "modelBasis.calculationModel = limitedGuidance requires a limited-guidance rule"
                )
            }
        case .unsupported:
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "modelBasis.calculationModel = unsupported is not implemented for launch preset modelBasis yet"
            )
        case .tableLookup:
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "modelBasis.calculationModel = tableLookup is not yet implemented"
            )
        }

        switch basis.sourceModel {
        case .manufacturerFormula,
             .manufacturerTable,
             .manufacturerGraphTable,
             .manufacturerRangeGuidance,
             .manufacturerLimitedGuidance:
            break
        case .practicalCommunityGuidance where isPromotedUnofficialPracticalPrimary(profile, filmID: filmID):
            break
        case .practicalCommunityGuidance:
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "modelBasis.sourceModel = practicalCommunityGuidance is not allowed for the official manufacturer launch catalog"
            )
        case .userDefined:
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "modelBasis.sourceModel = userDefined is not allowed for the official manufacturer launch catalog"
            )
        case .unknown:
            throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                filmID: filmID,
                reason: "modelBasis.sourceModel = unknown is not allowed for the launch catalog; omit modelBasis to rely on the inferred fallback"
            )
        }
    }

    private func validateFormulaParameters(
        _ profile: ReciprocityProfile,
        filmID: String
    ) throws {
        for rule in profile.rules {
            guard case let .formula(formulaRule) = rule else {
                continue
            }
            guard formulaRule.formula.hasValidParameters else {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "formula parameters violate the safe-formula contract (finite, positive coefficient and reference, non-negative no-correction boundary, source-range above no-correction)"
                )
            }
        }
    }

    private func validateTableInterpolationParameters(
        _ profile: ReciprocityProfile,
        filmID: String
    ) throws {
        for rule in profile.rules {
            guard case let .tableInterpolation(tableRule) = rule else {
                continue
            }
            guard tableRule.hasValidParameters else {
                throw LaunchPresetFilmCatalogLoaderError.invalidRuleShape(
                    filmID: filmID,
                    reason: "table-interpolation anchors violate the safe-table contract (at least two ascending positive anchors, each corrected ≥ metered, no-correction below the first anchor, source range at the last anchor)"
                )
            }
        }
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

public enum LaunchPresetFilmCatalogLoaderError: Error, Equatable {
    case missingBundledResource(name: String, fileExtension: String)
    case unreadableResource(String)
    case malformedResource(String)
    case emptyCatalog
    case invalidFilmIdentifier
    case duplicateFilmIdentifier(String)
    case invalidCanonicalStockName(String)
    case duplicateCanonicalStockName(String)
    case invalidFilmKind(String)
    case invalidProductionStatus(String)
    case invalidPrimaryProfileCount(filmID: String, count: Int)
    case invalidPrimaryProfileSource(String)
    case invalidFilmISO(filmID: String, iso: Int)
    case invalidRuleShape(filmID: String, reason: String)
}

extension LaunchPresetFilmCatalogLoaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingBundledResource(name, fileExtension):
            return "Bundled launch preset film catalog resource '\(name).\(fileExtension)' was not found."
        case let .unreadableResource(reason):
            return "Bundled launch preset film catalog resource could not be read: \(reason)"
        case let .malformedResource(reason):
            return "Bundled launch preset film catalog resource is malformed: \(reason)"
        case .emptyCatalog:
            return "Bundled launch preset film catalog is empty."
        case .invalidFilmIdentifier:
            return "Bundled launch preset film catalog contains a film with an empty identifier."
        case let .duplicateFilmIdentifier(identifier):
            return "Bundled launch preset film catalog contains a duplicate film identifier '\(identifier)'."
        case let .invalidCanonicalStockName(filmID):
            return "Bundled launch preset film catalog contains an empty canonical stock name for film '\(filmID)'."
        case let .duplicateCanonicalStockName(stockName):
            return "Bundled launch preset film catalog contains a duplicate canonical stock name '\(stockName)'."
        case let .invalidFilmKind(filmID):
            return "Bundled launch preset film catalog film '\(filmID)' is not a preset film."
        case let .invalidProductionStatus(filmID):
            return "Bundled launch preset film catalog film '\(filmID)' is not marked current-production."
        case let .invalidPrimaryProfileCount(filmID, count):
            return "Bundled launch preset film catalog film '\(filmID)' has \(count) profiles; launch scope requires exactly one primary profile."
        case let .invalidPrimaryProfileSource(filmID):
            return "Bundled launch preset film catalog film '\(filmID)' does not use a current official manufacturer primary profile."
        case let .invalidFilmISO(filmID, iso):
            return "Bundled launch preset film catalog film '\(filmID)' has non-positive ISO \(iso); launch scope requires a positive box-speed ISO."
        case let .invalidRuleShape(filmID, reason):
            return "Bundled launch preset film catalog film '\(filmID)' has an unsupported reciprocity rule shape: \(reason)."
        }
    }
}

private final class LaunchPresetFilmCatalogBundleMarker: NSObject {}
