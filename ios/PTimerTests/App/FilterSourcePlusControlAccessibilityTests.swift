// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// FILTER-A11Y-001 / FILTER-PLUS: the focusable Plus element itself
/// must expose Add, source adjustment, and Filter Set management to
/// assistive technology. Hosted in a window so the real UIKit
/// accessibility tree SwiftUI produces is inspected, not the modifiers.
@MainActor
final class FilterSourcePlusAccessibilityTests: XCTestCase {
    private struct Snapshot {
        let label: String?
        let value: String?
        let hint: String?
        let traits: UIAccessibilityTraits
        let customActionNames: [String]
        let element: NSObject
    }

    private let leeID = FilterSetID(rawValue: "lee")
    private let leeReason = "This Filter Set has no filters yet"

    /// Standard adds; the Lee set has no items, so it refuses with a reason.
    private func makeControl(
        selectedSource: FilterSource = .standard,
        added: @escaping (FilterSource) -> Void = { _ in }
    ) -> FilterSourcePlusControl {
        FilterSourcePlusControl(
            sources: [.standard, .filterSet(leeID)],
            selectedSource: selectedSource,
            sourceName: { $0 == .standard ? "Standard" : "Lee" },
            sourceColor: { $0 == .standard ? nil : .red },
            pickerHeight: 120,
            isInteractionQuiet: true,
            addUnavailabilityText: { $0 == .standard ? nil : self.leeReason },
            onAdd: added,
            onManage: {},
            onBrowsingChanged: { _ in }
        )
    }

    func testPlusElementExposesAddAdjustableValueAndManageActions() throws {
        let host = try hosted(makeControl())
        defer { host.window.isHidden = true }
        let plus = try XCTUnwrap(accessibilityElements(in: host).first { $0.label == "Add filter" }, "One focusable element labelled Add filter")
        XCTAssertEqual(plus.value, "Standard")
        XCTAssertFalse(plus.hint?.contains(leeReason) ?? false, "The remembered source can add; the hint is the usage hint.")
        XCTAssertTrue(plus.traits.contains(.adjustable), "Source stepping is the adjustable value.")
        XCTAssertTrue(plus.traits.contains(.button), "An addable source is activatable.")
        XCTAssertTrue(plus.customActionNames.contains("Manage Filter Sets"), "Manage must be in the Actions rotor: \(plus.customActionNames)")
        XCTAssertTrue(plus.customActionNames.contains("Add filter"), plus.customActionNames.description)
    }

    /// FILTER-PLUS-004/005 with ND-A11Y-002: an assistive increment
    /// browses a transient candidate; the element's value AND its
    /// hint/reason follow that candidate together. While the candidate
    /// cannot add, the Add operation is neither offered nor executed —
    /// activation does nothing and the Actions rotor keeps only Manage —
    /// yet the element stays adjustable so the user can step back, at
    /// which point Add returns and activation adds the remembered source.
    func testUnavailableTransientCandidateWithdrawsAddUntilTheUserStepsBack() throws {
        var added: [FilterSource] = []
        let host = try hosted(makeControl { added.append($0) })
        defer { host.window.isHidden = true }
        let before = try XCTUnwrap(accessibilityElements(in: host).first { $0.label == "Add filter" })
        XCTAssertEqual(before.value, "Standard")

        before.element.accessibilityIncrement()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let after = try XCTUnwrap(accessibilityElements(in: host).first { $0.label == "Add filter" })
        XCTAssertEqual(after.value, "Lee", "The spoken value is the browsed candidate.")
        XCTAssertEqual(after.hint, leeReason, "The reason follows the candidate, not the remembered source.")
        XCTAssertFalse(after.customActionNames.contains("Add filter"), "An unavailable candidate offers no Add: \(after.customActionNames)")
        XCTAssertTrue(after.customActionNames.contains("Manage Filter Sets"), "Manage stays available.")
        XCTAssertFalse(after.traits.contains(.button), "The element is not presented as activatable.")
        XCTAssertTrue(after.traits.contains(.adjustable), "Stepping away from the unavailable source stays possible.")

        after.element.accessibilityActivate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(added, [], "Activation on an unavailable candidate adds nothing.")

        after.element.accessibilityDecrement()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let back = try XCTUnwrap(accessibilityElements(in: host).first { $0.label == "Add filter" })
        XCTAssertEqual(back.value, "Standard")
        XCTAssertFalse(back.hint?.contains(leeReason) ?? false)
        XCTAssertTrue(back.customActionNames.contains("Add filter"), "Add returns with an addable source.")
        XCTAssertTrue(back.element.accessibilityActivate())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(added, [.standard], "Activation adds the displayed, addable source.")
    }

    /// ND-A11Y-002 from the other side: when the REMEMBERED source
    /// cannot add, the element starts without Add, and stepping to an
    /// addable candidate brings Add back and lets activation add it.
    func testUnavailableRememberedSourceStartsWithoutAddAndAnAvailableCandidateRestoresIt() throws {
        var added: [FilterSource] = []
        let host = try hosted(makeControl(selectedSource: .filterSet(leeID)) { added.append($0) })
        defer { host.window.isHidden = true }
        let start = try XCTUnwrap(accessibilityElements(in: host).first { $0.label == "Add filter" })
        XCTAssertEqual(start.value, "Lee")
        XCTAssertEqual(start.hint, leeReason)
        XCTAssertFalse(start.customActionNames.contains("Add filter"), start.customActionNames.description)
        XCTAssertTrue(start.customActionNames.contains("Manage Filter Sets"))
        XCTAssertFalse(start.traits.contains(.button), "Not presented as activatable while the remembered source cannot add.")
        start.element.accessibilityActivate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(added, [])

        start.element.accessibilityDecrement()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let candidate = try XCTUnwrap(accessibilityElements(in: host).first { $0.label == "Add filter" })
        XCTAssertEqual(candidate.value, "Standard")
        XCTAssertTrue(candidate.customActionNames.contains("Add filter"), candidate.customActionNames.description)
        XCTAssertTrue(candidate.element.accessibilityActivate())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(added, [.standard], "The transient candidate adds; the remembered source is the view model's to move on success.")
    }

    // MARK: Hosting

    private struct Host {
        let controller: UIViewController
        let window: UIWindow
    }

    private func hosted(_ control: FilterSourcePlusControl) throws -> Host {
        let host = UIHostingController(rootView: control.frame(width: 60, height: 160))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return Host(controller: host, window: window)
    }

    /// SwiftUI materializes UIKit accessibility elements only while the
    /// simulator's accessibility runtime is active; a pristine simulator
    /// yields an empty tree. That is a missing prerequisite, not a
    /// defect, so the test skips and names the one-time enabling step.
    private func accessibilityElements(in host: Host) throws -> [Snapshot] {
        let found = elements(in: host)
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

    private func elements(in host: Host) -> [Snapshot] {
        var found: [Snapshot] = []
        collect(from: host.controller.view, into: &found)
        return found
    }

    private func collect(from object: NSObject, into found: inout [Snapshot]) {
        if object.isAccessibilityElement {
            found.append(Snapshot(
                label: object.accessibilityLabel,
                value: object.accessibilityValue,
                hint: object.accessibilityHint,
                traits: object.accessibilityTraits,
                customActionNames: (object.accessibilityCustomActions ?? []).map(\.name),
                element: object
            ))
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
