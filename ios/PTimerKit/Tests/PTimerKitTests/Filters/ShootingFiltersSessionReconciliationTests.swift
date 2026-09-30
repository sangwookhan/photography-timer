// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// A Shooting Filters session across inventory edits made from a Set
/// editor opened in it (FILTER-FLOW-003, FILTER-ITEM-006/009,
/// FILTER-PERSIST-002): working-only picks that no longer resolve are
/// dropped without a replacement, a committed change is followed item by
/// item, and every unrelated draft pick, unmount, and choice stays.
@MainActor
final class ShootingFiltersSessionReconciliationTests: XCTestCase {
    private let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
    private let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
    private let night = FilterItem(name: "Night", behavior: .effect(FilterExposureLoss(stops: 1)))

    /// Kit holds the CPL and the Red; Pouch holds Night. The camera
    /// selects Kit and mounts `committed`.
    private func fixture(
        committed: (FilterSet) -> [MountedAuxiliaryFilter] = { _ in [] }
    ) throws -> (viewModel: ExposureCalculatorViewModel, kit: FilterSet, pouch: FilterSet) {
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let pouch = try XCTUnwrap(inventory.createFilterSet(name: "Pouch", color: .orange))
        inventory.addItem(cpl, to: kit.id)
        inventory.addItem(red, to: kit.id)
        inventory.addItem(night, to: pouch.id)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            filterInventoryModel: inventory
        )
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [kit.id], mounts: committed(kit)))
        return (viewModel, kit, pouch)
    }

    private func mount(_ item: FilterItem, in filterSet: FilterSet, _ choice: AuxiliaryFilterChoice = .registeredLoss) -> MountedAuxiliaryFilter {
        MountedAuxiliaryFilter(filterSetID: filterSet.id, itemID: item.id, choice: choice)
    }

    private func session(_ viewModel: ExposureCalculatorViewModel) -> ShootingFiltersSession {
        ShootingFiltersSession(
            committedFilterSetIDs: viewModel.candidateFilterSetIDs,
            committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount)
        )
    }

    /// Makes `change` — an inventory edit made from the popup — and runs
    /// what the popup runs on it: a rebase when the committed state
    /// changed and a reconcile when the inventory changed. SwiftUI does
    /// not order the two `onChange` handlers, so both orders must agree.
    private func edit(_ session: inout ShootingFiltersSession, _ viewModel: ExposureCalculatorViewModel, _ change: () -> Void) {
        func committed() -> ([FilterSetID], Set<MountedAuxiliaryFilter>) {
            (viewModel.candidateFilterSetIDs, Set(viewModel.mountedAuxiliaryFilters.map(\.mount)))
        }
        let committedBefore = committed()
        let inventoryBefore = viewModel.filterInventory
        change()
        let committedChanged = committed() != committedBefore
        let inventoryChanged = viewModel.filterInventory != inventoryBefore
        func rebase(_ working: inout ShootingFiltersSession) {
            guard committedChanged else { return }
            working.rebase(
                committedFilterSetIDs: viewModel.candidateFilterSetIDs,
                committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount),
                existingFilterSetIDs: Set(viewModel.filterInventory.filterSets.map(\.id))
            )
        }
        func reconcile(_ working: inout ShootingFiltersSession) {
            guard inventoryChanged else { return }
            working.reconcile(with: viewModel.filterInventory)
        }
        var rebasedFirst = session
        rebase(&rebasedFirst)
        reconcile(&rebasedFirst)
        var reconciledFirst = session
        reconcile(&reconciledFirst)
        rebase(&reconciledFirst)
        XCTAssertEqual(rebasedFirst, reconciledFirst, "The order of the two triggers does not matter.")
        session = rebasedFirst
    }

    private func canApply(_ session: ShootingFiltersSession, _ viewModel: ExposureCalculatorViewModel) -> Bool {
        guard session.hasChanges,
              case .success = viewModel.shootingFiltersPreview(selectedFilterSetIDs: session.selectedFilterSetIDs, mounts: session.mounts) else {
            return false
        }
        return true
    }

    // MARK: Working-only picks

    func testDeletingAWorkingOnlyPickDropsItAndKeepsTheOtherPicks() throws {
        let (viewModel, kit, _) = try fixture()
        var working = session(viewModel)
        working.setMount(mount(cpl, in: kit, .cplLoss(1.5)), for: cpl.id)
        working.setMount(mount(red, in: kit), for: red.id)

        edit(&working, viewModel) { viewModel.deleteFilterItem(id: cpl.id) }
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty, "The camera never committed the pick.")

        XCTAssertEqual(working.mounts, [mount(red, in: kit)])
        XCTAssertTrue(canApply(working, viewModel), "No hidden stale pick blocks Apply.")
    }

    func testDeletingAWorkingOnlySetDropsItsSelectionAndPicks() throws {
        let (viewModel, kit, pouch) = try fixture()
        var working = session(viewModel)
        working.setSelected(pouch.id, true)
        working.setMount(mount(night, in: pouch), for: night.id)

        edit(&working, viewModel) { viewModel.deleteFilterSet(id: pouch.id) }

        XCTAssertEqual(working.selectedFilterSetIDs, [kit.id])
        XCTAssertTrue(working.mounts.isEmpty)
        XCTAssertFalse(working.hasChanges, "Nothing is left to apply.")
        working.setSelected(pouch.id, true)
        XCTAssertNil(working.mount(of: night.id), "The deleted Set's pick does not come back.")
    }

    func testRemovingTheWorkingChoiceOfACPLDropsThePickWithoutAReplacement() throws {
        let (viewModel, kit, _) = try fixture()
        var working = session(viewModel)
        working.setMount(mount(cpl, in: kit, .cplLoss(2)), for: cpl.id)
        working.setMount(mount(red, in: kit), for: red.id)

        let edited = FilterItem(id: cpl.id, name: cpl.name, behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, nil])))
        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(edited, in: kit.id), .saved) }

        XCTAssertNil(working.mount(of: cpl.id), "A removed choice is never replaced by another.")
        XCTAssertEqual(working.mounts, [mount(red, in: kit)])
        XCTAssertTrue(canApply(working, viewModel))
    }

    /// FILTER-ITEM-009 with question 5972698491 still open: a working-only
    /// pick whose item moved to another Set is left as it is.
    func testAWorkingOnlyPickWhoseItemMovedIsLeftAsItIs() throws {
        let (viewModel, kit, pouch) = try fixture()
        var working = session(viewModel)
        working.setMount(mount(red, in: kit), for: red.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(red, in: pouch.id), .saved) }

        XCTAssertEqual(working.mount(of: red.id), mount(red, in: kit))
    }

    // MARK: Committed changes

    func testACommittedMoveKeepsUnrelatedDraftPicksAndUnmounts() throws {
        let (viewModel, kit, pouch) = try fixture { kit in
            [self.mount(self.cpl, in: kit, .cplLoss(1.5)), self.mount(self.red, in: kit)]
        }
        var working = session(viewModel)
        working.setMount(nil, for: red.id)
        working.setSelected(pouch.id, true)
        working.setMount(mount(night, in: pouch), for: night.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: pouch, .cplLoss(1.5)), "The committed move is followed.")
        XCTAssertNil(working.mount(of: red.id), "The draft unmount stays.")
        XCTAssertEqual(working.mount(of: night.id), mount(night, in: pouch), "The draft pick stays.")
        XCTAssertTrue(canApply(working, viewModel))

        // Cancel: the inventory move stays; the draft changes were never committed.
        XCTAssertEqual(viewModel.filterSet(withID: pouch.id)?.item(withID: cpl.id), cpl)
        XCTAssertEqual(Set(viewModel.mountedAuxiliaryFilters.map(\.mount)), [mount(cpl, in: pouch, .cplLoss(1.5)), mount(red, in: kit)])
    }

    func testACommittedMoveKeepsTheDraftChoiceUnderTheNewSet() throws {
        let (viewModel, kit, pouch) = try fixture { kit in [self.mount(self.cpl, in: kit, .cplLoss(1.5))] }
        var working = session(viewModel)
        working.setMount(mount(cpl, in: kit, .cplLoss(2)), for: cpl.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: pouch, .cplLoss(2)))
    }

    func testACommittedChangeKeepsThePicksOfASetRemovedInTheSession() throws {
        let (viewModel, _, pouch) = try fixture { kit in [self.mount(self.red, in: kit)] }
        let bag = try XCTUnwrap(viewModel.createFilterSet(name: "Bag", color: .blue))
        var working = session(viewModel)
        working.setSelected(pouch.id, true)
        working.setMount(mount(night, in: pouch), for: night.id)
        working.setSelected(pouch.id, false)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(red, in: bag.id), .saved) }
        XCTAssertEqual(working.mount(of: red.id), mount(red, in: bag))

        working.setSelected(pouch.id, true)
        XCTAssertEqual(working.mount(of: night.id), mount(night, in: pouch), "Adding the Set back restores its pick.")
        XCTAssertTrue(working.mounts.contains(mount(night, in: pouch)))
    }
}
