// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit
import PTimerCore

final class ShootingCollectionTests: XCTestCase {
    @MainActor
    func testCollectionRoundTripsCapturedRecordAfterHistoryRemoval() throws {
        let runtime = RuntimeBackedTimerManaging(dateProvider: { Date(timeIntervalSince1970: 100) })
        let timers = TimerWorkspaceModel(
            timerManager: runtime, metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            defaultName: { _ in "Manual" }
        )
        let id = try XCTUnwrap(timers.startTimer(
            duration: 30, name: "Captured", basisSummary: "Original basis",
            filmDisplayName: "Original film", selectedModelLabel: "Original model", ndStops: 6
        ))
        runtime.tick(now: Date(timeIntervalSince1970: 140))
        let store = ArchiveStore()
        let model = ShootingCollectionModel(store: store)
        let collectionID = try model.create(from: timers.timers, at: Date(), timeZone: .gmt).get()
        timers.clearCompletedTimers()
        XCTAssertTrue(timers.timers.isEmpty)
        let restored = ShootingCollectionModel(store: store)
        XCTAssertEqual(restored.collections.first?.id, collectionID)
        let record = try XCTUnwrap(restored.collection(containing: id)?.records.first)
        XCTAssertEqual(record.metadata.filmDisplayName, "Original film")
        XCTAssertEqual(record.metadata.selectedModelLabel, "Original model")
        XCTAssertEqual(record.metadata.ndStops, 6)
        XCTAssertEqual(record.terminalDate, Date(timeIntervalSince1970: 130))
        XCTAssertEqual(record.outcome, .completed)
    }

    @MainActor
    func testSaveFailureDoesNotPublishOrClaimMembershipAndRetrySucceeds() throws {
        let store = ArchiveStore()
        store.failSave = true
        let model = ShootingCollectionModel(store: store)
        let timer = makeTimer()
        XCTAssertEqual(model.create(from: [timer], at: Date(), timeZone: .gmt), .failure(.saveFailed))
        XCTAssertTrue(model.collections.isEmpty)
        XCTAssertNil(model.collection(containing: timer.id))
        XCTAssertTrue(try store.load().collections.isEmpty)
        store.failSave = false
        _ = try model.create(from: [timer], at: Date(), timeZone: .gmt).get()
        XCTAssertEqual(model.collections.count, 1)
    }

    @MainActor
    func testEventCannotBelongToTwoCollectionsAfterRelaunch() throws {
        let store = ArchiveStore()
        let timer = makeTimer()
        _ = try ShootingCollectionModel(store: store).create(from: [timer], at: Date(), timeZone: .gmt).get()
        let restored = ShootingCollectionModel(store: store)
        XCTAssertEqual(restored.create(from: [timer], at: Date(), timeZone: .gmt), .failure(.alreadyCollected))
        XCTAssertEqual(restored.collections.count, 1)
        XCTAssertNotNil(restored.collection(containing: timer.id))
    }

    @MainActor
    func testSelectionValidationAndReadFailureDoNotOverwriteArchive() {
        let store = ArchiveStore()
        let model = ShootingCollectionModel(store: store)
        let timer = makeTimer()
        XCTAssertEqual(model.create(from: [], at: Date(), timeZone: .gmt), .failure(.invalidSelection))
        XCTAssertEqual(model.create(from: [timer, timer], at: Date(), timeZone: .gmt), .failure(.invalidSelection))
        XCTAssertEqual(model.create(from: [makeTimer(status: .running)], at: Date(), timeZone: .gmt), .failure(.invalidSelection))
        store.failLoad = true
        let unavailable = ShootingCollectionModel(store: store)
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertEqual(unavailable.create(from: [timer], at: Date(), timeZone: .gmt), .failure(.unavailable))
        XCTAssertEqual(store.saveCount, 0)
    }

    @MainActor
    func testEarliestStartDeterminesFixedTitleAndRecordOrdering() throws {
        let store = ArchiveStore()
        let early = makeTimer(start: 7_200)
        let late = makeTimer(start: 200_000, status: .canceled)
        let model = ShootingCollectionModel(store: store)
        _ = try model.create(from: [late, early], at: Date(), timeZone: XCTUnwrap(TimeZone(secondsFromGMT: -28_800))).get()
        XCTAssertEqual(model.collections[0].title, "1969-12-31")
        XCTAssertEqual(model.collections[0].records.map(\.id), [early.id, late.id])
        XCTAssertEqual(ShootingCollectionModel(store: store).collections[0].title, "1969-12-31")
        XCTAssertEqual(model.collections[0].records.last?.remainingAtCancel, 12)
    }

