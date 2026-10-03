// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// FILTER-AUX-001: the mounted-auxiliary summary does not change while
/// an ND wheel is adjusted. The wheels block input during the short
/// reshaping window after a commit; the summary must render the same
/// in that window as at rest, so it does not flicker.
@MainActor
final class AuxiliaryFilterSummaryStabilityTests: XCTestCase {
    private let style = ExposureWorkspaceMainLayoutStyle(density: .regular)

    private var summary: AuxiliaryFilterSummaryDisplayState {
        let red = AuxiliaryFilterSummaryItemDisplay(
            itemID: FilterItemID(rawValue: "red"),
            name: "Red 25A",
            kindLabel: "Color",
            contributionText: "3",
            compactLabels: ["Red 25A", "Red"],
            opticalColor: .red,
            sourceColor: .red,
            accessibilityText: "Red 25A, 3 stops"
        )
        let cpl = AuxiliaryFilterSummaryItemDisplay(
            itemID: FilterItemID(rawValue: "cpl"),
            name: "CPL",
            kindLabel: "CPL",
            contributionText: "1",
            compactLabels: ["CPL"],
            opticalColor: nil,
            sourceColor: .blue,
            accessibilityText: "CPL, 1 stop"
        )
        return AuxiliaryFilterSummaryDisplayState(items: [red, cpl], accessibilityLabel: "Auxiliary filters")
    }

    private func rendered(isInteractive: Bool) throws -> Data {
        let view = AuxiliaryFilterSummaryView(
            summary: summary,
            height: 160,
            isInteractive: isInteractive,
            style: style,
            onOpen: {}
        )
        .frame(width: 80, height: 160)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage?.pngData(), "The summary renders.")
    }

    func testTheSummaryLooksTheSameWhileTheWheelsReshape() throws {
        XCTAssertEqual(
            try rendered(isInteractive: false),
            try rendered(isInteractive: true),
            "Blocking input during reshaping must not dim or redraw the summary."
        )
    }
}
