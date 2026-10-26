// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
import PTimerCore

final class FilmClassificationCatalogTests: XCTestCase {
    func testAllFortyStocksMatchTheSourceEvidenceMapping() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../shared/catalog/FilmClassificationSources.json")
        let mapping = try JSONDecoder().decode(Mapping.self, from: Data(contentsOf: url))
        let films = try LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        XCTAssertEqual(mapping.films.count, 40)
        XCTAssertEqual(Set(mapping.films.map(\.filmID)), Set(films.map(\.id)))
        for film in films {
            let row = try XCTUnwrap(mapping.films.first { $0.filmID == film.id })
            XCTAssertEqual(film.polarity, row.polarity, film.id)
            XCTAssertEqual(film.color, row.color, film.id)
            XCTAssertFalse(row.sources.isEmpty)
            for source in row.sources {
                XCTAssertEqual(URL(string: source.url)?.scheme, "https")
                XCTAssertFalse(source.location.isEmpty)
                XCTAssertFalse(source.evidence.isEmpty)
            }
        }
        XCTAssertEqual(films.first { $0.id == "ilford-sfx-200" }?.color, .blackAndWhite)
        XCTAssertEqual(films.first { $0.id == "rollei-retro-400s" }?.polarity, .negative)
    }

    func testPresetClassificationDecodeRejectsMissingUnknownAndNullValues() throws {
        let film = try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(film)) as? [String: Any])
        for key in ["polarity", "color"] {
            var missing = record
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(FilmIdentity.self, from: JSONSerialization.data(withJSONObject: missing)))
            for bad in ["future" as Any, NSNull()] {
                var invalid = record
                invalid[key] = bad
                XCTAssertThrowsError(try JSONDecoder().decode(FilmIdentity.self, from: JSONSerialization.data(withJSONObject: invalid)))
            }
        }
    }

    private struct Mapping: Decodable {
        let films: [Row]
    }

    private struct Row: Decodable {
        let filmID: String
        let polarity: FilmPolarity
        let color: FilmColor
        let sources: [Source]
    }

    private struct Source: Decodable {
        let url: String
        let location: String
        let evidence: String
    }
}
