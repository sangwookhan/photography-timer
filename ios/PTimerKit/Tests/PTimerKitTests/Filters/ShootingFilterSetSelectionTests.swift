// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Observation
import XCTest
import PTimerCore
@testable import PTimerKit

/// The Shooting Filters workflow (FILTER-AUX-003, FILTER-CAMERA-001/003,
/// FILTER-FLOW-003..005, FILTER-ITEM-009, FILTER-SET-001): one working
/// session over the camera's Filter Set selection and auxiliary mounts,
/// committed together by Apply and dropped by Cancel; the offered list as
/// the grouped union of the working selection; filter-first registration
/// into a new or an inline set; inventory edits that stay immediate.
@MainActor
final class ShootingFilterSetSelectionTests: XCTestCase {
    private func makeViewModel(inventoryModel: FilterInventoryModel) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            filterInventoryModel: inventoryModel
        )
    }

    private func effect(_ name: String, _ stops: Double) -> FilterItem {
        FilterItem(name: name, behavior: .effect(FilterExposureLoss(stops: stops)))
    }

    private func nd(_ name: String, _ stops: Double) -> FilterItem {
        FilterItem(name: name, behavior: .fixed(FilterRegisteredValue(value: stops, unit: .stops)))
    }

    private func select(_ item: FilterItem) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: item.id, choice: .fixed))
    }

    private let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
    private let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
    private let gnd = FilterItem(name: "Soft GND", behavior: .gnd(FilterRegisteredValue(value: 0.6, unit: .opticalDensity)))

    private func session(_ viewModel: ExposureCalculatorViewModel) -> ShootingFiltersSession {
        ShootingFiltersSession(
            committedFilterSetIDs: viewModel.candidateFilterSetIDs,
            committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount)
        )
    }

    private func apply(_ session: ShootingFiltersSession, _ viewModel: ExposureCalculatorViewModel) -> FilterStackRejection? {
        viewModel.applyShootingFilters(selectedFilterSetIDs: session.selectedFilterSetIDs, mounts: session.mounts)
    }

    func testSeveralSelectedSetsOfferTheirGroupedUnionInTheSelectedSetsOrder() throws {
        let inventory = FilterInventoryModel()
        let small = try XCTUnwrap(inventory.createFilterSet(name: "52mm", color: .red))
        let big = try XCTUnwrap(inventory.createFilterSet(name: "82mm", color: .blue))
        inventory.addItem(cpl, to: small.id)
        inventory.addItem(red, to: small.id)
        inventory.addItem(nd("ND8", 3), to: small.id)
        inventory.addItem(gnd, to: big.id)
        let night = effect("Night", 1)
        inventory.addItem(night, to: big.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "A fresh camera starts with no selected Set.")

        // What Shooting Filters lists: each Selected Set's strip, in the
        // order the Selected Sets are shown.
        func offered(_ selected: [FilterSetID]) -> [FilterItemID] {
            viewModel.displayedSelectedFilterSets(selected).flatMap { FilterSetItemOrder.ordered($0.auxiliaryItems).map(\.id) }
        }
        XCTAssertEqual(offered([small.id]), [red.id, cpl.id], "ND items are never offered here.")
        XCTAssertEqual(
            offered([small.id, big.id]),
            [red.id, cpl.id, night.id, gnd.id],
            "Union of both sets, grouped by set, each in Color, Effect, CPL, GND order."
        )
        XCTAssertEqual(
            offered([big.id, small.id]),
            [red.id, cpl.id, night.id, gnd.id],
            "A mixed Set precedes an auxiliary-only one whatever the selection order (FILTER-SET-004)."
        )
    }

    func testAuxiliaryFiltersFromDifferentSelectedSetsApplyTogetherWithTheSetSelection() throws {
        let inventory = FilterInventoryModel()
        let small = try XCTUnwrap(inventory.createFilterSet(name: "52mm", color: .red))
        let big = try XCTUnwrap(inventory.createFilterSet(name: "82mm", color: .blue))
        inventory.addItem(cpl, to: small.id)
        inventory.addItem(red, to: small.id)
        inventory.addItem(gnd, to: big.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        let smallSet = try XCTUnwrap(viewModel.filterSet(withID: small.id))
        let bigSet = try XCTUnwrap(viewModel.filterSet(withID: big.id))
        var working = session(viewModel)
        working.setSelected(big.id, true)
        working.setSelected(small.id, true)
        working.setMount(.mount(gnd, in: bigSet), for: gnd.id)
        working.setMount(.mount(cpl, in: smallSet, .cplLoss(1.5)), for: cpl.id)
        working.setMount(.mount(red, in: smallSet), for: red.id)
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty, "Working changes commit nothing.")

        XCTAssertNil(apply(working, viewModel))
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [big.id, small.id], "Applied in the order the sets were added.")
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [red.id, cpl.id, gnd.id])
        XCTAssertEqual(viewModel.auxiliaryFiltersSubtotal(working.mounts), 4.5, accuracy: 1e-9, "Red 3 + CPL 1.5 + Record-only GND 0.")
    }

    /// A set the camera uses (a mounted filter and an ND wheel), the
    /// session used across the tests below.
    private func usedSetFixture() throws -> (viewModel: ExposureCalculatorViewModel, kit: FilterSet) {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let other = try XCTUnwrap(inventory.createFilterSet(name: "Other", color: .blue))
        let nd8 = nd("ND8", 3)
        inventory.addItem(red, to: kit.id)
        inventory.addItem(nd8, to: kit.id)
        inventory.addItem(cpl, to: other.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.arrangeFilterSets([kit.id, other.id])
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        let otherSet = try XCTUnwrap(viewModel.filterSet(withID: other.id))
        XCTAssertNil(viewModel.applyMounts([.mount(red, in: kitSet), .mount(cpl, in: otherSet, .cplLoss(1.5))]))
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        return (viewModel, kitSet)
    }

    func testUncheckingAUsedSetChangesNothingCommittedBeforeApply() throws {
        let (viewModel, kit) = try usedSetFixture()
        let wheelsBefore = viewModel.filterWheels
        let mountsBefore = viewModel.mountedAuxiliaryFilters.map(\.mount)
        let totalBefore = viewModel.ndStep
        var working = session(viewModel)

        working.setSelected(kit.id, false)
        XCTAssertFalse(viewModel.displayedSelectedFilterSets(working.selectedFilterSetIDs).contains { $0.id == kit.id }, "Its group is hidden at once.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs.first, kit.id, "The committed selection is unchanged.")
        XCTAssertEqual(viewModel.filterWheels, wheelsBefore)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), mountsBefore)
        XCTAssertEqual(viewModel.ndStep, totalBefore)
        XCTAssertEqual(
            viewModel.shootingFiltersPreview(selectedFilterSetIDs: working.selectedFilterSetIDs, mounts: working.mounts).map(\.stops),
            .success(1.5),
            "The preview already leaves out the set's filter and ND wheel: CPL 1.5 with Standard 0."
        )
    }

    func testAddingARemovedSetBackRestoresItsRetainedWorkingSelectionsAtTheEnd() throws {
        let (viewModel, kit) = try usedSetFixture()
        let other = try XCTUnwrap(viewModel.candidateFilterSetIDs.last)
        var working = session(viewModel)
        let redMount = working.mount(of: red.id)
        let cplMount = working.mount(of: cpl.id)
        XCTAssertNotNil(redMount)

        // The last Selected Set removed and added back: back where it
        // started.
        working.setSelected(other, false)
        XCTAssertFalse(working.mounts.contains { $0.itemID == cpl.id }, "Hidden while removed.")
        working.setSelected(other, true)
        XCTAssertEqual(working.mount(of: cpl.id), cplMount)
        XCTAssertFalse(working.hasChanges, "Back where it started.")

        // Another set added back goes to the end of the Selected Sets
        // with its picks; the new order is a change to apply.
        working.setSelected(kit.id, false)
        XCTAssertFalse(working.mounts.contains { $0.itemID == red.id }, "Hidden while removed.")
        working.setSelected(kit.id, true)
        XCTAssertEqual(working.selectedFilterSetIDs, [other, kit.id])
        XCTAssertEqual(working.mount(of: red.id), redMount)
        XCTAssertTrue(working.mounts.contains { $0.itemID == red.id }, "Restored with the set.")
        XCTAssertTrue(working.hasChanges, "The selection order changed.")
    }

    func testASetOnlyChangeOffersApply() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let viewModel = makeViewModel(inventoryModel: inventory)
        var working = session(viewModel)
        XCTAssertFalse(working.hasChanges)

        working.setSelected(kit.id, true)
        XCTAssertTrue(working.hasChanges, "Adding a set alone is a change to apply.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "Not committed yet.")
        XCTAssertNil(apply(working, viewModel))
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [kit.id])
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty, "Selecting a set mounts nothing.")
    }

    func testApplyRemovesTheUncheckedSetsFiltersAndNDWheelsAndPersistsTheSelection() throws {
        let store = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let other = try XCTUnwrap(inventory.createFilterSet(name: "Other", color: .blue))
        let nd8 = nd("ND8", 3)
        inventory.addItem(red, to: kit.id)
        inventory.addItem(nd8, to: kit.id)
        inventory.addItem(cpl, to: other.id)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: store,
            filterInventoryModel: inventory
        )
        viewModel.arrangeFilterSets([kit.id, other.id])
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        let otherSet = try XCTUnwrap(viewModel.filterSet(withID: other.id))
        XCTAssertNil(viewModel.applyMounts([.mount(red, in: kitSet), .mount(cpl, in: otherSet, .cplLoss(1.5))]))
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let standardIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex(where: \.isStandard))
        viewModel.removeZeroWheelFromOverscroll(at: standardIndex)
        XCTAssertEqual(viewModel.filterWheels.map(\.source), [.filterSet(kit.id)], "Only the set's ND wheel is left.")

        var working = session(viewModel)
        working.setSelected(kit.id, false)
        XCTAssertNil(apply(working, viewModel), "Apply asks for nothing more.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [other.id])
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [cpl.id], "Another set's mount stays.")
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))], "One Standard 0-stop wheel is left.")
        XCTAssertEqual(viewModel.filterSet(withID: kit.id), kitSet, "The set and its items stay in the inventory.")

        let slot = try XCTUnwrap(store.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(slot.candidateFilterSetIDs, [other.id.rawValue], "The applied selection is persisted.")
    }

    func testCancellingASessionLeavesTheCameraAsItWas() throws {
        let (viewModel, kit) = try usedSetFixture()
        let candidatesBefore = viewModel.candidateFilterSetIDs
        let wheelsBefore = viewModel.filterWheels
        let mountsBefore = viewModel.mountedAuxiliaryFilters.map(\.mount)
        var working = session(viewModel)
        working.setSelected(kit.id, false)
        working.setMount(nil, for: cpl.id)
        XCTAssertTrue(working.hasChanges)

        // Cancel: the session is dropped without Apply.
        XCTAssertEqual(viewModel.candidateFilterSetIDs, candidatesBefore)
        XCTAssertEqual(viewModel.filterWheels, wheelsBefore)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), mountsBefore)
    }

    func testInventoryEditsDuringASessionStayDespiteCancel() throws {
        let (viewModel, kit) = try usedSetFixture()
        var working = session(viewModel)
        working.setSelected(kit.id, false)

        // Inventory edits from a set editor opened in the session are
        // immediate.
        let created = try XCTUnwrap(viewModel.createFilterSet(name: "Pouch", color: .orange))
        viewModel.renameFilterSet(id: kit.id, name: "Kit 2")
        viewModel.deleteFilterSet(id: created.id)
        let pouch2 = try XCTUnwrap(viewModel.createFilterSet(name: "Pouch 2", color: .orange))
        working.rebase(
            committedFilterSetIDs: viewModel.candidateFilterSetIDs,
            committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount),
            inventory: viewModel.filterInventory
        )

        // Cancel drops the session; the inventory edits stay.
        XCTAssertEqual(viewModel.filterSet(withID: kit.id)?.name, "Kit 2")
        XCTAssertNil(viewModel.filterSet(withID: created.id))
        XCTAssertNotNil(viewModel.filterSet(withID: pouch2.id))
        XCTAssertTrue(viewModel.candidateFilterSetIDs.contains(kit.id), "The camera selection is unchanged.")
    }

    func testRemovingTheOnlyNDWheelsFallsBackToOneStandardWheel() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let nd8 = nd("ND8", 3)
        inventory.addItem(nd8, to: kit.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.arrangeFilterSets([kit.id])
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let standardIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex(where: \.isStandard))
        viewModel.removeZeroWheelFromOverscroll(at: standardIndex)

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [], mounts: []))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        XCTAssertEqual(viewModel.ndStep.stops, 0, accuracy: 1e-9)
    }

    // MARK: Preferred ND source on Apply (FILTER-PLUS-006)

    private func ndSet(_ inventory: FilterInventoryModel, _ name: String, nd count: Int, auxiliary: Bool = false) throws -> FilterSet {
        let filterSet = try XCTUnwrap(inventory.createFilterSet(name: name, color: .teal))
        for index in 0..<count {
            inventory.addItem(nd("\(name) ND\(index)", Double(index + 1)), to: filterSet.id)
        }
        if auxiliary {
            inventory.addItem(effect("\(name) Night", 1), to: filterSet.id)
        }
        return try XCTUnwrap(inventory.filterSet(withID: filterSet.id))
    }

    func testPreferredNDSourceRanksByCountThenNDOnlyThenNameThenSelectionOrder() throws {
        let inventory = FilterInventoryModel()
        let two = try ndSet(inventory, "Two", nd: 2)
        let three = try ndSet(inventory, "Three", nd: 3)
        let mixedThree = try ndSet(inventory, "A mixed", nd: 3, auxiliary: true)
        let auxOnly = try ndSet(inventory, "Aux", nd: 0, auxiliary: true)
        let beta = try ndSet(inventory, "Beta", nd: 1)
        let alpha = try ndSet(inventory, "alpha", nd: 1)
        let sameA = try ndSet(inventory, "Same", nd: 1)
        let sameB = try ndSet(inventory, "Same", nd: 1)

        XCTAssertEqual(PreferredNDSource.winner(among: [two, three]), three.id, "Most registered ND items wins.")
        XCTAssertEqual(PreferredNDSource.winner(among: [mixedThree, three]), three.id, "On a tie an ND-only Set beats a mixed one.")
        XCTAssertEqual(PreferredNDSource.winner(among: [beta, alpha]), alpha.id, "Then the name, locale-aware.")
        XCTAssertEqual(PreferredNDSource.winner(among: [sameB, sameA]), sameB.id, "Equal names keep the selection order.")
        XCTAssertNil(PreferredNDSource.winner(among: [auxOnly]), "A Set without ND items is not eligible.")
        XCTAssertNil(PreferredNDSource.winner(among: []))
    }

    func testApplyAddingSetsWhilePlusIsStandardPrefersTheWinnerAndEmptiesZeroStandardWheels() throws {
        let inventory = FilterInventoryModel()
        let small = try ndSet(inventory, "Small", nd: 1)
        let big = try ndSet(inventory, "Big", nd: 2)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(.standard(NDStep(stops: 2)), at: 1)
        viewModel.addFilterWheel()
        let wheelsBefore = viewModel.filterWheels
        XCTAssertEqual(wheelsBefore.filter { $0 == .standard(NDStep(stops: 0)) }.count, 2)
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
        let idsBefore = viewModel.ndFilterWheelIDs
        let totalBefore = viewModel.ndStep.stops

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [small.id, big.id], mounts: []))

        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(big.id), "Plus remembers the preferred Set.")
        XCTAssertEqual(
            viewModel.filterWheels,
            wheelsBefore.map { $0 == .standard(NDStep(stops: 0)) ? .empty(in: big.id) : $0 },
            "Standard 0 wheels become Empty wheels of that Set in place; the non-zero Standard wheel stays."
        )
        XCTAssertEqual(viewModel.ndFilterWheelIDs, idsBefore, "Wheel identities are kept.")
        XCTAssertEqual(viewModel.ndStep.stops, totalBefore, accuracy: 1e-9, "Nothing is mounted; the total is unchanged.")
    }

    func testPreferredSourceAlsoTakesTheFallbackWheelAndSurvivesARestore() throws {
        let store = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let old = try ndSet(inventory, "Old", nd: 1)
        let fresh = try ndSet(inventory, "Fresh", nd: 1)
        let viewModel = makeViewModel(sessionStore: store, inventoryModel: inventory)
        viewModel.arrangeFilterSets([old.id])
        viewModel.selectFilterSource(.filterSet(old.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(old.items[0]), at: 1)
        let standardIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex(where: \.isStandard))
        viewModel.removeZeroWheelFromOverscroll(at: standardIndex)
        viewModel.selectFilterSource(.standard)

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [fresh.id], mounts: []))
        XCTAssertEqual(viewModel.filterWheels, [.empty(in: fresh.id)], "The Standard 0 fallback Apply adds becomes an Empty wheel of the winner.")
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(fresh.id))

        let restored = makeViewModel(sessionStore: store, inventoryModel: inventory)
        XCTAssertEqual(restored.selectedFilterSource, .filterSet(fresh.id), "The remembered source survives a restore.")
        XCTAssertEqual(restored.filterWheels, [.empty(in: fresh.id)])
    }

    /// A camera with Standard 2, a Standard 0, and a Kit ND wheel in the
    /// settled order, Plus on Standard, and an auxiliary-only Pouch that
    /// is not selected yet.
    private struct ConversionScenario {
        let viewModel: ExposureCalculatorViewModel
        let kit: FilterSet
        let pouch: FilterSet
        let kitWheel: FilterWheel
    }

    private func conversionScenario() throws -> ConversionScenario {
        let inventory = FilterInventoryModel()
        let kit = try ndSet(inventory, "Kit", nd: 1)
        let pouch = try ndSet(inventory, "Pouch", nd: 0, auxiliary: true)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.setWheelSelection(.standard(NDStep(stops: 2)), at: 0)
        viewModel.arrangeFilterSets([kit.id])
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(kit.items[0]), at: 1)
        viewModel.selectFilterSource(.standard)
        viewModel.addFilterWheel()
        // A commit settles the new Standard 0 into the Standard group.
        viewModel.setWheelSelection(.standard(NDStep(stops: 2)), at: 0)
        let kitWheel = FilterWheel(source: .filterSet(kit.id), selection: select(kit.items[0]))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2)), .standard(NDStep(stops: 0)), kitWheel])
        return ConversionScenario(viewModel: viewModel, kit: kit, pouch: pouch, kitWheel: kitWheel)
    }

    /// FILTER-PLUS-006 with FILTER-STACK-005: the converted Empty wheel
    /// joins its Set's group, after the Set's non-empty rows, and every
    /// wheel keeps its identity through the move.
    func testTheConvertedEmptyWheelTakesTheSettledOrderWithItsIdentity() throws {
        let scenario = try conversionScenario()
        let (viewModel, kit, pouch, kitWheel) = (scenario.viewModel, scenario.kit, scenario.pouch, scenario.kitWheel)
        let ids = viewModel.ndFilterWheelIDs

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [kit.id, pouch.id], mounts: []))

        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(kit.id))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2)), kitWheel, .empty(in: kit.id)])
        XCTAssertEqual(viewModel.ndFilterWheelIDs, [ids[0], ids[2], ids[1]], "Identity follows each wheel.")
        XCTAssertEqual(viewModel.ndStep.stops, 3, accuracy: 1e-9)
    }

    /// FILTER-A11Y-006: while the screen reader orders the wheels, Apply
    /// keeps the current positions; the one reconciliation on resume
    /// settles them.
    func testTheConversionKeepsPositionsWhileTheScreenReaderOrdersThenReconcilesOnce() async throws {
        let scenario = try conversionScenario()
        let (viewModel, kit, pouch, kitWheel) = (scenario.viewModel, scenario.kit, scenario.pouch, scenario.kitWheel)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        let ids = viewModel.ndFilterWheelIDs

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [kit.id, pouch.id], mounts: []))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2)), .empty(in: kit.id), kitWheel])
        XCTAssertEqual(viewModel.ndFilterWheelIDs, ids)

        viewModel.setFilterStackOrderingSuspended(false)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2)), kitWheel, .empty(in: kit.id)])
        XCTAssertEqual(viewModel.ndFilterWheelIDs, [ids[0], ids[2], ids[1]])
    }

    func testNoPreferenceWithoutAnAddedNDSetOrWhenPlusAlreadyNamesASet() throws {
        let inventory = FilterInventoryModel()
        let kit = try ndSet(inventory, "Kit", nd: 2)
        let other = try ndSet(inventory, "Other", nd: 3)
        let aux = try ndSet(inventory, "Aux", nd: 0, auxiliary: true)
        let viewModel = makeViewModel(inventoryModel: inventory)

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [aux.id], mounts: []))
        XCTAssertEqual(viewModel.selectedFilterSource, .standard, "No selected Set holds ND: Standard stays.")
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [aux.id, kit.id], mounts: []))
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(kit.id))

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [aux.id, kit.id, other.id], mounts: []))
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(kit.id), "Plus already names a Set: it is kept.")

        let auxItem = try XCTUnwrap(aux.auxiliaryItems.first)
        viewModel.selectFilterSource(.standard)
        XCTAssertNil(viewModel.applyShootingFilters(
            selectedFilterSetIDs: viewModel.candidateFilterSetIDs,
            mounts: [MountedAuxiliaryFilter(filterSetID: aux.id, itemID: auxItem.id, choice: .registeredLoss)]
        ))
        XCTAssertEqual(viewModel.selectedFilterSource, .standard, "An auxiliary-only change adds no Set and keeps Standard.")
    }

    func testAvailableSetContentsHintCountsRegisteredItemsByKindInFixedOrder() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let empty = try XCTUnwrap(inventory.createFilterSet(name: "Empty Holder", color: .green))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        for item in [cpl, red, nd("ND8", 3), effect("Night", 1), nd("ND64", 6), nd("ND1000", 10), FilterItem(name: "Yellow", behavior: .color(FilterExposureLoss(stops: 1), .yellow))] {
            inventory.addItem(item, to: kit.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        let stored = try XCTUnwrap(viewModel.filterSet(withID: kit.id))

        XCTAssertEqual(
            FilterSetContentsHint.entries(of: stored),
            [.init(kind: .fixed, count: 3), .init(kind: .color, count: 2), .init(kind: .effect, count: 1), .init(kind: .cpl, count: 1)],
            "ND, Color, Effect, CPL, GND order; absent kinds left out; CPL counts one item, not its three choices."
        )
        XCTAssertEqual(FilterSetContentsHint.text(of: stored), "ND ×3 · Color ×2 · Effect · CPL")
        XCTAssertEqual(FilterSetContentsHint.text(of: try XCTUnwrap(viewModel.filterSet(withID: empty.id))), "Empty")

        inventory.deleteItem(id: cpl.id)
        XCTAssertEqual(FilterSetContentsHint.text(of: try XCTUnwrap(viewModel.filterSet(withID: kit.id))), "ND ×3 · Color ×2 · Effect", "The hint follows inventory edits.")
    }

    /// The preview runs inside Shooting Filters' body: when the working
    /// selection leaves no ND wheel it must not touch observed state, or
    /// the body invalidates itself and redraws without end — the hang seen
    /// when every Set with an ND wheel is removed. Apply still gives the
    /// fresh Standard wheel a new identity.
    func testPreviewThatLeavesNoNDWheelChangesNoObservedState() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let nd8 = nd("ND8", 3)
        inventory.addItem(nd8, to: kit.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.arrangeFilterSets([kit.id])
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let standardIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex(where: \.isStandard))
        viewModel.removeZeroWheelFromOverscroll(at: standardIndex)
        let wheelIDsBefore = viewModel.ndFilterWheelIDs

        let invalidated = LockedFlag()
        withObservationTracking {
            _ = viewModel.shootingFiltersPreview(selectedFilterSetIDs: [], mounts: [])
        } onChange: {
            invalidated.set()
        }
        XCTAssertEqual(viewModel.shootingFiltersPreview(selectedFilterSetIDs: [], mounts: []).map(\.stops), .success(0))
        XCTAssertFalse(invalidated.value, "Computing the preview again changes nothing a view observes.")

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [], mounts: []))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        XCTAssertEqual(viewModel.ndFilterWheelIDs.count, 1)
        XCTAssertFalse(wheelIDsBefore.contains(viewModel.ndFilterWheelIDs[0]), "The fresh Standard wheel gets a new identity on Apply.")
    }

    /// FILTER-ITEM-009, FILTER-FLOW-004: with no Set yet, a filter saves
    /// with the New Filter Set made for it, which neither selects the Set
    /// for the camera nor mounts the filter; an inline Set made from the
    /// editor works the same way.
    func testFilterFirstRegistrationSavesIntoANewOrInlineSetWithoutSelectingIt() throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        XCTAssertTrue(viewModel.filterInventory.filterSets.isEmpty, "No built-in Set.")

        let proposed = try XCTUnwrap(viewModel.createFilterSet(name: "New Filter Set", color: .red, holding: red))
        XCTAssertEqual(viewModel.filterSet(withID: proposed.id)?.items, [red])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "Registration does not select the Set.")
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty, "Registration mounts nothing.")

        let inline = try XCTUnwrap(viewModel.createFilterSet(name: "52mm", color: .red))
        XCTAssertEqual(viewModel.saveFilterItem(cpl, in: inline.id), .saved)
        XCTAssertEqual(viewModel.filterSet(withID: inline.id)?.items, [cpl])
        XCTAssertEqual(viewModel.filterInventory.filterSets.map(\.id), [proposed.id, inline.id])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "Creating a set does not select it.")
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty)
    }

    private func makeViewModel(sessionStore: CameraSlotSessionPersistenceStoring, inventoryModel: FilterInventoryModel) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventoryModel
        )
    }

    /// FILTER-CAMERA-001: every fresh camera starts with no selected
    /// Set, and the Samples stay unselected; an emptied selection is
    /// stored as an empty list.
    func testAFreshCameraStartsWithNoSelectedSet() throws {
        let store = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel(initial: FilterInventory.samples())
        let viewModel = makeViewModel(sessionStore: store, inventoryModel: inventory)
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "Samples are not selected.")
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))], "Standard stays available on its own.")
        viewModel.selectCameraSlot(.camera3)
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "Every fresh camera starts the same way.")
        viewModel.selectCameraSlot(.camera1)

        let sample = try XCTUnwrap(inventory.filterSets.first)
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [sample.id], mounts: []))
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [], mounts: []))
        let slot = try XCTUnwrap(store.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(slot.candidateFilterSetIDs, [], "An emptied selection is stored as an empty list.")
        XCTAssertTrue(makeViewModel(sessionStore: store, inventoryModel: inventory).candidateFilterSetIDs.isEmpty)
    }

    func testSelectedSetsKeepTheirOrderAndAvailableSetsReadByName() throws {
        let inventory = FilterInventoryModel()
        let zeta = try XCTUnwrap(inventory.createFilterSet(name: "Zeta", color: .red))
        let alpha = try XCTUnwrap(inventory.createFilterSet(name: "alpha", color: .blue))
        let ten = try XCTUnwrap(inventory.createFilterSet(name: "Filter 10", color: .teal))
        let nine = try XCTUnwrap(inventory.createFilterSet(name: "Filter 9", color: .teal))
        let viewModel = makeViewModel(inventoryModel: inventory)
        var working = session(viewModel)
        XCTAssertEqual(viewModel.selectedFilterSets(working.selectedFilterSetIDs).map(\.id), [])
        XCTAssertEqual(
            viewModel.availableFilterSets(excluding: working.selectedFilterSetIDs).map(\.id),
            [alpha.id, nine.id, ten.id, zeta.id],
            "By name, case ignored, numbers in numeric order; creation order never matters."
        )

        // The trailing add control appends; the leading remove control
        // moves a set back among the Available Sets by name.
        working.setSelected(zeta.id, true)
        working.setSelected(alpha.id, true)
        working.setSelected(nine.id, true)
        XCTAssertEqual(viewModel.selectedFilterSets(working.selectedFilterSetIDs).map(\.id), [zeta.id, alpha.id, nine.id])
        XCTAssertEqual(viewModel.availableFilterSets(excluding: working.selectedFilterSetIDs).map(\.id), [ten.id])
        working.setSelected(nine.id, false)
        XCTAssertEqual(viewModel.selectedFilterSets(working.selectedFilterSetIDs).map(\.id), [zeta.id, alpha.id])
        XCTAssertEqual(viewModel.availableFilterSets(excluding: working.selectedFilterSetIDs).map(\.id), [nine.id, ten.id])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [], "Nothing is committed before Apply.")

        XCTAssertNil(apply(working, viewModel))
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [zeta.id, alpha.id])
        XCTAssertEqual(session(viewModel).selectedFilterSetIDs, [zeta.id, alpha.id], "Reopening keeps the order.")
    }

    func testSelectedFiltersListEveryFilterWithItsWholeNameTypeAndContribution() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let soft = FilterItem(name: "Soft GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let hard = FilterItem(name: "Hard GND 3", behavior: .gnd(FilterRegisteredValue(value: 3, unit: .stops)))
        let marumi = FilterItem(name: "MARUMI Red R2X1 72mm", behavior: .color(FilterExposureLoss(stops: 1), .red))
        for item in [red, cpl, soft, hard, marumi] {
            inventory.addItem(item, to: kit.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        XCTAssertEqual(viewModel.selectedFilterRows([]), [], "Nothing selected.")
        let rows = viewModel.selectedFilterRows([
            .mount(soft, in: kitSet),
            .mount(hard, in: kitSet, .gnd(.applyFullValue)),
            .mount(cpl, in: kitSet, .cplLoss(1.5)),
            .mount(red, in: kitSet),
            .mount(marumi, in: kitSet),
        ])
        XCTAssertEqual(rows.map(\.name), ["Red 25A", "MARUMI Red R2X1 72mm", "CPL", "Soft GND 2", "Hard GND 3"], "Every filter, in Main's order, with its whole name.")
        XCTAssertEqual(rows.map(\.kindLabel), ["Color", "Color", "CPL", "GND", "GND"])
        XCTAssertEqual(rows.map(\.valueText), ["3 stops", "1 stop", "1.5 stops", "Record only · 0 stops", "Apply to exposure · 3 stops"], "A GND reads by its effect.")
        XCTAssertEqual(rows.map(\.opticalColor), [.red, .red, nil, nil, nil])
    }

    func testAnEmptySelectedSetOffersAnAddFilterRowAndAFilledOneAHeaderControl() throws {
        let inventory = FilterInventoryModel()
        let empty = try XCTUnwrap(inventory.createFilterSet(name: "Empty", color: .red))
        let ndOnly = try XCTUnwrap(inventory.createFilterSet(name: "ND only", color: .blue))
        let aux = try XCTUnwrap(inventory.createFilterSet(name: "Aux", color: .green))
        inventory.addItem(nd("ND8", 3), to: ndOnly.id)
        inventory.addItem(red, to: aux.id)
        XCTAssertEqual(SelectedFilterSetAddFilterPlacement(for: try XCTUnwrap(inventory.filterSet(withID: empty.id))), .fullWidthRow)
        XCTAssertEqual(SelectedFilterSetAddFilterPlacement(for: try XCTUnwrap(inventory.filterSet(withID: ndOnly.id))), .headerControl)
        XCTAssertEqual(SelectedFilterSetAddFilterPlacement(for: try XCTUnwrap(inventory.filterSet(withID: aux.id))), .headerControl)
    }

    func testSelectedSetsShowGroupedByContentsInSelectionOrderAndRegroupAtOnce() throws {
        let inventory = FilterInventoryModel()
        let auxA = try XCTUnwrap(inventory.createFilterSet(name: "Aux A", color: .red))
        let empty = try XCTUnwrap(inventory.createFilterSet(name: "Empty", color: .green))
        let ndOnly = try XCTUnwrap(inventory.createFilterSet(name: "ND only", color: .blue))
        let auxB = try XCTUnwrap(inventory.createFilterSet(name: "Aux B", color: .pink))
        let mixed = try XCTUnwrap(inventory.createFilterSet(name: "Mixed", color: .teal))
        let bag = try XCTUnwrap(inventory.createFilterSet(name: "Bag", color: .blue))
        let wide = FilterItem(name: "77mm", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        inventory.addItem(red, to: auxA.id)
        inventory.addItem(nd("ND8", 3), to: ndOnly.id)
        inventory.addItem(wide, to: auxB.id)
        inventory.addItem(nd("ND64", 6), to: mixed.id)
        inventory.addItem(cpl, to: mixed.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        let selection = [auxA.id, bag.id, empty.id, ndOnly.id, auxB.id, mixed.id]
        XCTAssertEqual(
            viewModel.displayedSelectedFilterSets(selection).map(\.id),
            [ndOnly.id, mixed.id, auxA.id, auxB.id, bag.id, empty.id],
            "ND-only, mixed, auxiliary-only, empty; selection order within a group."
        )
        XCTAssertEqual(viewModel.selectedFilterSets(selection).map(\.id), selection, "The selection order itself is unchanged.")

        inventory.moveItem(wide, to: empty.id)
        XCTAssertEqual(
            viewModel.displayedSelectedFilterSets(selection).map(\.id),
            [ndOnly.id, mixed.id, auxA.id, empty.id, bag.id, auxB.id],
            "A moved item regroups both sets at once."
        )
        inventory.addItem(nd("ND1000", 10), to: auxA.id)
        XCTAssertEqual(
            viewModel.displayedSelectedFilterSets(selection).map(\.id),
            [ndOnly.id, auxA.id, mixed.id, empty.id, bag.id, auxB.id],
            "Gaining an ND filter makes a set mixed; selection order decides within the group."
        )
    }

    func testAMountOverThirtyStopsIsRefusedAtOnceAndTheSessionStays() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let soft = FilterItem(name: "Soft GND 3", behavior: .gnd(FilterRegisteredValue(value: 3, unit: .stops)))
        inventory.addItem(soft, to: kit.id)
        inventory.addItem(red, to: kit.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        viewModel.setNDFilterStep(NDStep(stops: 30), at: 0)
        let start = ShootingFiltersSession(committedFilterSetIDs: [kit.id], committedMounts: [])

        let recordOnly = try viewModel.shootingFiltersSession(start, settingMount: .mount(soft, in: kitSet), for: soft.id).get()
        XCTAssertEqual(recordOnly.mounts, [.mount(soft, in: kitSet)], "A Record-only GND mounts at 30 stops.")
        XCTAssertEqual(
            viewModel.shootingFiltersSession(recordOnly, settingMount: .mount(soft, in: kitSet, .gnd(.applyFullValue)), for: soft.id),
            .failure(.exceedsTotalLimit),
            "Applying its value would pass 30 stops."
        )
        XCTAssertEqual(viewModel.shootingFiltersSession(recordOnly, settingMount: .mount(red, in: kitSet), for: red.id), .failure(.exceedsTotalLimit))
        XCTAssertEqual(try viewModel.shootingFiltersSession(recordOnly, settingMount: nil, for: soft.id).get().mounts, [], "Unmounting is always accepted.")
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 30))], "No ND wheel changes.")
    }

    func testAMountBesideFourKeptNDWheelsIsRefusedUntilASetReleasesOne() throws {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let holder = try XCTUnwrap(inventory.createFilterSet(name: "Holder", color: .blue))
        let nd8 = nd("ND8", 3)
        inventory.addItem(red, to: kit.id)
        inventory.addItem(nd8, to: holder.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.arrangeFilterSets([kit.id, holder.id])
        viewModel.selectFilterSource(.filterSet(holder.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        viewModel.addFilterWheel(from: .standard)
        viewModel.addFilterWheel(from: .standard)
        XCTAssertEqual(viewModel.filterWheels.count, 4)
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        var working = ShootingFiltersSession(committedFilterSetIDs: [kit.id, holder.id], committedMounts: [])

        XCTAssertEqual(viewModel.shootingFiltersSession(working, settingMount: .mount(red, in: kitSet), for: red.id), .failure(.tooManyNDWheels))
        XCTAssertEqual(viewModel.filterWheels.count, 4, "No committed ND wheel is removed to fit the mount.")

        working.setSelected(holder.id, false)
        let released = try viewModel.shootingFiltersSession(working, settingMount: .mount(red, in: kitSet), for: red.id).get()
        XCTAssertEqual(released.mounts, [.mount(red, in: kitSet)], "Removing the Holder set frees its wheel for Apply.")
        XCTAssertEqual(viewModel.filterWheels.count, 4, "Nothing is committed before Apply.")
    }

    func testEverySetWithNDFiltersShowsTheNDCue() throws {
        let inventory = FilterInventoryModel()
        let empty = try XCTUnwrap(inventory.createFilterSet(name: "Empty", color: .red))
        let ndOnly = try XCTUnwrap(inventory.createFilterSet(name: "ND only", color: .blue))
        let mixed = try XCTUnwrap(inventory.createFilterSet(name: "Mixed", color: .green))
        inventory.addItem(nd("ND8", 3), to: ndOnly.id)
        inventory.addItem(nd("ND64", 6), to: mixed.id)
        inventory.addItem(red, to: mixed.id)
        let aux = try XCTUnwrap(inventory.createFilterSet(name: "Aux", color: .pink))
        inventory.addItem(cpl, to: aux.id)
        XCTAssertFalse(try XCTUnwrap(inventory.filterSet(withID: empty.id)).showsNDCue, "An empty set has its Add Filter row.")
        XCTAssertTrue(try XCTUnwrap(inventory.filterSet(withID: ndOnly.id)).showsNDCue)
        XCTAssertTrue(try XCTUnwrap(inventory.filterSet(withID: mixed.id)).showsNDCue, "A mixed set shows it beside its strip.")
        XCTAssertFalse(try XCTUnwrap(inventory.filterSet(withID: aux.id)).showsNDCue, "No ND filter, no cue.")
    }

    /// FILTER-ITEM-005/009: a moved item keeps its id, and every camera
    /// judges the move against its own selected Filter Sets. Where the
    /// destination is selected, the auxiliary filter follows and the ND
    /// wheel keeps the item; elsewhere the auxiliary filter is unmounted
    /// and the ND wheel becomes Empty under its original source. Each
    /// wheel keeps its identity, and no camera selects the destination.
    func testMovingAnItemKeepsItsIDAndEveryCameraJudgesItsOwnSelection() throws {
        let store = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let bag = try XCTUnwrap(inventory.createFilterSet(name: "Bag", color: .blue))
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let nd8 = nd("ND8", 3)
        inventory.addItem(red, to: bag.id)
        inventory.addItem(nd8, to: bag.id)
        let viewModel = makeViewModel(sessionStore: store, inventoryModel: inventory)
        let bagSet = try XCTUnwrap(viewModel.filterSet(withID: bag.id))

        // Camera 1 selects Bag only, mounts Red, and has an ND8 wheel
        // from Bag; camera 2, active while the items move, selects Bag
        // and Kit and mounts Red.
        viewModel.arrangeFilterSets([bag.id])
        XCTAssertNil(viewModel.applyMounts([.mount(red, in: bagSet)]))
        viewModel.selectFilterSource(.filterSet(bag.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let camera1Wheels = viewModel.filterWheels
        viewModel.selectCameraSlot(.camera2)
        viewModel.arrangeFilterSets([bag.id, kit.id])
        XCTAssertNil(viewModel.applyMounts([.mount(red, in: bagSet)]))
        viewModel.selectFilterSource(.filterSet(bag.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let camera2WheelIDs = viewModel.ndFilterWheelIDs

        var renamed = red
        renamed.name = "Red 25A Hoya"
        XCTAssertEqual(viewModel.saveFilterItem(renamed, in: kit.id), .saved)
        XCTAssertEqual(viewModel.saveFilterItem(nd8, in: kit.id), .saved)
        XCTAssertEqual(viewModel.filterSet(withID: kit.id)?.items.map(\.id), [red.id, nd8.id], "The same items, with their ids.")
        XCTAssertEqual(viewModel.filterSet(withID: bag.id)?.items, [])

        // Camera 2 selects Kit: Red follows it there, and the ND8 stays
        // on the same wheel under Kit.
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [.mount(renamed, in: try XCTUnwrap(viewModel.filterSet(withID: kit.id)))])
        XCTAssertTrue(viewModel.filterWheels.contains(FilterWheel(source: .filterSet(kit.id), selection: select(nd8))))
        XCTAssertEqual(viewModel.ndFilterWheelIDs, camera2WheelIDs, "The same wheels.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [bag.id, kit.id])
        XCTAssertEqual(viewModel.ndStep.stops, 3 + 3, accuracy: 1e-9)

        // Camera 1, inactive during the move, does not select Kit: Red is
        // unmounted and the ND8 wheel is Bag's Empty wheel in the same
        // place; Kit is not selected.
        viewModel.selectCameraSlot(.camera1)
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty)
        XCTAssertEqual(viewModel.filterWheels, camera1Wheels.map { $0 == FilterWheel(source: .filterSet(bag.id), selection: select(nd8)) ? .empty(in: bag.id) : $0 })
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [bag.id], "Kit is not selected.")
        XCTAssertEqual(viewModel.ndStep.stops, 0, accuracy: 1e-9)

        // A restart restores the same.
        let restored = makeViewModel(sessionStore: store, inventoryModel: inventory)
        XCTAssertTrue(restored.mountedAuxiliaryFilters.isEmpty)
        XCTAssertFalse(restored.filterWheels.contains { $0.mountedItemID == nd8.id })
        XCTAssertEqual(restored.candidateFilterSetIDs, [bag.id])
        restored.selectCameraSlot(.camera2)
        XCTAssertEqual(restored.mountedAuxiliaryFilters.map(\.mount.filterSetID), [kit.id])
        XCTAssertTrue(restored.filterWheels.contains(FilterWheel(source: .filterSet(kit.id), selection: select(nd8))))
    }

    /// FILTER-ITEM-005 on the active camera: an ND item saved into a Set
    /// the camera does not select leaves its wheel Empty under the
    /// original source with the same wheel identity. The selected Filter
    /// Sets keep their list and order, nothing is selected, and an open
    /// session's unrelated picks survive; Cancel or Apply cannot bring the
    /// item back because the inventory save already took effect.
    func testAnNDItemMovedToAnAvailableSetLeavesTheSameWheelEmptyOnTheActiveCamera() throws {
        let inventory = FilterInventoryModel()
        let bag = try XCTUnwrap(inventory.createFilterSet(name: "Bag", color: .blue))
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let spare = try XCTUnwrap(inventory.createFilterSet(name: "Spare", color: .green))
        let nd8 = nd("ND8", 3)
        inventory.addItem(nd8, to: bag.id)
        inventory.addItem(red, to: spare.id)
        let viewModel = makeViewModel(sessionStore: InMemoryMixedSessionStore(), inventoryModel: inventory)
        viewModel.arrangeFilterSets([bag.id, spare.id])
        viewModel.selectFilterSource(.filterSet(bag.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let wheelIDs = viewModel.ndFilterWheelIDs
        let index = try XCTUnwrap(viewModel.filterWheels.firstIndex(of: FilterWheel(source: .filterSet(bag.id), selection: select(nd8))))
        // An open session with an unrelated draft pick.
        var session = ShootingFiltersSession(committedFilterSetIDs: viewModel.candidateFilterSetIDs, committedMounts: [])
        session.setMount(.mount(red, in: try XCTUnwrap(viewModel.filterSet(withID: spare.id))), for: red.id)

        XCTAssertEqual(viewModel.saveFilterItem(nd8, in: kit.id), .saved)
        session.follow(committedFilterSetIDs: viewModel.candidateFilterSetIDs, committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount), inventory: viewModel.filterInventory)

        XCTAssertEqual(viewModel.filterWheels[index], .empty(in: bag.id))
        XCTAssertEqual(viewModel.ndFilterWheelIDs, wheelIDs, "The same wheel identities.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [bag.id, spare.id], "The selected Filter Sets are unchanged; Kit is not selected.")
        XCTAssertEqual(session.mounts.map(\.itemID), [red.id], "The unrelated draft pick stays.")
        XCTAssertEqual(session.selectedFilterSetIDs, [bag.id, spare.id])

        // Cancel leaves the camera as the inventory save made it; Apply
        // commits the draft without bringing the ND8 back.
        XCTAssertEqual(viewModel.filterWheels[index], .empty(in: bag.id))
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: session.selectedFilterSetIDs, mounts: session.mounts))
        XCTAssertFalse(viewModel.filterWheels.contains { $0.mountedItemID == nd8.id })
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [red.id])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [bag.id, spare.id])
    }

    func testItemsReadNDFirstThenByKindAndNameWithoutManualOrder() {
        let nd8 = nd("ND8", 3)
        let nd400 = nd("ND400", 8.6)
        let night = effect("Night", 1)
        let amber = FilterItem(name: "amber", behavior: .color(FilterExposureLoss(stops: 1), .orange))
        let stored = [gnd, cpl, red, nd400, night, nd8, amber]
        XCTAssertEqual(
            FilterSetItemOrder.ordered(stored).map(\.id),
            [nd8.id, nd400.id, amber.id, red.id, night.id, cpl.id, gnd.id],
            "ND, Color, Effect, CPL, GND; by name within a kind, numbers in numeric order, case ignored; the stored order never matters."
        )
        XCTAssertEqual(FilterSetItemOrder.ordered(stored.reversed()).map(\.id), FilterSetItemOrder.ordered(stored).map(\.id))
        XCTAssertEqual(FilterSetItemOrder.newItemKind, .fixed, "New Filter opens with ND.")
    }
}

/// A flag an observation callback may set from any context.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    var value: Bool { lock.withLock { isSet } }

    func set() { lock.withLock { isSet = true } }
}
