// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Unlimited auxiliary selection (FILTER-AUX-001/003/004): more than
/// three items mount, the popup subtotal counts only auxiliary filters,
/// and the 30-stop cap refuses the new change in either selection order
/// without removing what is already mounted.
@MainActor
final class AuxiliaryFilterSelectionTests: XCTestCase {
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

    func testMoreThanThreeAuxiliaryFiltersMountAndTheSubtotalExcludesND() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let items = [effect("A", 1), effect("B", 1.5), effect("C", 2), effect("D", 0.5), effect("E", 0)]
        for item in items {
            inventory.addItem(item, to: set.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.assignAllFilterSetsAsCandidates()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)

        let mounts = items.map { MountedAuxiliaryFilter.mount($0, in: set) }
        XCTAssertEqual(viewModel.auxiliaryFiltersSubtotal(mounts), 5, accuracy: 1e-9, "Only auxiliary contributions; the 10-stop ND wheel is not counted.")
        XCTAssertNil(viewModel.applyMounts(mounts))
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.count, 5)
        XCTAssertEqual(viewModel.ndStep.stops, 15, accuracy: 1e-9, "The full Total on Main still includes ND.")
        XCTAssertEqual(viewModel.auxiliaryFilterSummary?.hiddenItemCount, 2)
    }

    func testTheCapRefusesAuxiliaryAfterNDWithoutChangingTheSelection() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let small = effect("Small", 2)
        let big = effect("Big", 9)
        inventory.addItem(small, to: set.id)
        inventory.addItem(big, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.assignAllFilterSetsAsCandidates()
        viewModel.setNDFilterStep(NDStep(stops: 20), at: 0)
        XCTAssertNil(viewModel.applyMounts([.mount(small, in: set)]))

        let attempt = [MountedAuxiliaryFilter.mount(small, in: set), .mount(big, in: set)]
        XCTAssertEqual(viewModel.shootingFiltersPreview(selectedFilterSetIDs: viewModel.candidateFilterSetIDs, mounts: attempt), .failure(.exceedsTotalLimit))
        XCTAssertEqual(viewModel.applyMounts(attempt), .exceedsTotalLimit)
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [small.id], "The committed selection is untouched.")
        XCTAssertEqual(viewModel.ndStep.stops, 22, accuracy: 1e-9)
    }

    func testTheCapRefusesNDAfterAuxiliaryWithoutChangingTheSelection() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let big = effect("Big", 12)
        inventory.addItem(big, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.assignAllFilterSetsAsCandidates()
        XCTAssertNil(viewModel.applyMounts([.mount(big, in: set)]))

        viewModel.setNDFilterStep(NDStep(stops: 20), at: 0)
        XCTAssertEqual(viewModel.ndStep.stops, 12, accuracy: 1e-9, "20 + 12 would exceed 30; the ND change is refused.")
        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [big.id], "The auxiliary filter stays mounted.")
        viewModel.setNDFilterStep(NDStep(stops: 18), at: 0)
        XCTAssertEqual(viewModel.ndStep.stops, 30, accuracy: 1e-9, "Up to the remaining budget is accepted.")
    }

    func testAScaleChangeKeepsTheMountedAuxiliaryFilters() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .teal))
        let night = effect("Night", 1.5)
        inventory.addItem(night, to: set.id)
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.assignAllFilterSetsAsCandidates()
        viewModel.setNDFilterStep(NDStep(stops: 10), at: 0)
        XCTAssertNil(viewModel.applyMounts([.mount(night, in: set)]))

        viewModel.scaleMode = .fullStop

        XCTAssertEqual(viewModel.mountedAuxiliaryFilters.map(\.item.id), [night.id], "The Standard wheels re-snap; the auxiliary filters stay mounted.")
        XCTAssertEqual(viewModel.ndStep.stops, 11.5, accuracy: 1e-9)
    }
}
