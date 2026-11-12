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
        XCTAssertTrue(try store.load().isEmpty)
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
            PersistentShootingCollection(id: UUID(), title: "Two", createdAt: Date(), records: [first])
        ]
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ShootingCollectionCodec.encode(collections)) as? [String: Any])
        var raw = try XCTUnwrap(root["collections"] as? [[String: Any]])
        var records = try XCTUnwrap(raw[0]["records"] as? [[String: Any]])
        records.insert(["outcome": "unknown"], at: 1)
        raw[0]["records"] = records
        root["collections"] = raw
        let decoded = ShootingCollectionCodec.decode(try JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(decoded.outcome, .degraded)
        XCTAssertEqual(decoded.droppedRecordCount, 2)
        XCTAssertEqual(decoded.snapshot[0].records.map(\.id), [first.id, second.id])
        XCTAssertTrue(decoded.snapshot[1].records.isEmpty)
    }

    func testCodecRejectsUnknownVersionAndMalformedRootButAcceptsMissingVersion() throws {
        XCTAssertEqual(ShootingCollectionCodec.decode(Data("{\"schemaVersion\":2,\"collections\":[]}".utf8)).outcome, .versionRejected)
        XCTAssertEqual(ShootingCollectionCodec.decode(Data("{}".utf8)).outcome, .malformed)
        XCTAssertEqual(ShootingCollectionCodec.decode(Data("{\"collections\":[]}".utf8)).outcome, .loaded)
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
    func load() throws -> [PersistentShootingCollection] {
        if failLoad { throw CocoaError(.fileReadUnknown) }
        return data.map { ShootingCollectionCodec.decode($0).snapshot } ?? []
    }
    func save(_ collections: [PersistentShootingCollection]) throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        data = try ShootingCollectionCodec.encode(collections)
        saveCount += 1
    }
}
