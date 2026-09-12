// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-STACK-007 (spec revision `b46c9102`): every wheel viewport
/// is numeric-only with a persistent type / mode label above it; Fixed
/// and GND values follow the app-global notation through the shared
/// Standard formatter, CPL values stay exposure loss in stops, Empty is
/// blank, and the original registered representation survives for the
/// status region. FILTER-PERSIST-003: the start-time reference string.
final class FilterWheelPresenterTests: XCTestCase {
    private func row(_ item: FilterItem, _ choice: FilterRowChoice) throws -> ResolvedFilterRow {
        try XCTUnwrap(FilterStack.resolvedRow(
            for: FilterWheel(source: .filterSet(FilterSetID(rawValue: "s")), selection: .item(FilterRowSelection(itemID: item.id, choice: choice))),
            inventory: FilterInventory(filterSets: [FilterSet(id: FilterSetID(rawValue: "s"), name: "Lee", color: .red, items: [item])])
        ))
    }

    private func display(_ item: FilterItem, _ choice: FilterRowChoice, _ mode: NDNotationMode) throws -> FilterWheelRowDisplay {
        FilterWheelPresenter.rowDisplay(for: try row(item, choice), notationMode: mode)
    }

    // MARK: Numeric viewport in every notation (ND1000 = exactly 10 stops)

    func testFixedValuesFollowTheGlobalNotationNumericOnly() throws {
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        XCTAssertEqual(try display(nd1000, .fixed, .stops).compactValueText, "10")
        XCTAssertEqual(try display(nd1000, .fixed, .opticalDensity).compactValueText, "3.0")
        XCTAssertEqual(try display(nd1000, .fixed, .filterFactor).compactValueText, "1000")

        let three = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        XCTAssertEqual(try display(three, .fixed, .stops).compactValueText, "3")
        XCTAssertEqual(try display(three, .fixed, .opticalDensity).compactValueText, "0.9")
        XCTAssertEqual(try display(three, .fixed, .filterFactor).compactValueText, "8")

        let big = try display(nd1000, .fixed, .stops)
        XCTAssertEqual(big.typeLabel, "ND")
        XCTAssertNil(big.modeLabel)
        XCTAssertEqual(big.registeredText, "ND1000", "The original representation survives as reference text.")
        XCTAssertEqual(big.expandedLabelText, "Big Stopper · ND1000 · 10 stops")
    }

    func testGNDShowsRegisteredDensityInBothModesWithRecOrFullLabels() throws {
        let od = FilterItem(name: "Lee GND 0.9", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let rec = try display(od, .gnd(.recordOnly), .stops)
        XCTAssertEqual(rec.compactValueText, "3", "Record only still shows the registered full density.")
        XCTAssertEqual(rec.typeLabel, "GND")
        XCTAssertEqual(rec.modeLabel, "REC")
        XCTAssertEqual(rec.expandedLabelText, "Lee GND 0.9 · OD 0.9 · Record only · 0 stops")

        let full = try display(od, .gnd(.applyFullValue), .opticalDensity)
        XCTAssertEqual(full.compactValueText, "0.9")
        XCTAssertEqual(full.modeLabel, "FULL")
        XCTAssertEqual(full.expandedLabelText, "Lee GND 0.9 · OD 0.9 · Apply full value · 3 stops")
        XCTAssertEqual(try display(od, .gnd(.applyFullValue), .filterFactor).compactValueText, "8")
    }

    func testCPLValuesStayInStopsInEveryNotation() throws {
        let cpl = FilterItem(name: "Lee CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        for mode in NDNotationMode.allCases {
            let display = try display(cpl, .cplLoss(1.5), mode)
            XCTAssertEqual(display.compactValueText, "1.5", "\(mode)")
            XCTAssertEqual(display.typeLabel, "CPL")
            XCTAssertNil(display.modeLabel)
        }
        let display = try display(cpl, .cplLoss(1.5), .stops)
        XCTAssertEqual(display.registeredText, "CPL 1.5")
        XCTAssertEqual(display.expandedLabelText, "Lee CPL · CPL 1.5 · 1.5 stops")
    }

    func testEmptyAndStandardRows() {
        let empty = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil),
            notationMode: .filterFactor
        )
        XCTAssertEqual(empty.compactValueText, "", "Empty keeps a blank centered value.")
        XCTAssertEqual(empty.typeLabel, "EMPTY")
        XCTAssertTrue(empty.isEmpty)

