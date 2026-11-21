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
        XCTAssertTrue(try store.load().isEmpty)
        let model = ShootingCollectionModel(store: store)
        _ = try model.create(from: [sampleTimer()], at: Date(), timeZone: .gmt).get()
        XCTAssertEqual(try FileShootingCollectionStore(url: url).load(), model.collections)
        let bytes = try Data(contentsOf: url)
        // A regular file cannot be a directory: deterministic OS-boundary failure.
        let blocked = FileShootingCollectionStore(url: url.appendingPathComponent("child.json"))
        XCTAssertThrowsError(try blocked.save(model.collections))
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

    private func sampleTimer(startOffset: TimeInterval = 0) -> RunningTimerItem {
        RunningTimerItem(
            id: UUID(), order: 1, name: "Camera 1", basisSummary: "Base 1/30s · 6 stops",
            duration: 100, startDate: Date(timeIntervalSince1970: 1_794_450_000 + startOffset),
            endDate: Date(timeIntervalSince1970: 1_794_450_100 + startOffset), pausedRemainingTime: nil,
            pausedAt: nil, status: .completed, referenceDate: Date(),
            filmDisplayName: "ILFORD HP5 PLUS", exposureSource: .filmCorrectedExposure,
            selectedModelLabel: "App formula", ndStops: 6, baseShutterSeconds: 1.0 / 30,
            adjustedShutterSeconds: 2.133
        )
    }
}
