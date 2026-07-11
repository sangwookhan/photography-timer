// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

/// PTIMER-215 per-record decode behavior for the timer-state collection.
/// A timer carrying an unknown status token drops only itself; the rest of
/// the collection survives. Version-gate and malformed-root failures reject
/// the whole payload. All failure modes report a non-`.loaded` outcome.
final class PersistentTimerCollectionDecodeTests: XCTestCase {
    private let ref = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func running(_ idLast: Int) -> TimerState {
        TimerState(
            id: UUID(uuidString: "0000000\(idLast)-0000-0000-0000-000000000000")!,
            duration: 120, startDate: ref, endDate: ref.addingTimeInterval(120),
            pausedRemainingTime: nil, pausedAt: nil, status: .running
        )
    }

    private func encoded(_ timers: [TimerState]) throws -> String {
        let data = try JSONEncoder().encode(PersistentTimerCollectionSnapshot(timers: timers))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func test_validCollection_loadsAll() throws {
        let result = PersistentTimerCollectionSnapshot.decode(from: Data(try encoded([running(1), running(2)]).utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.snapshot.timers.count, 2)
    }

    func test_unknownStatusToken_dropsOnlyThatTimer() throws {
        let json = try encoded([running(1), running(2)])
            .replacingFirstOccurrence(of: "\"status\":\"running\"", with: "\"status\":\"warping\"")
        let result = PersistentTimerCollectionSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.droppedRecordCount, 1)
        XCTAssertEqual(result.snapshot.timers.count, 1)
    }

    func test_duplicateIds_collapseFirstValidWins() throws {
        let result = PersistentTimerCollectionSnapshot.decode(from: Data(try encoded([running(1), running(1)]).utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.snapshot.timers.count, 1)
    }

    func test_futureSchemaVersion_rejectsWholePayload() throws {
        let json = try encoded([running(1)])
            .replacingFirstOccurrence(of: "\"schemaVersion\":1", with: "\"schemaVersion\":999")
        let result = PersistentTimerCollectionSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .versionRejected)
        XCTAssertTrue(result.snapshot.timers.isEmpty)
    }

    func test_missingSchemaVersion_acceptedAsLegacyV1() throws {
        // The legacy shipping format carried no version field.
        let legacy = #"""
        {"timers":[{"duration":120,"expectedCompletionAt":700000120,"id":"00000001-0000-0000-0000-000000000000","startDate":700000000,"status":"running"}]}
        """#
        let result = PersistentTimerCollectionSnapshot.decode(from: Data(legacy.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.snapshot.timers.count, 1)
    }

    func test_malformedRoot_reportsMalformed() {
        let result = PersistentTimerCollectionSnapshot.decode(from: Data("not json".utf8))
        XCTAssertEqual(result.outcome, .malformed)
        XCTAssertTrue(result.snapshot.timers.isEmpty)
    }
}

private extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