        let standard = ResolvedFilterRow(selection: .standard(NDStep(stops: 9)), contributionStops: 9, registeredStops: 9, item: nil)
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .stops).compactValueText, "9")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .opticalDensity).compactValueText, "2.7")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .filterFactor).compactValueText, "512")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .stops).typeLabel, "ND")
    }

    func testUnavailableRowsCarryTheirReason() throws {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(.defaults))
        let option = FilterWheelRowOption(row: try row(cpl, .cplLoss(1)), unavailability: .itemAlreadyMounted)
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: option, notationMode: .stops).unavailabilityText, "Already mounted on this camera")
    }

    // MARK: FILTER-PERSIST-003 — reference string

    func testReferenceTextGroupsItemsBySetWithRepresentationAndMode() {
        let summary: [FilterSummaryEntry] = [
            FilterSummaryEntry(sourceKind: .standard, canonicalStops: 2, contributedStops: 2),
            FilterSummaryEntry(sourceKind: .filterSet, filterSetID: "haida", filterSetName: "Haida 100mm", itemID: "a", itemName: "Big Stopper", itemKind: .fixed, originalValue: 400, originalUnit: .filterFactor, canonicalStops: log2(400), calculationMode: .fixed, contributedStops: log2(400)),
            FilterSummaryEntry(sourceKind: .filterSet, filterSetID: "haida", filterSetName: "Haida 100mm", itemID: "b", itemName: "GND", itemKind: .gnd, originalValue: 2, originalUnit: .stops, canonicalStops: 2, calculationMode: .gndRecordOnly, contributedStops: 0),
            FilterSummaryEntry(sourceKind: .filterSet, filterSetID: "nisi", filterSetName: "NiSi", itemID: "c", itemName: "CPL", itemKind: .cpl, canonicalStops: 1.5, calculationMode: .cplLoss, contributedStops: 1.5),
        ]
        XCTAssertEqual(
            FilterSummaryReferencePresenter.referenceText(for: summary),
            "Standard 2 stops · Haida 100mm: Big Stopper ND400 + GND 2 stops (Record only) · NiSi: CPL 1.5 stops"
        )
        XCTAssertNil(FilterSummaryReferencePresenter.referenceText(for: [
            FilterSummaryEntry(sourceKind: .standard, canonicalStops: 0, contributedStops: 0),
        ]), "A Standard 0 wheel alone yields no reference text.")
    }

    func testBasisLineUsesCanonicalStopsForMixedStackTimersOnly() {
        let now = Date(timeIntervalSince1970: 1_000)
        func timer(summary: [FilterSummaryEntry]?) -> RunningTimerItem {
            RunningTimerItem(
                id: UUID(), order: 1, name: "t", basisSummary: "", duration: 10, startDate: now, endDate: now, pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now,
                exposureSource: .digitalResult, ndStops: 12, baseShutterSeconds: 1.0 / 30.0, filterSummary: summary
            )
        }
        let format: (TimeInterval) -> String = { _ in "1/30s" }
        let mixed = timer(summary: [FilterSummaryEntry(sourceKind: .filterSet, canonicalStops: 12, calculationMode: .fixed, contributedStops: 12)])
        XCTAssertEqual(TimerBasisPresenter.basisText(for: mixed, notationMode: .filterFactor, formatShutter: format), "Base 1/30s · 12 stops")
        // A decimal total renders as plain stops, never as a ladder fraction.
        let halfStop = RunningTimerItem(
            id: UUID(), order: 1, name: "t", basisSummary: "", duration: 10, startDate: now, endDate: now, pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now,
            exposureSource: .digitalResult, ndStops: 6.5, baseShutterSeconds: 1.0 / 30.0,
            filterSummary: [FilterSummaryEntry(sourceKind: .filterSet, canonicalStops: 1.5, calculationMode: .cplLoss, contributedStops: 1.5)]
        )
        XCTAssertEqual(TimerBasisPresenter.basisText(for: halfStop, notationMode: .stops, formatShutter: format), "Base 1/30s · 6.5 stops")
        let standardOnly = timer(summary: [FilterSummaryEntry(sourceKind: .standard, canonicalStops: 12, contributedStops: 12)])
        XCTAssertEqual(TimerBasisPresenter.basisText(for: standardOnly, notationMode: .filterFactor, formatShutter: format), "Base 1/30s · ND4000")
    }
}
