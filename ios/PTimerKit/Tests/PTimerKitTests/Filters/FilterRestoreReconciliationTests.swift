// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// The inventory and the camera sessions are saved separately, so a
/// relaunch can meet an inventory edit the camera snapshot has not seen
/// yet. The restore applies it the way the live reconciliation does
/// (FILTER-ITEM-005/009, FILTER-PERSIST-002): a moved item keeps its
/// references under its new Set, a kind change moves the selection into
/// the item's new role, and a deleted item keeps the deletion rules.
@MainActor
final class FilterRestoreReconciliationTests: XCTestCase {
    private let nd8 = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
    private let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
    private let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))

    private func makeViewModel(sessionStore: CameraSlotSessionPersistenceStoring, inventoryStore: InMemoryFilterInventoryStore) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: FilterInventoryModel(store: inventoryStore)
        )
    }

    /// Kit holds ND8, the CPL, and the Red; Pouch is empty. The camera
    /// selects Kit, has a Kit ND8 wheel beside Standard 2, and mounts the
    /// CPL at 1.5 and the Red. Returns the camera snapshot saved then.
    private struct SavedCamera {
        let sessionStore: InMemoryMixedSessionStore
        let inventoryStore: InMemoryFilterInventoryStore
        let kit: FilterSet
        let pouch: FilterSet
        let total: Double
    }

    private func savedCamera(pouchSelected: Bool = false) throws -> SavedCamera {
        let sessionStore = InMemoryMixedSessionStore()
        let inventoryStore = InMemoryFilterInventoryStore()
        let inventory = FilterInventoryModel(store: inventoryStore)
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let pouch = try XCTUnwrap(inventory.createFilterSet(name: "Pouch", color: .orange))
        inventory.addItem(nd8, to: kit.id)
        inventory.addItem(cpl, to: kit.id)
        inventory.addItem(red, to: kit.id)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventory
        )
        XCTAssertNil(viewModel.applyShootingFilters(
            selectedFilterSetIDs: pouchSelected ? [kit.id, pouch.id] : [kit.id],
            mounts: [.mount(cpl, in: kit, .cplLoss(1.5)), .mount(red, in: kit)]
        ))
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: nd8.id, choice: .fixed)), at: 1)
        XCTAssertEqual(viewModel.filterWheels.count, 2)
        XCTAssertNotNil(sessionStore.stored)
        return SavedCamera(sessionStore: sessionStore, inventoryStore: inventoryStore, kit: kit, pouch: pouch, total: total(viewModel))
    }

    private func total(_ viewModel: ExposureCalculatorViewModel) -> Double {
        viewModel.ndStep.stops
    }

    /// Edits the saved inventory only, as if the app stopped before the
    /// camera session was saved again.
    private func editSavedInventory(_ store: InMemoryFilterInventoryStore, _ edit: (FilterInventoryModel) -> Void) {
        edit(FilterInventoryModel(store: store))
    }

    /// One saved inventory moved an ND item and an auxiliary item into
    /// Pouch, which the camera does not select. The auxiliary rule is
    /// judged against the stored selection, so the CPL is unmounted even
    /// though the ND wheel follows its item into Pouch (today's ND-wheel
    /// behavior, its policy still open on #70, 6001226087).
    func testAMovedNDWheelFollowsAndAMovedAuxiliaryItemIsJudgedAgainstTheStoredSelection() throws {
        let saved = try savedCamera()
        let (sessionStore, inventoryStore, kit, pouch, total) = (saved.sessionStore, saved.inventoryStore, saved.kit, saved.pouch, saved.total)
        XCTAssertEqual(self.total(makeViewModel(sessionStore: sessionStore, inventoryStore: inventoryStore)), total, accuracy: 1e-9, "The unedited pair restores as saved.")
        editSavedInventory(inventoryStore) { inventory in
            inventory.moveItem(self.nd8, to: pouch.id)
            inventory.moveItem(self.cpl, to: pouch.id)
        }

        let restored = makeViewModel(sessionStore: sessionStore, inventoryStore: inventoryStore)

        XCTAssertTrue(restored.filterWheels.contains(FilterWheel(source: .filterSet(pouch.id), selection: .item(FilterRowSelection(itemID: nd8.id, choice: .fixed)))), "\(restored.filterWheels)")
        XCTAssertEqual(restored.mountedAuxiliaryFilters.map(\.mount), [.mount(red, in: kit)], "The ND wheel does not select Pouch for the CPL.")
        XCTAssertEqual(restored.candidateFilterSetIDs, [kit.id, pouch.id], "Pouch is referenced by the ND wheel.")
        XCTAssertEqual(self.total(restored), total - 1.5, accuracy: 1e-9, "Only the CPL's contribution is gone.")
    }

    /// FILTER-ITEM-009 at restore: an auxiliary item moved to a Set the
    /// camera does not select restores unmounted, without selecting that
    /// Set; moved to a selected Set, it restores under it.
    func testAMovedAuxiliaryItemRestoresOnlyUnderASelectedSet() throws {
        let unselected = try savedCamera()
        editSavedInventory(unselected.inventoryStore) { $0.moveItem(self.cpl, to: unselected.pouch.id) }
        let restored = makeViewModel(sessionStore: unselected.sessionStore, inventoryStore: unselected.inventoryStore)
        XCTAssertEqual(restored.mountedAuxiliaryFilters.map(\.mount), [.mount(red, in: unselected.kit)])
        XCTAssertEqual(restored.candidateFilterSetIDs, [unselected.kit.id], "The destination is not selected.")

        let selected = try savedCamera(pouchSelected: true)
        editSavedInventory(selected.inventoryStore) { $0.moveItem(self.cpl, to: selected.pouch.id) }
        let restoredSelected = makeViewModel(sessionStore: selected.sessionStore, inventoryStore: selected.inventoryStore)
        XCTAssertEqual(Set(restoredSelected.mountedAuxiliaryFilters.map(\.mount)), [.mount(cpl, in: selected.pouch, .cplLoss(1.5)), .mount(red, in: selected.kit)])
    }

    func testAKindChangeMovesTheSelectionIntoTheItemsNewRole() throws {
        let saved = try savedCamera()
        let (sessionStore, inventoryStore, kit) = (saved.sessionStore, saved.inventoryStore, saved.kit)
        editSavedInventory(inventoryStore) { inventory in
            // Red becomes an ND filter; ND8 becomes an Effect filter.
            inventory.updateItem(FilterItem(id: self.red.id, name: self.red.name, behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops))))
            inventory.updateItem(FilterItem(id: self.nd8.id, name: self.nd8.name, behavior: .effect(FilterExposureLoss(stops: 3))))
        }

        let restored = makeViewModel(sessionStore: sessionStore, inventoryStore: inventoryStore)

        XCTAssertTrue(restored.filterWheels.contains(FilterWheel(source: .filterSet(kit.id), selection: .item(FilterRowSelection(itemID: red.id, choice: .fixed)))), "\(restored.filterWheels)")
        XCTAssertFalse(restored.filterWheels.contains { $0.mountedItemID == nd8.id })
        XCTAssertEqual(Set(restored.mountedAuxiliaryFilters.map(\.mount)), [.mount(cpl, in: kit, .cplLoss(1.5)), .mount(nd8, in: kit, .registeredLoss)])
    }

    /// An edit made in the app saves the camera session at once; that
    /// save records each mount with its item's NEW kind, so the relaunch
    /// keeps it (FILTER-PERSIST-001/002).
    func testAKindCorrectionMadeLiveSurvivesARelaunch() throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventoryStore = InMemoryFilterInventoryStore()
        let inventory = FilterInventoryModel(store: inventoryStore)
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        inventory.addItem(nd8, to: kit.id)
        inventory.addItem(cpl, to: kit.id)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventory
        )
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [kit.id], mounts: [.mount(cpl, in: kit, .cplLoss(1.5))]))
        viewModel.selectFilterSource(.filterSet(kit.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: nd8.id, choice: .fixed)), at: 1)

        // ND8 is corrected to a Color filter, and the CPL to a Color filter.
        XCTAssertEqual(viewModel.saveFilterItem(FilterItem(id: nd8.id, name: nd8.name, behavior: .color(FilterExposureLoss(stops: 3), .red)), in: kit.id), .saved)
        XCTAssertEqual(viewModel.saveFilterItem(FilterItem(id: cpl.id, name: cpl.name, behavior: .color(FilterExposureLoss(stops: 1), .yellow)), in: kit.id), .saved)
        let live = Set(viewModel.mountedAuxiliaryFilters.map(\.mount))
        XCTAssertEqual(live, [.mount(nd8, in: kit, .registeredLoss), .mount(cpl, in: kit, .registeredLoss)])
        let saved = try XCTUnwrap(sessionStore.stored?.slots.first { $0.slotIDRaw == CameraSlotID.camera1.rawValue })
        XCTAssertEqual(Set(saved.auxiliaryFilters?.map(\.kind) ?? []), ["color"], "Saved with the new kind.")

        let restored = makeViewModel(sessionStore: sessionStore, inventoryStore: inventoryStore)
        XCTAssertEqual(Set(restored.mountedAuxiliaryFilters.map(\.mount)), live)
        XCTAssertEqual(restored.ndStep.stops, viewModel.ndStep.stops, accuracy: 1e-9)
    }

    func testADeletedItemKeepsTheDeletionRules() throws {
        let saved = try savedCamera()
        let (sessionStore, inventoryStore, kit) = (saved.sessionStore, saved.inventoryStore, saved.kit)
        editSavedInventory(inventoryStore) { inventory in
            inventory.deleteItem(id: self.nd8.id)
            inventory.deleteItem(id: self.cpl.id)
        }

        let restored = makeViewModel(sessionStore: sessionStore, inventoryStore: inventoryStore)

        XCTAssertTrue(restored.filterWheels.contains(.empty(in: kit.id)), "A deleted wheel item reads Empty.")
        XCTAssertEqual(restored.mountedAuxiliaryFilters.map(\.mount), [.mount(red, in: kit)], "A deleted auxiliary item is unmounted.")
    }
}
