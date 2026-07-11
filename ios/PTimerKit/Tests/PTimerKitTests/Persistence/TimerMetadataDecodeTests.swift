// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// PTIMER-215 per-record decode behavior for the timer-metadata collection.
/// A single undecodable entry drops only itself; duplicate ids collapse
/// first-valid-wins (which also removes the duplicate-key trap the restore
/// path's dictionary build would otherwise hit). Version-gate and malformed
/// failures reject the whole payload; `nextTimerOrder` is preserved.
final class TimerMetadataDecodeTests: XCTestCase {
    private func snapshot(id: String, order: Int) -> PersistentTimerMetadataSnapshot {
        PersistentTimerMetadataSnapshot(
            id: UUID(uuidString: id)!, order: order, name: "Shot \(order)", basisSummary: "\(order)s"
        )
    }

    private func encoded(nextTimerOrder: Int, _ snaps: [PersistentTimerMetadataSnapshot]) throws -> String {
        let data = try JSONEncoder().encode(
            PersistentTimerMetadataCollection(nextTimerOrder: nextTimerOrder, timers: snaps)
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func test_validCollection_loadsAllAndPreservesNextOrder() throws {
        let json = try encoded(nextTimerOrder: 7, [
            snapshot(id: "11111111-1111-1111-1111-111111111111", order: 1),
            snapshot(id: "22222222-2222-2222-2222-222222222222", order: 2)
        ])
        let result = PersistentTimerMetadataCollection.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.snapshot.nextTimerOrder, 7)
        XCTAssertEqual(result.snapshot.timers.count, 2)
    }

    func test_undecodableRecord_dropsOnlyThatEntry() throws {
        // Corrupt the first entry's id so it is not a valid UUID.
        let json = try encoded(nextTimerOrder: 3, [
            snapshot(id: "11111111-1111-1111-1111-111111111111", order: 1),
            snapshot(id: "22222222-2222-2222-2222-222222222222", order: 2)
        ]).replacingOccurrences(of: "11111111-1111-1111-1111-111111111111", with: "not-a-uuid")
        let result = PersistentTimerMetadataCollection.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.droppedRecordCount, 1)
        XCTAssertEqual(result.snapshot.timers.map(\.order), [2])
        XCTAssertEqual(result.snapshot.nextTimerOrder, 3)
    }

    func test_duplicateIds_collapseFirstValidWins() throws {
        let json = try encoded(nextTimerOrder: 2, [
            snapshot(id: "11111111-1111-1111-1111-111111111111", order: 1),
            snapshot(id: "11111111-1111-1111-1111-111111111111", order: 9)
        ])
        let result = PersistentTimerMetadataCollection.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .degraded)
        XCTAssertEqual(result.snapshot.timers.map(\.order), [1])
    }

    func test_futureSchemaVersion_rejectsWholePayload() throws {
        let json = try encoded(nextTimerOrder: 2, [snapshot(id: "11111111-1111-1111-1111-111111111111", order: 1)])
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":999")
        let result = PersistentTimerMetadataCollection.decode(from: Data(json.utf8))
        XCTAssertEqual(result.outcome, .versionRejected)
        XCTAssertTrue(result.snapshot.timers.isEmpty)
    }

    func test_missingSchemaVersion_acceptedAsLegacyV1() {
        // The legacy shipping format carried no version field.
        let legacy = #"""
        {"nextTimerOrder":5,"timers":[{"basisSummary":"1s","id":"11111111-1111-1111-1111-111111111111","name":"Shot 1","order":1}]}
        """#
        let result = PersistentTimerMetadataCollection.decode(from: Data(legacy.utf8))
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.snapshot.nextTimerOrder, 5)
        XCTAssertEqual(result.snapshot.timers.count, 1)
    }

    func test_malformedRoot_reportsMalformed() {
        let result = PersistentTimerMetadataCollection.decode(from: Data("not json".utf8))
        XCTAssertEqual(result.outcome, .malformed)
        XCTAssertTrue(result.snapshot.timers.isEmpty)
    }
}
