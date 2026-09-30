// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

/// Filter Set contract — ND wheels plus mounted auxiliary filters
/// (FILTER-STACK-001…006, FILTER-AUX-003/004, FILTER-GND-001/002,
/// FILTER-CPL-005, FILTER-PLUS-005, FILTER-PERSIST-002/003) driven by
/// the spec's verification examples.
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

    private func mount(_ item: FilterItem, in set: FilterSet, _ choice: AuxiliaryFilterChoice? = nil) -> MountedAuxiliaryFilter {
        MountedAuxiliaryFilter(
            filterSetID: set.id,
            itemID: item.id,
            choice: choice ?? MountedAuxiliaryFilter.initialChoice(for: item) ?? .registeredLoss
        )
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

    // MARK: Example 2 — FILTER-STACK-005 source groups by registered subtotal

    func testSourceGroupsSortByRegisteredSubtotalAndStayContiguous() throws {
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let nd8 = fixed("ND8", 3)
        let nd2 = fixed("ND2", 1)
        let nisi = FilterSet(name: "NiSi", color: .red, items: [nd1000])
        let lee = FilterSet(name: "Lee", color: .green, items: [nd8, nd2])
        let inventory = FilterInventory(filterSets: [nisi, lee])
        // Deliberately interleaved: Standard, Lee, NiSi, Lee.
        let stack = FilterStack(
            wheels: [
                .standard(NDStep(stops: 2)),
                FilterWheel(source: .filterSet(lee.id), selection: select(nd2)),
                FilterWheel(source: .filterSet(nisi.id), selection: select(nd1000)),
                FilterWheel(source: .filterSet(lee.id), selection: select(nd8)),
            ],
            inventory: inventory
        )
        XCTAssertEqual(stack.effectiveStep.stops, 16, accuracy: 1e-9)
        XCTAssertEqual(stack.registeredSubtotal(of: .filterSet(nisi.id)), 10, accuracy: 1e-9)
        XCTAssertEqual(stack.registeredSubtotal(of: .filterSet(lee.id)), 4, accuracy: 1e-9)
        XCTAssertEqual(stack.registeredSubtotal(of: .standard), 2, accuracy: 1e-9)

        // NiSi (10) > Lee (3 + 1 = 4) > Standard (2); Lee's rows descend.
        XCTAssertEqual(stack.commitSortPermutation(inventory: inventory), [2, 3, 1, 0])
        let sorted = stack.sortedForCommit(inventory: inventory)
        XCTAssertEqual(sorted.wheels.map(\.source), [.filterSet(nisi.id), .filterSet(lee.id), .filterSet(lee.id), .standard])
        XCTAssertEqual(sorted.wheels[1].selection, select(nd8))
        XCTAssertEqual(sorted.wheels[2].selection, select(nd2))
        XCTAssertEqual(sorted.effectiveStep.stops, 16, accuracy: 1e-9)
    }

    func testEqualSubtotalsPutStandardFirstThenFilterSetUserOrder() {
        let three = fixed("Three", 3)
        let alsoThree = fixed("Three", 3)
        let setA = FilterSet(name: "A", color: .red, items: [three])
        let setB = FilterSet(name: "B", color: .green, items: [alsoThree])
        let inventory = FilterInventory(filterSets: [setA, setB])
        let stack = FilterStack(
            wheels: [
                FilterWheel(source: .filterSet(setB.id), selection: select(alsoThree)),
                FilterWheel(source: .filterSet(setA.id), selection: select(three)),
                .standard(NDStep(stops: 3)),
            ],
            inventory: inventory
        )
        XCTAssertEqual(stack.commitSortPermutation(inventory: inventory), [2, 1, 0])

        // Reversing the user-defined set order reverses the tie only.
        let reversed = FilterInventory(filterSets: [setB, setA])
        XCTAssertEqual(stack.commitSortPermutation(inventory: reversed), [2, 0, 1])
    }

    func testStandardSelectionCanReorderGroupsOnlyThroughItsSubtotal() throws {
        let four = fixed("Four", 4)
        let set = FilterSet(name: "S", color: .teal, items: [four])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(
            wheels: [.standard(NDStep(stops: 2)), FilterWheel(source: .filterSet(set.id), selection: select(four))],
            inventory: inventory
        )
        XCTAssertEqual(stack.commitSortPermutation(inventory: inventory), [1, 0], "Set (4) ahead of Standard (2).")
        stack = try stack.replacingWheel(at: 0, with: .standard(NDStep(stops: 5)), inventory: inventory).get()
        XCTAssertEqual(stack.commitSortPermutation(inventory: inventory), [0, 1], "Standard (5) now ahead of the set (4).")
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
        // The set's subtotal (5 + 1 + 0) leads Standard 0; within the
        // set Five, One, then Empty.
        let sorted = stack.sortedForCommit(inventory: inventory)
        XCTAssertEqual(sorted.wheels[0].selection, select(five))
        XCTAssertEqual(sorted.wheels[1].selection, select(one))
        XCTAssertEqual(sorted.wheels[2].selection, .empty)
        XCTAssertEqual(sorted.wheels[3].selection, .standard(NDStep(stops: 0)))
        XCTAssertEqual(stack.sortValue(forWheelAt: 0), 0)
        XCTAssertEqual(stack.sortValue(forWheelAt: 2), 0)
    }

    // MARK: Example 4 — GND Record only vs Apply full value (auxiliary)

    func testGNDRecordOnlyContributesZeroAndApplyFullContributesRegisteredValue() throws {
        let gnd = FilterItem(name: "GND 0.6", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "GND", color: .purple, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(wheels: [.standard(NDStep(stops: 3))], inventory: inventory)

        XCTAssertEqual(MountedAuxiliaryFilter.initialChoice(for: gnd), .gnd(.recordOnly), "Record only is the default (FILTER-GND-002).")
        stack = try stack.replacingAuxiliaryFilters(with: [mount(gnd, in: set)], inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 3, accuracy: 1e-9)
        XCTAssertTrue(stack.hasAuxiliaryFilters, "A Record-only GND is mounted even at zero stops (FILTER-AUX-001).")
        XCTAssertEqual(stack.auxiliaryRows.first?.contributionStops, 0)
        XCTAssertEqual(stack.auxiliaryRows.first?.registeredStops, 2, "Registered density stays distinct from the contribution.")
        XCTAssertEqual(stack.wheels, [.standard(NDStep(stops: 3))], "Mounting never touches the ND wheels.")

        stack = try stack.replacingAuxiliaryFilters(with: [mount(gnd, in: set, .gnd(.applyFullValue))], inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 5, accuracy: 1e-9)
        XCTAssertEqual(stack.auxiliaryFilters.count, 1, "A mode change updates the same mounted item.")
    }

    func testEmptyWheelAndRecordOnlyMountAreDistinctStates() throws {
        let gnd = FilterItem(name: "GND", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "GND", color: .purple, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        let empty = FilterStack(wheels: [.standard(NDStep(stops: 1)), .empty(in: set.id)], inventory: inventory)
        XCTAssertTrue(empty.wheels[1].isCleanable)
        XCTAssertTrue(empty.canRemoveEmptyWheel)
        XCTAssertFalse(empty.hasAuxiliaryFilters)

        let recordOnly = try empty.replacingAuxiliaryFilters(with: [mount(gnd, in: set)], inventory: inventory).get()
        XCTAssertEqual(recordOnly.effectiveStep, empty.effectiveStep)
        XCTAssertTrue(recordOnly.hasAuxiliaryFilters)
        // Wheel cleanup never removes a mounted auxiliary filter
        // (FILTER-STACK-006): only the Empty wheel goes.
        let cleaned = recordOnly.removingRightmostEmptyWheel()
        XCTAssertEqual(cleaned.wheels.count, 1)
        XCTAssertEqual(cleaned.auxiliaryFilters, recordOnly.auxiliaryFilters)
    }

    // MARK: Example 5 — CPL choices and item exclusivity across wheels and auxiliary filters

    func testCPLMountsOnceWithOneChoiceAndTheSameItemIsExcludedEverywhere() throws {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let nd8 = fixed("ND8", 3)
        let set = FilterSet(name: "52mm", color: .orange, items: [cpl, nd8])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(wheels: [.empty(in: set.id)], inventory: inventory)

        XCTAssertEqual(MountedAuxiliaryFilter.initialChoice(for: cpl), .cplLoss(1), "The first configured choice is the initial one.")
        stack = try stack.replacingAuxiliaryFilters(with: [mount(cpl, in: set, .cplLoss(1.5))], inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 1.5, accuracy: 1e-9)

        // The wheel offers Empty and the set's ND items only; the CPL
        // never appears as a wheel row (FILTER-STACK-003).
        let rows = stack.rowOptions(forWheelAt: 0, inventory: inventory, scale: scale)
        XCTAssertEqual(rows.map(\.selection), [.empty, select(nd8)])

        // Changing the choice updates the same mounted item; a second
        // mount of the same physical item is refused (FILTER-AUX-004).
        stack = try stack.replacingAuxiliaryFilters(with: [mount(cpl, in: set, .cplLoss(2))], inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 2, accuracy: 1e-9)
        XCTAssertEqual(stack.auxiliaryFilters.count, 1)
        XCTAssertEqual(
            stack.replacingAuxiliaryFilters(with: [mount(cpl, in: set, .cplLoss(1)), mount(cpl, in: set, .cplLoss(2))], inventory: inventory),
            .failure(.itemAlreadyMounted)
        )
        // An unconfigured choice never resolves to another choice.
        XCTAssertEqual(
            stack.replacingAuxiliaryFilters(with: [mount(cpl, in: set, .cplLoss(1.25))], inventory: inventory),
            .failure(.unresolvedSelection)
        )
        // An item on a wheel cannot be mounted as an auxiliary filter,
        // and a wheel cannot select an item mounted as one.
        stack = try stack.replacingWheel(at: 0, with: select(nd8), inventory: inventory).get()
        XCTAssertEqual(
            stack.replacingAuxiliaryFilters(with: [mount(cpl, in: set, .cplLoss(2)), MountedAuxiliaryFilter(filterSetID: set.id, itemID: nd8.id, choice: .registeredLoss)], inventory: inventory),
            .failure(.unresolvedSelection),
            "An ND item is never an auxiliary filter."
        )
    }

    // MARK: Example 6 — cap behavior with Record only

    func testRecordOnlyRemainsMountableAtCapAndEnablingContributionIsRejected() throws {
        let gnd = FilterItem(name: "GND", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "GND", color: .purple, items: [gnd])
        let inventory = FilterInventory(filterSets: [set])
        var stack = FilterStack(wheels: [.standard(NDStep(stops: 30))], inventory: inventory)
        XCTAssertEqual(stack.addUnavailability(for: .standard, inventory: inventory, scale: scale), .noSelectableValue)
        XCTAssertEqual(stack.addUnavailability(for: .filterSet(set.id), inventory: inventory, scale: scale), .filterSetHasNoItems, "A set without ND items adds no wheel.")

        stack = try stack.replacingAuxiliaryFilters(with: [mount(gnd, in: set)], inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 30, accuracy: 1e-9)

        let before = stack
        XCTAssertEqual(
            stack.replacingAuxiliaryFilters(with: [mount(gnd, in: set, .gnd(.applyFullValue))], inventory: inventory),
            .failure(.exceedsTotalLimit)
        )
        XCTAssertEqual(stack, before, "A rejected change leaves the previous state intact.")
        XCTAssertEqual(stack.remainingBudget(excludingWheelAt: 0), 30, accuracy: 1e-9)

        // A Color filter's loss shares the same budget (FILTER-COLOR-002).
        let red = FilterItem(name: "Red", behavior: .color(FilterExposureLoss(stops: 2), .red))
        let colorSet = FilterSet(name: "Color", color: .red, items: [red])
        let both = FilterInventory(filterSets: [set, colorSet])
        XCTAssertEqual(
            stack.replacingAuxiliaryFilters(with: [mount(gnd, in: set), mount(red, in: colorSet)], inventory: both),
            .failure(.exceedsTotalLimit)
        )
    }

    // MARK: FILTER-STACK-001 — conditional wheel limit

    func testAuxiliaryFiltersLowerTheWheelLimitToThreeAndNeverRemoveWheels() throws {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(.defaults))
        let set = FilterSet(name: "S", color: .red, items: [cpl])
        let inventory = FilterInventory(filterSets: [set])
        XCTAssertEqual(FilterStack.wheelLimit(hasAuxiliaryFilters: false), 4)
        XCTAssertEqual(FilterStack.wheelLimit(hasAuxiliaryFilters: true), 3)

        let four = FilterStack(standardSteps: [NDStep(stops: 1), NDStep(stops: 1), NDStep(stops: 1), NDStep(stops: 1)])
        XCTAssertEqual(
            four.replacingAuxiliaryFilters(with: [mount(cpl, in: set)], inventory: inventory),
            .failure(.tooManyNDWheels),
            "Mounting never deletes or merges ND wheels; the user reduces them first."
        )
        XCTAssertNil(FilterStack.validated(wheels: four.wheels, auxiliaryFilters: [mount(cpl, in: set)], inventory: inventory))

        var three = FilterStack(standardSteps: [NDStep(stops: 1), NDStep(stops: 1), NDStep(stops: 1)])
        XCTAssertTrue(three.canAddWheel)
        three = try three.replacingAuxiliaryFilters(with: [mount(cpl, in: set)], inventory: inventory).get()
        XCTAssertEqual(three.wheelLimit, 3)
        XCTAssertFalse(three.canAddWheel)
        XCTAssertEqual(three.addUnavailability(for: .standard, inventory: inventory, scale: scale), .stackFull)
        XCTAssertEqual(three.addingWheel(for: .standard, inventory: inventory), three)

        // Removing the last auxiliary filter restores the four-wheel
        // capacity (FILTER-AUX-001).
        let cleared = try three.replacingAuxiliaryFilters(with: [], inventory: inventory).get()
        XCTAssertFalse(cleared.hasAuxiliaryFilters)
        XCTAssertTrue(cleared.canAddWheel)
    }

    func testAtMostThreeAuxiliaryFiltersMountAtOnce() throws {
        let items = (0..<4).map { FilterItem(name: "GND \($0)", behavior: .gnd(stops(1))) }
        let set = FilterSet(name: "GND", color: .purple, items: items)
        let inventory = FilterInventory(filterSets: [set])
        let stack = FilterStack(single: NDStep(stops: 0))
        let three = try stack.replacingAuxiliaryFilters(with: items.prefix(3).map { mount($0, in: set) }, inventory: inventory).get()
        XCTAssertEqual(three.auxiliaryFilters.count, 3)
        XCTAssertEqual(
            stack.replacingAuxiliaryFilters(with: items.map { mount($0, in: set) }, inventory: inventory),
            .failure(.tooManyAuxiliaryFilters)
        )
    }

    // MARK: FILTER-STACK-005 — auxiliary filters do not take part in ND ordering

    func testAuxiliaryChangesNeverReorderNDWheels() throws {
        let gnd = FilterItem(name: "GND 0.9", behavior: .gnd(stops(3)))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let nd2 = fixed("ND2", 1)
        let lee = FilterSet(name: "Lee", color: .red, items: [gnd, nd2])
        let nisi = FilterSet(name: "NiSi", color: .green, items: [cpl])
        let inventory = FilterInventory(filterSets: [lee, nisi])
        var stack = FilterStack(
            wheels: [FilterWheel(source: .filterSet(lee.id), selection: select(nd2)), .standard(NDStep(stops: 2))],
            inventory: inventory
        ).sortedForCommit(inventory: inventory)
        // Standard (2) leads Lee (1).
        XCTAssertEqual(stack.wheels.map(\.source), [.standard, .filterSet(lee.id)])

        stack = try stack.replacingAuxiliaryFilters(with: [mount(gnd, in: lee, .gnd(.applyFullValue)), mount(cpl, in: nisi, .cplLoss(2))], inventory: inventory).get()
        XCTAssertEqual(stack.effectiveStep.stops, 8, accuracy: 1e-9)
        // Lee's registered subtotal counts its ND wheel only, not the GND.
        XCTAssertEqual(stack.registeredSubtotal(of: .filterSet(lee.id)), 1, accuracy: 1e-9)
        XCTAssertEqual(stack.commitSortPermutation(inventory: inventory), [0, 1])
        let sorted = stack.sortedForCommit(inventory: inventory)
        XCTAssertEqual(sorted.auxiliaryFilters, stack.auxiliaryFilters, "Sorting carries the auxiliary filters through unchanged.")
        XCTAssertEqual(sorted.wheels, stack.wheels)
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

    func testNormalizationUnmountsAVanishedCPLChoiceNeverSubstitutingAnother() {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 2, nil])))
        let gnd = FilterItem(name: "GND", behavior: .gnd(stops(2)))
        let set = FilterSet(name: "CPL", color: .orange, items: [cpl, gnd])
        let inventory = FilterInventory(filterSets: [set])
        let stale = mount(cpl, in: set, .cplLoss(1.5))
        let valid = mount(gnd, in: set)
        XCTAssertEqual(
            FilterStack.normalizedAuxiliaryFilters([stale, valid, valid], inventory: inventory),
            [valid],
            "The stale CPL is unmounted, not moved to another choice; a duplicate item is dropped."
        )
        // A kind change that removes the mounted row unmounts it too.
        let nowND = FilterItem(id: cpl.id, name: "CPL", behavior: .fixed(stops(2)))
        let changed = FilterInventory(filterSets: [FilterSet(id: set.id, name: "CPL", color: .orange, items: [nowND, gnd])])
        XCTAssertEqual(FilterStack.normalizedAuxiliaryFilters([mount(cpl, in: set, .cplLoss(1)), valid], inventory: changed), [valid])
        // An unknown set drops its mounts.
        XCTAssertEqual(FilterStack.normalizedAuxiliaryFilters([mount(gnd, in: FilterSet(name: "Gone", color: .red))], inventory: inventory), [])
        // A legacy wheel that still names a CPL row can no longer
        // resolve on a wheel and reads Empty (FILTER-STACK-003).
        let wheel = FilterWheel(source: .filterSet(set.id), selection: select(cpl, .cplLoss(1)))
        XCTAssertEqual(FilterStack.normalizedWheels([wheel], inventory: inventory), [.empty(in: set.id)])
    }

    func testLegacyMixedWheelsMigrateCPLAndGNDRowsIntoAuxiliaryFilters() {
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        let gnd = FilterItem(name: "GND", behavior: .gnd(stops(2)))
        let nd8 = fixed("ND8", 3)
        let set = FilterSet(name: "Kit", color: .teal, items: [cpl, gnd, nd8])
        let legacy: [FilterWheel] = [
            .standard(NDStep(stops: 6.6)),
            FilterWheel(source: .filterSet(set.id), selection: select(cpl, .cplLoss(1.5))),
            FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.applyFullValue))),
            FilterWheel(source: .filterSet(set.id), selection: select(nd8)),
        ]
        let migrated = FilterStack.migratingLegacyWheels(legacy)
        XCTAssertEqual(migrated.wheels, [.standard(NDStep(stops: 6.6)), FilterWheel(source: .filterSet(set.id), selection: select(nd8))])
        XCTAssertEqual(migrated.auxiliaryFilters, [
            MountedAuxiliaryFilter(filterSetID: set.id, itemID: cpl.id, choice: .cplLoss(1.5)),
            MountedAuxiliaryFilter(filterSetID: set.id, itemID: gnd.id, choice: .gnd(.applyFullValue)),
        ])
        let inventory = FilterInventory(filterSets: [set])
        let stack = FilterStack.validated(wheels: migrated.wheels, auxiliaryFilters: migrated.auxiliaryFilters, inventory: inventory)
        XCTAssertEqual(stack?.effectiveStep.stops ?? 0, 6.6 + 1.5 + 2 + 3, accuracy: 1e-9, "The effective total is preserved.")

        // A stack that held only auxiliary rows receives one Standard 0 wheel.
        let auxiliaryOnly = FilterStack.migratingLegacyWheels([FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly)))])
        XCTAssertEqual(auxiliaryOnly.wheels, [.standard(NDStep(stops: 0))])
        XCTAssertEqual(auxiliaryOnly.auxiliaryFilters.count, 1)
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
        let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
        let set = FilterSet(name: "Lee holder", color: .indigo, items: [gnd, red])
        let inventory = FilterInventory(filterSets: [set])
        let stack = try FilterStack(
            wheels: [.standard(NDStep(stops: 6.6)), .empty(in: set.id)],
            inventory: inventory
        ).replacingAuxiliaryFilters(with: [mount(gnd, in: set), mount(red, in: set)], inventory: inventory).get()
        let summary = FilterSummaryEntry.summary(for: stack, inventory: inventory)
        XCTAssertEqual(summary.count, 3, "Auxiliary filters first, then wheels; Empty wheels are omitted.")
        XCTAssertEqual(summary[2].sourceKind, .standard)
        XCTAssertEqual(summary[2].contributedStops, 6.6)
        let color = summary[1]
        XCTAssertEqual(color.itemKind, .color)
        XCTAssertEqual(color.calculationMode, .fixed, "A Color filter contributes its registered loss.")
        XCTAssertEqual(color.canonicalStops, 3)
        XCTAssertEqual(color.contributedStops, 3)
        XCTAssertNil(color.originalUnit)
        let entry = summary[0]
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

    // MARK: Kind correction (FILTER-ITEM-005)

    func testReassigningRolesMovesSelectionsAcrossTheNDAndAuxiliaryRoles() {
        let ndID = FilterItemID(rawValue: "nd")
        let auxID = FilterItemID(rawValue: "aux")
        let setID = FilterSetID(rawValue: "set")
        let redNowColor = FilterItem(id: ndID, name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
        let cplNowND = FilterItem(id: auxID, name: "CPL", behavior: .fixed(FilterRegisteredValue(value: 1, unit: .stops)))
        let inventory = FilterInventory(filterSets: [FilterSet(id: setID, name: "S", color: .blue, items: [redNowColor, cplNowND])])
        let standard = FilterWheel.standard(NDStep(stops: 3))
        let mountedRed = FilterWheel(source: .filterSet(setID), selection: .item(FilterRowSelection(itemID: ndID, choice: .fixed)))
        let mountedCPL = MountedAuxiliaryFilter(filterSetID: setID, itemID: auxID, choice: .cplLoss(1))

        let result = FilterStack.reassigningRoles(wheels: [standard, mountedRed], auxiliaryFilters: [mountedCPL], inventory: inventory)

        XCTAssertEqual(result.wheels, [
            standard,
            FilterWheel(source: .filterSet(setID), selection: .item(FilterRowSelection(itemID: auxID, choice: .fixed))),
        ], "The ND wheel leaves the row; the former CPL becomes a wheel at the end.")
        XCTAssertEqual(result.wheelOrigins, [0, nil])
        XCTAssertEqual(result.auxiliaryFilters, [MountedAuxiliaryFilter(filterSetID: setID, itemID: ndID, choice: .registeredLoss)])
    }

    func testReassigningRolesLeavesUnchangedKindsAndUnknownItemsAlone() {
        let setID = FilterSetID(rawValue: "set")
        let nd = FilterItem(id: FilterItemID(rawValue: "nd"), name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let inventory = FilterInventory(filterSets: [FilterSet(id: setID, name: "S", color: .blue, items: [nd])])
        let wheel = FilterWheel(source: .filterSet(setID), selection: .item(FilterRowSelection(itemID: nd.id, choice: .fixed)))
        let unknown = MountedAuxiliaryFilter(filterSetID: setID, itemID: FilterItemID(rawValue: "gone"), choice: .registeredLoss)

        let result = FilterStack.reassigningRoles(wheels: [wheel], auxiliaryFilters: [unknown], inventory: inventory)

        XCTAssertEqual(result.wheels, [wheel])
        XCTAssertEqual(result.wheelOrigins, [0])
        XCTAssertEqual(result.auxiliaryFilters, [unknown], "Unknown items are left to normal re-resolution.")
    }
}
