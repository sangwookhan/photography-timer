// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-STACK-007: every ND wheel viewport is numeric-only with a
/// persistent ND / EMPTY label above it and a per-row type category
/// behind each row's color rail; ND values follow the app-global
/// notation through the shared Standard formatter, Empty renders
/// canonical zero, and the original registered representation survives
/// for the status region. CPL, GND, Color, and Effect items are
/// auxiliary filters and never wheel rows (FILTER-STACK-003).
/// FILTER-PERSIST-003: the start-time reference string.
final class FilterWheelPresenterTests: XCTestCase {
    private func wheelRow(_ item: FilterItem, _ choice: FilterRowChoice) -> ResolvedFilterRow? {
        FilterStack.resolvedRow(
            for: FilterWheel(source: .filterSet(FilterSetID(rawValue: "s")), selection: .item(FilterRowSelection(itemID: item.id, choice: choice))),
            inventory: FilterInventory(filterSets: [FilterSet(id: FilterSetID(rawValue: "s"), name: "Lee", color: .red, items: [item])])
        )
    }

    private func row(_ item: FilterItem, _ choice: FilterRowChoice) throws -> ResolvedFilterRow {
        try XCTUnwrap(wheelRow(item, choice))
    }

    private func display(_ item: FilterItem, _ choice: FilterRowChoice, _ mode: NDNotationMode) throws -> FilterWheelRowDisplay {
        FilterWheelPresenter.rowDisplay(for: try row(item, choice), notationMode: mode)
    }

    // MARK: FILTER-A11Y-001/005 — stable identity and dynamic value

    func testWheelAccessibilityLabelStaysStableWhileDynamicValueChanges() throws {
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let fixedDisplay = try display(nd1000, .fixed, .stops)
        let label = FilterWheelPresenter.wheelAccessibilityLabel(
            position: 2,
            wheelCount: 3,
            sourceName: "Lee"
        )
        XCTAssertEqual(label, "Filter 2 of 3, Lee")
        XCTAssertEqual(fixedDisplay.accessibilityValueText, "Big Stopper, ND, 10 stops")

        let nd8 = FilterItem(name: "Lee ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let changedValue = try display(nd8, .fixed, .stops).accessibilityValueText
        XCTAssertNotEqual(fixedDisplay.accessibilityValueText, changedValue)
        XCTAssertEqual(
            FilterWheelPresenter.wheelAccessibilityLabel(
                position: 2,
                wheelCount: 3,
                sourceName: "Lee"
            ),
            label,
            "Changing the committed value must not alter the stable wheel label."
        )
    }

    func testWheelAccessibilityValuesCoverEveryRowKindAndUnavailableState() throws {
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        XCTAssertEqual(try display(nd1000, .fixed, .opticalDensity).accessibilityValueText, "Big Stopper, ND, 10 stops")

        let emptyDisplay = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil),
            notationMode: .stops
        )
        XCTAssertEqual(emptyDisplay.accessibilityValueText, "Empty, 0 stops")

