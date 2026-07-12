// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
import PTimerKit
@testable import PTimer

/// PTIMER-215 quarantine state-transition coverage for the concrete
/// `UserDefaultsCustomFilmLibraryStore`. A decode failure copies the raw
/// payload to a sibling quarantine key at load time; normal saves and
/// live-snapshot clears never touch it; a later failed load replaces it. No
/// recovery-reset API is introduced in this ticket.
final class CustomFilmLibraryQuarantineTests: XCTestCase {
    private let mainKey = "ptimer.exposure-calculator.custom-films.snapshot"
    private var quarantineKey: String { mainKey + ".quarantine" }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ptimer.tests.custom-film-quarantine.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return (defaults, suiteName)
    }

    private func validPayload(ids: [String]) throws -> Data {
        let films = ids.map { CustomFilmTestSupport.makeCustomFilm(id: $0, stockName: $0.uppercased()) }
        return try JSONEncoder().encode(PersistentCustomFilmLibrarySnapshot(films: films))
    }

    /// A two-film payload whose first film has a corrupted rule kind, so a
    /// per-record decode drops it and keeps the second.
    private func partiallyCorruptPayload() throws -> Data {
        let data = try validPayload(ids: ["cf-1", "cf-2"])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let corrupted = json.replacingOccurrences(
            of: "\"kind\":\"formula\"", with: "\"kind\":\"quantumFlux\"",
            options: [], range: json.range(of: "\"kind\":\"formula\"")
        )
        return Data(corrupted.utf8)
    }

    func test_malformedLoad_quarantinesRawPayload() throws {
        let (defaults, _) = try makeDefaults()
        let raw = Data("not json".utf8)
        defaults.set(raw, forKey: mainKey)

        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults, snapshotKey: mainKey)
        let snapshot = store.loadSnapshot()

        XCTAssertEqual(snapshot?.films.isEmpty, true)
        XCTAssertEqual(defaults.data(forKey: quarantineKey), raw)
    }

    func test_partialDecode_recoversValidFilmsAndQuarantinesOriginal() throws {
        let (defaults, _) = try makeDefaults()
        let raw = try partiallyCorruptPayload()
        defaults.set(raw, forKey: mainKey)

        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults, snapshotKey: mainKey)
        let snapshot = store.loadSnapshot()

        XCTAssertEqual(snapshot?.films.map(\.id), ["cf-2"])
        XCTAssertEqual(defaults.data(forKey: quarantineKey), raw)
    }

    func test_secondFailureReplacesQuarantine() throws {
        let (defaults, _) = try makeDefaults()
        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults, snapshotKey: mainKey)

        let payloadA = Data("bad payload A".utf8)
        defaults.set(payloadA, forKey: mainKey)
        _ = store.loadSnapshot()
        XCTAssertEqual(defaults.data(forKey: quarantineKey), payloadA)

        let payloadB = Data("different bad payload B".utf8)
        defaults.set(payloadB, forKey: mainKey)
        _ = store.loadSnapshot()
        XCTAssertEqual(defaults.data(forKey: quarantineKey), payloadB)
    }

    func test_validLoadAfterFailure_keepsExistingQuarantine() throws {
        let (defaults, _) = try makeDefaults()
        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults, snapshotKey: mainKey)

        let bad = Data("bad".utf8)
        defaults.set(bad, forKey: mainKey)
        _ = store.loadSnapshot()
        XCTAssertEqual(defaults.data(forKey: quarantineKey), bad)

        // A subsequent healthy save + load must not clear the quarantine.
        defaults.set(try validPayload(ids: ["recovered"]), forKey: mainKey)
        let reloaded = store.loadSnapshot()
        XCTAssertEqual(reloaded?.films.map(\.id), ["recovered"])
        XCTAssertEqual(defaults.data(forKey: quarantineKey), bad)
    }

    func test_normalSaveDoesNotTouchQuarantine() throws {
        let (defaults, _) = try makeDefaults()
        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults, snapshotKey: mainKey)

        let bad = Data("bad".utf8)
        defaults.set(bad, forKey: mainKey)
        _ = store.loadSnapshot()

        store.saveSnapshot(PersistentCustomFilmLibrarySnapshot(
            films: [CustomFilmTestSupport.makeCustomFilm(id: "new", stockName: "New")]
        ))
        XCTAssertEqual(defaults.data(forKey: quarantineKey), bad)
        XCTAssertNotNil(defaults.data(forKey: mainKey))
    }

    func test_clearSnapshot_removesLiveKeyButKeepsQuarantine() throws {
        let (defaults, _) = try makeDefaults()
        let store = UserDefaultsCustomFilmLibraryStore(userDefaults: defaults, snapshotKey: mainKey)

        let bad = Data("bad".utf8)
        defaults.set(bad, forKey: mainKey)
        _ = store.loadSnapshot()
        XCTAssertNotNil(defaults.data(forKey: quarantineKey))

        // clearSnapshot is the "no live snapshot" operation, not a recovery
        // reset: the live key goes, the quarantine stays recoverable.
        store.clearSnapshot()
        XCTAssertNil(defaults.data(forKey: mainKey))
        XCTAssertEqual(defaults.data(forKey: quarantineKey), bad)
    }
}
