// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

/// Filter Set contract — mixed stack rules (FILTER-STACK-001…006,
/// FILTER-GND-001/002, FILTER-CPL-005, FILTER-PLUS-005,
/// FILTER-PERSIST-002) driven by the spec's verification examples.
final class FilterStackTests: XCTestCase {
    private let scale = ExposureScale.oneThirdStop

    private func stops(_ value: Double) -> FilterRegisteredValue {
        FilterRegisteredValue(value: value, unit: .stops)
    }

    private func fixed(_ name: String, _ value: Double) -> FilterItem {
        FilterItem(name: name, behavior: .fixed(stops(value)))
    }

    private func select(_ item: FilterItem, _ choice: FilterRowChoice = .fixed) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: item.id, choice: choice))
    }

    // MARK: Example 1 — two separate 3-stop items, exclusivity by id

    func testTwoEqualItemsSumWhileASecondSelectionOfEitherIsUnavailable() throws {
        let a = fixed("ND8", 3)
        let b = fixed("ND8", 3)
        let set = FilterSet(name: "Holder", color: .blue, items: [a, b])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(single: NDStep(stops: 0))
            .addingWheel(for: .filterSet(set.id), inventory: inventory)
            .addingWheel(for: .filterSet(set.id), inventory: inventory)

        stack = try stack.replacingWheel(at: 1, with: select(a), inventory: inventory).get()
        stack = try stack.replacingWheel(at: 2, with: select(b), inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 6, accuracy: 1e-9)

        let options = stack.rowOptions(forWheelAt: 2, inventory: inventory, scale: scale)
        XCTAssertEqual(options.first { $0.selection == select(a) }?.unavailability, .itemAlreadyMounted)
        XCTAssertNil(options.first { $0.selection == select(b) }?.unavailability, "The wheel's own item stays available.")
        XCTAssertEqual(
            stack.replacingWheel(at: 2, with: select(a), inventory: inventory),
            .failure(.itemAlreadyMounted)
        )
    }

    // MARK: Example 2 — Standard 2 + item 3 + item 4 = 9, source ordering

    func testMixedSumIsPreservedAcrossSourceOrderSorting() throws {
        let three = fixed("Three", 3)
        let four = fixed("Four", 4)
        let setA = FilterSet(name: "A", color: .red, items: [three])
        let setB = FilterSet(name: "B", color: .green, items: [four])
        let inventory = FilterInventory(filterSets: [setA, setB])
        // Deliberately out of source order: B, A, Standard.
        let stack = FilterStack(
            wheels: [
                FilterWheel(source: .filterSet(setB.id), selection: select(four)),
                FilterWheel(source: .filterSet(setA.id), selection: select(three)),
                .standard(NDStep(stops: 2)),
            ],
            inventory: inventory
        )
        XCTAssertEqual(stack.effectiveStep.stops, 9, accuracy: 1e-9)

        let sorted = stack.sortedForCommit(inventory: inventory)
        XCTAssertEqual(sorted.wheels.map(\.source), [.standard, .filterSet(setA.id), .filterSet(setB.id)])
        XCTAssertEqual(sorted.effectiveStep.stops, 9, accuracy: 1e-9)
        XCTAssertEqual(stack.commitSortPermutation(inventory: inventory), [2, 1, 0])
    }

    func testWithinSourceSortIsDescendingWithEmptyLast() {
        let one = fixed("One", 1)
        let five = fixed("Five", 5)
        let set = FilterSet(name: "S", color: .teal, items: [one, five])
        let inventory = FilterInventory(filterSets: [set])
        let stack = FilterStack(
            wheels: [
                .empty(in: set.id),
                FilterWheel(source: .filterSet(set.id), selection: select(one)),
                .standard(NDStep(stops: 0)),
                FilterWheel(source: .filterSet(set.id), selection: select(five)),
            ],
            inventory: inventory
        )
        let sorted = stack.sortedForCommit(inventory: inventory)
        XCTAssertEqual(sorted.wheels[0].selection, .standard(NDStep(stops: 0)))
        XCTAssertEqual(sorted.wheels[1].selection, select(five))
        XCTAssertEqual(sorted.wheels[2].selection, select(one))
        XCTAssertEqual(sorted.wheels[3].selection, .empty)
    }

    // MARK: Example 4 — GND Record only vs Apply full value

    func testGNDRecordOnlyContributesZeroAndApplyFullContributesRegisteredValue() throws {
        let gnd = FilterItem(name: "GND 0.6", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "GND", color: .purple, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(wheels: [.standard(NDStep(stops: 3)), .empty(in: set.id)], inventory: inventory)

        stack = try stack.replacingWheel(at: 1, with: select(gnd, .gnd(.recordOnly)), inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 3, accuracy: 1e-9)
        XCTAssertNotNil(stack.wheels[1].mountedItemID, "Record only is a mounted item.")
        XCTAssertFalse(stack.wheels[1].isCleanable, "A mounted Record-only item is never cleaned up.")
        XCTAssertFalse(stack.canRemoveEmptyWheel)

        stack = try stack.replacingWheel(at: 1, with: select(gnd, .gnd(.applyFullValue)), inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 5, accuracy: 1e-9)
        // The GND sorts by its registered value even in Record-only mode.
        XCTAssertEqual(stack.rows[1].registeredStops, 2)
    }

    func testEmptyAndRecordOnlyAreDistinctStates() throws {
        let gnd = FilterItem(name: "GND", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "GND", color: .purple, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        let empty = FilterStack(wheels: [.standard(NDStep(stops: 1)), .empty(in: set.id)], inventory: inventory)
        XCTAssertTrue(empty.wheels[1].isCleanable)
        XCTAssertTrue(empty.canRemoveEmptyWheel)
        XCTAssertEqual(empty.removingRightmostEmptyWheel().wheels.count, 1)

        let recordOnly = try empty.replacingWheel(at: 1, with: select(gnd, .gnd(.recordOnly)), inventory: inventory).get()
        XCTAssertEqual(recordOnly.effectiveStep, empty.effectiveStep)
        XCTAssertNotEqual(recordOnly.wheels[1], empty.wheels[1])
        XCTAssertEqual(recordOnly.removingRightmostEmptyWheel().wheels.count, 2)
    }

    // MARK: Example 5 — CPL rows and sibling exclusivity

    func testCPLRowsAreDistinctChoicesAndSiblingsDisableEveryRowOfTheItem() throws {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let set = FilterSet(name: "CPL", color: .orange, items: [cpl])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(wheels: [.empty(in: set.id), .empty(in: set.id)], inventory: inventory)

        let ownRows = stack.rowOptions(forWheelAt: 0, inventory: inventory, scale: scale)
        XCTAssertEqual(ownRows.map(\.selection), [.empty, select(cpl, .cplLoss(1)), select(cpl, .cplLoss(1.5)), select(cpl, .cplLoss(2))])

        stack = try stack.replacingWheel(at: 0, with: select(cpl, .cplLoss(1.5)), inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 1.5, accuracy: 1e-9)

        let siblingRows = stack.rowOptions(forWheelAt: 1, inventory: inventory, scale: scale)
        for option in siblingRows where option.selection != .empty {
            XCTAssertEqual(option.unavailability, .itemAlreadyMounted)
        }
        // The owning wheel may switch between the item's own rows.
        let owning = stack.rowOptions(forWheelAt: 0, inventory: inventory, scale: scale)
        XCTAssertTrue(owning.allSatisfy(\.isAvailable))
        stack = try stack.replacingWheel(at: 0, with: select(cpl, .cplLoss(2)), inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 2, accuracy: 1e-9)
    }

    // MARK: Example 6 — cap behavior with Record only

    func testRecordOnlyRemainsAddableAtCapAndEnablingContributionIsRejected() throws {
        let gnd = FilterItem(name: "GND", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "GND", color: .purple, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(wheels: [.standard(NDStep(stops: 30))], inventory: inventory)

        XCTAssertNil(stack.addUnavailability(for: .filterSet(set.id), inventory: inventory, scale: scale))
        XCTAssertEqual(stack.addUnavailability(for: .standard, inventory: inventory, scale: scale), .noSelectableValue)

        stack = stack.addingWheel(for: .filterSet(set.id), inventory: inventory)
        stack = try stack.replacingWheel(at: 1, with: select(gnd, .gnd(.recordOnly)), inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 30, accuracy: 1e-9)

        let before = stack
        XCTAssertEqual(
            stack.replacingWheel(at: 1, with: select(gnd, .gnd(.applyFullValue)), inventory: inventory),
            .failure(.exceedsTotalLimit)
        )
        XCTAssertEqual(stack, before, "A rejected change leaves the previous state intact.")
        let options = stack.rowOptions(forWheelAt: 1, inventory: inventory, scale: scale)
        XCTAssertEqual(options.first { $0.selection == select(gnd, .gnd(.applyFullValue)) }?.unavailability, .exceedsTotalLimit)
    }

    func testAddUnavailabilityReasons() {
        let mounted = fixed("Only", 3)
        let set = FilterSet(name: "One item", color: .pink, items: [mounted])
        let emptySet = FilterSet(name: "Empty", color: .pink)
        let inventory = FilterInventory(filterSets: [set, emptySet])
        let stack = FilterStack(
            wheels: [FilterWheel(source: .filterSet(set.id), selection: select(mounted))],
            inventory: inventory
        )
        XCTAssertEqual(stack.addUnavailability(for: .filterSet(set.id), inventory: inventory, scale: scale), .allItemsMounted)
        XCTAssertEqual(stack.addUnavailability(for: .filterSet(emptySet.id), inventory: inventory, scale: scale), .filterSetHasNoItems)
        XCTAssertEqual(stack.addUnavailability(for: .filterSet(FilterSetID.generate()), inventory: inventory, scale: scale), .unknownFilterSet)
        XCTAssertNil(stack.addUnavailability(for: .standard, inventory: inventory, scale: scale))
        let full = FilterStack(standardSteps: [NDStep(stops: 1), NDStep(stops: 1), NDStep(stops: 1), NDStep(stops: 1)])
        XCTAssertEqual(full.addUnavailability(for: .standard, inventory: inventory, scale: scale), .stackFull)
    }

    func testAddingAWheelNeverChangesTheEffectiveValue() {
        let set = FilterSet(name: "S", color: .red, items: [fixed("X", 4)])
        let inventory = FilterInventory(filterSets: [set])
        let stack = FilterStack(single: NDStep(stops: 6.6))
        let added = stack.addingWheel(for: .filterSet(set.id), inventory: inventory)
        XCTAssertEqual(added.wheels.count, 2)
        XCTAssertEqual(added.wheels[1], .empty(in: set.id))
        XCTAssertEqual(added.effectiveStep, stack.effectiveStep)
        XCTAssertEqual(stack.addingWheel(for: .filterSet(FilterSetID.generate()), inventory: inventory), stack)
    }

    // MARK: Standard wheels keep the budget-truncated ladder

    func testStandardRowsAreTruncatedToTheRemainingBudget() {
        let item = fixed("Big", 25)
        let set = FilterSet(name: "S", color: .red, items: [item])
        let inventory = FilterInventory(filterSets: [set])
        let stack = FilterStack(
            wheels: [.standard(NDStep(stops: 0)), FilterWheel(source: .filterSet(set.id), selection: select(item))],
            inventory: inventory
        )
        let rows = stack.rowOptions(forWheelAt: 0, inventory: inventory, scale: scale)
        XCTAssertEqual(rows.last?.row.contributionStops, 5)
        XCTAssertTrue(rows.allSatisfy(\.isAvailable))
        XCTAssertEqual(
            stack.replacingWheel(at: 0, with: .standard(NDStep(stops: 6)), inventory: inventory),
            .failure(.exceedsTotalLimit)
        )
    }

    // MARK: FILTER-PERSIST-002 — safe normalization

    func testNormalizationDropsUnknownSetsEmptiesUnknownItemsAndFallsBackToStandardZero() {
        let item = fixed("X", 4)
        let set = FilterSet(name: "S", color: .red, items: [item])
        let inventory = FilterInventory(filterSets: [set])
        let unknownSet = FilterSetID.generate()
        let wheels: [FilterWheel] = [
            FilterWheel(source: .filterSet(unknownSet), selection: .empty),
            FilterWheel(source: .filterSet(set.id), selection: .item(FilterRowSelection(itemID: .generate(), choice: .fixed))),
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
        ]
        let normalized = FilterStack.normalizedWheels(wheels, inventory: inventory)
        XCTAssertEqual(normalized, [
            .empty(in: set.id),
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
            .empty(in: set.id),
        ])
        XCTAssertEqual(
            FilterStack.normalizedWheels([FilterWheel(source: .filterSet(unknownSet), selection: .empty)], inventory: inventory),
            [.standard(NDStep(stops: 0))]
        )
        XCTAssertNil(FilterStack.normalizedWheels(Array(repeating: .standard(NDStep(stops: 0)), count: 5), inventory: inventory))
    }

    func testNormalizationFallsBackToAnItemsFirstRowWhenTheChosenRowIsGone() {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 2, nil])))
        let set = FilterSet(name: "CPL", color: .orange, items: [cpl])
        let inventory = FilterInventory(filterSets: [set])
        let wheel = FilterWheel(source: .filterSet(set.id), selection: select(cpl, .cplLoss(1.5)))
        XCTAssertEqual(
            FilterStack.normalizedWheels([wheel], inventory: inventory),
            [FilterWheel(source: .filterSet(set.id), selection: select(cpl, .cplLoss(1)))]
        )
    }

    func testValidatedRejectsOverCapDuplicateAndUnresolvedWheels() {
        let big = fixed("Big", 20)
        let set = FilterSet(name: "S", color: .red, items: [big])
        let inventory = FilterInventory(filterSets: [set])
        XCTAssertNil(FilterStack.validated(
            wheels: [.standard(NDStep(stops: 11)), FilterWheel(source: .filterSet(set.id), selection: select(big))],
            inventory: inventory
        ))
        XCTAssertNil(FilterStack.validated(
            wheels: [FilterWheel(source: .filterSet(set.id), selection: select(big)), FilterWheel(source: .filterSet(set.id), selection: select(big))],
            inventory: inventory
        ))
        XCTAssertNil(FilterStack.validated(wheels: [.empty(in: FilterSetID.generate())], inventory: inventory))
        XCTAssertNil(FilterStack.validated(wheels: [], inventory: inventory))
        XCTAssertNotNil(FilterStack.validated(
            wheels: [.standard(NDStep(stops: 10)), FilterWheel(source: .filterSet(set.id), selection: select(big))],
            inventory: inventory
        ))
    }

    // MARK: FILTER-PERSIST-003 — summary capture

    func testSummaryCapturesSourceItemModeAndContribution() throws {
        let gnd = FilterItem(name: "Lee GND 0.9", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        let set = FilterSet(name: "Lee holder", color: .indigo, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        let stack = FilterStack(
            wheels: [.standard(NDStep(stops: 6.6)), FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly))), .empty(in: set.id)],
            inventory: inventory
        )
        let summary = FilterSummaryEntry.summary(for: stack, inventory: inventory)
        XCTAssertEqual(summary.count, 2, "Empty wheels are omitted.")
        XCTAssertEqual(summary[0].sourceKind, .standard)
        XCTAssertEqual(summary[0].contributedStops, 6.6)
        let entry = summary[1]
        XCTAssertEqual(entry.sourceKind, .filterSet)
        XCTAssertEqual(entry.filterSetID, set.id.rawValue)
        XCTAssertEqual(entry.filterSetName, "Lee holder")
        XCTAssertEqual(entry.itemID, gnd.id.rawValue)
        XCTAssertEqual(entry.itemName, "Lee GND 0.9")
        XCTAssertEqual(entry.itemKind, .gnd)
        XCTAssertEqual(entry.originalValue, 0.9)
        XCTAssertEqual(entry.originalUnit, .opticalDensity)
        XCTAssertEqual(try XCTUnwrap(entry.canonicalStops), 3, accuracy: 1e-9)
        XCTAssertEqual(entry.calculationMode, .gndRecordOnly)
        XCTAssertEqual(entry.contributedStops, 0)
    }
}
