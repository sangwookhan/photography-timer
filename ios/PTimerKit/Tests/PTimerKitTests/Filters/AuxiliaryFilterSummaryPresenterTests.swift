// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-AUX-002 / FILTER-COLOR-003 / FILTER-A11Y-001: the Main
/// summary shows every mounted auxiliary item as one compact row (a
/// short identifier and the current contribution), and speaks the full
/// identity, mode, and contribution as one button.
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

    func testEveryItemIsOneCompactRowWithIdentifierAndContribution() throws {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let softGND = FilterItem(name: "Soft GND 3", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let marumi = FilterItem(name: "MARUMI", behavior: .color(FilterExposureLoss(stops: 2), .red))
        let rows = [
            try resolved(cpl, .cplLoss(1.5)),
            try resolved(softGND, .gnd(.recordOnly)),
            try resolved(marumi, .registeredLoss),
        ]
        let state = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: rows))
        XCTAssertEqual(state.items.map(\.compactLabels), [["CPL"], ["Soft GND 3", "Soft GND", "Soft"], ["MARUMI"]], "A single CPL reads by type; a GND by its distinguishing name; a Color by name.")
        XCTAssertEqual(state.items.map(\.contributionText), ["1.5", "0", "2"], "Contributions are plain stops values.")
        XCTAssertEqual(state.items.map(\.kindLabel), ["CPL", "GND", "Color"])
        XCTAssertEqual(state.items[2].opticalColor, .red, "The circle is the optical color, not the set cue.")
        XCTAssertEqual(state.items.map(\.sourceColor), [.orange, .orange, .orange])
        XCTAssertEqual(state.items[1].accessibilityText, "Soft GND 3, GND Record only, 0 stops", "The full identity and mode stay spoken.")
        XCTAssertEqual(state.items[2].accessibilityText, "MARUMI, Color Red, 2 stops")
        XCTAssertEqual(state.accessibilityLabel, "Auxiliary filters, CPL, CPL, 1.5 stops, Soft GND 3, GND Record only, 0 stops, MARUMI, Color Red, 2 stops")
    }

    func testTwoItemsOfOneTypeAreToldApartByName() throws {
        let hard = FilterItem(name: "Hard GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let soft = FilterItem(name: "Soft GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let state = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: [
            try resolved(hard, .gnd(.recordOnly)),
            try resolved(soft, .gnd(.applyFullValue)),
        ]))
        XCTAssertEqual(state.items.map(\.compactLabels), [["Hard GND 2", "Hard GND", "Hard"], ["Soft GND 2", "Soft GND", "Soft"]])
        XCTAssertEqual(state.items.map(\.contributionText), ["0", "2"])

        // Shortened names the two would share are left out.
        let two = FilterItem(name: "GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let three = FilterItem(name: "GND 3", behavior: .gnd(FilterRegisteredValue(value: 3, unit: .stops)))
        let shared = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: [
            try resolved(two, .gnd(.recordOnly)),
            try resolved(three, .gnd(.recordOnly)),
        ]))
        XCTAssertEqual(shared.items.map(\.compactLabels), [["GND 2"], ["GND 3"]])
    }

    func testLongNamesShortenByTheDeterministicRule() throws {
        let long = FilterItem(name: "MARUMI Red 25A 52mm", behavior: .color(FilterExposureLoss(stops: 2), .red))
        let item = AuxiliaryFilterSummaryPresenter.itemDisplay(for: try resolved(long, .registeredLoss), among: [])
        XCTAssertEqual(item.compactLabels, ["MARUMI Red 25A 52mm", "MARUMI Red", "MARUMI"], "Whole name, the words before the first number, then the first word.")
        XCTAssertEqual(item.name, "MARUMI Red 25A 52mm", "The full name stays available for the popup and speech.")
    }

    func testEffectFilterShowsItsExplicitLossWithoutAColor() throws {
        let night = FilterItem(name: "Night", behavior: .effect(FilterExposureLoss(stops: 0.5)))
        let row = try resolved(night, .registeredLoss)
        let item = AuxiliaryFilterSummaryPresenter.itemDisplay(for: row, among: [row])
        XCTAssertEqual(item.kindLabel, "Effect")
        XCTAssertEqual(item.compactLabels, ["Night"])
        XCTAssertEqual(item.contributionText, "0.5")
        XCTAssertNil(item.opticalColor)
        XCTAssertEqual(item.accessibilityText, "Night, Effect, 0.5 stops")
    }

    /// Main shows the first three rows and counts the rest; every item
    /// is still spoken.
    func testMoreThanThreeItemsShowTheFirstThreePlusACount() throws {
        let items = (1...5).map { FilterItem(name: "Effect \($0)", behavior: .effect(FilterExposureLoss(stops: 0.5))) }
        let inventory = FilterInventory(filterSets: [FilterSet(id: set.id, name: set.name, color: set.color, items: items)])
        let rows = try items.map { item in
            try XCTUnwrap(FilterStack.resolvedAuxiliaryFilter(
                MountedAuxiliaryFilter(filterSetID: set.id, itemID: item.id, choice: .registeredLoss),
                inventory: inventory
            ))
        }
        let state = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: rows))
        XCTAssertEqual(state.visibleItems.map(\.name), ["Effect 1", "Effect 2", "Effect 3"])
        XCTAssertEqual(state.hiddenItemCount, 2)
        XCTAssertEqual(state.moreText, "+ 2 more")
        XCTAssertTrue(state.accessibilityLabel.hasSuffix("Effect 5, Effect, 0.5 stops"), "Hidden items are still spoken.")

        let three = try XCTUnwrap(AuxiliaryFilterSummaryPresenter.displayState(for: Array(rows.prefix(3))))
        XCTAssertEqual(three.hiddenItemCount, 0)
        XCTAssertNil(three.moreText)
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
