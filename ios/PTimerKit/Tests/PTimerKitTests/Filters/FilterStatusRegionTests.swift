// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-STACK-008: the mixed-stack interaction has exactly one
/// transient status region. Content states replace or combine within
/// one value, a rejection replaces movement with its reason and the
/// unchanged total, and a stale fade task can never remove newer
/// content.
@MainActor
final class FilterStatusRegionTests: XCTestCase {
    private let total = NDStackTotalDisplayState(effectiveStep: NDStep(stops: 18), wheelCount: 3)
    private let moving = MovingWheelStatus(expandedLabel: "Lee GND 0.9 · OD 0.9 · Apply full value", contributionStops: 3)

    // MARK: Composition — one content, priority order

    func testMovingWheelCombinesExpandedInformationAndLiveTotalInOneContent() {
        let content = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total)
        XCTAssertEqual(content?.primaryText, "Lee GND 0.9 · OD 0.9 · Apply full value")
        XCTAssertEqual(content?.secondaryText, "+3 stops · Total 18 stops")
        XCTAssertEqual(content?.isHeld, true)
        XCTAssertEqual(content?.isWarning, false)
    }

    func testRejectionReplacesMovementWithReasonAndUnchangedTotal() {
        let rejection = FilterRejectionNotice(sequence: 1, rejection: .itemAlreadyMounted)
        let content = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: "Lee holder", rejection: rejection, total: total)
        XCTAssertEqual(content?.primaryText, "Already mounted on this camera")
        XCTAssertEqual(content?.secondaryText, "Total 18 stops")
        XCTAssertEqual(content?.isWarning, true)
        XCTAssertEqual(content?.isHeld, true)
    }

    func testPlusBrowsingShowsTheSourceNameWithTheTotal() {
        let content = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: "NiSi kit", rejection: nil, total: total)
        XCTAssertEqual(content?.primaryText, "NiSi kit")
        XCTAssertEqual(content?.secondaryText, "Total 18 stops")
    }

    func testIdleTotalIsUnheldAndAbsentForASingleWheel() {
        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total)
        XCTAssertNil(idle?.primaryText)
        XCTAssertEqual(idle?.secondaryText, "Total 18 stops")
        XCTAssertEqual(idle?.isHeld, false)

        let single = NDStackTotalDisplayState(effectiveStep: NDStep(stops: 4), wheelCount: 1)
        XCTAssertNil(FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: single))
        XCTAssertEqual(
            FilterStatusRegionPresenter.totalText(NDStackTotalDisplayState(effectiveStep: NDStep(stops: 30), wheelCount: 2)),
            "Total 30 stops · Maximum"
        )
    }

    // MARK: Controller — one visible content, deterministic fade

    func testHeldContentStaysAndIdleTotalFadesAfterTheInterval() async {
        let controller = TransientStatusRegionController()
        controller.fadeDelay = 0.05
        let held = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total)
        controller.apply(held)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.visibleContent, held, "Held content never fades on its own.")

        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total)
        controller.apply(idle)
        XCTAssertEqual(controller.visibleContent, idle)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(controller.visibleContent, "The idle total fades after the interval.")
    }

    func testStaleFadeTaskCannotRemoveNewerContent() async {
        let controller = TransientStatusRegionController()
        controller.fadeDelay = 0.05
        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total)
        controller.apply(idle)
        let staleToken = controller.currentGeneration

        // A new movement arrives before the idle fade fires.
        let held = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total)
        controller.apply(held)
        controller.fireFadeIfPending(token: staleToken)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.visibleContent, held, "The earlier fade belongs to a superseded state.")
    }

    func testRejectionDuringMovementReplacesTheVisibleContentWithoutStacking() {
        let controller = TransientStatusRegionController()
        controller.apply(FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total))
        let rejection = FilterRejectionNotice(sequence: 1, rejection: .exceedsTotalLimit)
        controller.apply(FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: rejection, total: total))
        XCTAssertEqual(controller.visibleContent?.primaryText, "Exceeds 30 stops")
        XCTAssertEqual(controller.visibleContent?.secondaryText, "Total 18 stops")
        // Clearing the rejection returns to the idle total, still one content.
        controller.apply(FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total))
        XCTAssertNil(controller.visibleContent?.primaryText)
        XCTAssertEqual(controller.visibleContent?.secondaryText, "Total 18 stops")
    }

    func testMovingStatusKeepsOriginalRepresentationAndExactContributionForND1000() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee", color: .red))
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        inventory.addItem(nd1000, to: set.id)
        let viewModel = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging(), filterInventoryModel: inventory)
        viewModel.ndWheelReshapeDuration = 0
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let wheelID = viewModel.ndFilterWheelIDs[1]
        viewModel.filterWheelDidObserveRow(.item(FilterRowSelection(itemID: nd1000.id, choice: .fixed)), wheelID: wheelID, generation: viewModel.ndWheelGeneration)
        let status = try XCTUnwrap(viewModel.movingWheelStatus)
        XCTAssertEqual(status.expandedLabel, "Big Stopper · ND1000 · 10 stops")
        XCTAssertEqual(status.contributionStops, 10)
        let content = FilterStatusRegionPresenter.content(moving: status, browsingSourceName: nil, rejection: nil, total: viewModel.ndStackTotalDisplayState)
        XCTAssertEqual(content?.secondaryText, "+10 stops · Total 10 stops")
    }

    func testViewModelMovingWheelStatusCarriesLabelAndContribution() async throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Lee holder", color: .red))
        let gnd = FilterItem(name: "Lee GND 0.9", behavior: .gnd(FilterRegisteredValue(value: 0.9, unit: .opticalDensity)))
        inventory.addItem(gnd, to: set.id)
        let viewModel = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging(), filterInventoryModel: inventory)
        viewModel.selectFilterSource(.filterSet(set.id))
        viewModel.addFilterWheel()
        viewModel.ndWheelReshapeDuration = 0
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: gnd.id, choice: .gnd(.recordOnly))), at: 1)
        // Let the set-commit RESHAPING window close before observing motion.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.movingWheelStatus)

        // Live movement onto Apply full value on the settled wheel.
        let wheelID = viewModel.ndFilterWheelIDs[1]
        viewModel.filterWheelDidObserveRow(
            .item(FilterRowSelection(itemID: gnd.id, choice: .gnd(.applyFullValue))),
            wheelID: wheelID,
            generation: viewModel.ndWheelGeneration
        )
        let status = try XCTUnwrap(viewModel.movingWheelStatus)
        XCTAssertEqual(status.expandedLabel, "Lee GND 0.9 · OD 0.9 · Apply full value · 3 stops")
        XCTAssertEqual(status.contributionStops, 3, accuracy: 1e-9)
    }
}
