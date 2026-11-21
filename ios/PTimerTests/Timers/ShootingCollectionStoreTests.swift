// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import SwiftUI
import PTimerCore
import PTimerKit
@testable import PTimer

@MainActor
final class ShootingCollectionStoreTests: XCTestCase {
    func testAtomicFileRoundTripAndUnavailableWriteLeavePreviousArchiveIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.json")
        let store = FileShootingCollectionStore(url: url)
        XCTAssertTrue(try store.load().collections.isEmpty)
        let model = ShootingCollectionModel(store: store)
        _ = try model.create(from: [sampleTimer()], at: Date(), timeZone: .gmt).get()
        XCTAssertEqual(try FileShootingCollectionStore(url: url).load().collections, model.collections)
        let bytes = try Data(contentsOf: url)
        // A regular file cannot be a directory: deterministic OS-boundary failure.
        let blocked = FileShootingCollectionStore(url: url.appendingPathComponent("child.json"))
        XCTAssertThrowsError(try blocked.save(PersistentShootingArchive(collections: model.collections)))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testMalformedArchiveIsQuarantinedAndCannotBeOverwrittenAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.json")
        let original = Data("{\"schemaVersion\":99,\"collections\":[]}".utf8)
        try original.write(to: url)
        let model = ShootingCollectionModel(store: FileShootingCollectionStore(url: url))
        XCTAssertFalse(model.isAvailable)
        XCTAssertEqual(model.create(from: [sampleTimer()], at: Date(), timeZone: .gmt), .failure(.unavailable))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("quarantine")), original)
    }

    func testActualSwiftUIListSelectionAndRecordSurfaces() throws {
        let model = ShootingCollectionModel(store: NoOpShootingCollectionStore())
        let timer = sampleTimer()
        _ = try model.create(from: [timer], at: Date(), timeZone: .gmt).get()
        let record = try XCTUnwrap(model.collections.first?.records.first)
        try capture(ShootingCollectionBrowser(model: model, history: [timer]), name: "Collections")
        try capture(ShootingCollectionBrowser(model: model, history: [timer], startsSelecting: true), name: "History selection")
        try capture(NavigationStack { ShootingRecordDetailView(record: record) }, name: "Captured record")
    }

    func testTimeSuggestionSurfacesBeforeAndAfterConfirmation() throws {
        let model = ShootingCollectionModel(store: NoOpShootingCollectionStore())
        let anchor = sampleTimer()
        let near = sampleTimer(startOffset: 300)
        let otherNear = sampleTimer(startOffset: 600)
        let far = sampleTimer(startOffset: 4_000)
        let collected = sampleTimer(startOffset: 900)
        _ = try model.create(from: [collected], at: Date(), timeZone: .gmt).get()
        let history = [anchor, near, otherNear, collected, far]
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        try capture(NavigationStack {
            ShootingCollectionSelectionView(
                model: model, history: history, initialSelection: selection,
                onCreated: { _ in }, onCancel: {}
            ).navigationTitle("Select History")
                .navigationBarTitleDisplayMode(.inline)
        }, name: "Time suggestion before confirmation")
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
        let distantHistory = (1...8).map { sampleTimer(startOffset: Double($0) * 10_000) }
        try capture(NavigationStack {
            ShootingCollectionSelectionView(
                model: model, history: distantHistory + Array(history.dropFirst()) + [anchor],
                initialSelection: selection, onCreated: { _ in }, onCancel: {}
            ).navigationTitle("Select History")
                .navigationBarTitleDisplayMode(.inline)
        }, name: "Anchor marker near list end")
        let suggestion = try XCTUnwrap(selection.suggestion(from: history, collectedIDs: model.collectedEventIDs))
        try capture(NavigationStack {
            ShootingCollectionSelectionView(
                model: model, history: history, initialSelection: selection,
                onCreated: { _ in }, onCancel: {}
            ).navigationTitle("Select History")
                .navigationBarTitleDisplayMode(.inline)
        }.sheet(item: .constant(Optional(suggestion))) { preview in
            ShootingCollectionSuggestionView(suggestion: preview, onConfirm: { _ in })
        }, name: "Time suggestion preview", expectsSheet: true)
        selection.confirmSuggestion(suggestion, choosing: [near.id], from: history, collectedIDs: model.collectedEventIDs)
        try capture(NavigationStack {
            ShootingCollectionSelectionView(
                model: model, history: history, initialSelection: selection,
                onCreated: { _ in }, onCancel: {}
            ).navigationTitle("Select History")
                .navigationBarTitleDisplayMode(.inline)
        }, name: "Time suggestion after confirmation")
        XCTAssertEqual(selection.selectedIDs, [anchor.id, near.id])
        XCTAssertEqual(model.collections.count, 1, "Selecting together does not create a Collection.")
    }

    func testLegacyFileMigratesThenRemovalAndReassignmentSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.json")
        let timer = sampleTimer()
        let record = try XCTUnwrap(PersistentShootingRecord(timer: timer))
        let collection = PersistentShootingCollection(id: UUID(), title: "Legacy", createdAt: Date(), records: [record])
        let old = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "collections": JSONSerialization.jsonObject(with: JSONEncoder().encode([collection])),
        ])
        try old.write(to: url)
        let model = ShootingCollectionModel(store: FileShootingCollectionStore(url: url))
        XCTAssertEqual(model.records(in: collection.id), [record])
        try model.remove(recordIDs: [timer.id], from: collection.id).get()
        let restored = ShootingCollectionModel(store: FileShootingCollectionStore(url: url))
        XCTAssertTrue(restored.records(in: collection.id).isEmpty)
        XCTAssertEqual(restored.uncollectedRecords, [record])
        try restored.move(recordIDs: [timer.id], from: nil, to: collection.id).get()
        let assigned = ShootingCollectionModel(store: FileShootingCollectionStore(url: url))
        XCTAssertEqual(assigned.records(in: collection.id), [record])
        XCTAssertTrue(assigned.uncollectedRecords.isEmpty)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, 2)
    }

    func testNativeMembershipEditingUncollectedAndDestinationSurfaces() throws {
        let model = ShootingCollectionModel(store: NoOpShootingCollectionStore())
        let first = sampleTimer()
        let second = sampleTimer(startOffset: 300)
        let third = sampleTimer(startOffset: 600)
        let collectionID = try model.create(from: [first, second, third], at: Date(), timeZone: .gmt).get()
        _ = try model.create(from: [sampleTimer(startOffset: 86_400)], at: Date(), timeZone: .gmt).get()
        try capture(NavigationStack {
            ShootingCollectionRecordsView(model: model, collectionID: collectionID, isEditing: .constant(false))
        }, name: "Collection records normal mode")
        try capture(NavigationStack {
            ShootingCollectionRecordsView(
                model: model, collectionID: collectionID, isEditing: .constant(true),
                initialSelection: [first.id, second.id]
            )
        }, name: "Collection records edit mode")
        try capture(ShootingCollectionMoveView(
            model: model, sourceID: collectionID, recordIDs: [first.id, second.id], onMoved: {}
        ), name: "Move Collection records")
        try model.remove(recordIDs: [first.id, second.id], from: collectionID).get()
        try capture(NavigationStack {
            ShootingCollectionRecordsView(model: model, collectionID: nil, isEditing: .constant(false))
        }, name: "Preserved uncollected records")
        try model.remove(recordIDs: [third.id], from: collectionID).get()
        try capture(NavigationStack {
            ShootingCollectionRecordsView(model: model, collectionID: collectionID, isEditing: .constant(false))
        }, name: "Empty Collection retained")
        XCTAssertEqual(model.uncollectedRecords.count, 3)
    }

    func testSameDateMoveTargetsShowCapturedTimeAndCameraSummaries() throws {
        let model = ShootingCollectionModel(store: NoOpShootingCollectionStore())
        let original = sampleTimer()
        let source = try model.create(from: [original], at: Date(), timeZone: .gmt).get()
        _ = try model.create(from: [
            sampleTimer(startOffset: 300, camera: .init(id: .camera1, displayName: "Nikon D850")),
            sampleTimer(startOffset: 600, camera: .init(id: .camera1, displayName: "Nikon D850")),
        ], at: Date(), timeZone: .gmt).get()
        _ = try model.create(from: [
            sampleTimer(startOffset: 3_600, camera: .init(id: .camera2, displayName: "Nikon F3")),
            sampleTimer(startOffset: 3_900, camera: .init(id: .camera3, displayName: "Leica M6")),
        ], at: Date(), timeZone: .gmt).get()
        _ = try model.create(from: [sampleTimer(startOffset: 7_200)], at: Date(), timeZone: .gmt).get()
        let destinations = model.collections.filter { $0.id != source }
        XCTAssertEqual(Set(destinations.map(\.title)).count, 1)
        let summaries = destinations.map(ShootingCollectionSummaryPresenter.display)
        XCTAssertEqual(Set(summaries.compactMap(\.startDate)).count, 3)
        XCTAssertEqual(Set(summaries.compactMap(\.representativeCameraName)), ["Nikon D850", "Nikon F3"])
        try capture(ShootingCollectionMoveView(
            model: model, sourceID: source, recordIDs: [original.id], onMoved: {}
        ), name: "Same-date movement destination summaries")
    }

    private func capture<Content: View>(_ content: Content, name: String, expectsSheet: Bool = false) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first)
        let previous = window.rootViewController
        let host = UIHostingController(rootView: content)
        defer {
            host.dismiss(animated: false)
            window.rootViewController = previous
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.bounds.height, 0)
        if expectsSheet {
            XCTAssertNotNil(host.presentedViewController, "The explicit preview request presents a sheet.")
        } else {
            XCTAssertNil(host.presentedViewController, "Checkbox changes must not automatically present a preview.")
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sampleTimer(startOffset: TimeInterval = 0, camera: CameraSlotIdentity? = nil) -> RunningTimerItem {
        RunningTimerItem(
            id: UUID(), order: 1, name: "Camera 1", basisSummary: "Base 1/30s · 6 stops",
            duration: 100, startDate: Date(timeIntervalSince1970: 1_794_450_000 + startOffset),
            endDate: Date(timeIntervalSince1970: 1_794_450_100 + startOffset), pausedRemainingTime: nil,
            pausedAt: nil, status: .completed, referenceDate: Date(), cameraSlot: camera,
            filmDisplayName: "ILFORD HP5 PLUS", exposureSource: .filmCorrectedExposure,
            selectedModelLabel: "App formula", ndStops: 6, baseShutterSeconds: 1.0 / 30,
            adjustedShutterSeconds: 2.133
        )
    }
}
