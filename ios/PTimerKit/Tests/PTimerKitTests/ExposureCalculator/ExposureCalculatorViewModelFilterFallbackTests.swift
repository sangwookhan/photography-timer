// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
@testable import PTimerKit
import XCTest

/// FILTER-STACK-004: a sighted touch gesture on a Filter Set wheel that
/// settles on an unavailable row never commits it; the wheel falls back
/// to the nearest selectable row the gesture just traversed, never
/// beyond the attempted row and never wrapping. With nothing selectable
/// on that interval the previous selection stays and the actual reason
/// is shown. Assistive and programmatic commits keep the plain refusal
/// (FILTER-A11Y-004 is untouched).
@MainActor
final class ExposureCalculatorFilterFallbackTests: XCTestCase {
    private struct FallbackScenario {
        let viewModel: ExposureCalculatorViewModel
        let items: [Double: FilterItem]
        let movingIndex: Int
    }

    private func select(_ item: FilterItem, _ choice: FilterRowChoice = .fixed) -> FilterWheelSelection {
        .item(FilterRowSelection(itemID: item.id, choice: choice))
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

    /// Items 2 / 3 / 4 stops in one set. Returns the view model with
    /// the requested items mounted on their own wheels plus one more
    /// Filter Set wheel (the one the gesture moves) committed to `start`.
    private func makeFallbackScenario(
        mounted: [Double],
        start: FilterWheelSelection,
        standardStops: Double = 0
    ) async throws -> FallbackScenario {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Kit", color: .red))
        var items: [Double: FilterItem] = [:]
        for stops in [2.0, 3.0, 4.0] {
            let item = fixed("ND \(Int(stops))", stops)
            items[stops] = item
            inventory.addItem(item, to: set.id)
        }
        let viewModel = makeViewModel(inventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setNDFilterStep(NDStep(stops: standardStops), at: 0)
        viewModel.selectFilterSource(.filterSet(set.id))
        for stops in mounted {
            viewModel.addFilterWheel()
            let emptyIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.selection == .empty })
            viewModel.setWheelSelection(select(try XCTUnwrap(items[stops])), at: emptyIndex)
        }
        viewModel.addFilterWheel()
        let emptyIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.selection == .empty })
        if start != .empty {
            viewModel.setWheelSelection(start, at: emptyIndex)
        }
        // Let the programmatic commits' reshaping window (0 s, but
        // asynchronous) close so the gesture is accepted as input.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let movingIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.source == .filterSet(set.id) && $0.selection == start })
        return FallbackScenario(viewModel: viewModel, items: items, movingIndex: movingIndex)
    }

    /// One sighted touch on a wheel: the finger goes down, the poll
    /// reports each row crossed, the finger lifts, and the picker's
    /// `didSelectRow` reports the row it settled on.
    private func sightedGesture(
        _ viewModel: ExposureCalculatorViewModel,
        wheelIndex: Int,
        crossing rows: [FilterWheelSelection],
        settlingOn final: FilterWheelSelection
    ) async {
        let wheelID = viewModel.ndFilterWheelIDs[wheelIndex]
        let generation = viewModel.ndWheelGeneration
        viewModel.ndWheelTouchBegan(wheelID: wheelID, generation: generation)
        for row in rows {
            viewModel.filterWheelDidObserveRow(row, wheelID: wheelID, generation: generation)
        }
        viewModel.ndWheelTouchEnded(wheelID: wheelID)
        viewModel.filterWheelDidSelect(final, wheelID: wheelID, generation: generation)
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    func testSightedSettleOnAMountedRowFallsBackToTheNearestTraversedSelectableRow() async throws {
        let scenario = try await makeFallbackScenario(mounted: [4], start: .empty)
        let viewModel = scenario.viewModel
        let nd2 = try XCTUnwrap(scenario.items[2]), nd3 = try XCTUnwrap(scenario.items[3]), nd4 = try XCTUnwrap(scenario.items[4])
        // Start the moving wheel on 2 through a sighted gesture, then drag it up to 4.
        await sightedGesture(viewModel, wheelIndex: scenario.movingIndex, crossing: [select(nd2)], settlingOn: select(nd2))
        let movingIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.selection == select(nd2) })

        await sightedGesture(viewModel, wheelIndex: movingIndex, crossing: [select(nd3), select(nd4)], settlingOn: select(nd4))

        XCTAssertEqual(viewModel.filterWheels.filter { $0.selection == select(nd4) }.count, 1, "The mounted 4 stays where it was; the moving wheel never commits it.")
        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd3) }, "The nearest traversed selectable row (3) is committed.")
        XCTAssertFalse(viewModel.filterWheels.contains { $0.selection == select(nd2) }, "The wheel left 2.")
        XCTAssertEqual(viewModel.ndStep.stops, 7, accuracy: 1e-9, "Total reflects 4 + 3.")
        XCTAssertNil(viewModel.filterRejectionNotice, "A settled fallback shows the committed row and Total, not the rejected candidate's reason.")
    }

    func testSightedSettleSkipsTwoUnavailableRowsAndFallsBackToTheFirstTraversedSelectableRow() async throws {
        // 4 and 3 are mounted elsewhere; the moving wheel starts Empty and releases on 4.
        let scenario = try await makeFallbackScenario(mounted: [4, 3], start: .empty)
        let viewModel = scenario.viewModel
        let nd2 = try XCTUnwrap(scenario.items[2]), nd3 = try XCTUnwrap(scenario.items[3]), nd4 = try XCTUnwrap(scenario.items[4])

        await sightedGesture(viewModel, wheelIndex: scenario.movingIndex, crossing: [select(nd2), select(nd3), select(nd4)], settlingOn: select(nd4))

        XCTAssertEqual(viewModel.filterWheels.filter { $0.selection == select(nd4) }.count, 1)
        XCTAssertEqual(viewModel.filterWheels.filter { $0.selection == select(nd3) }.count, 1)
        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd2) }, "3 is unavailable too, so the traversed 2 commits.")
        XCTAssertEqual(viewModel.ndStep.stops, 9, accuracy: 1e-9)
        XCTAssertNil(viewModel.filterRejectionNotice)
    }

    func testSightedSettleWithNoTraversedSelectableRowKeepsThePreviousSelectionAndShowsTheReason() async throws {
        // 4 and 3 are mounted elsewhere; the moving wheel sits on 2 and
        // drags up through 3 to release on 4 — every traversed row is
        // unavailable.
        let scenario = try await makeFallbackScenario(mounted: [4, 3], start: .empty)
        let viewModel = scenario.viewModel
        let nd2 = try XCTUnwrap(scenario.items[2]), nd3 = try XCTUnwrap(scenario.items[3]), nd4 = try XCTUnwrap(scenario.items[4])
        await sightedGesture(viewModel, wheelIndex: scenario.movingIndex, crossing: [select(nd2)], settlingOn: select(nd2))
        let movingIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.selection == select(nd2) })
        let before = viewModel.filterWheels

        await sightedGesture(viewModel, wheelIndex: movingIndex, crossing: [select(nd3), select(nd4)], settlingOn: select(nd4))

        XCTAssertEqual(viewModel.filterWheels, before, "Nothing traversed was selectable: the previous selection (2) remains.")
        XCTAssertEqual(viewModel.ndStep.stops, 9, accuracy: 1e-9, "The total is unchanged.")
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted, "The actual rejection reason is shown.")
    }

    func testSightedFallbackNeverSearchesBeyondTheAttemptedRowOrWraps() async throws {
        // Rows: Empty, 2, 3, 4. Mount 3 elsewhere; the moving wheel sits on 2
        // and releases on 3. 4 lies beyond the attempted row and Empty lies
        // behind the committed row; neither may be chosen.
        let scenario = try await makeFallbackScenario(mounted: [3], start: .empty)
        let viewModel = scenario.viewModel
        let nd2 = try XCTUnwrap(scenario.items[2]), nd3 = try XCTUnwrap(scenario.items[3]), nd4 = try XCTUnwrap(scenario.items[4])
        await sightedGesture(viewModel, wheelIndex: scenario.movingIndex, crossing: [select(nd2)], settlingOn: select(nd2))
        let movingIndex = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.selection == select(nd2) })
        let before = viewModel.filterWheels

        await sightedGesture(viewModel, wheelIndex: movingIndex, crossing: [select(nd3)], settlingOn: select(nd3))

        XCTAssertEqual(viewModel.filterWheels, before, "Only the interval (2, 3] is inspected; 3 is unavailable, so 2 remains.")
        XCTAssertFalse(viewModel.filterWheels.contains { $0.selection == select(nd4) }, "4 is beyond the attempted row and is never chosen.")
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)

        // Downward: from 4 (now mounting it on the moving wheel) toward
        // the mounted 3 — nothing lies between, no wrap to Empty or 2.
        viewModel.setWheelSelection(select(nd4), at: movingIndex)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let movingIndex4 = try XCTUnwrap(viewModel.filterWheels.firstIndex { $0.selection == select(nd4) })
        let before4 = viewModel.filterWheels
        await sightedGesture(viewModel, wheelIndex: movingIndex4, crossing: [select(nd3)], settlingOn: select(nd3))
        XCTAssertEqual(viewModel.filterWheels, before4, "No selectable row between 4 and the attempted 3: 4 remains, nothing wraps.")
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)
    }

    func testSightedSettleOverTheThirtyStopCapFallsBackTheSameWay() async throws {
        // Standard 27 + Kit wheel: 4 would make 31 (rejected), 3 makes 30.
        let scenario = try await makeFallbackScenario(mounted: [], start: .empty, standardStops: 27)
        let viewModel = scenario.viewModel
        let nd2 = try XCTUnwrap(scenario.items[2]), nd3 = try XCTUnwrap(scenario.items[3]), nd4 = try XCTUnwrap(scenario.items[4])
        XCTAssertEqual(viewModel.filterWheelRowOptions(forWheel: scenario.movingIndex).first { $0.selection == select(nd4) }?.unavailability, .exceedsTotalLimit)

        await sightedGesture(viewModel, wheelIndex: scenario.movingIndex, crossing: [select(nd2), select(nd3), select(nd4)], settlingOn: select(nd4))

        XCTAssertTrue(viewModel.filterWheels.contains { $0.selection == select(nd3) }, "The over-cap 4 never commits; the traversed 3 does.")
        XCTAssertEqual(viewModel.ndStep.stops, 30, accuracy: 1e-9)
        XCTAssertNil(viewModel.filterRejectionNotice)
    }

    func testAssistiveOrProgrammaticCommitOfAnUnavailableRowStillRefusesWithoutFallback() async throws {
        // No motion preceded the commit: FILTER-A11Y-004's scan already
        // avoids unavailable rows, and a direct commit keeps the plain
        // refusal so the sighted fallback never leaks into that path.
        let scenario = try await makeFallbackScenario(mounted: [4], start: .empty)
        let viewModel = scenario.viewModel
        let nd4 = try XCTUnwrap(scenario.items[4])
        let before = viewModel.filterWheels
        let wheelID = viewModel.ndFilterWheelIDs[scenario.movingIndex]

        viewModel.filterWheelDidSelect(select(nd4), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(viewModel.filterWheels, before)
        XCTAssertEqual(viewModel.filterRejectionNotice?.rejection, .itemAlreadyMounted)
    }
}