    @MainActor
    func testRepeatedTimerHasIndependentMembershipAndActiveTimerIsUntouched() throws {
        let runtime = RuntimeBackedTimerManaging(dateProvider: { Date(timeIntervalSince1970: 100) })
        let timers = TimerWorkspaceModel(timerManager: runtime, metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(), defaultName: { _ in "Manual" })
        let id = try XCTUnwrap(timers.startTimer(duration: 30, name: "Manual", basisSummary: "Manual timer"))
        runtime.cancel(id: id)
        let source = try XCTUnwrap(timers.timers.first)
        let repeatedID = try XCTUnwrap(timers.startTimer(cloning: source))
        let before = runtime.timers
        let archive = ShootingCollectionModel(store: ArchiveStore())
        _ = try archive.create(from: [source], at: Date(), timeZone: .gmt).get()
        XCTAssertEqual(runtime.timers, before)
        XCTAssertNil(archive.collection(containing: repeatedID))
        timers.removeTimer(id: id)
        XCTAssertEqual(timers.timers.count, 1)
        XCTAssertNotNil(archive.collection(containing: id))
    }

    func testLegacyMetadataAndManualRecordsDoNotInventMissingContext() throws {
        let record = try XCTUnwrap(PersistentShootingRecord(timer: makeTimer()))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        payload["metadata"] = ["id": record.id.uuidString, "order": 0, "name": "Legacy", "basisSummary": "Historical text"]
        let restored = try JSONDecoder().decode(PersistentShootingRecord.self, from: JSONSerialization.data(withJSONObject: payload))
        let display = ShootingRecordPresenter.display(restored)
        XCTAssertNil(restored.metadata.cameraSlotIDRaw)
        XCTAssertNil(restored.metadata.filmDisplayName)
        XCTAssertNil(restored.metadata.exposureSourceRaw)
        XCTAssertTrue(display.fields.contains { $0.value == "Historical text" })
        XCTAssertFalse(display.fields.contains { ["Camera", "Film", "Exposure source"].contains($0.label) })
    }

