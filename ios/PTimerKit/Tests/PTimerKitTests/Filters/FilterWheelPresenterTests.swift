// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-STACK-007: Filter Item rows keep their registered
/// representation independently of the Standard notation, and the
/// expanded label carries name, representation, mode, and canonical
/// contribution. FILTER-PERSIST-003: the start-time reference string.
final class FilterWheelPresenterTests: XCTestCase {
    private func row(_ item: FilterItem, _ choice: FilterRowChoice) throws -> ResolvedFilterRow {
        try XCTUnwrap(FilterStack.resolvedRow(
            for: FilterWheel(source: .filterSet(FilterSetID(rawValue: "s")), selection: .item(FilterRowSelection(itemID: item.id, choice: choice))),
            inventory: FilterInventory(filterSets: [FilterSet(id: FilterSetID(rawValue: "s"), name: "Lee", color: .red, items: [item])])
        ))
    }

    func testFixedAndGNDCompactValuesPreserveTheRegisteredRepresentation() throws {
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let od = FilterItem(name: "Lee GND 0.9", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let stops = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))

        let big = FilterWheelPresenter.rowDisplay(for: try row(nd1000, .fixed), notationMode: .stops)
        XCTAssertEqual(big.compactValueText, "ND1000")
        XCTAssertEqual(big.registeredText, "ND1000")
        XCTAssertNil(big.modeCaption)
        XCTAssertEqual(big.expandedLabelText, "Big Stopper · ND1000 · 9.97 stops")

        let rec = FilterWheelPresenter.rowDisplay(for: try row(od, .gnd(.recordOnly)), notationMode: .stops)
        XCTAssertEqual(rec.compactValueText, "OD 0.9")
        XCTAssertEqual(rec.modeCaption, "Rec")
        XCTAssertEqual(rec.expandedLabelText, "Lee GND 0.9 · OD 0.9 · Record only · 0 stops")

        let full = FilterWheelPresenter.rowDisplay(for: try row(od, .gnd(.applyFullValue)), notationMode: .stops)
        XCTAssertEqual(full.compactValueText, "OD 0.9")
        XCTAssertEqual(full.modeCaption, "Full")
        XCTAssertEqual(full.expandedLabelText, "Lee GND 0.9 · OD 0.9 · Apply full value · 3 stops")

        let eight = FilterWheelPresenter.rowDisplay(for: try row(stops, .fixed), notationMode: .stops)
        XCTAssertEqual(eight.compactValueText, "3 stops")
        XCTAssertEqual(eight.expandedLabelText, "ND8 · 3 stops", "A stops-registered item shows its value once.")
    }

    func testCPLCompactValueIsTheSelectedChoice() throws {
        let cpl = FilterItem(name: "Lee CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let display = FilterWheelPresenter.rowDisplay(for: try row(cpl, .cplLoss(1.5)), notationMode: .stops)
        XCTAssertEqual(display.compactValueText, "CPL 1.5")
        XCTAssertNil(display.modeCaption)
        XCTAssertEqual(display.expandedLabelText, "Lee CPL · CPL 1.5 · 1.5 stops")
    }

    func testStandardNotationDoesNotChangeFilterItemValuesButChangesStandardRows() throws {
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let item = try row(nd1000, .fixed)
        for mode in NDNotationMode.allCases {
            XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: item, notationMode: mode).compactValueText, "ND1000")
        }
        let standard = ResolvedFilterRow(selection: .standard(NDStep(stops: 9)), contributionStops: 9, registeredStops: 9, item: nil)
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .stops).compactValueText, "9")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .opticalDensity).compactValueText, "2.7")
        // The Standard wheel's band carries the `ND` unit; the row shows the factor.
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .filterFactor).compactValueText, "512")
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
