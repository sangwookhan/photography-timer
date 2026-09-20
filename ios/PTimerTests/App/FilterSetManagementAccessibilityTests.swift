// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// FILTER-SET-001: while the Filter Set list is in reorder / delete edit
/// mode, the control that leaves edit mode stays directly visible in the
/// toolbar and is worded apart from the `Done` that dismisses the whole
/// management surface. Hosted in a window so the real UIKit navigation
/// bar and its accessibility elements are inspected.
@MainActor
final class FilterSetManagementAccessibilityTests: XCTestCase {
    func testEditModeExitIsVisibleAndDistinctFromTheSurfaceDone() throws {
        let inventory = FilterInventoryModel()
        _ = inventory.createFilterSet(name: "A kit", color: .red)
        _ = inventory.createFilterSet(name: "B holder", color: .blue)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            filterInventoryModel: inventory
        )
        var doneTaps = 0
        let host = try hosted(FilterSetManagementView(viewModel: viewModel) { doneTaps += 1 })
        defer { host.window.isHidden = true }

        let idle = try accessibilityElements(in: host)
        XCTAssertNotNil(idle.first { $0.label == "Done" }, "The surface's Done: \(idle.map(\.label))")
        let edit = try XCTUnwrap(idle.first { $0.label == "Edit" }, "Edit is directly visible in the toolbar: \(idle.map(\.label))")
        XCTAssertNil(idle.first { $0.label == "Finish Editing" })

        XCTAssertTrue(edit.element.accessibilityActivate())
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let editing = try accessibilityElements(in: host)
        let finish = try XCTUnwrap(editing.first { $0.label == "Finish Editing" }, "Leaving edit mode is directly visible while editing: \(editing.map(\.label))")
        XCTAssertNotNil(editing.first { $0.label == "Done" }, "The surface's Done is still a separate element.")
        XCTAssertNil(editing.first { $0.label == "Edit" })
        XCTAssertEqual(doneTaps, 0, "Entering edit mode never dismisses the surface.")

        XCTAssertTrue(finish.element.accessibilityActivate())
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let back = try accessibilityElements(in: host)
        XCTAssertNotNil(back.first { $0.label == "Edit" }, "Edit mode ended: \(back.map(\.label))")
        XCTAssertNil(back.first { $0.label == "Finish Editing" })
        XCTAssertEqual(doneTaps, 0, "Leaving edit mode never dismisses the surface.")
    }

    // MARK: Hosting

    private struct Snapshot {
        let label: String?
        let element: NSObject
    }

    private struct Host {
        let controller: UIViewController
        let window: UIWindow
    }

    private func hosted(_ view: FilterSetManagementView) throws -> Host {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        return Host(controller: host, window: window)
    }

    /// Every accessibility element in tree order. An empty tree means the
    /// simulator's accessibility runtime is off — a missing prerequisite,
    /// not a defect — so the test skips and names the one-time enabling step.
    private func accessibilityElements(in host: Host) throws -> [Snapshot] {
        var found: [Snapshot] = []
        collect(from: host.controller.view, into: &found)
        if found.isEmpty {
            throw XCTSkip(
                "The simulator's accessibility runtime is off (empty hosted accessibility tree). "
                    + "Enable it once per simulator: xcrun simctl spawn <udid> defaults write "
                    + "com.apple.Accessibility AccessibilityEnabled -bool true; xcrun simctl spawn <udid> "
                    + "defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -int 1"
            )
        }
        return found
    }

    private func collect(from object: NSObject, into found: inout [Snapshot]) {
        if object.isAccessibilityElement {
            found.append(Snapshot(label: object.accessibilityLabel, element: object))
            return
        }
        if let elements = object.accessibilityElements as? [NSObject] {
            for element in elements {
                collect(from: element, into: &found)
            }
        }
        if let view = object as? UIView {
            for subview in view.subviews {
                collect(from: subview, into: &found)
            }
        }
    }
}
