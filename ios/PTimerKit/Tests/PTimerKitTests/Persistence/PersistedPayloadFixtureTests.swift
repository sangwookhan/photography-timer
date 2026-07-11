// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Regression gate for PTIMER-215. The `frozen*` strings are byte-exact
/// captures of the CURRENT on-disk format for the custom film library
/// and the timer-metadata collection, taken before any
/// schema-evolution-hardening change. The custom-film payload carries
/// `schemaVersion: 1`; the timer-metadata payload (matching shipping
/// builds) carries no version field. The hardened decoders must decode
/// both to identical domain values.
final class PersistedPayloadFixtureTests: XCTestCase {
    /// Captured from the shipping `JSONEncoder` (sorted keys) before any
    /// PTIMER-215 change. Do not regenerate.
    static let frozenCustomFilm = #"""
    {"films":[{"aliases":[],"canonicalStockName":"Alpha","id":"cf-1","iso":100,"kind":"custom","productionStatus":"unknown","profiles":[{"id":"cf-1-profile","name":"Profile for Alpha","notes":[],"rules":[{"formula":{"additionalAdjustments":[],"formula":{"coefficientSeconds":1,"exponent":1.3,"formulaFamily":"modifiedSchwarzschild","noCorrectionThroughSeconds":1,"offsetSeconds":0,"referenceMeteredTimeSeconds":1},"notes":[]},"kind":"formula"}],"source":{"authority":"userDefined","confidence":"unknown","kind":"userDefined","publisher":""},"sourceEvidence":[],"userMetadata":{"customSourceType":"userDefined","notes":[],"tags":[]}}],"userMetadata":{"customSourceType":"userDefined","notes":[],"tags":[]}},{"aliases":[],"canonicalStockName":"Beta","id":"cf-2","iso":400,"kind":"custom","productionStatus":"unknown","profiles":[{"id":"cf-2-profile","name":"Profile for Beta","notes":[],"rules":[{"formula":{"additionalAdjustments":[],"formula":{"coefficientSeconds":1,"exponent":1.3,"formulaFamily":"modifiedSchwarzschild","noCorrectionThroughSeconds":1,"offsetSeconds":0,"referenceMeteredTimeSeconds":1},"notes":[]},"kind":"formula"}],"source":{"authority":"userDefined","confidence":"unknown","kind":"userDefined","publisher":""},"sourceEvidence":[],"userMetadata":{"customSourceType":"userDefined","notes":[],"tags":[]}}],"userMetadata":{"customSourceType":"userDefined","notes":[],"tags":[]}}],"schemaVersion":1}
    """#

    static let frozenTimerMetadata = #"""
    {"nextTimerOrder":5,"timers":[{"baseShutterSeconds":0.008,"basisSummary":"1\/125 · f8","exposureSourceRaw":"meteredExposure","filmDisplayName":"Alpha","id":"11111111-1111-1111-1111-111111111111","name":"Shot 1","ndStops":3,"order":1},{"basisSummary":"2s","customProfileSummary":"Beta · ISO 400","id":"22222222-2222-2222-2222-222222222222","name":"Shot 2","order":2}]}
    """#

    func test_frozenCustomFilmPayload_decodesToExpectedDomainValues() throws {
        let data = Data(Self.frozenCustomFilm.utf8)
        let snapshot = try JSONDecoder().decode(PersistentCustomFilmLibrarySnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.films.map(\.id), ["cf-1", "cf-2"])
        XCTAssertEqual(snapshot.films.map(\.canonicalStockName), ["Alpha", "Beta"])
        XCTAssertEqual(snapshot.films.map(\.iso), [100, 400])

        let alpha = snapshot.films[0]
        XCTAssertEqual(alpha.kind, .custom)
        let profile = try XCTUnwrap(alpha.profiles.first)
        XCTAssertEqual(profile.source.authority, .userDefined)
        XCTAssertEqual(profile.rules.count, 1)
        XCTAssertEqual(profile.rules.first?.kind, .formula)
    }

    func test_frozenTimerMetadataPayload_decodesToExpectedDomainValues() throws {
        let data = Data(Self.frozenTimerMetadata.utf8)
        let snapshot = try JSONDecoder().decode(PersistentTimerMetadataCollection.self, from: data)

        XCTAssertEqual(snapshot.nextTimerOrder, 5)
        XCTAssertEqual(snapshot.timers.map(\.id.uuidString),
                       ["11111111-1111-1111-1111-111111111111",
                        "22222222-2222-2222-2222-222222222222"])

        let first = snapshot.timers[0]
        XCTAssertEqual(first.order, 1)
        XCTAssertEqual(first.name, "Shot 1")
        XCTAssertEqual(first.basisSummary, "1/125 · f8")
        XCTAssertEqual(first.filmDisplayName, "Alpha")
        XCTAssertEqual(first.exposureSourceRaw, "meteredExposure")
        XCTAssertEqual(first.ndStops, 3)
        XCTAssertEqual(first.baseShutterSeconds, 0.008)

        let second = snapshot.timers[1]
        XCTAssertEqual(second.customProfileSummary, "Beta · ISO 400")
    }
}
