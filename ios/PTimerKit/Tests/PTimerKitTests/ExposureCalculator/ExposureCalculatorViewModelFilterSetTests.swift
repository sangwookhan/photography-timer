// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Facade behavior for the Filter Set contract: per-camera source
/// memory (FILTER-PLUS-003/004, example 3), inventory edits following
/// into every camera stack (FILTER-ITEM-005/006), Plus availability
/// (FILTER-PLUS-005), rejection notices (FILTER-STACK-004), cleanup
/// exclusions (FILTER-STACK-006), GND mode isolation (FILTER-GND-002,
/// example 4), and the immutable timer summary (FILTER-PERSIST-003,
/// example 7).
@MainActor
final class ExposureCalculatorFilterSetTests: XCTestCase {
    private struct OrderingScenario {
        let viewModel: ExposureCalculatorViewModel
        let nd3: FilterItem
        let nd6: FilterItem
        let nd10: FilterItem
    }

    private func select(_ item: FilterItem, _ choice: FilterRowChoice = .fixed) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: item.id, choice: choice))
    }

    private func fixed(_ name: String, _ stops: Double) -> FilterItem {
        FilterItem(name: name, behavior: .fixed(FilterRegisteredValue(value: stops, unit: .stops)))
    }

    // MARK: Example 3 — source selection, adding Empty, per-camera memory

    func testPlusSourceIsRememberedPerCameraAndFreshCamerasUseStandard() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let item = fixed("Big Stopper", 10)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)

        viewModel.selectFilterSource(.filterSet(set.id))
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(set.id))
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))], "Changing the source never mutates the stack.")

        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0)), .empty(in: set.id)])
        XCTAssertEqual(viewModel.ndStep.stops, 0, "Adding an Empty wheel leaves the calculation unchanged.")

        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 10, accuracy: 1e-9)

        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(set.id))
        // FILTER-STACK-005: the set's subtotal (10) leads Standard 0.
        XCTAssertEqual(viewModel.filterWheels, [
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
            .standard(NDStep(stops: 0)),
        ])
    }

    // MARK: FILTER-PLUS-003 / FR-1.13 — one direct add per gesture

    func testAddingFromABrowsedSourceAddsExactlyOnceAndRemembersItOnlyThen() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        inventory.addItem(fixed("Big Stopper", 10), to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)

        // A tap adds the displayed (remembered) source once.
        viewModel.addFilterWheel(from: .standard)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0)), .standard(NDStep(stops: 0))])
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)

        // A browse that settled on the Filter Set adds exactly one
        // wheel from it and only then moves the camera's memory.
        viewModel.addFilterWheel(from: .filterSet(set.id))
        XCTAssertEqual(viewModel.filterWheels.count, 3)
        XCTAssertEqual(viewModel.filterWheels.last, .empty(in: set.id))
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(set.id), "Memory follows a successful add.")
        XCTAssertNil(viewModel.filterRejectionNotice)
        XCTAssertEqual(viewModel.ndStep.stops, 0, "An Empty wheel leaves the total unchanged.")

        viewModel.selectCameraSlot(.camera2)
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(set.id), "The last successful addition is what the camera remembers.")
    }

    func testARefusedAddCreatesNoWheelKeepsTheTotalAndMemoryAndReportsTheReason() throws {
        let inventory = FilterInventoryModel()
        let lee = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        inventory.addItem(fixed("Big Stopper", 10), to: lee.id)
        let empty = try XCTUnwrap(inventory.createFilterSet(name: "Empty set", color: .blue))
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 4), at: 0)
        let wheelsBefore = viewModel.filterWheels
        let totalBefore = viewModel.ndStep.stops

        // Browsing settled on a set without items: refused with its reason.
        viewModel.addFilterWheel(from: .filterSet(empty.id))
        XCTAssertEqual(viewModel.filterWheels, wheelsBefore, "No wheel is created.")
        XCTAssertEqual(viewModel.ndStep.stops, totalBefore, accuracy: 1e-9, "The total is unchanged.")
        XCTAssertEqual(viewModel.selectedFilterSource, .standard, "A refused add does not touch the remembered source.")
        XCTAssertEqual(viewModel.filterRejectionNotice?.addUnavailability, .filterSetHasNoItems)
        XCTAssertNil(viewModel.filterRejectionNotice?.rejection)
        XCTAssertEqual(viewModel.filterRejectionNotice?.text, FilterWheelPresenter.addUnavailabilityText(for: .filterSetHasNoItems))

        // Mount every Lee item, then a browse onto Lee is refused too.
        viewModel.addFilterWheel(from: .filterSet(lee.id))
        let item = try XCTUnwrap(inventory.filterSet(withID: lee.id)?.items.first)
        viewModel.setWheelSelection(select(item), at: 1)
        let mounted = viewModel.filterWheels
        viewModel.addFilterWheel(from: .filterSet(lee.id))
        XCTAssertEqual(viewModel.filterWheels, mounted)
        XCTAssertEqual(viewModel.filterRejectionNotice?.addUnavailability, .allItemsMounted)

        // Unknown source: nothing at all.
        viewModel.addFilterWheel(from: .filterSet(FilterSetID.generate()))
        XCTAssertEqual(viewModel.filterWheels, mounted)
    }

    func testAFullStackRefusesATapWithTheReasonAndNoDuplicate() throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        for _ in 0..<3 {
            viewModel.addFilterWheel(from: .standard)
        }
        XCTAssertEqual(viewModel.filterWheels.count, 4)
        viewModel.addFilterWheel(from: .standard)
        XCTAssertEqual(viewModel.filterWheels.count, 4, "Exactly four wheels, never a fifth.")
        XCTAssertEqual(viewModel.filterRejectionNotice?.addUnavailability, .stackFull)
    }

    func testUnknownSourceIsRefused() throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        viewModel.selectFilterSource(.filterSet(FilterSetID.generate()))
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
    }

    // MARK: FILTER-PLUS-005 — Plus stays visible, adding disabled with a reason

    func testPlusRemainsVisibleAtCapAndRecordOnlyStaysAddable() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        let gnd = FilterItem(name: "GND 0.6", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 30), at: 0)

        XCTAssertTrue(viewModel.showsAddFilterWheelControl)
        XCTAssertFalse(viewModel.isNDWheelInteractionQuiet && viewModel.filterAddUnavailability == nil)
        XCTAssertEqual(viewModel.filterAddUnavailability, .noSelectableValue)
        XCTAssertNotNil(viewModel.filterAddUnavailabilityText(for: .standard))

        viewModel.selectFilterSource(.filterSet(set.id))
        XCTAssertNil(viewModel.filterAddUnavailability, "A Record-only row keeps the set addable at the cap.")
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.filterWheels.count, 2)
        // The Empty wheel is usable (Record only fits), so the A0
        // saturation rule must not remove it before the selection.
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 30, accuracy: 1e-9)
        XCTAssertEqual(viewModel.filterWheels.count, 2)

        // Example 6: enabling the contribution is rejected, state intact.
        let before = viewModel.filterWheels
        viewModel.setWheelSelection(select(gnd, .gnd(.applyFullValue)), at: 1)
        XCTAssertEqual(viewModel.filterWheels, before)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .exceedsTotalLimit)
    }

    // MARK: FILTER-STACK-006 — cleanup never removes a mounted Record-only item

    func testCleanupRemovesEmptyButKeepsRecordOnly() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.setNDFilterStep(NDStep(stops: 5), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        // [5, gnd(rec), empty]
        XCTAssertEqual(viewModel.filterWheels.count, 3)
        await awaitCleanupFire()
        XCTAssertEqual(viewModel.filterWheels, [
            .standard(NDStep(stops: 5)),
            FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly))),
        ])
        XCTAssertFalse(viewModel.calculatorModel.canRemoveEmptyFilterWheel)
    }

    // MARK: FILTER-SET-001 — deletion stays bound to the targeted set's id

    /// Device report (unverified): deleting one set appeared to remove
    /// another. The facade deletes by the stable id the row captured;
    /// this pins that rule in both directions, with the other set's
    /// items, id, and mounted wheels untouched and the confirmation's
    /// camera list naming only the targeted set's cameras.
    func testDeletingOneFilterSetLeavesTheOtherUntouchedInBothDirections() throws {
        for deleteFirst in [true, false] {
            let inventory = FilterInventoryModel()
            let setA = try XCTUnwrap(inventory.createFilterSet(name: "A kit", color: .red))
            let setB = try XCTUnwrap(inventory.createFilterSet(name: "B holder", color: .blue))
            let itemA = fixed("ND A", 3)
            let itemB = fixed("ND B", 6)
            inventory.addItem(itemA, to: setA.id)
            inventory.addItem(itemB, to: setB.id)
            let viewModel = makeViewModel(inventoryModel: inventory)
            // Camera 1 mounts B; camera 2 mounts A.
            viewModel.selectFilterSource(.filterSet(setB.id))
            viewModel.addFilterWheel()
            viewModel.setWheelSelection(select(itemB), at: 1)
            viewModel.selectCameraSlot(.camera2)
            viewModel.selectFilterSource(.filterSet(setA.id))
            viewModel.addFilterWheel()
            viewModel.setWheelSelection(select(itemA), at: 1)

            let target = deleteFirst ? setA : setB
            let other = deleteFirst ? setB : setA
            let otherBefore = try XCTUnwrap(viewModel.filterSet(withID: other.id))
            XCTAssertEqual(
                viewModel.cameraNames(affectedByDeletingFilterSet: target.id),
                [deleteFirst ? "Camera 2" : "Camera 1"],
                "The confirmation names only the cameras mounting the targeted set."
            )

            viewModel.deleteFilterSet(id: target.id)

            XCTAssertNil(viewModel.filterSet(withID: target.id), "\(target.name) is gone.")
            XCTAssertEqual(viewModel.filterSet(withID: other.id), otherBefore, "\(other.name) keeps its id, name, color, and items.")
            XCTAssertEqual(viewModel.filterInventory.filterSets.map(\.id), [other.id])
            // The other set's wheel is still mounted on its camera (the
            // settled order puts the set group first); the deleted set's
            // camera fell back to Standard.
            let survivingCamera: CameraSlotID = deleteFirst ? .camera1 : .camera2
            let emptiedCamera: CameraSlotID = deleteFirst ? .camera2 : .camera1
            viewModel.selectCameraSlot(survivingCamera)
            XCTAssertEqual(Set(viewModel.filterWheels.map(\.source)), [.standard, .filterSet(other.id)])
            XCTAssertEqual(viewModel.filterWheels.count, 2)
            viewModel.selectCameraSlot(emptiedCamera)
            XCTAssertEqual(viewModel.filterWheels.map(\.source), [.standard])
        }
    }

    // MARK: Example 4 — GND mode switch affects only that wheel and camera

    func testGNDModeSwitchDoesNotTouchAnotherCamera() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 0)
        // The GND's registered 2 stops lead Standard 0 after the commit.
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(gnd, .gnd(.recordOnly)))

        viewModel.setWheelSelection(select(gnd, .gnd(.applyFullValue)), at: 0)
        XCTAssertEqual(viewModel.ndStep.stops, 2)
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(gnd, .gnd(.applyFullValue)), "A mode switch never moves the GND.")

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.ndStep.stops, 0, "Camera 1 keeps Record only.")
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(gnd, .gnd(.recordOnly)))
    }

    // MARK: FILTER-ITEM-005/006 — edits follow into every camera

    func testDeletingAnItemEmptiesItsWheelsOnEveryCamera() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 4)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)

        XCTAssertEqual(Set(viewModel.cameraNames(affectedByDeletingItem: item.id)), ["Camera 1", "Camera 2"])
        viewModel.deleteFilterItem(id: item.id)

        // The wheel empties in place; the settled order is untouched
        // until the next commit.
        XCTAssertEqual(viewModel.filterWheels, [.empty(in: set.id), .standard(NDStep(stops: 0))])
        XCTAssertEqual(viewModel.ndStep.stops, 0)
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.filterWheels, [.empty(in: set.id), .standard(NDStep(stops: 0))])
    }

    func testDeletingAFilterSetRemovesItsWheelsAndFallsBackToStandard() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 4)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        // Drop the Standard 0 wheel so only the set wheel remains.
        await awaitCleanupFire()
        XCTAssertEqual(viewModel.filterWheels.count, 1)

        XCTAssertEqual(viewModel.cameraNames(affectedByDeletingFilterSet: set.id), ["Camera 1"])
        viewModel.deleteFilterSet(id: set.id)

        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
        XCTAssertTrue(viewModel.filterSources == [.standard])
    }

    func testEditingAnItemUpdatesEveryStackAndIsBlockedWhenACameraWouldExceedTheCap() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 4)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 20), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 24, accuracy: 1e-9)

        var edited = item
        edited.behavior = .fixed(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)) // 3 stops
        XCTAssertEqual(viewModel.saveFilterItem(edited, in: set.id), .saved)
        XCTAssertEqual(viewModel.ndStep.stops, 23, accuracy: 1e-9)

        var tooBig = item
        tooBig.behavior = .fixed(FilterRegisteredValue(value: 11, unit: .stops))
        XCTAssertEqual(viewModel.saveFilterItem(tooBig, in: set.id), .blocked(affectedCameras: ["Camera 1"], reason: .exceedsTotalLimit))
        XCTAssertEqual(viewModel.ndStep.stops, 23, accuracy: 1e-9, "A blocked save changes nothing.")
        XCTAssertEqual(viewModel.filterInventory.item(withID: item.id)?.item, edited)
    }

    // MARK: FILTER-ITEM-005 — removing an active CPL choice is blocked

    func testRemovingASelectedCPLChoiceIsBlockedAndNamesEveryAffectedCamera() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        inventory.addItem(cpl, to: set.id)
        let sessionStore = InMemoryMixedSessionStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventory
        )
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(cpl, .cplLoss(1.5)), at: 1)
        let cameraOneWheels = viewModel.filterWheels
        let persistedBefore = sessionStore.stored
        let inventoryBefore = viewModel.filterInventory

        // One camera affected.
        var withoutOnePointFive = cpl
        withoutOnePointFive.behavior = .cpl(CPLExposureLossChoices(fields: [1, nil, 2]))
        XCTAssertEqual(viewModel.filterItemSaveConflicts(for: withoutOnePointFive, in: set.id), ["Camera 1"])
        XCTAssertEqual(viewModel.saveFilterItem(withoutOnePointFive, in: set.id), .blocked(affectedCameras: ["Camera 1"], reason: .removesSelectedChoice))
        XCTAssertEqual(viewModel.filterWheels, cameraOneWheels, "The previous valid stack stays intact.")
        XCTAssertEqual(viewModel.filterInventory, inventoryBefore, "The previous inventory stays intact.")
        XCTAssertEqual(sessionStore.stored, persistedBefore, "A blocked save persists nothing.")
        XCTAssertEqual(viewModel.ndStep.stops, 1.5, accuracy: 1e-9)

        // Two cameras affected: camera 2 mounts the same CPL at 2.
        viewModel.selectCameraSlot(.camera2)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(cpl, .cplLoss(2)), at: 1)
        var onlyOne = cpl
        onlyOne.behavior = .cpl(CPLExposureLossChoices(fields: [1, nil, nil]))
        XCTAssertEqual(Set(viewModel.filterItemSaveConflicts(for: onlyOne, in: set.id)), ["Camera 1", "Camera 2"])
        XCTAssertEqual(viewModel.saveFilterItem(onlyOne, in: set.id), .blocked(affectedCameras: ["Camera 1", "Camera 2"], reason: .removesSelectedChoice))
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(cpl, .cplLoss(2)), "The CPL group (2) leads Standard 0.")

        // Keeping every selected choice (adding a fourth value is not
        // possible, but changing the unselected slot is) saves.
        var keepsSelected = cpl
        keepsSelected.behavior = .cpl(CPLExposureLossChoices(fields: [0.5, 1.5, 2]))
        XCTAssertEqual(viewModel.saveFilterItem(keepsSelected, in: set.id), .saved)
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(cpl, .cplLoss(2)))
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(cpl, .cplLoss(1.5)))

        // After the camera changes its wheel, the removal is allowed.
        viewModel.setWheelSelection(select(cpl, .cplLoss(2)), at: 0)
        viewModel.selectCameraSlot(.camera2)
        viewModel.setWheelSelection(.empty, at: 0)
        var withoutOnePointFiveAgain = cpl
        withoutOnePointFiveAgain.behavior = .cpl(CPLExposureLossChoices(fields: [0.5, nil, 2]))
        XCTAssertEqual(viewModel.saveFilterItem(withoutOnePointFiveAgain, in: set.id), .saved)
    }

    func testChangingAMountedItemsKindIsBlockedLikeARemovedRow() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 3)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        var asGND = item
        asGND.behavior = .gnd(FilterRegisteredValue(value: 3, unit: .stops))
        XCTAssertEqual(viewModel.saveFilterItem(asGND, in: set.id), .blocked(affectedCameras: ["Camera 1"], reason: .removesSelectedChoice))
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(item))
    }

    // MARK: FILTER-STACK-002 — rejection notice for a mounted item

    func testSelectingAnItemMountedElsewhereIsRejectedWithANotice() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 4)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        let before = viewModel.filterWheels
        // Settled order: the set group (item, Empty) leads Standard 0.
        XCTAssertEqual(before.map(\.selection), [select(item), .empty, .standard(NDStep(stops: 0))])
        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.filterWheels, before)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)
        let rows = viewModel.filterWheelRowOptions(forWheel: 1)
        XCTAssertEqual(rows.first { $0.selection == select(item) }?.unavailability, .itemAlreadyMounted)
    }

    // MARK: FILTER-A11Y-004 — skip unavailable rows during adjustment

    func testVoiceOverAdjustmentSkipsMountedND10AndCommitsND6() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let nd3 = fixed("ND 3", 3)
        let nd6 = fixed("ND 6", 6)
        let nd10 = fixed("ND 10", 10)
        let cpl = FilterItem(
            name: "CPL",
            behavior: .cpl(CPLExposureLossChoices(fields: [1, nil, nil]))
        )
        for item in [nd3, nd6, nd10, cpl] {
            inventory.addItem(item, to: set.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd10), at: 1)
        let emptyIndex = try XCTUnwrap(
            viewModel.filterWheels.firstIndex(where: { $0.source == .filterSet(set.id) && $0.selection == .empty })
        )
        viewModel.setWheelSelection(select(cpl, .cplLoss(1)), at: emptyIndex)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let cplIndex = try XCTUnwrap(
            viewModel.filterWheels.firstIndex(where: { $0.selection == select(cpl, .cplLoss(1)) })
        )
        let options = viewModel.filterWheelRowOptions(forWheel: cplIndex)
        XCTAssertEqual(
            options.first { $0.selection == select(nd10) }?.unavailability,
            .itemAlreadyMounted
        )
        let outcome = FilterWheelAccessibilityAdjustment.outcome(
            from: select(cpl, .cplLoss(1)),
            direction: .decrement,
            options: options
        )
        guard case .selection(let nextSelection) = outcome else {
            return XCTFail("Expected an available row before the boundary")
        }
        XCTAssertEqual(nextSelection, select(nd6))

        let wheelID = viewModel.ndFilterWheelIDs[cplIndex]
        viewModel.filterWheelDidSelect(
            nextSelection,
            wheelID: wheelID,
            generation: viewModel.ndWheelGeneration
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd6) })
        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd10) })
        XCTAssertEqual(viewModel.ndStep.stops, 16, accuracy: 1e-9)
        XCTAssertNil(viewModel.filterRejectionNotice)
    }

    func testVoiceOverAdjustmentFromND10SkipsMountedND6AndCommitsND3() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let nd3 = fixed("ND 3", 3)
        let nd6 = fixed("ND 6", 6)
        let nd10 = fixed("ND 10", 10)
        for item in [nd3, nd6, nd10] {
            inventory.addItem(item, to: set.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd6), at: 1)
        let emptyIndex = try XCTUnwrap(
            viewModel.filterWheels.firstIndex(where: { $0.source == .filterSet(set.id) && $0.selection == .empty })
        )
        viewModel.setWheelSelection(select(nd10), at: emptyIndex)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let nd10Index = try XCTUnwrap(
            viewModel.filterWheels.firstIndex(where: { $0.selection == select(nd10) })
        )
        let options = viewModel.filterWheelRowOptions(forWheel: nd10Index)
        XCTAssertEqual(
            options.first { $0.selection == select(nd6) }?.unavailability,
            .itemAlreadyMounted
        )
        let outcome = FilterWheelAccessibilityAdjustment.outcome(
            from: select(nd10),
            direction: .decrement,
            options: options
        )
        guard case .selection(let nextSelection) = outcome else {
            return XCTFail("Expected ND 3 before the boundary")
        }
        XCTAssertEqual(nextSelection, select(nd3))

        let wheelID = viewModel.ndFilterWheelIDs[nd10Index]
        viewModel.filterWheelDidSelect(
            nextSelection,
            wheelID: wheelID,
            generation: viewModel.ndWheelGeneration
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd3) })
        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd6) })
        XCTAssertFalse(viewModel.filterWheels.contains { $0.selection == select(nd10) })
        XCTAssertEqual(viewModel.ndStep.stops, 9, accuracy: 1e-9)
        XCTAssertNil(viewModel.filterRejectionNotice)
    }

    // MARK: FILTER-A11Y-006 — stable screen-reader ordering

    func testScreenReaderSuspensionKeepsAdjustedWheelAndIdentityThenReconcilesOnce() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let secondWheelID = viewModel.ndFilterWheelIDs[1]
        viewModel.filterWheelDidSelect(
            select(scenario.nd10),
            wheelID: secondWheelID,
            generation: viewModel.ndWheelGeneration
        )

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd10)])
        XCTAssertEqual(viewModel.ndFilterWheelIDs[1], secondWheelID, "The focused logical wheel stays in position 2.")
        XCTAssertEqual(viewModel.ndStep.stops, 16, accuracy: 1e-9)

        let generationBeforeResume = viewModel.ndWheelGeneration
        viewModel.setFilterStackOrderingSuspended(false)
        viewModel.setFilterStackOrderingSuspended(false)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd10), select(scenario.nd6)])
        XCTAssertEqual(viewModel.ndFilterWheelIDs[0], secondWheelID, "Identity follows ND 10 through the one reconciliation.")
        XCTAssertEqual(viewModel.ndStep.stops, 16, accuracy: 1e-9)
        XCTAssertEqual(viewModel.ndWheelGeneration, generationBeforeResume + 1, "Repeated inactive notifications do not reorder twice.")
    }

    func testResumeWaitsForTouchAndPendingCommitBeforeReordering() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let firstWheelID = viewModel.ndFilterWheelIDs[0]
        let secondWheelID = viewModel.ndFilterWheelIDs[1]
        let generation = viewModel.ndWheelGeneration
        viewModel.ndWheelTouchBegan(wheelID: firstWheelID, generation: generation)
        viewModel.filterWheelDidSelect(
            select(scenario.nd10),
            wheelID: secondWheelID,
            generation: generation
        )
        viewModel.setFilterStackOrderingSuspended(false)

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd3)])
        XCTAssertEqual(viewModel.displayWheelSelections[1], select(scenario.nd10), "The pending value remains visible at the barrier.")

        viewModel.ndWheelTouchEnded(wheelID: firstWheelID)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd10), select(scenario.nd6)])
        XCTAssertEqual(viewModel.ndFilterWheelIDs[0], secondWheelID)
        XCTAssertEqual(viewModel.ndStep.stops, 16, accuracy: 1e-9)
    }

    func testTouchCommitAndMembershipChangesPreserveOrderWhileSuspended() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let secondWheelID = viewModel.ndFilterWheelIDs[1]
        let generation = viewModel.ndWheelGeneration
        viewModel.ndWheelTouchBegan(wheelID: secondWheelID, generation: generation)
        viewModel.filterWheelDidSelect(
            select(scenario.nd10),
            wheelID: secondWheelID,
            generation: generation
        )
        viewModel.ndWheelTouchEnded(wheelID: secondWheelID)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd10)])
        XCTAssertEqual(viewModel.ndFilterWheelIDs[1], secondWheelID)

        let preservedIDs = viewModel.ndFilterWheelIDs
        viewModel.addFilterWheel(from: .standard)
        XCTAssertEqual(Array(viewModel.ndFilterWheelIDs.prefix(2)), preservedIDs)
        XCTAssertEqual(viewModel.filterWheels.last, .standard(NDStep(stops: 0)))
        await awaitCleanupFire()
        XCTAssertEqual(viewModel.ndFilterWheelIDs, preservedIDs)
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd10)])
    }

    func testReenablingSuspensionCancelsQueuedReconciliation() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.setWheelSelection(select(scenario.nd10), at: 1)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let firstWheelID = viewModel.ndFilterWheelIDs[0]
        let frozenOrder = viewModel.ndFilterWheelIDs
        let generation = viewModel.ndWheelGeneration
        viewModel.ndWheelTouchBegan(wheelID: firstWheelID, generation: generation)
        viewModel.setFilterStackOrderingSuspended(false)
        viewModel.setFilterStackOrderingSuspended(true)
        viewModel.ndWheelTouchEnded(wheelID: firstWheelID)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isFilterStackOrderingSuspended)
        XCTAssertEqual(viewModel.ndFilterWheelIDs, frozenOrder)
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd10)])
        XCTAssertEqual(viewModel.ndWheelGeneration, generation, "The canceled resume never starts a reorder window.")
    }

    func testLaunchWithScreenReaderSuspensionRestoresPersistedOrder() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let nd3 = fixed("ND 3", 3)
        let nd10 = fixed("ND 10", 10)
        inventory.addItem(nd3, to: set.id)
        inventory.addItem(nd10, to: set.id)
        let sessionStore = InMemoryMixedSessionStore()
        sessionStore.stored = PersistentCameraSlotSessionSnapshot(
            schemaVersion: 1,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: CameraSlotID.camera1.rawValue,
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 13,
                    ndStack: [],
                    filterStack: [
                        PersistentFilterWheelSnapshot(
                            sourceKind: "filterSet",
                            filterSetID: set.id.rawValue,
                            itemID: nd3.id.rawValue,
                            rowKind: "fixed"
                        ),
                        PersistentFilterWheelSnapshot(
                            sourceKind: "filterSet",
                            filterSetID: set.id.rawValue,
                            itemID: nd10.id.rawValue,
                            rowKind: "fixed"
                        ),
                    ]
                ),
            ]
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventory,
            isFilterStackOrderingSuspended: true
        )

        XCTAssertTrue(viewModel.isFilterStackOrderingSuspended)
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(nd3), select(nd10)])
        XCTAssertEqual(viewModel.ndStep.stops, 13, accuracy: 1e-9)
    }

    // MARK: Example 7 / FILTER-PERSIST-003 — immutable timer summary

    func testTimerCapturesFilterSummaryThatLaterRenamesDoNotRewrite() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let item = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 3.0, unit: .opticalDensity)))
        inventory.addItem(item, to: set.id)
        let timerManager = RuntimeBackedTimerManaging(tickInterval: 60, dateProvider: { Date(timeIntervalSince1970: 100) })
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            filterInventoryModel: inventory
        )
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        let summary = try XCTUnwrap(timer.filterSummary)
        XCTAssertEqual(summary.count, 2)
        // Settled order: Lee (10) leads Standard (2).
        XCTAssertEqual(summary[0].filterSetName, "Lee")
        XCTAssertEqual(summary[0].itemName, "Big Stopper")
        XCTAssertEqual(summary[0].originalUnit, .opticalDensity)
        XCTAssertEqual(try XCTUnwrap(summary[0].canonicalStops), 10, accuracy: 1e-9)
        XCTAssertEqual(summary[0].contributedStops, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(timer.ndStops), 12, accuracy: 1e-9)

        viewModel.renameFilterSet(id: set.id, name: "Renamed")
        var renamed = item
        renamed.name = "Renamed item"
        XCTAssertEqual(viewModel.saveFilterItem(renamed, in: set.id), .saved)
        XCTAssertEqual(viewModel.timers.first?.filterSummary, summary, "Captured summaries never change.")
        XCTAssertEqual(viewModel.filterRows[0].item?.name, "Renamed item", "The live stack follows the rename.")
    }

    func testTimerReferenceTextIsCapturedAtStartAndSurvivesInventoryChanges() throws {
        let inventory = FilterInventoryModel()
        let haida = try XCTUnwrap(inventory.createFilterSet(name: "Haida 100mm", color: .red))
        let nd400 = FilterItem(name: "ND400", behavior: .fixed(FilterRegisteredValue(value: 400, unit: .filterFactor)))
        let gnd = FilterItem(name: "GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(nd400, to: haida.id)
        inventory.addItem(gnd, to: haida.id)
        let timerManager = RuntimeBackedTimerManaging(tickInterval: 60, dateProvider: { Date(timeIntervalSince1970: 100) })
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            filterInventoryModel: inventory
        )
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)
        viewModel.selectFilterSource(.filterSet(haida.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd400, .fixed), at: 1)
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 2)
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        // Settled order: Haida (log2(400) + registered 2) leads Standard 2.
        let expected = "Haida 100mm: ND400 ND400 + GND 2 2 stops (Record only) · Standard 2 stops"
        XCTAssertEqual(timer.filterReferenceText, expected)
        XCTAssertEqual(try XCTUnwrap(timer.ndStops), 2 + log2(400), accuracy: 1e-9, "The primary value is the canonical total.")
        XCTAssertEqual(timer.filterSummary?[1].contributedStops, 0, "Record only contributes 0 yet appears in the reference.")

        // Rename, edit, reorder, delete — the captured record never moves.
        viewModel.renameFilterSet(id: haida.id, name: "Renamed")
        var edited = nd400
        edited.name = "Edited"
        XCTAssertEqual(viewModel.saveFilterItem(edited, in: haida.id), .saved)
        viewModel.moveFilterItems(in: haida.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        viewModel.deleteFilterSet(id: haida.id)
        XCTAssertEqual(viewModel.timers.first?.filterReferenceText, expected)
        XCTAssertEqual(viewModel.timers.first?.filterSummary, timer.filterSummary)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2))], "The live stack lost the deleted set's wheels.")
    }

    func testStalePersistedCPLChoiceRestoresAsEmpty() throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, nil, 2])))
        inventory.addItem(cpl, to: set.id)
        sessionStore.stored = PersistentCameraSlotSessionSnapshot(
            schemaVersion: 1,
            activeSlotIDRaw: CameraSlotID.camera1.rawValue,
            slots: [
                PersistentCameraSlotCalculatorSnapshot(
                    slotIDRaw: CameraSlotID.camera1.rawValue,
                    selectedPresetFilmID: nil,
                    selectedProfileID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 3,
                    ndStack: [PersistentNDFilterWheelSnapshot(ndStop: 3)],
                    filterStack: [
                        PersistentFilterWheelSnapshot(sourceKind: "standard", ndStop: 3),
                        PersistentFilterWheelSnapshot(sourceKind: "filterSet", filterSetID: set.id.rawValue, itemID: cpl.id.rawValue, rowKind: "cpl", cplLossStops: 1.5),
                    ]
                ),
            ]
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventory
        )
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 3)), .empty(in: set.id)])
        XCTAssertEqual(viewModel.ndStep.stops, 3)
    }

    func testND1000IsExactlyTenStopsInTimerCaptureAndReference() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let item = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        inventory.addItem(item, to: set.id)
        let timerManager = RuntimeBackedTimerManaging(tickInterval: 60, dateProvider: { Date(timeIntervalSince1970: 100) })
        let viewModel = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: timerManager, filterInventoryModel: inventory)
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 12, "2 + exactly 10.")
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.ndStops, 12)
        // Settled order (FILTER-STACK-005): Lee (10) before Standard (2).
        let entry = try XCTUnwrap(timer.filterSummary?[0])
        XCTAssertEqual(entry.canonicalStops, 10)
        XCTAssertEqual(entry.contributedStops, 10)
        XCTAssertEqual(entry.originalValue, 1000)
        XCTAssertEqual(entry.originalUnit, .filterFactor)
        XCTAssertEqual(timer.filterReferenceText, "Lee: Big Stopper ND1000 · Standard 2 stops")
        XCTAssertEqual(
            TimerBasisPresenter.basisText(for: timer, notationMode: .filterFactor, formatShutter: { _ in "1/30s" }),
            "Base 1/30s · 12 stops"
        )
    }

    func testTrackedSelectionsFollowTheLiveRowAndSettleAfterCommit() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        try? await Task.sleep(nanoseconds: 100_000_000)
        // The GND's registered 3 stops lead Standard 0 after the commit.
        XCTAssertEqual(viewModel.trackedWheelSelections[0], select(gnd, .gnd(.recordOnly)))

        // The label follows the candidate at the touch center while moving.
        let wheelID = viewModel.ndFilterWheelIDs[0]
        viewModel.filterWheelDidObserveRow(select(gnd, .gnd(.applyFullValue)), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        XCTAssertEqual(viewModel.trackedWheelSelections[0], select(gnd, .gnd(.applyFullValue)))
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(gnd, .gnd(.recordOnly)), "Committed row unchanged until the commit.")

        // Selecting settles: the tracked selection is the committed row.
        viewModel.filterWheelDidSelect(select(gnd, .gnd(.applyFullValue)), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.filterWheels[0].selection, select(gnd, .gnd(.applyFullValue)))
        XCTAssertEqual(viewModel.trackedWheelSelections[0], select(gnd, .gnd(.applyFullValue)))
    }

    func testRowTypeCategoriesStayBoundToTheirCandidatesThroughObservationCommitAndRejection() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let nd = fixed("ND8", 3)
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, nil, nil])))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        inventory.addItem(nd, to: set.id)
        inventory.addItem(cpl, to: set.id)
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd), at: 1)
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Settled: [ND8, Empty, Standard 0]; wheel 1 is the Empty set wheel.
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(nd), .empty, .standard(NDStep(stops: 0))])
        let wheelID = viewModel.ndFilterWheelIDs[1]
        let expected: [FilterRowTypeCategory] = [.empty, .nd, .cpl, .gnd, .gnd]
        func categories() -> [FilterRowTypeCategory] {
            viewModel.filterWheelRowOptions(forWheel: 1).map { FilterWheelPresenter.rowDisplay(for: $0, notationMode: viewModel.ndNotationMode).typeCategory }
        }
        XCTAssertEqual(categories(), expected)

        // Observing the CPL row (fast fling) moves the tracked header, not the rails.
        viewModel.filterWheelDidObserveRow(select(cpl, .cplLoss(1)), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        XCTAssertEqual(viewModel.trackedWheelSelections[1], select(cpl, .cplLoss(1)))
        XCTAssertEqual(categories(), expected)
        viewModel.filterWheelDidObserveRow(select(gnd, .gnd(.applyFullValue)), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        XCTAssertEqual(categories(), expected)

        // A rejected commit (ND8 is mounted on the sibling) snaps back.
        viewModel.filterWheelDidSelect(select(nd), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)
        XCTAssertEqual(viewModel.filterWheels[1].selection, .empty)
        XCTAssertEqual(categories(), expected)

        // An accepted GND Record only commit: every row keeps its category.
        viewModel.filterWheelDidSelect(select(gnd, .gnd(.recordOnly)), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let gndIndex = try XCTUnwrap(viewModel.ndFilterWheelIDs.firstIndex(of: wheelID))
        XCTAssertEqual(viewModel.filterWheels[gndIndex].selection, select(gnd, .gnd(.recordOnly)))
        let displays = viewModel.filterWheelRowOptions(forWheel: gndIndex).map { FilterWheelPresenter.rowDisplay(for: $0, notationMode: .stops) }
        XCTAssertEqual(displays.map(\.typeCategory), expected)
        XCTAssertEqual(displays.first { $0.selection == select(gnd, .gnd(.recordOnly)) }?.typeCategory, .gnd)
        XCTAssertEqual(displays.first { $0.selection == select(gnd, .gnd(.applyFullValue)) }?.typeCategory, .gnd)
    }

    /// A touch that never moves the wheel leaves no presentation state
    /// behind: touching and releasing keeps the stack, the tracked row,
    /// and interactivity exactly as they were (no exploration state).
    func testTouchWithoutMotionLeavesNoTransientState() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        inventory.addItem(fixed("ND8", 3), to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let wheelID = viewModel.ndFilterWheelIDs[1]
        let before = (viewModel.filterWheels, viewModel.trackedWheelSelections, viewModel.areNDWheelsInteractive)
        viewModel.ndWheelTouchBegan(wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        viewModel.ndWheelTouchEnded(wheelID: wheelID)
        XCTAssertEqual(viewModel.filterWheels, before.0)
        XCTAssertEqual(viewModel.trackedWheelSelections, before.1)
        XCTAssertEqual(viewModel.areNDWheelsInteractive, before.2)
        XCTAssertTrue(viewModel.areNDWheelsInteractive)
    }

    func testManualTimerCapturesNoFilterSummary() throws {
        let timerManager = RuntimeBackedTimerManaging(tickInterval: 60, dateProvider: { Date(timeIntervalSince1970: 100) })
        let viewModel = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: timerManager)
        viewModel.startTimer(from: 5)
        XCTAssertNil(try XCTUnwrap(viewModel.timers.first).filterSummary)
    }

    func testFilterSummaryRoundTripsThroughTimerMetadataPersistence() throws {
        let entry = FilterSummaryEntry(
            sourceKind: .filterSet,
            filterSetID: "s",
            filterSetName: "Lee",
            itemID: "i",
            itemName: "GND",
            itemKind: .gnd,
            originalValue: 0.9,
            originalUnit: .opticalDensity,
            canonicalStops: 3,
            calculationMode: .gndRecordOnly,
            contributedStops: 0
        )
        let snapshot = PersistentTimerMetadataSnapshot(id: UUID(), order: 1, name: "t", basisSummary: "b", filterSummary: [entry])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: data)
        XCTAssertEqual(decoded.filterSummary, [entry])

        let malformed = """
        {"id":"\(snapshot.id.uuidString)","order":1,"name":"t","basisSummary":"b","filterSummary":{"bad":true}}
        """
        let lenient = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: Data(malformed.utf8))
        XCTAssertNil(lenient.filterSummary)
    }

    // MARK: FILTER-STACK-006 — automatic cleanup announces actual removals once

    func testActualCleanupPublishesOneRemovalAndSchedulingOrNoOpPublishesNothing() async throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        viewModel.ndWheelReshapeDuration = 0
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        viewModel.addFilterWheel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(viewModel.filterWheels.count, 2)
        XCTAssertTrue(viewModel.isNDWheelCleanupPending)
        XCTAssertNil(viewModel.emptyFilterWheelRemoval, "Scheduling announces nothing.")

        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [.standard(NDStep(stops: 10))])
        XCTAssertEqual(viewModel.emptyFilterWheelRemoval, EmptyFilterWheelRemoval(sequence: 1, removedCount: 1))

        await awaitCleanupFire()
        XCTAssertEqual(viewModel.emptyFilterWheelRemoval?.sequence, 1, "A cleanup that removes nothing announces nothing.")
    }

    func testDeferredCleanupAnnouncesNothingUntilItActuallyRemoves() async throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        viewModel.ndWheelReshapeDuration = 0
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        viewModel.addFilterWheel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.ndWheelTouchBegan(wheelID: viewModel.ndFilterWheelIDs[0], generation: viewModel.ndWheelGeneration)

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.filterWheels.count, 2, "A touch defers the fire-time judgment.")
        XCTAssertNil(viewModel.emptyFilterWheelRemoval, "Deferral announces nothing.")

        viewModel.ndWheelTouchEnded(wheelID: viewModel.ndFilterWheelIDs[0])
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(viewModel.filterWheels.count, 1)
        XCTAssertEqual(viewModel.emptyFilterWheelRemoval, EmptyFilterWheelRemoval(sequence: 1, removedCount: 1))
    }

    func testCleanupAnnouncementCountsRemovedEmptyWheelsAndNeverAMountedRecordOnlyGND() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.setNDFilterStep(NDStep(stops: 5), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        viewModel.addFilterWheel(from: .standard)
        // [5, gnd(rec, 0 stops), empty, standard 0]
        XCTAssertEqual(viewModel.filterWheels.count, 4)

        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(viewModel.filterWheels, [
            .standard(NDStep(stops: 5)),
            FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly))),
        ], "The mounted Record-only GND stays although it contributes 0.")
        XCTAssertEqual(viewModel.emptyFilterWheelRemoval, EmptyFilterWheelRemoval(sequence: 1, removedCount: 2))
        XCTAssertEqual(FilterWheelPresenter.emptyWheelRemovalText(count: 1), String(localized: "Empty filter wheel removed"))
        XCTAssertEqual(FilterWheelPresenter.emptyWheelRemovalText(count: 2), String(localized: "2 empty filter wheels removed"))
    }

    // MARK: ND-CLEANUP-001/002 — a settle starts a fresh idle interval

    func testACommitRestartsTheIdleCleanupIntervalInsteadOfInheritingIt() async throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        viewModel.ndWheelReshapeDuration = 0
        viewModel.ndWheelCleanupDelay = 0.5
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        viewModel.addFilterWheel()
        // t = 0: [10, 0]; the inherited timer would fire at 0.5 s.
        let armsAfterAdd = viewModel.ndWheelCleanupArmCount

        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.setNDFilterStep(NDStep(stops: 8), at: 0)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertGreaterThan(viewModel.ndWheelCleanupArmCount, armsAfterAdd, "The commit scheduled a fresh interval.")
        XCTAssertTrue(viewModel.isNDWheelCleanupPending)

        try? await Task.sleep(nanoseconds: 370_000_000)
        // t = 0.6 s: past the inherited deadline, inside the fresh one.
        XCTAssertEqual(viewModel.filterWheels.count, 2, "The zero wheel received a full new interval after the commit.")

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [.standard(NDStep(stops: 8))])
    }

    func testMotionThatReturnsToTheCommittedRowAlsoRestartsTheInterval() async throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        viewModel.ndWheelReshapeDuration = 0
        viewModel.ndWheelResolutionDelay = 0.05
        viewModel.ndWheelCleanupDelay = 5
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        viewModel.addFilterWheel()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let armsAfterAdd = viewModel.ndWheelCleanupArmCount
        let zeroWheelID = viewModel.ndFilterWheelIDs[1]

        viewModel.filterWheelDidObserveRow(.standard(NDStep(stops: 3)), wheelID: zeroWheelID, generation: viewModel.ndWheelGeneration)
        viewModel.filterWheelDidObserveRow(.standard(NDStep(stops: 0)), wheelID: zeroWheelID, generation: viewModel.ndWheelGeneration)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(viewModel.ndWheelInteractionState, .idle, "Returning to the committed row resolves without a commit.")
        XCTAssertGreaterThan(viewModel.ndWheelCleanupArmCount, armsAfterAdd, "Settled motion restarts the interval.")
        XCTAssertTrue(viewModel.isNDWheelCleanupPending)
        XCTAssertEqual(viewModel.filterWheels.count, 2)
    }

    // MARK: FILTER-A11Y-006 — a command right after VoiceOver turns off is not lost

    func testAddRightAfterScreenReaderOffIsNotLostAndTheOrderStillReconciles() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.ndWheelReshapeDuration = 5
        viewModel.setFilterStackOrderingSuspended(true)
        let secondWheelID = viewModel.ndFilterWheelIDs[1]
        viewModel.filterWheelDidSelect(select(scenario.nd10), wheelID: secondWheelID, generation: viewModel.ndWheelGeneration)
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd10)])
        XCTAssertEqual(viewModel.ndWheelInteractionState, .reshaping, "The commit's window is still open.")

        viewModel.setFilterStackOrderingSuspended(false)
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd6), select(scenario.nd10)], "Reconciliation waits for quiet.")

        viewModel.ndWheelReshapeDuration = 0
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.filterWheels.count, 3, "The Plus command survives the queued reconciliation.")

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(
            viewModel.filterWheels.map(\.selection),
            [select(scenario.nd10), select(scenario.nd6), .empty],
            "The queued reconciliation still runs once the command has settled."
        )
        XCTAssertEqual(viewModel.ndStep.stops, 16, accuracy: 1e-9)
    }

    func testSelectionRightAfterScreenReaderOffIsAppliedAndReconciled() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.ndWheelReshapeDuration = 5
        viewModel.setFilterStackOrderingSuspended(true)
        viewModel.filterWheelDidSelect(select(scenario.nd10), wheelID: viewModel.ndFilterWheelIDs[1], generation: viewModel.ndWheelGeneration)
        viewModel.setFilterStackOrderingSuspended(false)

        viewModel.ndWheelReshapeDuration = 0
        viewModel.setWheelSelection(select(scenario.nd3), at: 0)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(scenario.nd10), select(scenario.nd3)], "The selection was applied and the order reconciled.")
        XCTAssertEqual(viewModel.ndStep.stops, 13, accuracy: 1e-9)
    }

    // MARK: FILTER-STACK-008 — an assistive commit shows its item in the status detail

    func testAssistiveCommitKeepsTheItemDetailVisibleThroughTheReshapingWindow() async throws {
        let scenario = try await makeOrderingScenario()
        let viewModel = scenario.viewModel
        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.ndWheelReshapeDuration = 0.1
        XCTAssertNil(viewModel.movingWheelStatus)

        viewModel.filterWheelDidSelect(select(scenario.nd10), wheelID: viewModel.ndFilterWheelIDs[1], generation: viewModel.ndWheelGeneration)

        let status = try XCTUnwrap(viewModel.movingWheelStatus, "No motion preceded the commit, yet the detail is shown.")
        XCTAssertTrue(status.expandedLabel.contains("ND 10"), status.expandedLabel)
        XCTAssertEqual(status.contributionStops, 10, accuracy: 1e-9)

        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(viewModel.movingWheelStatus, "The detail leaves with the reshaping window; the region then lingers on its own.")
    }

    // MARK: Rejection notices belong to their context

    func testRejectionNoticeIsClearedBySlotSwitchAndInventoryChange() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 4)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)

        viewModel.selectCameraSlot(.camera2)
        XCTAssertNil(viewModel.filterRejectionNotice, "Camera 2 never saw camera 1's refusal.")

        viewModel.selectCameraSlot(.camera1)
        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)
        inventory.addItem(fixed("Y", 1), to: set.id)
        XCTAssertNil(viewModel.filterRejectionNotice, "An inventory change resets the transient notice.")
    }

    // MARK: FILTER-PERSIST-003 — one coherent snapshot even mid-motion

    func testTimerStartDuringWheelMotionCapturesTotalSummaryAndReferenceFromOneSnapshot() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let bigStopper = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 3.0, unit: .opticalDensity)))
        let nd6 = fixed("ND 6", 6)
        inventory.addItem(bigStopper, to: set.id)
        inventory.addItem(nd6, to: set.id)
        let timerManager = RuntimeBackedTimerManaging(tickInterval: 60, dateProvider: { Date(timeIntervalSince1970: 100) })
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            filterInventoryModel: inventory
        )
        viewModel.ndWheelReshapeDuration = 0
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(bigStopper), at: 1)
        try? await Task.sleep(nanoseconds: 20_000_000)
        // Committed: Lee Big Stopper (10) leads Standard 2 → 12 stops.
        let setIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.source == .filterSet(set.id) })
        viewModel.filterWheelDidObserveRow(select(nd6), wheelID: viewModel.ndFilterWheelIDs[setIndex], generation: viewModel.ndWheelGeneration)
        XCTAssertEqual(viewModel.filterWheels[setIndex].selection, select(bigStopper), "The commit has not landed; the wheel is moving.")

        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        let summary = try XCTUnwrap(timer.filterSummary)
        XCTAssertEqual(try XCTUnwrap(timer.ndStops), 8, accuracy: 1e-9, "The live total the result was computed from.")
        XCTAssertEqual(summary.map(\.contributedStops).reduce(0, +), 8, accuracy: 1e-9, "The summary describes the same wheels as the total.")
        XCTAssertEqual(summary.map(\.itemName), ["ND 6", nil])
        XCTAssertTrue(try XCTUnwrap(timer.filterReferenceText).contains("ND 6"), timer.filterReferenceText ?? "")
        XCTAssertFalse(try XCTUnwrap(timer.filterReferenceText).contains("Big Stopper"))
    }

    // MARK: FILTER-STACK-006 — the immediate saturation cleanup announces too

    func testSaturationCleanupInsideTheBarrierPublishesOneRemovalWhileScreenReaderPolicyIsActive() async throws {
        let viewModel = makeViewModel(inventoryModel: FilterInventoryModel())
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.setNDFilterStep(NDStep(stops: 29), at: 0)
        try? await Task.sleep(nanoseconds: 20_000_000)
        // [29, 0, 0]: below the cap, zeros wait on the idle timer.
        XCTAssertEqual(viewModel.filterWheels.count, 3)
        XCTAssertNil(viewModel.emptyFilterWheelRemoval)

        // Committing 1 saturates the cap; the barrier sheds the unusable
        // zero at once (ND-CLEANUP-003) and that removal is announced.
        viewModel.setNDFilterStep(NDStep(stops: 1), at: 1)

        XCTAssertEqual(viewModel.ndFilterSteps, [NDStep(stops: 29), NDStep(stops: 1)])
        XCTAssertEqual(viewModel.emptyFilterWheelRemoval, EmptyFilterWheelRemoval(sequence: 1, removedCount: 1))

        // A further commit at the cap with nothing left to shed publishes nothing.
        viewModel.setNDFilterStep(NDStep(stops: 1), at: 1)
        XCTAssertEqual(viewModel.emptyFilterWheelRemoval?.sequence, 1)
    }

    func testSaturationKeepsAnEmptyWheelThatCanStillMountRecordOnlyAndAnnouncesNothing() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        let gnd = FilterItem(name: "GND 0.6", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setFilterStackOrderingSuspended(true)
        viewModel.setNDFilterStep(NDStep(stops: 29), at: 0)
        viewModel.addFilterWheel(from: .filterSet(set.id))
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(viewModel.filterWheels.count, 2)

        viewModel.setNDFilterStep(NDStep(stops: 30), at: 0)

        XCTAssertEqual(viewModel.filterWheels.count, 2, "An Empty wheel that can mount a Record-only GND is usable at the cap (FILTER-PLUS-005).")
        XCTAssertNil(viewModel.emptyFilterWheelRemoval, "Nothing was removed, so nothing is announced.")
    }

    // MARK: FILTER-PLUS-005 — availability follows the displayed source

    func testAddAvailabilityIsAnsweredPerSourceInBothDirections() throws {
        let inventory = FilterInventoryModel()
        let gndSet = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        inventory.addItem(FilterItem(name: "GND 0.6", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops))), to: gndSet.id)
        let emptySet = try XCTUnwrap(inventory.createFilterSet(name: "Empty pouch", color: .red))
        let viewModel = makeViewModel(inventoryModel: inventory)

        // Remembered Standard is unavailable at the cap; the browsed
        // GND set is available (Record-only mounts at 30 stops).
        viewModel.setNDFilterStep(NDStep(stops: 30), at: 0)
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
        XCTAssertEqual(viewModel.filterAddUnavailabilityText(for: .standard), FilterWheelPresenter.addUnavailabilityText(for: .noSelectableValue))
        XCTAssertNil(viewModel.filterAddUnavailabilityText(for: .filterSet(gndSet.id)))
        XCTAssertEqual(viewModel.selectedFilterSource, .standard, "Asking never changes the remembered source.")

        // Remembered source available; the browsed item-less set is not.
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        XCTAssertNil(viewModel.filterAddUnavailabilityText(for: .standard))
        XCTAssertEqual(viewModel.filterAddUnavailabilityText(for: .filterSet(emptySet.id)), FilterWheelPresenter.addUnavailabilityText(for: .filterSetHasNoItems))

        // A refused add from the browsed candidate leaves the memory; a
        // successful one moves it.
        viewModel.addFilterWheel(from: .filterSet(emptySet.id))
        XCTAssertEqual(viewModel.selectedFilterSource, .standard)
        viewModel.addFilterWheel(from: .filterSet(gndSet.id))
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(gndSet.id))
    }

    // MARK: Helpers

    private func makeOrderingScenario() async throws -> OrderingScenario {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let nd3 = fixed("ND 3", 3)
        let nd6 = fixed("ND 6", 6)
        let nd10 = fixed("ND 10", 10)
        for item in [nd3, nd6, nd10] {
            inventory.addItem(item, to: set.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelCleanupDelay = 0.05
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd6), at: 1)
        let emptyIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex(where: { $0.selection == .empty }))
        viewModel.setWheelSelection(select(nd3), at: emptyIndex)
        await awaitCleanupFire()
        viewModel.ndWheelCleanupDelay = 4.0
        XCTAssertEqual(viewModel.filterWheels.map(\.selection), [select(nd6), select(nd3)])
        return OrderingScenario(
            viewModel: viewModel,
            nd3: nd3,
            nd6: nd6,
            nd10: nd10
        )
    }

    /// The self-cleaning timer is the only cleanup path
    /// (FILTER-STACK-006) — there is no on-demand command. Tests
    /// shorten `ndWheelCleanupDelay` when they build the view model
    /// and then wait here for one fire. The window also covers the
    /// reshaping animation, which the fire-time judgment waits out.
    private func awaitCleanupFire() async {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private func makeViewModel(inventoryModel: FilterInventoryModel) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            filterInventoryModel: inventoryModel
        )
    }
}
