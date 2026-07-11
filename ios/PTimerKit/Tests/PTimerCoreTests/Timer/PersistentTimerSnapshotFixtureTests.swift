// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

/// Regression gate for PTIMER-215. `frozenPayload` is a byte-exact
/// capture of the CURRENT (pre-schema-evolution-hardening) timer-state
/// on-disk format — note it carries no `schemaVersion` field, matching
/// what shipping builds have written. The hardened decoder must decode
/// this legacy payload to identical domain values (missing version is
/// accepted as the legacy v1).
final class PersistentTimerSnapshotFixtureTests: XCTestCase {
    /// Captured from the shipping `JSONEncoder` (sorted keys) before any
    /// PTIMER-215 change. Do not regenerate — regenerating defeats the
    /// point of a frozen fixture (it would track the decoder instead of
    /// gating it).
    static let frozenPayload = #"""
    {"timers":[{"duration":120,"expectedCompletionAt":700000120,"id":"11111111-1111-1111-1111-111111111111","startDate":700000000,"status":"running"},{"duration":90,"id":"22222222-2222-2222-2222-222222222222","pausedAt":700000045,"pausedRemainingDuration":45,"startDate":700000000,"status":"paused"},{"completedAt":700000060,"duration":60,"id":"33333333-3333-3333-3333-333333333333","startDate":700000000,"status":"completed"},{"completedAt":700000030,"duration":200,"id":"44444444-4444-4444-4444-444444444444","pausedRemainingDuration":170,"startDate":700000000,"status":"canceled"}]}
    """#

    func test_frozenLegacyPayload_decodesToExpectedDomainValues() throws {
        let data = Data(Self.frozenPayload.utf8)
        let snapshot = try JSONDecoder().decode(PersistentTimerCollectionSnapshot.self, from: data)

        XCTAssertEqual(snapshot.timers.count, 4)

        let byID = Dictionary(uniqueKeysWithValues: snapshot.timers.map { ($0.id.uuidString, $0) })

        let running = try XCTUnwrap(byID["11111111-1111-1111-1111-111111111111"])
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(running.duration, 120)
        XCTAssertEqual(running.expectedCompletionAt,
                       Date(timeIntervalSinceReferenceDate: 700_000_120))

        let paused = try XCTUnwrap(byID["22222222-2222-2222-2222-222222222222"])
        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(paused.pausedRemainingDuration, 45)
        XCTAssertEqual(paused.pausedAt, Date(timeIntervalSinceReferenceDate: 700_000_045))

        let completed = try XCTUnwrap(byID["33333333-3333-3333-3333-333333333333"])
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.completedAt, Date(timeIntervalSinceReferenceDate: 700_000_060))

        let canceled = try XCTUnwrap(byID["44444444-4444-4444-4444-444444444444"])
        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(canceled.pausedRemainingDuration, 170)
        XCTAssertEqual(canceled.completedAt, Date(timeIntervalSinceReferenceDate: 700_000_030))
    }
}
