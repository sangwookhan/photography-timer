// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// FILTER-A11Y-005 / FILTER-STACK-008: the one-row status region exposes
/// its leading text and the complete Total as two separate accessibility
/// elements, so Total is focusable directly without listening through the
/// source summary or item detail first. Hosted in a window so the real
/// UIKit accessibility tree SwiftUI produces is inspected.
@MainActor
final class FilterStatusRegionAccessibilityTests: XCTestCase {
    private let style = ExposureWorkspaceMainLayoutStyle(density: .regular)

    func testMixedSourceIdleSummaryAndTotalAreSeparateElements() throws {
        let summary = [
            FilterStatusSourceSummaryItem(source: .filterSet(FilterSetID(rawValue: "nisi")), name: "NiSi kit", count: 1, color: .red),
            FilterStatusSourceSummaryItem(source: .filterSet(FilterSetID(rawValue: "lee")), name: "Lee holder", count: 2, color: .green),
            FilterStatusSourceSummaryItem(source: .standard, name: "Standard", count: 1, color: nil),
        ]
        let content = FilterStatusRegionContent(
            primaryText: FilterStatusRegionPresenter.summaryText(summary),
            secondaryText: "Total 13 stops",
            isHeld: true,
            isSecondaryEmphasis: true,
            idleSourceSummary: summary
        )
        let host = try hosted(FilterStatusRegionView(content: content, occupiedSpaceCount: 2, style: style))
        defer { host.window.isHidden = true }

        let labels = try accessibilityLabels(in: host)
        let total = try XCTUnwrap(labels.first { $0 == "Total 13 stops" }, "Total is its own focusable element: \(labels)")
        let leading = try XCTUnwrap(labels.first { $0.hasPrefix("NiSi kit") }, "The leading summary is its own element: \(labels)")
        XCTAssertEqual(leading, "NiSi kit · Lee holder ×2 · Standard", "The leading element carries the complete summary.")
        XCTAssertFalse(leading.contains(total), "Total is not appended to the summary element.")
        XCTAssertEqual(labels.count, 2, "Exactly two elements, in leading-then-total order: \(labels)")
        XCTAssertEqual(labels, [leading, total])
    }

    func testMovingDetailAndTotalAreSeparateElements() throws {
        let content = FilterStatusRegionContent(
            primaryText: "Big Stopper · ND1000 · 10 stops",
            secondaryText: "Total 16 stops",
            isHeld: true
        )
        let host = try hosted(FilterStatusRegionView(content: content, occupiedSpaceCount: 2, style: style))
        defer { host.window.isHidden = true }

        let labels = try accessibilityLabels(in: host)
        XCTAssertEqual(labels, ["Big Stopper · ND1000 · 10 stops", "Total 16 stops"], "Held detail keeps the same two-element shape.")
    }

    // MARK: Hosting

    private struct Host {
        let controller: UIViewController
        let window: UIWindow
    }

    private func hosted(_ view: FilterStatusRegionView) throws -> Host {
        let host = UIHostingController(rootView: view.frame(width: 320))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 200))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return Host(controller: host, window: window)
    }

    /// Labels of every accessibility element in tree order. An empty
    /// tree means the simulator's accessibility runtime is off — a
    /// missing prerequisite, not a defect — so the test skips and names
    /// the one-time enabling step.
    private func accessibilityLabels(in host: Host) throws -> [String] {
        var found: [String] = []
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

    private func collect(from object: NSObject, into found: inout [String]) {
        if object.isAccessibilityElement {
            found.append(object.accessibilityLabel ?? "")
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

/// Measurement checkpoint for Spec #99 at 8ca4e9ac. These measurements
/// report a contract-fit obstruction; they do not claim UI conformance.
@MainActor
final class TargetNDProposalLayoutCheckpointTests: XCTestCase {
    func testCandidateActionKeepsOriginalOneRowGeometry() throws {
        let style = ExposureWorkspaceMainLayoutStyle.compact
        let width = UIScreen.main.bounds.width - 2 * style.horizontalPadding - 2 * style.sectionCardPadding
        for language in ["en", "ko"] {
            for appearance in [UIUserInterfaceStyle.light, .dark] {
                for fixture in [TargetNDProposalPreview.live, .ordinary, .warning, .noCombination] {
                    var frames: [String: CGRect] = [:]
                    let view = FilterStatusRegionView(content: nil, occupiedSpaceCount: 2, style: style,
                        previewTotal: .init(totalStopsText: "13", isAtMaximum: false, wheelCount: 2),
                        onReviewFrame: { frames[$0] = $1 })
                        .environment(\.targetNDProposalPreview, fixture)
                        .environment(\.locale, Locale(identifier: language))
                        .frame(width: width)
                    let host = UIHostingController(rootView: view)
                    host.overrideUserInterfaceStyle = appearance
                    let window = UIWindow(frame: UIScreen.main.bounds)
                    window.rootViewController = host
                    window.isHidden = false
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    let row = try XCTUnwrap(frames["region"])
                    XCTAssertEqual(row.height, style.filterStatusRegionHeight, accuracy: 0.5)
                    if let action = frames["apply"] {
                        XCTAssertGreaterThanOrEqual(action.minX, row.minX - 0.5)
                        XCTAssertGreaterThanOrEqual(action.minY, row.minY + 3)
                        XCTAssertLessThanOrEqual(action.maxX, row.maxX + 0.5)
                        XCTAssertLessThanOrEqual(action.maxY, row.maxY + 0.5)
                        if let warning = frames["leading"] { XCTAssertLessThanOrEqual(warning.maxX, action.minX) }
                    }
                    if let live = frames["live"] {
                        XCTAssertGreaterThan(live.midX, row.midX)
                        XCTAssertLessThanOrEqual(live.maxX, row.maxX + 0.5)
                    }
                    if let total = frames["current-total"] {
                        XCTAssertGreaterThan(total.midX, row.midX)
                        XCTAssertLessThanOrEqual(total.maxX, row.maxX + 0.5)
                    }
                    let raw = XCTAttachment(string: "\(language) \(appearance.rawValue) \(fixture.rawValue) frames=\(frames)")
                    raw.name = "single-row-\(language)-\(appearance.rawValue)-\(fixture.rawValue)-frames"
                    raw.lifetime = .keepAlways; add(raw)
                    let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let png = XCTAttachment(image: image)
                    png.name = "single-row-\(language)-\(appearance.rawValue)-\(fixture.rawValue)"
                    png.lifetime = .keepAlways; add(png)
                    window.isHidden = true
                }
            }
        }
    }
}
