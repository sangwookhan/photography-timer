// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-STACK-008: the mixed-stack interaction has exactly one
/// stable status region. Content states replace or combine within one
/// value, a rejection replaces movement with its reason and the
/// unchanged total, a stack with a Filter Set wheel keeps a persistent
/// secondary source summary at idle, and a stale timer can never
/// replace newer content.
@MainActor
final class FilterStatusRegionTests: XCTestCase {
    private let total = NDStackTotalDisplayState(effectiveStep: NDStep(stops: 18), wheelCount: 3)
    private let moving = MovingWheelStatus(expandedLabel: "Lee GND 0.9 · OD 0.9 · Apply full value", contributionStops: 3)

    // MARK: Composition — one content, priority order

    func testMovingWheelCombinesExpandedInformationAndLiveTotalInOneContent() {
        let content = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total)
        XCTAssertEqual(content?.primaryText, "Lee GND 0.9 · OD 0.9 · Apply full value")
        XCTAssertEqual(content?.secondaryText, "Total 18 stops", "The trailing text is the localized total alone; the contribution lives in the leading detail.")
        XCTAssertEqual(content?.isHeld, true)
        XCTAssertEqual(content?.isWarning, false)
    }

    // MARK: One row in every state (FILTER-STACK-007/008)

    func testEveryStateIsLeadingTextPlusCompleteTotalWithFullAccessibilityText() {
        let longName = "Formatt-Hitech Firecrest Ultra 100mm"
        let summary = items([("Standard", nil), ("Lee holder", .mint), (longName, .blue)])
        let totalText = FilterStatusRegionPresenter.totalText(total)
        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: summary)
        let movingContent = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: summary)
        let browsing = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: longName, rejection: nil, total: total, idleSourceSummary: summary)
        let rejected = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: FilterRejectionNotice(sequence: 1, rejection: .exceedsTotalLimit), total: total, idleSourceSummary: summary)

        for (name, content) in [("idle", idle), ("moving", movingContent), ("browsing", browsing), ("rejection", rejected)] {
            let content = try? XCTUnwrap(content, name)
            // Exactly two texts: one leading, one trailing total. There
            // is no third field and no alternative layout for a state to
            // fall back to.
            XCTAssertEqual(content?.secondaryText, totalText, "\(name): the trailing text is exactly the localized total")
            XCTAssertNotNil(content?.primaryText, "\(name): the leading text carries the identity or reason")
            XCTAssertFalse(content?.secondaryText?.contains("+") ?? true, "\(name): the total never carries a contribution prefix")
            XCTAssertEqual(content?.accessibilityText, "\(content?.primaryText ?? "") · \(totalText)", "\(name): accessibility exposes the complete leading text and the total")
        }
        XCTAssertEqual(idle?.primaryText, "Standard · Lee holder · \(longName)")
        XCTAssertTrue(idle?.accessibilityText.contains(longName) ?? false, "The full long name stays available even when the row truncates it visually.")
        XCTAssertEqual(idle?.idleSourceSummary, summary)
        XCTAssertEqual(movingContent?.primaryText, moving.expandedLabel)
        XCTAssertEqual(rejected?.primaryText, "Exceeds 30 stops")
        XCTAssertEqual(rejected?.accessibilityText, "Exceeds 30 stops · Total 18 stops")

        let standardOnly = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total)
        XCTAssertNil(standardOnly?.primaryText)
        XCTAssertEqual(standardOnly?.accessibilityText, totalText)
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

    // MARK: Persistent idle source summary (spec revision 70da3d5b)

    private let nisi = FilterSetID(rawValue: "nisi")
    private let lee = FilterSetID(rawValue: "lee")

    private func name(_ source: FilterSource) -> String {
        switch source {
        case .standard: return "Standard"
        case .filterSet(let id): return id == nisi ? "NiSi kit" : "Lee holder"
        }
    }

    private func color(_ source: FilterSource) -> FilterSetColor? {
        switch source {
        case .standard: return nil
        case .filterSet(let id): return id == nisi ? .indigo : .teal
        }
    }

    private func items(_ texts: [(String, FilterSetColor?)]) -> [FilterStatusSourceSummaryItem] {
        texts.map { FilterStatusSourceSummaryItem(source: $0.1 == nil ? .standard : .filterSet(lee), name: $0.0, count: 1, color: $0.1) }
    }

    func testSourceSummaryListsEachSourceOnceInSettledOrderWithCountsAndSourceColors() {
        let wheels: [FilterWheel] = [
            FilterWheel(source: .filterSet(nisi), selection: .empty),
            FilterWheel(source: .filterSet(lee), selection: .empty),
            FilterWheel(source: .filterSet(lee), selection: .empty),
            .standard(NDStep(stops: 2)),
        ]
        XCTAssertEqual(FilterStatusRegionPresenter.sourceSummaryText(wheels: wheels, sourceName: name), "NiSi kit · Lee holder ×2 · Standard")
        let summary = FilterStatusRegionPresenter.sourceSummary(wheels: wheels, sourceName: name, sourceColor: color)
        XCTAssertEqual(summary?.map(\.text), ["NiSi kit", "Lee holder ×2", "Standard"])
        XCTAssertEqual(summary?.map(\.count), [1, 2, 1])
        XCTAssertEqual(summary?.map(\.color), [.indigo, .teal, nil], "Filter Sets carry their source color; Standard stays text only.")
        XCTAssertEqual(summary?.map(\.source), [.filterSet(nisi), .filterSet(lee), .standard])
        XCTAssertEqual(summary.map(FilterStatusRegionPresenter.summaryText), "NiSi kit · Lee holder ×2 · Standard")
        XCTAssertEqual(
            FilterStatusRegionPresenter.sourceSummaryText(wheels: [.standard(NDStep(stops: 2)), FilterWheel(source: .filterSet(lee), selection: .empty)], sourceName: name),
            "Standard · Lee holder"
        )
        XCTAssertEqual(
            FilterStatusRegionPresenter.sourceSummaryText(wheels: [FilterWheel(source: .filterSet(lee), selection: .empty)], sourceName: name),
            "Lee holder",
            "A single Filter Set wheel still identifies its source."
        )
        XCTAssertNil(
            FilterStatusRegionPresenter.sourceSummaryText(wheels: [.standard(NDStep(stops: 2)), .standard(NDStep(stops: 1))], sourceName: name),
            "A Standard-only stack keeps the existing ND status behavior."
        )
    }

    func testIdleSummaryIsPersistentAndSecondaryWhileStandardOnlyIdleIsUnchanged() {
        let nisiStandard = items([("NiSi kit", .indigo), ("Standard", nil)])
        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: nisiStandard)
        XCTAssertEqual(idle?.primaryText, "NiSi kit · Standard")
        XCTAssertEqual(idle?.secondaryText, "Total 18 stops")
        XCTAssertEqual(idle?.idleSourceSummary, nisiStandard, "The structured summary drives the one-row idle layout (sources leading, total trailing).")
        XCTAssertEqual(idle?.isHeld, true)
        XCTAssertEqual(idle?.isSecondaryEmphasis, true)
        XCTAssertEqual(idle?.isWarning, false)
        XCTAssertEqual(idle?.isPersistentIdle, true)

        // One Filter Set wheel: the total shows even below two wheels.
        let single = NDStackTotalDisplayState(effectiveStep: NDStep(stops: 3), wheelCount: 1)
        XCTAssertEqual(FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: single, idleSourceSummary: items([("Lee holder", .teal)]))?.secondaryText, "Total 3 stops")

        // Moving, browsing, and rejection outrank the summary at normal
        // emphasis and keep the two-line detailed form (no summary items).
        let movingContent = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: nisiStandard)
        XCTAssertEqual(movingContent?.primaryText, moving.expandedLabel)
        XCTAssertEqual(movingContent?.isSecondaryEmphasis, false)
        XCTAssertNil(movingContent?.idleSourceSummary)
        let browsing = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: "Lee holder", rejection: nil, total: total, idleSourceSummary: nisiStandard)
        XCTAssertEqual(browsing?.primaryText, "Lee holder")
        XCTAssertNil(browsing?.idleSourceSummary)
        let rejection = FilterRejectionNotice(sequence: 1, rejection: .exceedsTotalLimit)
        let rejected = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: rejection, total: total, idleSourceSummary: nisiStandard)
        XCTAssertEqual(rejected?.primaryText, "Exceeds 30 stops")
        XCTAssertEqual(rejected?.isSecondaryEmphasis, false)
        XCTAssertNil(rejected?.idleSourceSummary)

        // Standard-only: no summary, the previous unheld total.
        let standardOnly = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: nil)
        XCTAssertNil(standardOnly?.primaryText)
        XCTAssertEqual(standardOnly?.isHeld, false)
    }

    func testSummaryReturnsAfterTheIntervalFollowingSettlementAndImmediatelyAfterRejection() async {
        let controller = TransientStatusRegionController()
        controller.fadeDelay = 0.05
        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: items([("NiSi kit", .indigo), ("Standard", nil)]))
        controller.apply(idle)
        XCTAssertEqual(controller.visibleContent, idle, "The persistent summary shows at once from an empty region.")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.visibleContent, idle, "The persistent summary never fades.")

        // Movement replaces it immediately at normal emphasis.
        let held = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: items([("NiSi kit", .indigo), ("Standard", nil)]))
        controller.apply(held)
        XCTAssertEqual(controller.visibleContent, held)

        // Settlement: the expanded information lingers for the interval, then the summary returns.
        controller.apply(idle)
        XCTAssertEqual(controller.visibleContent, held, "The settled expanded information lingers.")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.visibleContent, idle, "The summary returns after the interval.")

        // Plus browsing settles the same way.
        let browsing = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: "Lee holder", rejection: nil, total: total, idleSourceSummary: items([("NiSi kit", .indigo), ("Standard", nil)]))
        controller.apply(browsing)
        controller.apply(idle)
        XCTAssertEqual(controller.visibleContent, browsing)
        controller.fireFadeIfPending()
        XCTAssertEqual(controller.visibleContent, idle)

        // A rejection has its own notice interval: the summary returns as soon as it clears.
        let rejection = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: FilterRejectionNotice(sequence: 1, rejection: .itemAlreadyMounted), total: total, idleSourceSummary: items([("NiSi kit", .indigo), ("Standard", nil)]))
        controller.apply(rejection)
        XCTAssertEqual(controller.visibleContent, rejection)
        controller.apply(idle)
        XCTAssertEqual(controller.visibleContent, idle)
    }

    func testNewMovementDuringTheLingerCancelsTheReturnToTheSummary() async {
        let controller = TransientStatusRegionController()
        controller.fadeDelay = 0.05
        let idle = FilterStatusRegionPresenter.content(moving: nil, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: items([("NiSi kit", .indigo)]))
        let held = FilterStatusRegionPresenter.content(moving: moving, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: items([("NiSi kit", .indigo)]))
        controller.apply(held)
        controller.apply(idle)
        let staleToken = controller.currentGeneration
        let secondMove = MovingWheelStatus(expandedLabel: "Big Stopper · ND1000 · 10 stops", contributionStops: 10)
        let heldAgain = FilterStatusRegionPresenter.content(moving: secondMove, browsingSourceName: nil, rejection: nil, total: total, idleSourceSummary: items([("NiSi kit", .indigo)]))
        controller.apply(heldAgain)
        controller.fireFadeIfPending(token: staleToken)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.visibleContent, heldAgain, "The earlier linger belongs to a superseded state.")
    }

    func testViewModelSourceSummaryFollowsAddRemoveDeleteRestoreAndSettledOrder() async throws {
        let sessionStore = InMemoryMixedSessionStore()
        let inventoryStore = InMemoryFilterInventoryStore()
        let inventory = FilterInventoryModel(store: inventoryStore)
        let nisiSet = try XCTUnwrap(inventory.createFilterSet(name: "NiSi kit", color: .red))
        let leeSet = try XCTUnwrap(inventory.createFilterSet(name: "Lee holder", color: .green))
        let nd1000 = FilterItem(name: "Big Stopper", behavior: .fixed(FilterRegisteredValue(value: 1000, unit: .filterFactor)))
        let nd8 = FilterItem(name: "ND8", behavior: .fixed(FilterRegisteredValue(value: 3, unit: .stops)))
        let cpl = FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2])))
        inventory.addItem(nd1000, to: nisiSet.id)
        inventory.addItem(nd8, to: leeSet.id)
        inventory.addItem(cpl, to: leeSet.id)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: inventory
        )
        viewModel.ndWheelReshapeDuration = 0
        XCTAssertNil(viewModel.filterSourceSummaryText, "Standard-only stacks keep the existing ND behavior.")
        viewModel.setNDFilterStep(NDStep(stops: 2), at: 0)

        viewModel.selectFilterSource(.filterSet(leeSet.id))
        viewModel.addFilterWheel()
        XCTAssertEqual(viewModel.filterSourceSummaryText, "Standard · Lee holder", "An Empty wheel already identifies its source.")
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: nd8.id, choice: .fixed)), at: 1)
        XCTAssertEqual(viewModel.filterSourceSummaryText, "Lee holder · Standard", "The summary follows the settled order.")
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: cpl.id, choice: .cplLoss(1))), at: 2)
        XCTAssertEqual(viewModel.filterSourceSummaryText, "Lee holder ×2 · Standard")

        viewModel.selectFilterSource(.filterSet(nisiSet.id))
        viewModel.addFilterWheel()
        viewModel.setWheelSelection(.item(FilterRowSelection(itemID: nd1000.id, choice: .fixed)), at: 3)
        XCTAssertEqual(viewModel.filterSourceSummaryText, "NiSi kit · Lee holder ×2 · Standard")
        XCTAssertEqual(viewModel.filterSourceSummary?.map(\.color), [.red, .green, nil], "Each Filter Set carries its own color; Standard none.")
        XCTAssertEqual(viewModel.filterSourceSummary?.map(\.count), [1, 2, 1])

        // Another camera has its own (Standard-only) identity; restore keeps camera 1's.
        viewModel.selectCameraSlot(.camera2)
        XCTAssertNil(viewModel.filterSourceSummaryText)
        viewModel.selectCameraSlot(.camera1)
        XCTAssertEqual(viewModel.filterSourceSummaryText, "NiSi kit · Lee holder ×2 · Standard")
        let restored = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            contextPersistenceStore: NoOpCalculatorContextStore(),
            cameraSlotSessionPersistenceStore: sessionStore,
            filterInventoryModel: FilterInventoryModel(store: inventoryStore)
        )
        XCTAssertEqual(restored.filterSourceSummaryText, "NiSi kit · Lee holder ×2 · Standard")

        // Rename follows; deleting a set removes its wheels from the summary.
        viewModel.renameFilterSet(id: leeSet.id, name: "Lee 100")
        XCTAssertEqual(viewModel.filterSourceSummaryText, "NiSi kit · Lee 100 ×2 · Standard")
        viewModel.deleteFilterSet(id: leeSet.id)
        XCTAssertEqual(viewModel.filterSourceSummaryText, "NiSi kit · Standard")
        // Removing the last Filter Set wheel returns to the Standard-only behavior.
        viewModel.setWheelSelection(.empty, at: 0)
        viewModel.cleanupEmptyFilterWheels()
        XCTAssertNil(viewModel.filterSourceSummaryText)
        XCTAssertEqual(viewModel.filterWheels, [.standard(NDStep(stops: 2))])
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
        XCTAssertEqual(content?.secondaryText, "Total 10 stops")
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

        // Live movement onto Apply full value on the settled wheel (the
        // GND's registered 3 stops lead Standard 0 after the commit).
        let wheelID = viewModel.ndFilterWheelIDs[0]
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
