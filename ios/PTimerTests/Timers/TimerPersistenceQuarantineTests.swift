// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
import PTimerKit
@testable import PTimer

/// PTIMER-215 quarantine state-transition coverage for the concrete
/// timer-state and timer-metadata UserDefaults stores. A decode failure
/// copies the raw payload to a sibling quarantine key at load time; a normal
/// save never touches it; an explicit clear removes both keys.
final class TimerPersistenceQuarantineTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ptimer.tests.timer-quarantine.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    // MARK: - Timer state

    private func timerStatePayload(count: Int) throws -> Data {
        let ref = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let timers = (1...count).map { i in
            TimerState(
                id: UUID(uuidString: "0000000\(i)-0000-0000-0000-000000000000")!,
                duration: 120, startDate: ref, endDate: ref.addingTimeInterval(120),
                pausedRemainingTime: nil, pausedAt: nil, status: .running
            )
        }
        return try JSONEncoder().encode(PersistentTimerCollectionSnapshot(timers: timers))
    }

    func test_timerState_partialDecodeRecoversAndQuarantines() throws {
        let defaults = try makeDefaults()
        let key = "ptimer.timer-state.snapshot"
        // Corrupt the first timer's status; the second must survive.
        let valid = try timerStatePayload(count: 2)
        var json = try XCTUnwrap(String(data: valid, encoding: .utf8))
        json = json.replacingOccurrences(
            of: "\"status\":\"running\"", with: "\"status\":\"warping\"",
            options: [], range: json.range(of: "\"status\":\"running\"")
        )
        let raw = Data(json.utf8)
        defaults.set(raw, forKey: key)

        let store = UserDefaultsTimerPersistenceStore(userDefaults: defaults, snapshotKey: key)
        let snapshot = store.loadSnapshot()

        XCTAssertEqual(snapshot?.timers.count, 1)
        XCTAssertEqual(defaults.data(forKey: key + ".quarantine"), raw)
    }

    func test_timerState_clearRemovesLiveKeyButKeepsQuarantine() throws {
        let defaults = try makeDefaults()
        let key = "ptimer.timer-state.snapshot"
        let bad = Data("bad".utf8)
        defaults.set(bad, forKey: key)
        let store = UserDefaultsTimerPersistenceStore(userDefaults: defaults, snapshotKey: key)
        _ = store.loadSnapshot()
        XCTAssertNotNil(defaults.data(forKey: key + ".quarantine"))

        // A normal remove-to-empty (what TimerRuntime does) must not destroy
        // the quarantine.
        store.clearSnapshot()
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertEqual(defaults.data(forKey: key + ".quarantine"), bad)
    }

    func test_timerState_normalSaveKeepsQuarantine() throws {
        let defaults = try makeDefaults()
        let key = "ptimer.timer-state.snapshot"
        let bad = Data("bad".utf8)
        defaults.set(bad, forKey: key)
        let store = UserDefaultsTimerPersistenceStore(userDefaults: defaults, snapshotKey: key)
        _ = store.loadSnapshot()

        store.saveSnapshot(try JSONDecoder().decode(
            PersistentTimerCollectionSnapshot.self, from: try timerStatePayload(count: 1)
        ))
        XCTAssertEqual(defaults.data(forKey: key + ".quarantine"), bad)
    }

    // MARK: - Timer metadata

    private func metadataPayload(ids: [String]) throws -> Data {
        let snaps = ids.enumerated().map { index, id in
            PersistentTimerMetadataSnapshot(
                id: UUID(uuidString: id)!, order: index + 1,
                name: "Shot \(index + 1)", basisSummary: "\(index + 1)s"
            )
        }
        return try JSONEncoder().encode(
            PersistentTimerMetadataCollection(nextTimerOrder: ids.count + 1, timers: snaps)
        )
    }

    func test_timerMetadata_partialDecodeRecoversAndQuarantines() throws {
        let defaults = try makeDefaults()
        let key = "ptimer.timer-metadata.snapshot"
        let valid = try metadataPayload(ids: [
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222"
        ])
        let json = try XCTUnwrap(String(data: valid, encoding: .utf8))
            .replacingOccurrences(of: "11111111-1111-1111-1111-111111111111", with: "not-a-uuid")
        let raw = Data(json.utf8)
        defaults.set(raw, forKey: key)

        let store = UserDefaultsTimerMetadataStore(userDefaults: defaults, snapshotKey: key)
        let snapshot = store.loadSnapshot()

        XCTAssertEqual(snapshot?.timers.count, 1)
        XCTAssertEqual(defaults.data(forKey: key + ".quarantine"), raw)
    }

    func test_timerMetadata_clearRemovesLiveKeyButKeepsQuarantine() throws {
        let defaults = try makeDefaults()
        let key = "ptimer.timer-metadata.snapshot"
        let bad = Data("bad".utf8)
        defaults.set(bad, forKey: key)
        let store = UserDefaultsTimerMetadataStore(userDefaults: defaults, snapshotKey: key)
        _ = store.loadSnapshot()
        XCTAssertNotNil(defaults.data(forKey: key + ".quarantine"))

        store.clearSnapshot()
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertEqual(defaults.data(forKey: key + ".quarantine"), bad)
    }

    // MARK: - Runtime empty-persist path (PTIMER-215 review Blocker 1)

    /// Restoring a timer-state payload whose every record is undecodable
    /// yields an empty runtime, which persists empty via clearSnapshot(). The
    /// quarantine written during that same load must survive — otherwise the
    /// only recoverable copy is destroyed in the load cycle that created it.
    @MainActor
    func test_timerRuntimeRestore_allRecordsDropped_keepsQuarantine() throws {
        let defaults = try makeDefaults()
        let key = "ptimer.timer-state.snapshot"
        // One timer with an unknown status → the only record is dropped, so
        // the restored collection is empty.
        let ref = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let one = PersistentTimerCollectionSnapshot(timers: [
            TimerState(
                id: UUID(), duration: 120, startDate: ref, endDate: ref.addingTimeInterval(120),
                pausedRemainingTime: nil, pausedAt: nil, status: .running
            )
        ])
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(one), encoding: .utf8))
            .replacingOccurrences(of: "\"status\":\"running\"", with: "\"status\":\"warping\"")
        let raw = Data(json.utf8)
        defaults.set(raw, forKey: key)

        let store = UserDefaultsTimerPersistenceStore(userDefaults: defaults, snapshotKey: key)
        // Constructing the runtime restores (all dropped → empty) and then
        // persists the empty result via clearSnapshot().
        let runtime = TimerRuntime(persistenceStore: store)
        XCTAssertTrue(runtime.timers.isEmpty)

        XCTAssertEqual(defaults.data(forKey: key + ".quarantine"), raw)
    }
}