        let standardDisplay = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(
                selection: .standard(NDStep(stops: 3)),
                contributionStops: 3,
                registeredStops: 3,
                item: nil
            ),
            notationMode: .stops
        )
        XCTAssertEqual(standardDisplay.accessibilityValueText, "Standard, ND, 3 stops")

        let unavailable = FilterWheelPresenter.rowDisplay(
            for: FilterWheelRowOption(row: try row(nd1000, .fixed), unavailability: .exceedsTotalLimit),
            notationMode: .stops
        )
        XCTAssertEqual(
            unavailable.accessibilityValueText,
            "Big Stopper, ND, 10 stops, Exceeds 30 stops"
        )

        // Auxiliary kinds never resolve as wheel rows (FILTER-STACK-003).
        let cpl = FilterItem(name: "Lee CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        XCTAssertNil(wheelRow(cpl, .cplLoss(1.5)))
        let gnd = FilterItem(name: "Lee GND 0.9", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        XCTAssertNil(wheelRow(gnd, .gnd(.recordOnly)))
    }

    // MARK: FILTER-A11Y-005 — a successful adjustment speaks the value then the Total

    func testWheelAccessibilityValueAppendsTheCurrentTotalOnceAfterTheCommittedValue() throws {
        let nd8 = FilterItem(name: "Lee ND8", behavior: .fixed(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let total = NDStackTotalDisplayState(totalStopsText: "21.6", isAtMaximum: false, wheelCount: 3)
        let spoken = FilterWheelPresenter.wheelAccessibilityValue(
            committed: try display(nd8, .fixed, .stops),
            total: total
        )
        XCTAssertEqual(spoken, "Lee ND8, ND, 3 stops, Total 21.6 stops")
        XCTAssertEqual(spoken.components(separatedBy: "Total").count - 1, 1, "The Total is spoken exactly once.")

        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        XCTAssertEqual(
            FilterWheelPresenter.wheelAccessibilityValue(
                committed: try display(nd1000, .fixed, .opticalDensity),
                total: NDStackTotalDisplayState(totalStopsText: "13", isAtMaximum: false, wheelCount: 2)
            ),
            "Big Stopper, ND, 10 stops, Total 13 stops",
            "The value stays canonical stops in every notation; the Total follows it."
        )

        let standard = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(selection: .standard(NDStep(stops: 30)), contributionStops: 30, registeredStops: 30, item: nil),
            notationMode: .stops
        )
        XCTAssertEqual(
            FilterWheelPresenter.wheelAccessibilityValue(
                committed: standard,
                total: NDStackTotalDisplayState(totalStopsText: "30", isAtMaximum: true, wheelCount: 1)
            ),
            "Standard, ND, 30 stops, Total 30 stops · Maximum"
        )
    }

    func testRejectionAndBoundarySpeechCarryNoValueAndNoTotal() {
        for text in [
            FilterWheelPresenter.rejectionText(for: .exceedsTotalLimit),
            FilterWheelPresenter.rejectionText(for: .itemAlreadyMounted),
            FilterWheelPresenter.boundaryText(),
        ] {
            XCTAssertFalse(text.contains("Total"), "\(text) is the reason alone.")
            XCTAssertFalse(text.contains("stops,"), "\(text) repeats no value.")
        }
    }

    func testPlusAccessibilityHintNamesTheDisplayedSourceAndNeedsNoDragOrLongPress() {
        let hint = FilterWheelPresenter.plusAccessibilityHint(sourceName: "Lee holder")
        XCTAssertTrue(hint.contains("Lee holder"))
        XCTAssertTrue(hint.hasPrefix("Double-tap to add a filter from"))
        XCTAssertFalse(hint.lowercased().contains("long press"))
        XCTAssertTrue(hint.contains("manage Filter Sets"))
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

    // MARK: Per-row type category behind the color rail (spec revision 7f727082)

    func testEveryRowCarriesItsTypeCategoryWithFullAccessibleNamesAndNoTypeWords() throws {
        let nd = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        XCTAssertEqual(try display(nd, .fixed, .stops).typeCategory, .nd)
        let empty = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil),
            notationMode: .stops
        )
        XCTAssertEqual(empty.typeCategory, .empty)
        let standard = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(selection: .standard(NDStep(stops: 2)), contributionStops: 2, registeredStops: 2, item: nil),
            notationMode: .stops
        )
        XCTAssertEqual(standard.typeCategory, .nd)

        // Visual rows are numeric-only: the value text carries no type
        // words; the accessible text keeps the full names.
        for display in [try display(nd, .fixed, .stops), empty, standard] {
            XCTAssertNil(display.compactValueText.rangeOfCharacter(from: .letters), "\(display.compactValueText) must stay numeric-only.")
        }
        XCTAssertEqual(try display(nd, .fixed, .stops).expandedLabelText, "ND8 · 3 stops")
        XCTAssertEqual(empty.expandedLabelText, "Empty · no filter mounted")
    }

    func testRowCategoriesFollowEachCandidateRegardlessOfTheCenteredRow() throws {
        let nd = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let nd2 = FilterItem(name: "ND2", behavior: .fixed(FilterRegisteredValue(value: 1, unit: .stops)))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, nil, nil])))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let set = FilterSet(name: "Lee", color: .teal, items: [nd, cpl, gnd, nd2])
        let inventory = FilterInventory(filterSets: [set])
        let stack = try XCTUnwrap(FilterStack.validated(
            wheels: [
                FilterWheel(source: .filterSet(set.id), selection: .item(FilterRowSelection(itemID: nd.id, choice: .fixed))),
                .empty(in: set.id),
            ],
            inventory: inventory
        ))
        // Rows of the second wheel in picker order: Empty plus the
        // set's ND items only, weakest first (FILTER-STACK-003); ND8 is
        // disabled here (mounted on wheel 0) yet keeps its category.
        let options = stack.rowOptions(forWheelAt: 1, inventory: inventory, scale: .oneThirdStop)
        let displays = options.map { FilterWheelPresenter.rowDisplay(for: $0, notationMode: .opticalDensity) }
        XCTAssertEqual(displays.map(\.typeCategory), [.empty, .nd, .nd])
        XCTAssertEqual(displays.map(\.compactValueText), ["0.0", "0.3", "0.9"])
        XCTAssertEqual(displays[2].isAvailable, false)
        XCTAssertEqual(displays[2].typeCategory, .nd)
        // The set's own color (teal) is not part of the row display at
        // all: categories come from the row.
        XCTAssertEqual(set.color, .teal)

        // A Standard ladder is all ND.
        let standardStack = FilterStack(standardSteps: [NDStep(stops: 2), NDStep(stops: 0)])
        let standardDisplays = standardStack.rowOptions(forWheelAt: 0, inventory: inventory, scale: .oneThirdStop)
            .map { FilterWheelPresenter.rowDisplay(for: $0, notationMode: .stops) }
        XCTAssertEqual(Set(standardDisplays.map(\.typeCategory)), [.nd])
    }

    // MARK: Empty aligned with Standard zero (spec revision b61b6347)

    func testEmptyRendersCanonicalZeroLikeStandardZeroWhileStayingADistinctState() {
        let emptyRow = ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil)
        let zeroRow = ResolvedFilterRow(selection: .standard(NDStep(stops: 0)), contributionStops: 0, registeredStops: 0, item: nil)
        let expected: [(NDNotationMode, String)] = [(.stops, "0"), (.opticalDensity, "0.0"), (.filterFactor, "1")]
        for (mode, value) in expected {
            let empty = FilterWheelPresenter.rowDisplay(for: emptyRow, notationMode: mode)
            let zero = FilterWheelPresenter.rowDisplay(for: zeroRow, notationMode: mode)
            XCTAssertEqual(empty.compactValueText, value, "Empty in \(mode)")
            XCTAssertEqual(zero.compactValueText, value, "Standard zero in \(mode)")
            XCTAssertEqual(empty.compactValueText, zero.compactValueText, "Same shared formatter output in \(mode)")
            // Labels and meaning stay apart.
            XCTAssertEqual(empty.typeLabel, "EMPTY")
            XCTAssertEqual(empty.typeCategory, .empty)
            XCTAssertEqual(zero.typeLabel, "ND")
            XCTAssertEqual(zero.typeCategory, .nd)
            XCTAssertEqual(empty.expandedLabelText, "Empty · no filter mounted")
            XCTAssertNotEqual(empty.expandedLabelText, zero.expandedLabelText)
            XCTAssertTrue(empty.isEmpty)
            XCTAssertFalse(empty.isMounted)
            XCTAssertEqual(empty.selection, .empty)
            XCTAssertEqual(zero.selection, .standard(NDStep(stops: 0)))
            XCTAssertNotEqual(empty.selection, zero.selection, "Domain identities remain different.")
            XCTAssertNotEqual(empty, zero)
        }
    }

    func testEmptyAndStandardRows() {
        let empty = FilterWheelPresenter.rowDisplay(
            for: ResolvedFilterRow(selection: .empty, contributionStops: 0, registeredStops: 0, item: nil),
            notationMode: .filterFactor
        )
        XCTAssertEqual(empty.compactValueText, "1", "Empty shows canonical zero in ND notation.")
        XCTAssertEqual(empty.typeLabel, "EMPTY")
        XCTAssertTrue(empty.isEmpty)

        let standard = ResolvedFilterRow(selection: .standard(NDStep(stops: 9)), contributionStops: 9, registeredStops: 9, item: nil)
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .stops).compactValueText, "9")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .opticalDensity).compactValueText, "2.7")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .filterFactor).compactValueText, "512")
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: standard, notationMode: .stops).typeLabel, "ND")
    }

    func testUnavailableRowsCarryTheirReason() throws {
        let nd = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let option = FilterWheelRowOption(row: try row(nd, .fixed), unavailability: .itemAlreadyMounted)
        XCTAssertEqual(FilterWheelPresenter.rowDisplay(for: option, notationMode: .stops).unavailabilityText, "Already mounted on this camera")
        XCTAssertEqual(FilterWheelPresenter.rejectionText(for: .tooManyNDWheels), "Reduce the ND wheels to three or fewer")
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
