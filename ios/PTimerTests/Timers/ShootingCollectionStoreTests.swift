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

    private func capture<Content: View>(_ content: Content, name: String) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first)
        let previous = window.rootViewController
        defer { window.rootViewController = previous }
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(host.view.bounds.height, 0)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sampleTimer() -> RunningTimerItem {
        RunningTimerItem(
            id: UUID(), order: 1, name: "Camera 1", basisSummary: "Base 1/30s · 6 stops",
            duration: 100, startDate: Date(timeIntervalSince1970: 1_794_450_000),
            endDate: Date(timeIntervalSince1970: 1_794_450_100), pausedRemainingTime: nil,
            pausedAt: nil, status: .completed, referenceDate: Date(),
            filmDisplayName: "ILFORD HP5 PLUS", exposureSource: .filmCorrectedExposure,
            selectedModelLabel: "App formula", ndStops: 6, baseShutterSeconds: 1.0 / 30,
            adjustedShutterSeconds: 2.133
        )
    }
}
