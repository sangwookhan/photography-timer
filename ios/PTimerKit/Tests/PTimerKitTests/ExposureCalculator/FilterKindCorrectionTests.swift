// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Correcting a mounted item's kind (FILTER-ITEM-005): the selection
/// follows the item into its new role, and a change into a role that is
/// already full is blocked with its specific limit.
@MainActor
final class FilterKindCorrectionTests: XCTestCase {
    private func select(_ item: FilterItem) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: item.id, choice: .fixed))
    }

    private func fixed(_ name: String, _ stops: Double) -> FilterItem {
        FilterItem(name: name, behavior: .fixed(FilterRegisteredValue(value: stops, unit: .stops)))
    }

    private func makeViewModel(inventoryModel: FilterInventoryModel) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            filterInventoryModel: inventoryModel
        )
    }

    /// FILTER-ITEM-005 correction path: an item entered with the wrong
    /// kind is corrected while mounted, and its selection follows the
    /// item into the new role — no manual deselection, no lost mount.
    func testChangingAMountedItemsKindMovesItsSelectionIntoTheNewRole() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let item = fixed("Red 25A", 3)
        inventory.addItem(item, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.assignAllFilterSetsAsCandidates()
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(item), at: 1)
        XCTAssertEqual(viewModel.ndStep.stops, 3, accuracy: 1e-9)

        // ND entered by mistake → Color: the wheel leaves the ND row and
        // the item is mounted as an auxiliary filter at the same loss.
        var asColor = item
        asColor.behavior = .color(FilterExposureLoss(stops: 3), .red)
        XCTAssertEqual(viewModel.saveFilterItem(asColor, in: set.id), .saved)
        XCTAssertFalse(viewModel.filterWheels.contains { $0.mountedItemID == item.id })
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), [.mount(asColor, in: set, .registeredLoss)])
        XCTAssertEqual(viewModel.ndStep.stops, 3, accuracy: 1e-9)

        // Another auxiliary kind takes that kind's default choice.
        var asGND = item
        asGND.behavior = .gnd(FilterRegisteredValue(value: 3, unit: .stops))
        XCTAssertEqual(viewModel.saveFilterItem(asGND, in: set.id), .saved)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount.choice), [.gnd(.recordOnly)])

        // Back to ND: the mount becomes a Filter Set ND wheel again.
        XCTAssertEqual(viewModel.saveFilterItem(item, in: set.id), .saved)
        XCTAssertTrue(viewModel.mountedAuxiliaryFilters.isEmpty)
        XCTAssertEqual(viewModel.filterWheels.filter { $0.mountedItemID == item.id }.count, 1)
        XCTAssertEqual(viewModel.ndStep.stops, 3, accuracy: 1e-9)
    }

    /// A kind change never deletes selections to make room. The
    /// auxiliary role has no count limit, so a fourth auxiliary item is
    /// fine; the ND wheel limit and the 30-stop cap still block Save
    /// with their specific reason, and nothing changes.
    func testAKindChangeIsBlockedOnlyByTheWheelLimitOrTheCap() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "S", color: .red))
        let nd = fixed("ND8", 3)
        let cpl = FilterItem(name: "CPL", behavior: .cpl(.defaults))
        let gnd = FilterItem(name: "Soft GND 2", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops)))
        let red = FilterItem(name: "Red 25A", behavior: .color(FilterExposureLoss(stops: 3), .red))
        for item in [nd, cpl, gnd, red] {
            inventory.addItem(item, to: set.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.assignAllFilterSetsAsCandidates()
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(select(nd), at: 1)
        XCTAssertNil(viewModel.applyAuxiliaryFilters([.mount(cpl, in: set), .mount(gnd, in: set), .mount(red, in: set)]))

        // Three auxiliary filters already mounted: the corrected ND item
        // becomes the fourth, in display order (Color first, set order).
        var ndAsColor = nd
        ndAsColor.behavior = .color(FilterExposureLoss(stops: 3), .blue)
        XCTAssertEqual(viewModel.saveFilterItem(ndAsColor, in: set.id), .saved)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [nd.id, red.id, cpl.id, gnd.id])
        XCTAssertFalse(viewModel.filterWheels.contains { $0.mountedItemID == nd.id })

        // Summary + three ND wheels: an auxiliary item turned ND has no
        // wheel left to take.
        viewModel.selectFilterSource(.standard)
        viewModel.addFilterWheel()
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.filterWheels.count, 3)
        let mountsBefore = viewModel.mountedAuxiliaryFilters.map(\.mount)
        var gndAsND = gnd
        gndAsND.behavior = .fixed(FilterRegisteredValue(value: 2, unit: .stops))
        XCTAssertEqual(viewModel.saveFilterItem(gndAsND, in: set.id), .blocked(affectedCameras: ["Camera 1"], reason: .tooManyNDWheels))
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), mountsBefore)

        // A kind change that would push the stack past 30 stops is
        // blocked by the cap.
        viewModel.setNDFilterStep(NDStep(stops: 16), at: 0)
        var heavierRed = red
        heavierRed.behavior = .color(FilterExposureLoss(stops: 12), .red)
        XCTAssertEqual(viewModel.saveFilterItem(heavierRed, in: set.id), .blocked(affectedCameras: ["Camera 1"], reason: .exceedsTotalLimit))
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.mount), mountsBefore)
    }
}
