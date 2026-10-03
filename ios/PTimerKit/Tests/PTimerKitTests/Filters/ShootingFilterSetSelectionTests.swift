// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// The Shooting Filters workflow (FILTER-AUX-003, FILTER-CAMERA-001/003,
/// FILTER-FLOW-003..005, FILTER-ITEM-009, FILTER-SET-001/002): one working
/// session over the camera's Filter Set selection and auxiliary mounts,
/// committed together by Apply and dropped by Cancel; the offered list as
/// the grouped union of the working selection; filter-first registration
/// into Default or an inline set; inventory edits that stay immediate.
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

    func testSeveralSelectedSetsOfferTheirGroupedUnionAndFollowTheWorkingSelectionAndSetOrder() throws {
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
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet], "A fresh camera starts with Default selected.")

        XCTAssertEqual(viewModel.offeredAuxiliaryItems(selectedFilterSetIDs: [small.id]).map(\.item.id), [red.id, cpl.id], "ND items are never offered here.")
        XCTAssertEqual(
            viewModel.offeredAuxiliaryItems(selectedFilterSetIDs: [small.id, big.id]).map(\.item.id),
            [red.id, cpl.id, night.id, gnd.id],
            "Union of both sets, grouped by set, each in Color, Effect, CPL, GND order."
        )
        XCTAssertEqual(viewModel.offeredAuxiliaryItems(selectedFilterSetIDs: [small.id, big.id]).map(\.filterSet.id), [small.id, small.id, big.id, big.id])
        XCTAssertEqual(
            viewModel.offeredAuxiliaryItems(selectedFilterSetIDs: [big.id, small.id]).map(\.item.id),
            [night.id, gnd.id, red.id, cpl.id],
            "The groups follow the selection order."
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
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet, big.id, small.id], "Applied in the order the sets were added.")
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
        viewModel.setCandidateFilterSetIDs([kit.id, other.id])
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        let otherSet = try XCTUnwrap(viewModel.filterSet(withID: other.id))
        XCTAssertNil(viewModel.applyAuxiliaryFilters([.mount(red, in: kitSet), .mount(cpl, in: otherSet, .cplLoss(1.5))]))
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
        XCTAssertFalse(viewModel.offeredAuxiliaryItems(selectedFilterSetIDs: working.selectedFilterSetIDs).contains { $0.filterSet.id == kit.id }, "Its group is hidden at once.")
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
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet], "Not committed yet.")
        XCTAssertNil(apply(working, viewModel))
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet, kit.id], "Appended after Default.")
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
        viewModel.setCandidateFilterSetIDs([kit.id, other.id])
        let kitSet = try XCTUnwrap(viewModel.filterSet(withID: kit.id))
        let otherSet = try XCTUnwrap(viewModel.filterSet(withID: other.id))
        XCTAssertNil(viewModel.applyAuxiliaryFilters([.mount(red, in: kitSet), .mount(cpl, in: otherSet, .cplLoss(1.5))]))
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
        working.setSelected(.defaultSet, true)
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
            existingFilterSetIDs: Set(viewModel.filterInventory.filterSets.map(\.id))
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
        viewModel.setCandidateFilterSetIDs([kit.id])
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let standardIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex(where: \.isStandard))
        viewModel.removeZeroWheelFromOverscroll(at: standardIndex)

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [], mounts: []))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        XCTAssertEqual(viewModel.ndStep.stops, 0, accuracy: 1e-9)
    }

    func testFilterFirstRegistrationSavesIntoTheSelectedDefaultOrAnInlineSetWithoutSelectingIt() throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        XCTAssertEqual(viewModel.filterInventory.filterSets.map(\.id), [.defaultSet], "Default exists before any set is created.")

        XCTAssertEqual(viewModel.saveFilterItem(red, in: .defaultSet), .saved)
        XCTAssertEqual(viewModel.filterSet(withID: .defaultSet)?.items, [red])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet], "A fresh camera has Default selected, so its filter is offered at once.")
        XCTAssertEqual(viewModel.offeredAuxiliaryItems(selectedFilterSetIDs: viewModel.candidateFilterSetIDs).map(\.item.id), [red.id])

        // Add Filter Set from the editor's Filter Set field: the new set
        // is created, then the in-progress filter saves into it.
        let inline = try XCTUnwrap(viewModel.createFilterSet(name: "52mm", color: .red))
        XCTAssertEqual(viewModel.saveFilterItem(cpl, in: inline.id), .saved)
        XCTAssertEqual(viewModel.filterSet(withID: inline.id)?.items, [cpl])
        XCTAssertEqual(viewModel.filterInventory.filterSets.map(\.id), [.defaultSet, inline.id])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet], "Creating a set does not select it.")
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

    func testAFreshCameraStartsWithDefaultAndARemovedDefaultStaysRemoved() throws {
        let store = InMemoryMixedSessionStore()
        let viewModel = makeViewModel(sessionStore: store, inventoryModel: FilterInventoryModel())
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet])
        viewModel.selectCameraSlot(.camera3)
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet], "Every fresh camera starts with Default.")
        viewModel.selectCameraSlot(.camera1)

        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [], mounts: []))
        XCTAssertTrue(viewModel.candidateFilterSetIDs.isEmpty, "Default can be removed like any other set.")
        let slot = try XCTUnwrap(store.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(slot.candidateFilterSetIDs, [], "An emptied selection is stored as an empty list.")

        let restored = makeViewModel(sessionStore: store, inventoryModel: FilterInventoryModel())
        XCTAssertTrue(restored.candidateFilterSetIDs.isEmpty, "It does not come back as a fresh camera.")
        restored.selectCameraSlot(.camera3)
        XCTAssertEqual(restored.candidateFilterSetIDs, [.defaultSet])
    }

    func testSelectedSetsKeepTheirOrderAndAvailableSetsReadByName() throws {
        let inventory = FilterInventoryModel()
        let zeta = try XCTUnwrap(inventory.createFilterSet(name: "Zeta", color: .red))
        let alpha = try XCTUnwrap(inventory.createFilterSet(name: "alpha", color: .blue))
        let ten = try XCTUnwrap(inventory.createFilterSet(name: "Filter 10", color: .teal))
        let nine = try XCTUnwrap(inventory.createFilterSet(name: "Filter 9", color: .teal))
        let viewModel = makeViewModel(inventoryModel: inventory)
        var working = session(viewModel)
        XCTAssertEqual(viewModel.selectedFilterSets(working.selectedFilterSetIDs).map(\.id), [.defaultSet])
        XCTAssertEqual(
            viewModel.availableFilterSets(excluding: working.selectedFilterSetIDs).map(\.id),
            [alpha.id, nine.id, ten.id, zeta.id],
            "By name, case ignored, numbers in numeric order; creation order never matters."
        )

        // The trailing add control appends; the leading remove control
        // moves a set back among the Available Sets by name.
        working.setSelected(zeta.id, true)
        working.setSelected(alpha.id, true)
        XCTAssertEqual(viewModel.selectedFilterSets(working.selectedFilterSetIDs).map(\.id), [.defaultSet, zeta.id, alpha.id])
        XCTAssertEqual(viewModel.availableFilterSets(excluding: working.selectedFilterSetIDs).map(\.id), [nine.id, ten.id])
        working.setSelected(.defaultSet, false)
        XCTAssertEqual(viewModel.selectedFilterSets(working.selectedFilterSetIDs).map(\.id), [zeta.id, alpha.id])
        XCTAssertEqual(viewModel.availableFilterSets(excluding: working.selectedFilterSetIDs).map(\.id), [.defaultSet, nine.id, ten.id])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet], "Nothing is committed before Apply.")

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
        inventory.addItem(nd("ND8", 3), to: ndOnly.id)
        inventory.addItem(red, to: .defaultSet)
        XCTAssertEqual(SelectedFilterSetAddFilterPlacement(for: try XCTUnwrap(inventory.filterSet(withID: empty.id))), .fullWidthRow)
        XCTAssertEqual(SelectedFilterSetAddFilterPlacement(for: try XCTUnwrap(inventory.filterSet(withID: ndOnly.id))), .headerControl)
        XCTAssertEqual(SelectedFilterSetAddFilterPlacement(for: try XCTUnwrap(inventory.filterSet(withID: .defaultSet))), .headerControl)
    }

    func testSelectedSetsShowGroupedByContentsInSelectionOrderAndRegroupAtOnce() throws {
        let inventory = FilterInventoryModel()
        let auxA = try XCTUnwrap(inventory.createFilterSet(name: "Aux A", color: .red))
        let empty = try XCTUnwrap(inventory.createFilterSet(name: "Empty", color: .green))
        let ndOnly = try XCTUnwrap(inventory.createFilterSet(name: "ND only", color: .blue))
        let auxB = try XCTUnwrap(inventory.createFilterSet(name: "Aux B", color: .pink))
        let mixed = try XCTUnwrap(inventory.createFilterSet(name: "Mixed", color: .teal))
        let wide = FilterItem(name: "77mm", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        inventory.addItem(red, to: auxA.id)
        inventory.addItem(nd("ND8", 3), to: ndOnly.id)
        inventory.addItem(wide, to: auxB.id)
        inventory.addItem(nd("ND64", 6), to: mixed.id)
        inventory.addItem(cpl, to: mixed.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        let selection = [auxA.id, .defaultSet, empty.id, ndOnly.id, auxB.id, mixed.id]
        XCTAssertEqual(
            viewModel.displayedSelectedFilterSets(selection).map(\.id),
            [ndOnly.id, mixed.id, auxA.id, auxB.id, .defaultSet, empty.id],
            "ND-only, mixed, auxiliary-only, empty; selection order within a group."
        )
        XCTAssertEqual(viewModel.selectedFilterSets(selection).map(\.id), selection, "The selection order itself is unchanged.")

        inventory.moveItem(wide, to: empty.id)
        XCTAssertEqual(
            viewModel.displayedSelectedFilterSets(selection).map(\.id),
            [ndOnly.id, mixed.id, auxA.id, empty.id, .defaultSet, auxB.id],
            "A moved item regroups both sets at once."
        )
        inventory.addItem(nd("ND1000", 10), to: auxA.id)
        XCTAssertEqual(
            viewModel.displayedSelectedFilterSets(selection).map(\.id),
            [ndOnly.id, auxA.id, mixed.id, empty.id, .defaultSet, auxB.id],
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
        viewModel.setCandidateFilterSetIDs([kit.id, holder.id])
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
        inventory.addItem(cpl, to: .defaultSet)
        XCTAssertFalse(try XCTUnwrap(inventory.filterSet(withID: empty.id)).showsNDCue, "An empty set has its Add Filter row.")
        XCTAssertTrue(try XCTUnwrap(inventory.filterSet(withID: ndOnly.id)).showsNDCue)
        XCTAssertTrue(try XCTUnwrap(inventory.filterSet(withID: mixed.id)).showsNDCue, "A mixed set shows it beside its strip.")
        XCTAssertFalse(try XCTUnwrap(inventory.filterSet(withID: .defaultSet)).showsNDCue, "No ND filter, no cue.")
    }

    func testMovingAnItemOutOfDefaultKeepsItsIDAndEveryCameraReference() throws {
        let store = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let nd8 = nd("ND8", 3)
        inventory.addItem(red, to: .defaultSet)
        inventory.addItem(nd8, to: .defaultSet)
        let viewModel = makeViewModel(sessionStore: store, inventoryModel: inventory)
        let defaultSet = try XCTUnwrap(viewModel.filterSet(withID: .defaultSet))

        // Camera 1 mounts Red and an ND8 wheel from Default; camera 2,
        // active while the items move, mounts Red only.
        XCTAssertNil(viewModel.applyAuxiliaryFilters([.mount(red, in: defaultSet)]))
        viewModel.selectFilterSource(.filterSet(.defaultSet))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd8), at: 1)
        let cameraOneTotal = viewModel.ndStep.stops
        viewModel.selectCameraSlot(.camera2)
        XCTAssertNil(viewModel.applyAuxiliaryFilters([.mount(red, in: defaultSet)]))

        var renamed = red
        renamed.name = "Red 25A Hoya"
        XCTAssertEqual(viewModel.saveFilterItem(renamed, in: kit.id), .saved)
        XCTAssertEqual(viewModel.saveFilterItem(nd8, in: kit.id), .saved)
        XCTAssertEqual(viewModel.filterSet(withID: kit.id)?.items.map(\.id), [red.id, nd8.id], "The same items, with their ids.")
        XCTAssertEqual(viewModel.filterSet(withID: .defaultSet)?.items, [])

        // The active camera keeps Red under Kit; Kit joins its sets and
        // Default stays.
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [.mount(renamed, in: try XCTUnwrap(viewModel.filterSet(withID: kit.id)))])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet, kit.id])

        // The inactive camera kept both references the same way.
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount.filterSetID), [kit.id])
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [red.id])
        XCTAssertTrue(viewModel.filterWheels.contains(FilterWheel(source: .filterSet(kit.id), selection: select(nd8))), "The ND8 wheel follows its item.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [.defaultSet, kit.id])
        XCTAssertEqual(viewModel.ndStep.stops, cameraOneTotal, accuracy: 1e-9, "The total is unchanged.")
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
        XCTAssertEqual(FilterSetItemOrder.auxiliaryKinds, [.color, .effect, .cpl, .gnd])
    }
}
