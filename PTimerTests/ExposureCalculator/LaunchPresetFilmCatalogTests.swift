import Foundation
import XCTest
@testable import PTimer

final class LaunchPresetFilmCatalogTests: XCTestCase {
    func testBundledLaunchPresetFilmCatalogLoadsSuccessfully() throws {
        let films = try LaunchPresetFilmCatalogLoader().loadBundledCatalog()

        XCTAssertEqual(
            films.map(\.canonicalStockName),
            ["Tri-X 400", "Portra 400", "Velvia 50", "HP5 Plus"]
        )
    }

    func testBundledLaunchPresetFilmCatalogPreservesExpectedSelectorOrdering() {
        XCTAssertEqual(
            LaunchPresetFilmCatalog.films.map(\.canonicalStockName),
            ["Tri-X 400", "Portra 400", "Velvia 50", "HP5 Plus"]
        )
    }

    func testLaunchPresetFilmCatalogRespectsPTIMER86LaunchPolicyConstraints() {
        XCTAssertFalse(LaunchPresetFilmCatalog.films.isEmpty)

        for film in LaunchPresetFilmCatalog.films {
            XCTAssertEqual(film.kind, .preset)
            XCTAssertEqual(film.productionStatus, .current)
            XCTAssertEqual(film.profiles.count, 1, "Launch flow should use one primary profile per film identity.")
            XCTAssertFalse(film.canonicalStockName.isEmpty)

            let profile = film.profiles[0]
            XCTAssertEqual(profile.source.kind, .manufacturerPublished)
            XCTAssertEqual(profile.source.authority, .official)
        }
    }

    func testLaunchPresetFilmCatalogRejectsDuplicateFilmIdentifiers() throws {
        let originalFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let duplicatedFilm = copyFilm(originalFilm)
        let duplicatedData = try encodeCatalog([originalFilm, duplicatedFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(try LaunchPresetFilmCatalogLoader().loadCatalog(from: duplicatedData))
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(error, .duplicateFilmIdentifier(originalFilm.id))
        XCTAssertEqual(
            error.errorDescription,
            "Bundled launch preset film catalog contains a duplicate film identifier '\(originalFilm.id)'."
        )
    }

    func testLaunchPresetFilmCatalogRejectsInvalidCanonicalStockNames() throws {
        let originalFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let invalidFilm = copyFilm(originalFilm, canonicalStockName: "  ")
        let invalidData = try encodeCatalog([invalidFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(try LaunchPresetFilmCatalogLoader().loadCatalog(from: invalidData))
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(error, .invalidCanonicalStockName(originalFilm.id))
    }

    func testLaunchPresetFilmCatalogRejectsDuplicateCanonicalStockNames() throws {
        let firstFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let secondFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.dropFirst().first)
        let duplicateNameFilm = copyFilm(secondFilm, canonicalStockName: firstFilm.canonicalStockName)
        let duplicatedData = try encodeCatalog([firstFilm, duplicateNameFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(try LaunchPresetFilmCatalogLoader().loadCatalog(from: duplicatedData))
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(error, .duplicateCanonicalStockName(firstFilm.canonicalStockName))
    }

    func testLaunchPresetFilmCatalogMissingResourceFailsSafely() {
        let error = XCTAssertThrowsErrorAndReturn(
            try LaunchPresetFilmCatalogLoader().loadBundledCatalog(
                resourceName: "MissingLaunchPresetFilmCatalog",
                bundleCandidates: [Bundle(for: Self.self)]
            )
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(
            error,
            .missingBundledResource(name: "MissingLaunchPresetFilmCatalog", fileExtension: "json")
        )
    }

    func testLaunchPresetFilmCatalogMalformedResourceFailsSafely() {
        let malformedData = Data("{".utf8)

        let error = XCTAssertThrowsErrorAndReturn(
            try LaunchPresetFilmCatalogLoader().loadCatalog(from: malformedData)
        ) as? LaunchPresetFilmCatalogLoaderError

        guard case .malformedResource? = error else {
            return XCTFail("Expected malformed resource error, got \(String(describing: error)).")
        }
    }

    func testLaunchPresetFilmCatalogDecodeFailureReportsMissingKeyAndCodingPath() {
        let invalidJSON = Data(
            """
            [
              {
                "id": "kodak-tri-x-400",
                "kind": "preset",
                "canonicalStockName": "Tri-X 400",
                "manufacturer": "Kodak",
                "brandLabel": "KODAK PROFESSIONAL TRI-X 400",
                "aliases": ["TRI-X", "TX 400"],
                "productionStatus": "current",
                "profiles": [
                  {
                    "id": "kodak-tri-x-official-table",
                    "name": "Official table",
                    "source": {
                      "kind": "manufacturerPublished",
                      "authority": "official",
                      "confidence": "high",
                      "publisher": "Kodak"
                    },
                    "rules": [],
                    "notes": []
                  }
                ]
              }
            ]
            """.utf8
        )

        let error = XCTAssertThrowsErrorAndReturn(
            try LaunchPresetFilmCatalogLoader().loadCatalog(from: invalidJSON)
        ) as? LaunchPresetFilmCatalogLoaderError

        guard case let .malformedResource(reason)? = error else {
            return XCTFail("Expected malformed resource error, got \(String(describing: error)).")
        }

        XCTAssertTrue(reason.contains("Missing key 'userMetadata'"))
        XCTAssertTrue(reason.contains("[0]"))
    }

    func testLaunchPresetFilmCatalogValidationFailureDescriptionsNameOffendingEntry() throws {
        let firstFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let invalidFilm = copyFilm(firstFilm, profiles: [])
        let invalidData = try encodeCatalog([invalidFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(try LaunchPresetFilmCatalogLoader().loadCatalog(from: invalidData))
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(error, .invalidPrimaryProfileCount(filmID: firstFilm.id, count: 0))
        XCTAssertEqual(
            error.errorDescription,
            "Bundled launch preset film catalog film '\(firstFilm.id)' has 0 profiles; launch scope requires exactly one primary profile."
        )
    }

    private func encodeCatalog(_ films: [FilmIdentity]) throws -> Data {
        try JSONEncoder().encode(films)
    }

    private func copyFilm(
        _ film: FilmIdentity,
        id: String? = nil,
        canonicalStockName: String? = nil,
        kind: FilmIdentityKind? = nil,
        productionStatus: FilmProductionStatus? = nil,
        profiles: [ReciprocityProfile]? = nil
    ) -> FilmIdentity {
        FilmIdentity(
            id: id ?? film.id,
            kind: kind ?? film.kind,
            canonicalStockName: canonicalStockName ?? film.canonicalStockName,
            manufacturer: film.manufacturer,
            brandLabel: film.brandLabel,
            aliases: film.aliases,
            productionStatus: productionStatus ?? film.productionStatus,
            profiles: profiles ?? film.profiles,
            userMetadata: film.userMetadata
        )
    }
}

private func XCTAssertThrowsErrorAndReturn<T>(
    _ expression: @autoclosure () throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Error? {
    do {
        _ = try expression()
        XCTFail("Expected expression to throw an error.", file: file, line: line)
        return nil
    } catch {
        return error
    }
}
