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
final class FilterSetViewModelTests: XCTestCase {
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
        XCTAssertEqual(viewModel.filterWheels, [
            .standard(NDStep(stops: 0)),
            FilterWheel(source: .filterSet(set.id), selection: select(item)),
        ])
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
        XCTAssertFalse(viewModel.canAddFilterWheel)
        XCTAssertEqual(viewModel.filterAddUnavailability, .noSelectableValue)
        XCTAssertNotNil(viewModel.filterAddUnavailabilityText)

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

    func testCleanupRemovesEmptyButKeepsRecordOnly() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "GND", color: .purple))
        let gnd = FilterItem(name: "GND", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.setNDFilterStep(NDStep(stops: 5), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(gnd, .gnd(.recordOnly)), at: 1)
        // [5, gnd(rec), empty]
        XCTAssertEqual(viewModel.filterWheels.count, 3)
        viewModel.cleanupEmptyFilterWheels()
        XCTAssertEqual(viewModel.filterWheels, [
            .standard(NDStep(stops: 5)),
            FilterWheel(source: .filterSet(set.id), selection: select(gnd, .gnd(.recordOnly))),
        ])
        XCTAssertFalse(viewModel.calculatorModel.canRemoveEmptyFilterWheel)
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

        viewModel.setWheelSelection(select(gnd, .gnd(.applyFullValue)), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 2)

        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.ndStep.stops, 0, "Camera 1 keeps Record only.")
        XCTAssertEqual(viewModel.filterWheels[1].selection, select(gnd, .gnd(.recordOnly)))
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

        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0)), .empty(in: set.id)])
        XCTAssertEqual(viewModel.ndStep.stops, 0)
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0)), .empty(in: set.id)])
    }

    func testDeletingAFilterSetRemovesItsWheelsAndFallsBackToStandard() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("X", 4)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        // Drop the Standard 0 wheel so only the set wheel remains.
        viewModel.cleanupEmptyFilterWheels()
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
        XCTAssertEqual(viewModel.filterWheels[1].selection, select(cpl, .cplLoss(2)))

        // Keeping every selected choice (adding a fourth value is not
        // possible, but changing the unselected slot is) saves.
        var keepsSelected = cpl
        keepsSelected.behavior = .cpl(CPLExposureLossChoices(fields: [0.5, 1.5, 2]))
        XCTAssertEqual(viewModel.saveFilterItem(keepsSelected, in: set.id), .saved)
        XCTAssertEqual(viewModel.filterWheels[1].selection, select(cpl, .cplLoss(2)))
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.filterWheels[1].selection, select(cpl, .cplLoss(1.5)))

        // After the camera changes its wheel, the removal is allowed.
        viewModel.setWheelSelection(select(cpl, .cplLoss(2)), at: 1)
        viewModel.selectCameraSlot(.camera2)
        viewModel.setWheelSelection(.empty, at: 1)
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
        XCTAssertEqual(viewModel.filterWheels[1].selection, select(item))
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
        viewModel.setWheelSelection(select(item), at: 2)
        XCTAssertEqual(viewModel.filterWheels, before)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)
        let rows = viewModel.filterWheelRowOptions(forWheel: 2)
        XCTAssertEqual(rows.first { $0.selection == select(item) }?.unavailability, .itemAlreadyMounted)
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
        XCTAssertEqual(summary[1].filterSetName, "Lee")
        XCTAssertEqual(summary[1].itemName, "Big Stopper")
        XCTAssertEqual(summary[1].originalUnit, .opticalDensity)
        XCTAssertEqual(try XCTUnwrap(summary[1].canonicalStops), 10, accuracy: 1e-9)
        XCTAssertEqual(summary[1].contributedStops, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(timer.ndStops), 12, accuracy: 1e-9)

        viewModel.renameFilterSet(id: set.id, name: "Renamed")
        var renamed = item
        renamed.name = "Renamed item"
        XCTAssertEqual(viewModel.saveFilterItem(renamed, in: set.id), .saved)
        XCTAssertEqual(viewModel.timers.first?.filterSummary, summary, "Captured summaries never change.")
        XCTAssertEqual(viewModel.filterRows[1].item?.name, "Renamed item", "The live stack follows the rename.")
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
        let expected = "Standard 2 stops · Haida 100mm: ND400 ND400 + GND 2 2 stops (Record only)"
        XCTAssertEqual(timer.filterReferenceText, expected)
        XCTAssertEqual(try XCTUnwrap(timer.ndStops), 2 + log2(400), accuracy: 1e-9, "The primary value is the canonical total.")
        XCTAssertEqual(timer.filterSummary?.last?.contributedStops, 0, "Record only contributes 0 yet appears in the reference.")

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

    // MARK: Helpers

    private func makeViewModel(inventoryModel: FilterInventoryModel) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            filterInventoryModel: inventoryModel
        )
    }
}
