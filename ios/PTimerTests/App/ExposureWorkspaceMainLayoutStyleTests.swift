// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import SwiftUI
import UIKit
import PTimerCore
import PTimerKit
@testable import PTimer

/// FILTER-STACK-007 (spec revision 7f727082): the established numeric
/// hierarchy — Regular 28 / 24 / 20, Compact 23 / 20 / 17, Dense
/// 18 / 16 / 14 points for two / three / four actual wheels — shared by
/// Base Shutter and every filter wheel, settled or moving, plus the
/// fixed type-color rail palette that stays independent of the
/// user-selected Filter Set color.
final class ExposureWorkspaceMainLayoutStyleTests: XCTestCase {
    func testStackedNumericHierarchyMatchesTheReferenceTable() {
        let expected: [ExposureWorkspaceMainLayoutStyle: [CGFloat]] = [
            .regular: [28, 24, 20],
            .compact: [23, 20, 17],
            .dense: [18, 16, 14],
        ]
        for (style, sizes) in expected {
            XCTAssertEqual(style.stackedNDValuePointSize(forWheelCount: 2), sizes[0], "\(style) two wheels")
            XCTAssertEqual(style.stackedNDValuePointSize(forWheelCount: 3), sizes[1], "\(style) three wheels")
            XCTAssertEqual(style.stackedNDValuePointSize(forWheelCount: 4), sizes[2], "\(style) four wheels")
            XCTAssertEqual(style.wheelRowValuePointSize(forNDWheelCount: 4), sizes[2], "Four-wheel rows use the table.")
        }
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.dense.wheelRowValuePointSize(forNDWheelCount: 4), 14, "Four wheels in Dense render 14-point values.")
    }

    func testSingleWheelKeepsTheFullWidthPickerSize() {
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.regular.wheelRowValuePointSize(forNDWheelCount: 1), 32)
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.compact.wheelRowValuePointSize(forNDWheelCount: 1), 26)
        XCTAssertEqual(ExposureWorkspaceMainLayoutStyle.dense.wheelRowValuePointSize(forNDWheelCount: 1), 19)
    }

    /// Base Shutter and the filter wheels read the same function for a
    /// density and wheel count, so parity is structural; the expanded
    /// rows render their value through the same function.
    func testBaseShutterAndFilterWheelsShareOneNumericSizePerCount() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            for count in 1...4 {
                let size = style.wheelRowValuePointSize(forNDWheelCount: count)
                XCTAssertEqual(size, count <= 1 ? style.pickerValuePointSize : style.stackedNDValuePointSize(forWheelCount: count))
            }
            XCTAssertGreaterThan(style.wheelRowValuePointSize(forNDWheelCount: 2), style.wheelRowValuePointSize(forNDWheelCount: 3))
            XCTAssertGreaterThan(style.wheelRowValuePointSize(forNDWheelCount: 3), style.wheelRowValuePointSize(forNDWheelCount: 4))
        }
    }

    /// FILTER-STACK-007 (spec revision 56e381e2): the Base Shutter
    /// column and every filter column read one geometry, so their
    /// viewport top and bottom, selection-band center, value size, and
    /// vertical touch center are identical for every tier and wheel
    /// count; the tier's exact numeric sizes hold for 1, 3 plus Plus,
    /// and 4 wheels.
    func testBaseShutterAndFilterColumnsShareOneVerticalAxis() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            for count in 1...4 {
                let base = style.baseShutterColumnGeometry(ndWheelCount: count)
                let filter = style.filterWheelColumnGeometry(ndWheelCount: count)
                XCTAssertEqual(base, filter, "\(style) \(count) wheels: one shared geometry")
                XCTAssertEqual(base.viewportTop, filter.viewportTop)
                XCTAssertEqual(base.viewportBottom, filter.viewportBottom)
                XCTAssertEqual(base.selectionBandCenter, filter.selectionBandCenter)
                XCTAssertEqual(base.touchCenter, filter.touchCenter)
                XCTAssertEqual(base.valuePointSize, filter.valuePointSize)
                XCTAssertEqual(base.viewportTop, 30 + style.pickerLabelSpacing + style.filterWheelLabelRowHeight, "The label row sits directly on the viewport with no extra spacing.")
                XCTAssertEqual(base.viewportHeight, style.pickerHeight)
                XCTAssertEqual(base.selectionBandHeight, style.pickerSelectionBandHeight)
            }
        }
        let compact = ExposureWorkspaceMainLayoutStyle.compact
        XCTAssertEqual(compact.wheelColumnGeometry(ndWheelCount: 1).valuePointSize, 26)
        XCTAssertEqual(compact.wheelColumnGeometry(ndWheelCount: 3).valuePointSize, 20, "Three wheels plus Plus")
        XCTAssertEqual(compact.wheelColumnGeometry(ndWheelCount: 4).valuePointSize, 17)
        XCTAssertEqual(compact.wheelColumnGeometry(ndWheelCount: 1).viewportTop, 49)
        XCTAssertEqual(compact.wheelColumnGeometry(ndWheelCount: 1).viewportBottom, 157)
        XCTAssertEqual(compact.wheelColumnGeometry(ndWheelCount: 1).selectionBandCenter, 103)
    }

    /// The type rail fits inside the row's existing geometry: a narrow
    /// overlay at the leading edge, shorter than the 32 pt row, never a
    /// layout participant that could shift the numeric column.
    func testTypeRailFitsInsideTheRowGeometry() {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact, .dense] {
            XCTAssertLessThanOrEqual(style.filterWheelTypeRailWidth, 4)
            XCTAssertLessThan(style.filterWheelTypeRailHeight, 32)
            XCTAssertLessThanOrEqual(style.filterWheelTypeRailInset + style.filterWheelTypeRailWidth, 8)
        }
    }

    /// One fixed semantic palette: ND blue, CPL amber/orange, GND teal
    /// for both modes, Empty neutral gray — and independent of the
    /// Filter Set color even when a set deliberately picks a type hue.
    func testTypeRailPaletteIsFixedAndIndependentOfTheFilterSetColor() {
        XCTAssertEqual(Color.filterType(.nd), .blue)
        XCTAssertEqual(Color.filterType(.cpl), .orange)
        XCTAssertEqual(Color.filterType(.gnd), .filterTypeGND)
        XCTAssertNotEqual(Color.filterType(.gnd), .teal, "GND leaves system teal for a green-leaning teal.")
        XCTAssertEqual(Color.filterType(.empty), .gray)
        XCTAssertEqual(Set(FilterRowTypeCategory.allCases.map { Color.filterType($0) }).count, 4, "Every category has its own hue.")

        // A teal Filter Set resembles the GND hue on purpose: the source
        // cue and the rail are different channels, so a CPL row in that
        // set still gets the CPL rail and the set keeps its teal cue.
        let tealSet = FilterSetColor.teal
        XCTAssertNotEqual(Color.filterType(.cpl), Color.filterSet(tealSet))
        XCTAssertNotEqual(Color.filterType(.nd), Color.filterSet(tealSet))
        XCTAssertEqual(Color.filterSet(.blue), Color.filterType(.nd), "No collision avoidance or derivation between the channels.")
    }

    /// The GND rail is green-leaning in both appearances and stays
    /// far from ND blue in hue, so faded adjacent rows still separate.
    func testGNDRailIsGreenLeaningAndDistinctFromNDBlueInLightAndDark() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let gnd = UIColor(Color.filterTypeGND).resolvedColor(with: traits)
            let blue = UIColor.systemBlue.resolvedColor(with: traits)
            var gndHue: CGFloat = 0, blueHue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(gnd.getHue(&gndHue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
            XCTAssertTrue(blue.getHue(&blueHue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
            var red: CGFloat = 0, green: CGFloat = 0, blueComponent: CGFloat = 0
            XCTAssertTrue(gnd.getRed(&red, green: &green, blue: &blueComponent, alpha: &alpha))
            XCTAssertGreaterThan(green, blueComponent, "Green-leaning in \(style == .dark ? "dark" : "light") mode.")
            XCTAssertGreaterThan(green, red)
            XCTAssertGreaterThan(abs(gndHue - blueHue) * 360, 30, "At least 30° of hue away from ND blue in \(style == .dark ? "dark" : "light") mode.")
        }
    }
}
