import Foundation

enum LaunchPresetFilmCatalog {
    static let resourceName = "LaunchPresetFilmCatalog"
    static let resourceExtension = "json"

    static let films: [FilmIdentity] = {
        do {
            return try LaunchPresetFilmCatalogLoader().loadBundledCatalog()
        } catch {
            assertionFailure("Failed to load bundled launch preset film catalog: \(error)")
            return []
        }
    }()

    static func defaultResourceBundles() -> [Bundle] {
        let candidates = [Bundle.main, Bundle(for: LaunchPresetFilmCatalogBundleMarker.self)]
            + Bundle.allBundles
            + Bundle.allFrameworks

        var seenBundlePaths: Set<String> = []
        return candidates.filter { bundle in
            let path = bundle.bundleURL.standardizedFileURL.path
            return seenBundlePaths.insert(path).inserted
        }
    }
}

struct LaunchPresetFilmCatalogLoader {
    private let decoder = JSONDecoder()

    func loadBundledCatalog(
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

    func loadCatalog(from url: URL) throws -> [FilmIdentity] {
        do {
            let data = try Data(contentsOf: url)
            return try loadCatalog(from: data)
        } catch let error as LaunchPresetFilmCatalogLoaderError {
            throw error
        } catch {
            throw LaunchPresetFilmCatalogLoaderError.unreadableResource(error.localizedDescription)
        }
    }

    func loadCatalog(from data: Data) throws -> [FilmIdentity] {
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

            guard profile.source.kind == .manufacturerPublished,
                  profile.source.authority == .official else {
                throw LaunchPresetFilmCatalogLoaderError.invalidPrimaryProfileSource(filmID)
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

enum LaunchPresetFilmCatalogLoaderError: Error, Equatable {
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
}

extension LaunchPresetFilmCatalogLoaderError: LocalizedError {
    var errorDescription: String? {
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
        }
    }
}

private final class LaunchPresetFilmCatalogBundleMarker: NSObject {}
