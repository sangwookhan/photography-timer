// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

/// Filter Set contract — inventory value rules: registered-value
/// conversion (FILTER-ITEM-004), CPL choice validation and decimal
/// input normalization (FILTER-CPL-001/002/003), and the creation
/// color suggestion (FILTER-SET-003).
final class FilterInventoryTests: XCTestCase {

    // MARK: FILTER-ITEM-004 — conversion to canonical stops

    func testStopsValueIsUnchanged() {
        XCTAssertEqual(FilterRegisteredValue(value: 3.3, unit: .stops).canonicalStops, 3.3)
    }

    func testOpticalDensityDividesByPointThree() throws {
        let stops = try XCTUnwrap(FilterRegisteredValue(value: 0.9, unit: .opticalDensity).canonicalStops)
        XCTAssertEqual(stops, 3, accuracy: 1e-9)
        // OD 2.0 is NOT snapped to the Standard 6.6 preset.
        let od2 = try XCTUnwrap(FilterRegisteredValue(value: 2.0, unit: .opticalDensity).canonicalStops)
        XCTAssertEqual(od2, 2.0 / 0.3, accuracy: 1e-9)
    }

    func testFilterFactorUsesLog2() throws {
        let nd8 = try XCTUnwrap(FilterRegisteredValue(value: 8, unit: .filterFactor).canonicalStops)
        XCTAssertEqual(nd8, 3, accuracy: 1e-9)
        let nd1000 = try XCTUnwrap(FilterRegisteredValue(value: 1000, unit: .filterFactor).canonicalStops)
        XCTAssertEqual(nd1000, log2(1000), accuracy: 1e-9)
    }

    func testInvalidRegisteredValuesAreRejected() {
        XCTAssertNil(FilterRegisteredValue(value: 0, unit: .stops).canonicalStops)
        XCTAssertNil(FilterRegisteredValue(value: -1, unit: .stops).canonicalStops)
        XCTAssertNil(FilterRegisteredValue(value: 30.5, unit: .stops).canonicalStops)
        XCTAssertNil(FilterRegisteredValue(value: .nan, unit: .stops).canonicalStops)
        XCTAssertNil(FilterRegisteredValue(value: .infinity, unit: .opticalDensity).canonicalStops)
        XCTAssertNil(FilterRegisteredValue(value: 1, unit: .filterFactor).canonicalStops, "ND1 is 0 stops.")
        XCTAssertNil(FilterRegisteredValue(value: 0, unit: .filterFactor).canonicalStops)
        XCTAssertEqual(FilterRegisteredValue(value: 30, unit: .stops).canonicalStops, 30)
    }

    // MARK: FILTER-CPL-001/002 — choices

    func testDefaultChoicesAreOneOnePointFiveTwo() {
        XCTAssertEqual(CPLExposureLossChoices.defaults.shootingChoices, [1, 1.5, 2])
        XCTAssertTrue(CPLExposureLossChoices.defaults.isValid)
    }

    func testChoiceRangeAndPrecision() {
        XCTAssertFalse(CPLExposureLossChoices.isValidChoice(0))
        XCTAssertFalse(CPLExposureLossChoices.isValidChoice(10))
        XCTAssertFalse(CPLExposureLossChoices.isValidChoice(1.25))
        XCTAssertTrue(CPLExposureLossChoices.isValidChoice(0.1))
        XCTAssertTrue(CPLExposureLossChoices.isValidChoice(9.9))
        XCTAssertTrue(CPLExposureLossChoices.isValidChoice(1.5))
    }

    func testEmptyFieldsOmitChoicesAndDuplicatesCollapse() {
        let choices = CPLExposureLossChoices(fields: [2, nil, 2])
        XCTAssertTrue(choices.isValid)
        XCTAssertEqual(choices.shootingChoices, [2])
        XCTAssertEqual(choices.fields.count, 3)
    }

    func testAtLeastOneValidChoiceIsRequired() {
        XCTAssertFalse(CPLExposureLossChoices(fields: [nil, nil, nil]).isValid)
        XCTAssertFalse(CPLExposureLossChoices(fields: [1, 1.25, nil]).isValid)
    }

    // MARK: FILTER-CPL-003 — decimal input normalization

    func testCPLFieldParsingNormalizesSeparatorsAndRejectsOutOfRule() {
        XCTAssertEqual(FilterDecimalInput.parseCPLField("1,5"), .value(1.5))
        XCTAssertEqual(FilterDecimalInput.parseCPLField(" 2 "), .value(2))
        XCTAssertEqual(FilterDecimalInput.parseCPLField(""), .empty)
        XCTAssertEqual(FilterDecimalInput.parseCPLField("0"), .invalid)
        XCTAssertEqual(FilterDecimalInput.parseCPLField("10"), .invalid)
        XCTAssertEqual(FilterDecimalInput.parseCPLField("1.25"), .invalid)
        XCTAssertEqual(FilterDecimalInput.parseCPLField("abc"), .invalid)
    }

    func testGeneralDecimalParsing() {
        XCTAssertEqual(FilterDecimalInput.parseDecimal("0,9"), 0.9)
        XCTAssertEqual(FilterDecimalInput.parseDecimal("1000"), 1000)
        XCTAssertNil(FilterDecimalInput.parseDecimal(""))
        XCTAssertNil(FilterDecimalInput.parseDecimal("1e3"))
    }

    // MARK: FILTER-SET-003 — color suggestion

    func testColorSuggestionDiffersFromPreviousSuggestion() {
        var generator = SystemRandomNumberGenerator()
        var previous: FilterSetColor?
        for _ in 0..<200 {
            let next = FilterSetColor.suggestion(excluding: previous, using: &generator)
            XCTAssertNotEqual(next, previous)
            previous = next
        }
    }

    // MARK: FILTER-ITEM-002 — duplicates are distinct items

    func testEqualItemsRemainDistinctByID() {
        let value = FilterRegisteredValue(value: 3, unit: .stops)
        let first = FilterItem(name: "ND8", behavior: .fixed(value))
        let second = FilterItem(name: "ND8", behavior: .fixed(value))
        XCTAssertNotEqual(first.id, second.id)
        let inventory = FilterInventory(filterSets: [FilterSet(name: "Holder", color: .red, items: [first, second])])
        XCTAssertEqual(inventory.item(withID: second.id)?.item, second)
    }
}
