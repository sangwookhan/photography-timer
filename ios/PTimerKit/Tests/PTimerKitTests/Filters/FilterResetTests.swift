// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Camera Reset with Filter Sets (RESET-004/011/012, FILTER-PLUS-004):
/// both choices return the Filter Stack to one Standard 0 wheel and clear
/// every auxiliary selection, a zero-contribution Record-only GND
/// included, while the camera's selected Filter Sets and its remembered
/// Plus source stay; the inventory and other cameras are untouched.
@MainActor
final class FilterResetTests: XCTestCase {
    private let gnd = FilterItem(name: "Soft GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
    private let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
    private let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
    private let night = FilterItem(name: "Night", behavior: .effect(FilterExposureLoss(stops: 1)))
    private let nd8 = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))

    private struct Camera {
        let viewModel: ExposureCalculatorViewModel
        let store: InMemoryMixedSessionStore
        let inventory: FilterInventoryModel
        let kit: FilterSet
    }

    /// Kit holds every kind; the camera selects it with Plus on Kit.
    private func camera() throws -> Camera {
        let store = InMemoryMixedSessionStore()
        let inventory = FilterInventoryModel()
        let kit = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        for item in [gnd, cpl, red, night, nd8] {
            inventory.addItem(item, to: kit.id)
        }
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: store,
            filterInventoryModel: inventory
        )
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [kit.id], mounts: []))
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(kit.id), "Plus moved to Kit on Apply.")
        XCTAssertEqual(viewModel.filterWheels, [.empty(in: kit.id)])
        XCTAssertFalse(viewModel.canResetFilmModeWorkingContext, "Selecting a Filter Set alone, with the Empty wheel its Apply leaves, does not show Reset.")
        return Camera(viewModel: viewModel, store: store, inventory: inventory, kit: try XCTUnwrap(inventory.filterSet(withID: kit.id)))
    }

    func testAZeroTotalRecordOnlyGNDAndAnEmptySetWheelAreResetAndSelectedSetsStay() throws {
        let camera = try camera()
        let viewModel = camera.viewModel
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [camera.kit.id], mounts: [.mount(gnd, in: camera.kit)]))
        XCTAssertEqual(viewModel.filterWheels, [.empty(in: camera.kit.id)])
        XCTAssertEqual(viewModel.ndStep.stops, 0, accuracy: 1e-9, "Record only and an Empty wheel: the total is 0.")
        XCTAssertTrue(viewModel.canResetFilmModeWorkingContext, "A zero-contribution auxiliary filter shows Reset.")
        let inventoryBefore = viewModel.filterInventory

        viewModel.resetFilmModeWorkingContext()

        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty)
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [camera.kit.id], "Selected Filter Sets stay.")
        XCTAssertEqual(viewModel.selectedFilterSource, .filterSet(camera.kit.id), "The remembered Plus source stays.")
        XCTAssertEqual(viewModel.filterInventory, inventoryBefore, "The inventory is unchanged.")
        XCTAssertFalse(viewModel.canResetFilmModeWorkingContext, "Selected Filter Sets alone do not show Reset.")

        let restored = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: camera.store,
            filterInventoryModel: camera.inventory
        )
        XCTAssertEqual(restored.filterWheels, [.standard(NDStep(stops: 0))], "The reset is saved.")
        XCTAssertTrue(restored.mountedAuxiliaryFilters.isEmpty)
        XCTAssertEqual(restored.candidateFilterSetIDs, [camera.kit.id])
    }

    func testResetSettingsAndNameClearsEveryAuxiliaryKindAndLeavesOtherCamerasAlone() throws {
        let camera = try camera()
        let viewModel = camera.viewModel
        viewModel.selectCameraSlot(.camera2)
        XCTAssertNil(viewModel.applyShootingFilters(selectedFilterSetIDs: [camera.kit.id], mounts: [.mount(red, in: camera.kit)]))
        viewModel.selectCameraSlot(.camera1)
        viewModel.setCameraSlotCustomName("Field", for: .camera1)
        XCTAssertNil(viewModel.applyShootingFilters(
            selectedFilterSetIDs: [camera.kit.id],
            mounts: [.mount(cpl, in: camera.kit, .cplLoss(1.5)), .mount(red, in: camera.kit), .mount(night, in: camera.kit), .mount(gnd, in: camera.kit)]
        ))
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: nd8.id, choice: .fixed)), at: 0)
        XCTAssertEqual(viewModel.ndStep.stops, 3 + 1.5 + 3 + 1, accuracy: 1e-9)

        viewModel.resetFilmModeWorkingContextAndCameraName()

        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 0))])
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty)
        XCTAssertEqual(viewModel.candidateFilterSetIDs, [camera.kit.id])
        XCTAssertNil(viewModel.activeCameraSlot.customDisplayName)
        viewModel.selectCameraSlot(.camera2)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [.mount(red, in: camera.kit)], "Another camera is unchanged.")
    }
}
