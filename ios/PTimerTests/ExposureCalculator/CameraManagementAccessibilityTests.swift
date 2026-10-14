// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// What VoiceOver is given by camera management, read from the live
/// accessibility tree of the hosted view (CAMERA-PAGER-006/008): each row's
/// label, its custom actions in normal mode, the edit-mode Move up and Move
/// down actions, and the leading Close control that disappears in edit mode.
/// This inspects the tree; it does not run VoiceOver itself.
@MainActor
final class CameraManagementAccessibilityTests: XCTestCase {

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            cameraSlotSessionPersistenceStore: NoOpCameraSlotSessionPersistenceStore()
        )
    }

    private func host(_ viewModel: ExposureCalculatorViewModel) -> UIView {
        let controller = UIHostingController(rootView: CameraManagementView(viewModel: viewModel, onDismiss: {}))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = scene.windows.first ?? UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        settle()
        return controller.view
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    }

    /// Accessibility objects reachable from `root`, depth first, bounded so a
    /// cyclic or regenerating tree cannot loop.
    private func elements(in root: UIView) -> [NSObject] {
        var found: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ node: NSObject, depth: Int) {
            guard depth < 40, found.count < 4000, seen.insert(ObjectIdentifier(node)).inserted else { return }
            found.append(node)
            if let view = node as? UIView {
                view.subviews.forEach { walk($0, depth: depth + 1) }
            }
            if let children = node.accessibilityElements as? [NSObject] {
                children.forEach { walk($0, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return found
    }

    private func element(_ identifier: String, in root: UIView) -> NSObject? {
        elements(in: root).first { node in
            guard node.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return false }
            return (node.value(forKey: "accessibilityIdentifier") as? String) == identifier
        }
    }

    func testRowsExposeLabelAndActionsAndEditModeAddsMoveActions() throws {
        let root = host(makeViewModel())
        let all = elements(in: root)
        let labels = all.compactMap(\.accessibilityLabel)
        XCTAssertTrue(
            labels.contains { $0.contains("Camera 1") && $0.contains("1 of 4") },
            "A row's label names the camera, its state, and its position. Found: \(labels.prefix(12))"
        )

        let row = try XCTUnwrap(element("camera-management-row-0", in: root), "Row 0 is in the tree.")
        let normalActions = (row.accessibilityCustomActions ?? []).map(\.name)
        XCTAssertTrue(normalActions.contains("Rename camera"), "Actions: \(normalActions)")
        XCTAssertTrue(normalActions.contains("Delete camera"), "Actions: \(normalActions)")
        XCTAssertFalse(normalActions.contains("Move up"), "Reordering belongs to edit mode.")
        XCTAssertTrue(all.contains { $0.accessibilityLabel == "Close" }, "The leading Close control is present in normal mode.")
        XCTAssertNotNil(element("camera-management-title", in: root), "The Cameras title is visible in normal mode.")

        let editControls = elements(in: root).filter { node in
            node.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                && (node.value(forKey: "accessibilityIdentifier") as? String) == "camera-management-edit-button"
        }
        XCTAssertFalse(editControls.isEmpty, "The Edit control is in the tree.")
        XCTAssertTrue(
            editControls.contains { $0.accessibilityActivate() },
            "Edit can be activated through accessibility (\(editControls.count) matching objects)."
        )
        settle()

        let editRow = try XCTUnwrap(element("camera-management-row-1", in: root))
        let editActions = (editRow.accessibilityCustomActions ?? []).map(\.name)
        XCTAssertTrue(editActions.contains("Move up"), "Edit-mode actions: \(editActions)")
        XCTAssertTrue(editActions.contains("Move down"), "Edit-mode actions: \(editActions)")
        XCTAssertFalse(
            elements(in: root).contains { $0.accessibilityLabel == "Close" },
            "Edit mode removes the leading Close control."
        )
        let title = try XCTUnwrap(element("camera-management-title", in: root), "The Cameras title stays in edit mode.")
        XCTAssertEqual(title.accessibilityLabel, "Cameras")
    }
}
