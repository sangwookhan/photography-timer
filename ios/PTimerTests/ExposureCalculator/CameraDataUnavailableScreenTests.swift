// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// The shooting workspace while the camera storage read failed
/// (CAMERA-PERSIST-004): it shows the explanation instead of the pager,
/// offers no camera actions, and writes nothing. Set `CAMERA_FAILED_READ_HOLD`
/// to a file path to keep the screen up until that file is removed, so it can
/// be captured from the simulator.
@MainActor
final class CameraDataUnavailableScreenTests: XCTestCase {

    /// A session store whose managed-list read supplies no content.
    private final class FailingReadSessionStore: CameraSlotSessionPersistenceStoring {
        private(set) var writeCount = 0
        func loadSnapshot() -> PersistentCameraSlotSessionSnapshot? { nil }
        func saveSnapshot(_ snapshot: PersistentCameraSlotSessionSnapshot) { writeCount += 1 }
        func clearSnapshot() { writeCount += 1 }
        func loadManagedList() -> ManagedCameraListLoadResult { .readFailed }
        func saveManagedList(_ snapshot: PersistentManagedCameraListSnapshot) { writeCount += 1 }
    }

    private func makeScreen(store: FailingReadSessionStore) -> ExposureCalculatorScreen {
        let dependencies = ViewModelDependencies(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            presetFilms: LaunchPresetFilmCatalogV2.userSelectableFilms,
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: store,
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            lockScreenTargetExposer: NoOpLockScreenTimerTargetExposer(),
            customFilmLibrary: CustomFilmLibrary(store: NoOpCustomFilmLibraryStore())
        )
        return ExposureCalculatorScreen(
            coordinator: WorkspaceCoordinator(dependencies: dependencies, isFilterStackOrderingSuspended: false),
            bottomSheetStateStore: BottomSheetWorkspaceStateStore()
        )
    }

    private func labels(in view: UIView) -> [String] {
        var found: [String] = []
        func walk(_ node: NSObject) {
            if let text = node.accessibilityLabel, !text.isEmpty { found.append(text) }
            if let view = node as? UIView {
                view.subviews.forEach(walk)
                (view.accessibilityElements as? [NSObject])?.forEach(walk)
            }
        }
        walk(view)
        return found
    }

    func testTheWorkspaceShowsTheExplanationAndWritesNothing() throws {
        let store = FailingReadSessionStore()
        let host = UIHostingController(rootView: makeScreen(store: store))
        // Use the host app's own window so the screen is really on screen.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first ?? UIWindow(windowScene: scene))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.view.layoutIfNeeded()

        let texts = labels(in: host.view)
        XCTAssertTrue(
            texts.contains { $0.contains("Camera data couldn't be loaded. Restart the app.") },
            "The explanation is on screen. Found: \(texts.prefix(20))"
        )
        XCTAssertFalse(texts.contains { $0.contains("Manage cameras") }, "No camera action is offered.")
        XCTAssertFalse(texts.contains { $0.contains("Add camera") }, "No camera action is offered.")
        XCTAssertEqual(store.writeCount, 0, "Nothing is written for the launch.")

        if let marker = ProcessInfo.processInfo.environment["CAMERA_FAILED_READ_HOLD"] {
            FileManager.default.createFile(atPath: marker, contents: Data())
            let deadline = Date().addingTimeInterval(90)
            while FileManager.default.fileExists(atPath: marker), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            }
        }
    }
}
