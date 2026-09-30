// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-AUX-002 / FILTER-COLOR-003 / FILTER-A11Y-001: the Main
/// summary names every mounted auxiliary item with its current
/// contribution, keeps a GND's registered density and mode distinct
/// from that contribution, names a Color filter's optical color as
/// text, and speaks all of it as one button.
final class AuxiliaryFilterSummaryPresenterTests: XCTestCase {
    private let set = FilterSet(id: FilterSetID(rawValue: "s"), name: "52mm", color: .orange)

    private func resolved(_ item: FilterItem, _ choice: AuxiliaryFilterChoice) throws -> ResolvedAuxiliaryFilter {
        let inventory = FilterInventory(filterSets: [FilterSet(id: set.id, name: set.name, color: set.color, items: [item])])
        return try XCTUnwrap(FilterStack.resolvedAuxiliaryFilter(
            MountedAuxiliaryFilter(filterSetID: set.id, itemID: item.id, choice: choice),
            inventory: inventory
        ))
    }

    func testNothingMountedHidesTheSummary() {
        XCTAssertNil(AuxiliaryFilterSummaryPresenter.displayState(for: []))
    }

    func testEveryItemShowsIdentityAndContributionWithDistinguishingDetail() throws {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let softGND = FilterItem(name: "Soft GND 3", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
        let rows = [
            try resolved(cpl, .cplLoss(1.5)),
            try resolved(softGND, .gnd(.recordOnly)),
            try resolved(red, .registeredLoss),
        ]
        let state = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: rows))
        XCTAssertEqual(state.items.map(\.name), ["CPL", "Soft GND 3", "Red 25A"])
        XCTAssertEqual(state.items.map(\.contributionText), ["1.5", "0", "3"], "Contributions are plain stops values.")
        XCTAssertEqual(state.items.map(\.kindLabel), ["CPL", "GND", "Color"])
        XCTAssertEqual(state.items[0].detailText, nil, "A CPL's choice is its contribution; nothing more to distinguish.")
        XCTAssertEqual(state.items[1].detailText, "Record only · OD 0.9", "Registered density stays beside the mode so 0 is not read as a 0-stop filter.")
        XCTAssertEqual(state.items[1].detailSegments, ["Record only", "OD 0.9"], "A narrow column breaks between the mode and the density, not inside either.")
        XCTAssertEqual(state.items[0].detailSegments, [])
        XCTAssertEqual(state.items[2].detailText, "Red", "The optical color is named as text (FILTER-COLOR-003).")
        XCTAssertEqual(state.items[2].opticalColor, .red)
        XCTAssertEqual(state.items.map(\.sourceColor), [.orange, .orange, .orange])
        XCTAssertEqual(state.items[1].accessibilityText, "Soft GND 3, GND Record only, 0 stops")
        XCTAssertEqual(state.items[2].accessibilityText, "Red 25A, Color Red, 3 stops")
        XCTAssertEqual(state.accessibilityLabel, "Auxiliary filters, CPL, CPL, 1.5 stops, Soft GND 3, GND Record only, 0 stops, Red 25A, Color Red, 3 stops")

        let full = try resolved(softGND, .gnd(.applyFullValue))
        let fullItem = AuxiliaryFilterSummaryPresenter.itemDisplay(for: full)
        XCTAssertEqual(fullItem.contributionText, "3")
        XCTAssertEqual(fullItem.detailText, "Apply full value", "At full value the contribution is the registered density; the mode alone distinguishes it.")
    }

    func testEqualDensityGNDsAreToldApartByName() throws {
        let hard = FilterItem(name: "Hard GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let soft = FilterItem(name: "Soft GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let state = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: [
            try resolved(hard, .gnd(.recordOnly)),
            try resolved(soft, .gnd(.applyFullValue)),
        ]))
        XCTAssertEqual(state.items.map(\.name), ["Hard GND 2", "Soft GND 2"])
        XCTAssertEqual(state.items.map(\.contributionText), ["0", "2"])
        XCTAssertEqual(state.items.map(\.detailText), ["Record only · 2 stops", "Apply full value"])
    }

    func testEffectFilterShowsItsExplicitLossWithoutAColor() throws {
        let night = FilterItem(name: "Night", behavior: .effect(FilterExposureLoss(stops: 0.5)))
        let item = AuxiliaryFilterSummaryPresenter.itemDisplay(for: try resolved(night, .registeredLoss))
        XCTAssertEqual(item.kindLabel, "Effect")
        XCTAssertEqual(item.contributionText, "0.5")
        XCTAssertNil(item.detailText)
        XCTAssertNil(item.opticalColor)
        XCTAssertEqual(item.accessibilityText, "Night, Effect, 0.5 stops")
    }

    func testPlusChoicesEndWithTheAuxiliaryAction() {
        let lee = FilterSetID(rawValue: "lee")
        XCTAssertEqual(
            FilterPlusChoice.choices(for: [.standard, .filterSet(lee)]),
            [.source(.standard), .source(.filterSet(lee)), .auxiliaryFilters]
        )
        XCTAssertEqual(FilterPlusChoice.auxiliaryFilters.source, nil)
        XCTAssertEqual(FilterPlusChoice.source(.standard).source, .standard)
    }
}
