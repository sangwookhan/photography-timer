// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// A Shooting Filters session across inventory edits made from a Set
/// editor opened in it (FILTER-FLOW-003, FILTER-ITEM-006/009,
/// FILTER-PERSIST-002): working-only picks that no longer resolve are
/// dropped without a replacement, a committed change is followed item by
/// item, a moved item stays picked only under a Set the session selects,
/// and every unrelated draft pick, unmount, and choice stays.
@MainActor
final class ShootingFiltersSessionReconciliationTests: XCTestCase {
    private let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
    private let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
    private let night = FilterItem(name: "Night", behavior: .effect(FilterExposureLoss(stops: 1)))

    /// Kit holds the CPL and the Red; Pouch holds Night. The camera
    /// selects Kit, and Pouch too when `pouchSelected`, and mounts
    /// `committed`.
    private func fixture(
        pouchSelected: Bool = false,
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
        XCTAssertNil(viewModel.applyShootingFilters(
            selectedFilterSetIDs: pouchSelected ? [kit.id, pouch.id] : [kit.id],
            mounts: committed(kit)
        ))
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
    /// not order the two `onChange` handlers, so both orders must agree,
    /// and `follow`, which the popup calls from each handler, must agree
    /// with them.
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
                inventory: viewModel.filterInventory
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
        // What the screen calls: once per handler that fires.
        var followed = session
        for _ in 0..<(committedChanged ? 1 : 0) + (inventoryChanged ? 1 : 0) {
            followed.follow(
                committedFilterSetIDs: viewModel.candidateFilterSetIDs,
                committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount),
                inventory: viewModel.filterInventory
            )
        }
        XCTAssertEqual(followed, rebasedFirst, "follow gives the same result, however many handlers fire.")
        session = rebasedFirst
    }

    private func apply(_ session: ShootingFiltersSession, _ viewModel: ExposureCalculatorViewModel) -> FilterStackRejection? {
        viewModel.applyShootingFilters(selectedFilterSetIDs: session.selectedFilterSetIDs, mounts: session.mounts)
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

    // MARK: Moves (FILTER-ITEM-009)

    func testAWorkingOnlyPickMovedToAnAvailableSetIsClearedForGood() throws {
        let (viewModel, kit, pouch) = try fixture()
        var working = session(viewModel)
        working.setMount(mount(red, in: kit), for: red.id)
        working.setMount(mount(cpl, in: kit, .cplLoss(1.5)), for: cpl.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(red, in: pouch.id), .saved) }

        XCTAssertNil(working.mount(of: red.id), "Moved to an unselected Set: unchecked.")
        XCTAssertEqual(working.selectedFilterSetIDs, [kit.id], "The destination is not selected.")
        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: kit, .cplLoss(1.5)), "Unrelated picks stay.")
        XCTAssertTrue(canApply(working, viewModel), "No stale reference blocks Apply.")
        working.setSelected(pouch.id, true)
        XCTAssertNil(working.mount(of: red.id), "Selecting the destination later does not bring it back.")
    }

    func testAWorkingOnlyPickMovedToASelectedSetKeepsItsChoiceThere() throws {
        let (viewModel, kit, pouch) = try fixture()
        var working = session(viewModel)
        working.setSelected(pouch.id, true)
        working.setMount(mount(cpl, in: kit, .cplLoss(2)), for: cpl.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: pouch, .cplLoss(2)), "Selected only in the session: it follows.")
        XCTAssertTrue(canApply(working, viewModel))
    }

    // MARK: Committed changes

    /// A kind correction of a committed CPL to a Color filter: the camera
    /// remounts it with the Color filter's choice, and the session follows
    /// whichever of its two triggers runs first.
    func testACommittedKindChangeIsFollowedInEitherOrder() throws {
        let (viewModel, kit, _) = try fixture { kit in [self.mount(self.cpl, in: kit, .cplLoss(1.5))] }
        var working = session(viewModel)

        let asColor = FilterItem(id: cpl.id, name: cpl.name, behavior: .color(FilterExposureLoss(stops: 1), .yellow))
        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(asColor, in: kit.id), .saved) }

        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [mount(asColor, in: kit)])
        XCTAssertEqual(working.mount(of: cpl.id), mount(asColor, in: kit), "The session keeps the remounted filter.")
        XCTAssertFalse(working.hasChanges, "Apply would change nothing.")
    }

    func testACommittedPickWhoseItemIsDeletedLeavesInEitherOrder() throws {
        let (viewModel, kit, _) = try fixture { kit in [self.mount(self.cpl, in: kit, .cplLoss(1.5)), self.mount(self.red, in: kit)] }
        var working = session(viewModel)

        edit(&working, viewModel) { viewModel.deleteFilterItem(id: cpl.id) }

        XCTAssertEqual(working.mounts, [mount(red, in: kit)])
        XCTAssertFalse(working.hasChanges)
    }

    func testACommittedPickMovedToAnAvailableSetIsUncheckedOnTheCameraAndInTheSession() throws {
        let (viewModel, kit, pouch) = try fixture { kit in
            [self.mount(self.cpl, in: kit, .cplLoss(1.5)), self.mount(self.red, in: kit)]
        }
        var working = session(viewModel)
        working.setMount(nil, for: red.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [mount(red, in: kit)], "The camera unmounts it.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [kit.id], "The camera does not select the destination.")
        XCTAssertNil(working.mount(of: cpl.id))
        XCTAssertNil(working.mount(of: red.id), "The draft unmount stays.")
        XCTAssertEqual(working.selectedFilterSetIDs, [kit.id])
        working.setSelected(pouch.id, true)
        XCTAssertNil(working.mount(of: cpl.id), "Selecting the destination later does not bring it back.")

        // Cancel: the move and the camera's unmount stay.
        XCTAssertEqual(viewModel.filterSet(withID: pouch.id)?.item(withID: cpl.id), cpl)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [mount(red, in: kit)])
    }

    func testACommittedPickMovedToASetOnlyTheSessionSelectsStaysPickedThere() throws {
        let (viewModel, kit, pouch) = try fixture { kit in [self.mount(self.cpl, in: kit, .cplLoss(1.5))] }
        var working = session(viewModel)
        working.setSelected(pouch.id, true)
        working.setMount(mount(night, in: pouch), for: night.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty, "The camera does not select Pouch, so it unmounts the CPL.")
        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: pouch, .cplLoss(1.5)), "The session selects Pouch, so the CPL stays picked.")
        XCTAssertEqual(working.mount(of: night.id), mount(night, in: pouch), "The draft pick stays.")
        XCTAssertNil(apply(working, viewModel))
        XCTAssertEqual(Set(viewModel.mountedAuxiliaryFilters.map(\.mount)), [mount(cpl, in: pouch, .cplLoss(1.5)), mount(night, in: pouch)])
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [kit.id, pouch.id])
    }

    func testACommittedMoveBetweenSelectedSetsKeepsUnrelatedDraftPicksAndUnmounts() throws {
        let (viewModel, kit, pouch) = try fixture(pouchSelected: true) { kit in
            [self.mount(self.cpl, in: kit, .cplLoss(1.5)), self.mount(self.red, in: kit)]
        }
        var working = session(viewModel)
        working.setMount(nil, for: red.id)
        working.setMount(mount(night, in: pouch), for: night.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: pouch, .cplLoss(1.5)), "The committed move is followed.")
        XCTAssertNil(working.mount(of: red.id), "The draft unmount stays.")
        XCTAssertEqual(working.mount(of: night.id), mount(night, in: pouch), "The draft pick stays.")
        XCTAssertTrue(canApply(working, viewModel))
        XCTAssertEqual(Set(viewModel.mountedAuxiliaryFilters.map(\.mount)), [mount(cpl, in: pouch, .cplLoss(1.5)), mount(red, in: kit)])
    }

    func testACommittedMoveBetweenSelectedSetsKeepsTheDraftChoice() throws {
        let (viewModel, kit, pouch) = try fixture(pouchSelected: true) { kit in [self.mount(self.cpl, in: kit, .cplLoss(1.5))] }
        var working = session(viewModel)
        working.setMount(mount(cpl, in: kit, .cplLoss(2)), for: cpl.id)

        edit(&working, viewModel) { XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved) }

        XCTAssertEqual(working.mount(of: cpl.id), mount(cpl, in: pouch, .cplLoss(2)))
    }

    func testACommittedChangeKeepsThePicksOfASetRemovedInTheSession() throws {
        let (viewModel, kit, pouch) = try fixture { kit in [self.mount(self.red, in: kit)] }
        let bag = try XCTUnwrap(viewModel.createFilterSet(name: "Bag", color: .blue))
        viewModel.arrangeFilterSets([kit.id, bag.id])
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

    /// Each camera judges a move against its own selected Sets.
    func testEveryCameraJudgesAMoveAgainstItsOwnSelectedSets() throws {
        let (viewModel, kit, pouch) = try fixture(pouchSelected: true) { kit in [self.mount(self.cpl, in: kit, .cplLoss(1.5))] }
        viewModel.selectCameraSlot(.camera2)
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [kit.id], mounts: [mount(cpl, in: kit, .cplLoss(2))]))
        viewModel.selectCameraSlot(.camera1)

        XCTAssertEqual(viewModel.saveFilterItem(cpl, in: pouch.id), .saved)

        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [mount(cpl, in: pouch, .cplLoss(1.5))], "Camera 1 selects Pouch.")
        viewModel.selectCameraSlot(.camera2)
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty, "Camera 2 does not.")
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [kit.id])
    }
}
