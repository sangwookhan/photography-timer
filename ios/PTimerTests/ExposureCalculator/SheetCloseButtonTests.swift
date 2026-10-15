// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// The About screen closes through the shared X control, not a visible
/// "Done" action; the control keeps the accessible name `Close`.
@MainActor
final class SheetCloseButtonTests: XCTestCase {
    func testTheCloseControlIsAnXIconNamedClose() {
        XCTAssertEqual(SheetCloseButton.systemImageName, "xmark")
        XCTAssertEqual(SheetCloseButton.accessibilityLabelText, "Close")
    }

    func testTheCloseControlIsExposedToAssistiveTechnologyAsAButtonNamedClose() throws {
        var closed = 0
        let host = UIHostingController(rootView: SheetCloseButton { closed += 1 })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        let elements = Self.accessibilityElements(in: host.view)
        let close = try XCTUnwrap(elements.first { $0.accessibilityLabel == "Close" })
        XCTAssertTrue(close.accessibilityTraits.contains(.button))
        XCTAssertTrue(close.accessibilityActivate(), "Activating the control runs the close action.")
        XCTAssertEqual(closed, 1)
    }

    private static func accessibilityElements(in view: UIView) -> [NSObject] {
        var found: [NSObject] = []
        if view.isAccessibilityElement { found.append(view) }
        for index in 0..<(view.accessibilityElementCount() == NSNotFound ? 0 : view.accessibilityElementCount()) {
            if let element = view.accessibilityElement(at: index) as? NSObject {
                found.append(element)
            }
        }
        for subview in view.subviews {
            found += accessibilityElements(in: subview)
        }
        return found
    }
}
