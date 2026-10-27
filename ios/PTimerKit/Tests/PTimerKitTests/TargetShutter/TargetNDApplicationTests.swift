// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

@MainActor
final class TargetNDApplicationTests: XCTestCase {
    private func model() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: RuntimeBackedTimerManaging(dateProvider: { Date(timeIntervalSince1970: 1_000) }))
    }

    func testApplyPreservesBaseTargetCamerasAndCapturedTimers() throws {
        let vm = model()
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        vm.startTargetShutterTimer()
        XCTAssertEqual(vm.timers.count, 1)
        let cameras = vm.cameraList
        let timers = vm.timers
        let snapshot = try XCTUnwrap(vm.targetNDProposalInput)
        let result = snapshot.evaluate()
        try vm.applyTargetNDProposal(snapshot, result: result).get()
        XCTAssertEqual(vm.ndStep.stops, 10)
        XCTAssertEqual(vm.baseShutter, 1)
        XCTAssertEqual(vm.targetShutterSeconds, 1024)
        XCTAssertEqual(vm.cameraList, cameras)
        XCTAssertEqual(vm.timers, timers)
        guard case .failure = vm.applyTargetNDProposal(snapshot, result: result) else { return XCTFail("Repeated Apply must not commit") }
    }

    func testChangedTargetOrDisabledSettingsRejectsWithoutMutation() throws {
        for disable in [false, true] {
            let vm = model()
            vm.baseShutter = 1
            vm.setTargetShutter(1024)
            let snapshot = try XCTUnwrap(vm.targetNDProposalInput)
            let result = snapshot.evaluate()
            if disable {
                vm.targetNDSettingsModel.settings.isEnabled = false
            } else {
                vm.setTargetShutter(512)
            }
            guard case .failure(.stale) = vm.applyTargetNDProposal(snapshot, result: result) else { return XCTFail("Expected stale rejection") }
            XCTAssertEqual(vm.ndStep.stops, 0)
            XCTAssertEqual(vm.baseShutter, 1)
        }
    }

    func testAtomicModelCommitRetainsExactAuxSetsAndPlusSource() throws {
        let nd = FilterItem(name: "ND6", behavior: .fixed(.init(value: 6, unit: .stops)))
        let aux = FilterItem(name: "CPL", behavior: .cpl(.init(fields: [1, 2])))
        let set = FilterSet(name: "Kit", color: .blue, items: [nd, aux])
        let inventory = FilterInventory(filterSets: [set])
        let calculator = CalculatorModel(calculator: ExposureCalculator())
        calculator.applyFilterInventory(inventory)
        let mounts = [MountedAuxiliaryFilter(filterSetID: set.id, itemID: aux.id, choice: .cplLoss(2))]
        XCTAssertNil(calculator.applyShootingFilters(selectedFilterSetIDs: [set.id], mounts: mounts))
        let source = calculator.lastFilterSource
        let selected = calculator.candidateFilterSetIDs
        let proposed = try XCTUnwrap(FilterStack.validated(wheels: [.init(source: .filterSet(set.id), selection: .item(.init(itemID: nd.id, choice: .fixed)))], auxiliaryFilters: mounts, inventory: inventory))
        XCTAssertTrue(calculator.applyTargetNDStack(proposed, orderingPolicy: .automatic))
        XCTAssertEqual(calculator.filterStack.auxiliaryFilters, mounts)
        XCTAssertEqual(calculator.candidateFilterSetIDs, selected)
        XCTAssertEqual(calculator.lastFilterSource, source)
        XCTAssertEqual(calculator.filterStack.effectiveStep.stops, 8)
        let withoutAux = FilterStack(standardSteps: [NDStep(stops: 10)])
        XCTAssertFalse(calculator.applyTargetNDStack(withoutAux, orderingPolicy: .automatic))
        XCTAssertEqual(calculator.filterStack.effectiveStep.stops, 8)
    }
    func testAllowanceSettingsAreGlobalAcrossCameraChanges() throws {
        let vm = model()
        let first = try XCTUnwrap(vm.activeCameraSlotID)
        let second = try XCTUnwrap(vm.availableCameraSlots.first { $0 != first })
        vm.targetNDSettingsModel.settings.negative = .extended
        vm.selectCameraSlot(second)
        XCTAssertEqual(vm.targetNDSettingsModel.settings.negative, .extended)
        vm.targetNDSettingsModel.settings.digital = .extended
        vm.selectCameraSlot(first)
        XCTAssertEqual(vm.targetNDSettingsModel.settings.negative, .extended)
        XCTAssertEqual(vm.targetNDSettingsModel.settings.digital, .extended)
    }

}