    func testCodecIsolatesMalformedRecordAndDuplicateMembership() throws {
        let first = try XCTUnwrap(PersistentShootingRecord(timer: makeTimer()))
        let second = try XCTUnwrap(PersistentShootingRecord(timer: makeTimer()))
        let collections = [
            PersistentShootingCollection(id: UUID(), title: "One", createdAt: Date(), records: [first, second]),
            PersistentShootingCollection(id: UUID(), title: "Two", createdAt: Date(), records: [first]),
        ]
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ShootingCollectionCodec.encode(PersistentShootingArchive(collections: collections))) as? [String: Any])
        var raw = try XCTUnwrap(root["collections"] as? [[String: Any]])
        var records = try XCTUnwrap(raw[0]["records"] as? [[String: Any]])
        records.insert(["outcome": "unknown"], at: 1)
        raw[0]["records"] = records
        root["collections"] = raw
        let decoded = ShootingCollectionCodec.decode(try JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(decoded.outcome, .degraded)
        XCTAssertEqual(decoded.droppedRecordCount, 2)
        XCTAssertEqual(decoded.snapshot.collections[0].records.map(\.id), [first.id, second.id])
        XCTAssertTrue(decoded.snapshot.collections[1].records.isEmpty)
    }

    func testCodecRejectsUnknownVersionAndMalformedRootButAcceptsMissingVersion() throws {
        XCTAssertEqual(ShootingCollectionCodec.decode(Data("{\"schemaVersion\":99,\"collections\":[]}".utf8)).outcome, .versionRejected)
        XCTAssertEqual(ShootingCollectionCodec.decode(Data("{}".utf8)).outcome, .malformed)
        XCTAssertEqual(ShootingCollectionCodec.decode(Data("{\"collections\":[]}".utf8)).outcome, .loaded)
    }

    @MainActor
    func testRemovePreservesCaptureAndTimerListAndEmptyCollectionAfterRelaunch() throws {
        let runtime = RuntimeBackedTimerManaging(dateProvider: { Date(timeIntervalSince1970: 100) })
        let timers = TimerWorkspaceModel(timerManager: runtime, metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(), defaultName: { _ in "Manual" })
        let id = try XCTUnwrap(timers.startTimer(duration: 30, name: "Original", basisSummary: "Captured"))
        runtime.cancel(id: id)
        _ = timers.startTimer(duration: 90, name: "Still active", basisSummary: "Manual")
        let store = ArchiveStore()
        let model = ShootingCollectionModel(store: store)
        let source = try model.create(from: timers.timers.filter { $0.id == id }, at: Date(), timeZone: .gmt).get()
        let captured = try XCTUnwrap(model.record(id: id))
        let before = timers.timers
        try model.remove(recordIDs: [id], from: source).get()
        XCTAssertEqual(timers.timers, before, "Removal must not change Timer IDs, order, contents or runtime.")
        XCTAssertEqual(model.collections.count, 1)
        XCTAssertTrue(model.records(in: source).isEmpty)
        XCTAssertNil(model.collection(containing: id))
        XCTAssertEqual(model.uncollectedRecords, [captured])
        timers.removeTimer(id: id)
        let restored = ShootingCollectionModel(store: store)
        XCTAssertEqual(restored.uncollectedRecords, [captured])
        XCTAssertTrue(restored.records(in: source).isEmpty)
    }

    @MainActor
    func testBatchMoveIsAtomicOrderedAndPreservesCollectionIdentity() throws {
        let store = ArchiveStore()
        let model = ShootingCollectionModel(store: store)
        let early = makeTimer(start: 100)
        let late = makeTimer(start: 300, status: .canceled)
        let middle = makeTimer(start: 200)
        let source = try model.create(from: [late, early], at: Date(timeIntervalSince1970: 1), timeZone: .gmt).get()
        let target = try model.create(from: [middle], at: Date(timeIntervalSince1970: 2), timeZone: .gmt).get()
        let before = model.collections
        let writes = store.saveCount
        store.failSave = true
        XCTAssertThrowsError(try model.move(recordIDs: [early.id, late.id], from: source, to: target).get())
        XCTAssertEqual(model.collections, before)
        XCTAssertEqual(try store.load().collections, before)
        store.failSave = false
        try model.move(recordIDs: [early.id, late.id], from: source, to: target).get()
        XCTAssertEqual(store.saveCount, writes + 1, "A batch move saves exactly once.")
        let restored = ShootingCollectionModel(store: store)
        XCTAssertEqual(restored.records(in: target).map(\.id), [early.id, middle.id, late.id])
        XCTAssertTrue(restored.records(in: source).isEmpty)
        let movedTarget = try XCTUnwrap(restored.collections.first { $0.id == target })
        XCTAssertEqual(movedTarget.title, before.first { $0.id == target }?.title)
        XCTAssertEqual(movedTarget.createdAt, before.first { $0.id == target }?.createdAt)
        XCTAssertEqual(restored.collectedEventIDs.count, 3)
    }

    @MainActor
    func testFailedRemoveAndStaleOrInvalidSelectionsDoNotMutateArchive() throws {
        let store = ArchiveStore()
        let model = ShootingCollectionModel(store: store)
        let one = makeTimer()
        let two = makeTimer()
        let source = try model.create(from: [one, two], at: Date(), timeZone: .gmt).get()
        let before = try store.load()
        store.failSave = true
        XCTAssertThrowsError(try model.remove(recordIDs: [one.id, two.id], from: source).get())
        XCTAssertEqual(try store.load(), before)
        XCTAssertTrue(model.uncollectedRecords.isEmpty)
        store.failSave = false
        XCTAssertThrowsError(try model.remove(recordIDs: [one.id, UUID()], from: source).get())
        XCTAssertThrowsError(try model.remove(recordIDs: [], from: source).get())
        XCTAssertThrowsError(try model.move(recordIDs: [one.id], from: source, to: source).get())
        XCTAssertThrowsError(try model.move(recordIDs: [one.id], from: source, to: UUID()).get())
        XCTAssertEqual(try store.load(), before)
        try model.remove(recordIDs: [one.id], from: source).get()
        let writes = store.saveCount
        XCTAssertThrowsError(try model.remove(recordIDs: [one.id], from: source).get())
        XCTAssertEqual(store.saveCount, writes)
        store.failLoad = true
        let unavailable = ShootingCollectionModel(store: store)
        XCTAssertThrowsError(try unavailable.remove(recordIDs: [two.id], from: source).get())
        XCTAssertThrowsError(try unavailable.move(recordIDs: [two.id], from: source, to: UUID()).get())
        XCTAssertEqual(store.saveCount, writes)
    }

    @MainActor
    func testUncollectedReassignmentAndHistoryRecollectionReuseOriginalCapture() throws {
        let store = ArchiveStore()
        let model = ShootingCollectionModel(store: store)
        let original = makeTimer()
        let first = try model.create(from: [original], at: Date(), timeZone: .gmt).get()
        let capture = try XCTUnwrap(model.record(id: original.id))
        try model.remove(recordIDs: [original.id], from: first).get()
        store.failSave = true
        XCTAssertThrowsError(try model.move(recordIDs: [original.id], from: nil, to: first).get())
        XCTAssertEqual(model.uncollectedRecords, [capture])
        XCTAssertTrue(model.records(in: first).isEmpty)
        store.failSave = false
        try model.move(recordIDs: [original.id], from: nil, to: first).get()
        XCTAssertTrue(model.uncollectedRecords.isEmpty)
        XCTAssertEqual(model.records(in: first), [capture])
        try model.remove(recordIDs: [original.id], from: first).get()
        // History can carry a later display value; the archived capture must win.
        let changed = RunningTimerItem(id: original.id, order: 1, name: "Changed", basisSummary: "Changed",
            duration: 90, startDate: original.startDate, endDate: original.endDate,
            pausedRemainingTime: nil, pausedAt: nil, status: .completed, referenceDate: Date())
        let second = try model.create(from: [changed], at: Date(), timeZone: .gmt).get()
        XCTAssertEqual(model.records(in: second), [capture])
        XCTAssertTrue(model.uncollectedRecords.isEmpty)
        XCTAssertEqual(ShootingCollectionModel(store: store).collection(containing: original.id)?.id, second)
    }

    func testVersionOneArchiveMigratesWithoutLosingCapturedRecords() throws {
        let record = try XCTUnwrap(PersistentShootingRecord(timer: makeTimer()))
        let original = PersistentShootingCollection(id: UUID(), title: "Legacy", createdAt: Date(), records: [record])
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "collections": JSONSerialization.jsonObject(with: JSONEncoder().encode([original])),
        ])
        let decoded = ShootingCollectionCodec.decode(data)
        XCTAssertEqual(decoded.outcome, .loaded)
        XCTAssertEqual(decoded.snapshot.collections, [original])
        XCTAssertTrue(decoded.snapshot.uncollectedRecords.isEmpty)
        XCTAssertEqual(ShootingCollectionCodec.decode(try ShootingCollectionCodec.encode(decoded.snapshot)).snapshot, decoded.snapshot)
    }

    func testVersionTwoRequiresUncollectedArrayAndIsolatesDuplicatesAndBadRecords() throws {
        let one = try XCTUnwrap(PersistentShootingRecord(timer: makeTimer()))
        let two = try XCTUnwrap(PersistentShootingRecord(timer: makeTimer()))
        let collection = PersistentShootingCollection(id: UUID(), title: "One", createdAt: Date(), records: [one])
        let archive = PersistentShootingArchive(collections: [collection], uncollectedRecords: [one, two])
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ShootingCollectionCodec.encode(archive)) as? [String: Any])
        var raw = try XCTUnwrap(root["uncollectedRecords"] as? [Any])
        raw.append(["outcome": "unknown"])
        root["uncollectedRecords"] = raw
        let decoded = ShootingCollectionCodec.decode(try JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(decoded.outcome, .degraded)
        XCTAssertEqual(decoded.droppedRecordCount, 2)
        XCTAssertEqual(decoded.snapshot.uncollectedRecords, [two])
        XCTAssertEqual(decoded.snapshot.collections, [collection])
        root.removeValue(forKey: "uncollectedRecords")
        XCTAssertEqual(ShootingCollectionCodec.decode(try JSONSerialization.data(withJSONObject: root)).outcome, .malformed)
    }

    private func makeTimer(start: TimeInterval = 100, status: TimerStatus = .completed) -> RunningTimerItem {
        RunningTimerItem(
            id: UUID(), order: 1, name: "Manual", basisSummary: "Manual timer", duration: 30,
            startDate: Date(timeIntervalSince1970: start), endDate: Date(timeIntervalSince1970: start + 30),
            pausedRemainingTime: nil, pausedAt: nil, status: status, referenceDate: Date(),
            canceledRemainingTime: status == .canceled ? 12 : nil
        )
    }
}

private final class ArchiveStore: ShootingCollectionStoring {
    var data: Data?
    var failSave = false
    var failLoad = false
    var saveCount = 0
    func load() throws -> PersistentShootingArchive {
        if failLoad { throw CocoaError(.fileReadUnknown) }
        return data.map { ShootingCollectionCodec.decode($0).snapshot } ?? PersistentShootingArchive()
    }
    func save(_ archive: PersistentShootingArchive) throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        data = try ShootingCollectionCodec.encode(archive)
        saveCount += 1
    }
}
