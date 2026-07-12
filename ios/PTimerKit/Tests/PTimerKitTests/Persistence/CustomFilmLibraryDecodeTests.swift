// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// PTIMER-215 per-record decode behavior for the custom film library.
/// Unknown enum values / rule kinds injected into one record drop only
/// that record; the rest of the library survives. Version-gate and
/// malformed-root failures reject the whole payload. All failure modes
/// report a non-`.loaded` outcome so the store can quarantine + signal.
final class CustomFilmLibraryDecodeTests: XCTestCase {
    private let encoder = JSONEncoder()

    private func encodedLibrary(_ films: [FilmIdentity]) throws -> String {
        let data = try encoder.encode(PersistentCustomFilmLibrarySnapshot(films: films))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func twoFilms() -> [FilmIdentity] {
        [CustomFilmTestSupport.makeCustomFilm(id: "cf-1", stockName: "Alpha"),
         CustomFilmTestSupport.makeCustomFilm(id: "cf-2", stockName: "Beta")]
    }

    func test_validLibrary_loadsAllRecords() throws {
        let json = try encodedLibrary(twoFilms())
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.droppedRecordCount, 0)
        XCTAssertEqual(result.snapshot.films.map(\.id), ["cf-1", "cf-2"])
    }

    func test_unknownRuleKind_dropsOnlyThatFilm() throws {
        // Corrupt the first film's reciprocity rule kind. The second film,
        // structurally identical, must still load.
        let json = try encodedLibrary(twoFilms())
            .replacingFirstOccurrence(of: "\"kind\":\"formula\"", with: "\"kind\":\"quantumFlux\"")
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.droppedRecordCount, 1)
        XCTAssertEqual(result.snapshot.films.map(\.id), ["cf-2"])
    }

    func test_unknownAuthorityEnum_dropsOnlyThatFilm() throws {
        let json = try encodedLibrary(twoFilms())
            .replacingFirstOccurrence(of: "\"authority\":\"userDefined\"", with: "\"authority\":\"martian\"")
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.snapshot.films.map(\.id), ["cf-2"])
    }

    func test_unknownFilmKindEnum_dropsOnlyThatFilm() throws {
        let json = try encodedLibrary(twoFilms())
            .replacingFirstOccurrence(of: "\"kind\":\"custom\"", with: "\"kind\":\"hologram\"")
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.snapshot.films.map(\.id), ["cf-2"])
    }

    func test_duplicateIds_collapseFirstValidWins() throws {
        let dup = [CustomFilmTestSupport.makeCustomFilm(id: "dup", stockName: "First"),
                   CustomFilmTestSupport.makeCustomFilm(id: "dup", stockName: "Second")]
        let json = try encodedLibrary(dup)
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.droppedRecordCount, 1)
        XCTAssertEqual(result.snapshot.films.map(\.canonicalStockName), ["First"])
    }

    func test_futureSchemaVersion_rejectsWholePayload() throws {
        let json = try encodedLibrary(twoFilms())
            .replacingFirstOccurrence(of: "\"schemaVersion\":1", with: "\"schemaVersion\":999")
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .versionRejected)
        XCTAssertTrue(result.snapshot.films.isEmpty)
    }

    func test_missingSchemaVersion_acceptedAsLegacyV1() throws {
        let json = try encodedLibrary(twoFilms())
            .replacingFirstOccurrence(of: ",\"schemaVersion\":1", with: "")
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.snapshot.films.map(\.id), ["cf-1", "cf-2"])
    }

    func test_malformedRoot_reportsMalformed() {
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data("not json".utf8))
        XCTAssertEqual(result.outcome, .malformed)
        XCTAssertTrue(result.snapshot.films.isEmpty)
    }

    func test_missingFilmsKey_reportsMalformed() {
        // The encoder always writes `films` (empty when none), so an absent
        // key is corruption, not an empty library.
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(#"{"schemaVersion":1}"#.utf8))
        XCTAssertEqual(result.outcome, .malformed)
        XCTAssertTrue(result.snapshot.films.isEmpty)
    }

    func test_explicitEmptyFilmsArray_isLoadedEmpty() {
        let result = PersistentCustomFilmLibrarySnapshot.decode(from: Data(#"{"films":[],"schemaVersion":1}"#.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertTrue(result.snapshot.films.isEmpty)
    }
}

private extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
