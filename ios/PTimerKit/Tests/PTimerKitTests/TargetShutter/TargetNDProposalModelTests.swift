// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

@MainActor
final class TargetNDProposalModelTests: XCTestCase {
    private func input(target: Double = 1024) -> TargetNDProposalInput {
        .init(cameraID: "a", baseSeconds: 1, targetSeconds: target, profile: nil,
              inventory: .empty, selectedSets: [], current: .init(standardSteps: [.init(stops: 0)]), settings: .init(), medium: .digital)
    }

    private func finishEvaluation(_ vm: ExposureCalculatorViewModel) async {
        for _ in 0..<100 where vm.targetNDProposalModel.session.phase == .evaluating {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func testLateWorkersCannotRestoreAnInvalidatedOrNewerOffer() {
        var completions: [(TargetNDSelectionResult) -> Void] = []
        let model = TargetNDProposalModel(evaluate: { _, complete in completions.append(complete); return {} })
        let old = input()
        model.begin(old); model.settle(old, filtersAreQuiet: true)
        XCTAssertEqual(model.session.phase, .evaluating)
        model.begin(input(target: 512)); model.settle(input(target: 512), filtersAreQuiet: true)
        completions[0](old.evaluate())
        XCTAssertEqual(model.session.phase, .evaluating)
        completions[1](input(target: 512).evaluate())
        XCTAssertEqual(model.session.phase, .result)
        model.invalidate()
        completions[1](input(target: 512).evaluate())
        XCTAssertEqual(model.session.phase, .idle)
    }

    func testSchedulerUsesReadinessAndIgnoresCancelledOlderTimeout() {
        var time = 10.0
        var actions: [() -> Void] = []
        var delays: [Double] = []
        let model = TargetNDProposalModel(now: { time }, schedule: { delay, action in
            delays.append(delay); actions.append(action); return {}
        }, evaluate: { input, complete in complete(input.evaluate()); return {} })
        let current = input()
        model.begin(current)
        model.preview(base: 2)
        XCTAssertEqual(model.session.input?.baseSeconds, 2)
        XCTAssertEqual(model.session.phase, .interacting)
        XCTAssertTrue(actions.isEmpty)
        model.settle(current, filtersAreQuiet: true)
        XCTAssertEqual(delays, [5])
        model.begin(current)
        time = 12
        model.settle(current, filtersAreQuiet: true)
        time = 15
        actions[0]()
        XCTAssertEqual(model.session.phase, .result)
        model.focusAction(true)
        time = 100
        actions[1]()
        XCTAssertEqual(model.session.phase, .result)
        model.focusAction(false)
        XCTAssertEqual(delays.last, 2)
        time = 102
        actions.last?()
        XCTAssertEqual(model.session.phase, .idle)
    }

    func testExternalInputChangeDuringMovementCannotOfferAtFinalCommit() {
        let model = TargetNDProposalModel()
        let old = input()
        model.begin(old)
        model.reconcile(input(target: 512))
        model.settle(input(target: 512), filtersAreQuiet: true)
        XCTAssertEqual(model.session.phase, .idle)
        model.begin(old)
        model.settle(old, filtersAreQuiet: false)
        XCTAssertEqual(model.session.phase, .idle)
    }

    func testRealViewModelSameValueAndApplyAreConnectedAndOneShot() async throws {
        let vm = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: RuntimeBackedTimerManaging())
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        vm.baseWheelInteractionBegan()
        vm.baseWheelPreview(2)
        XCTAssertEqual(vm.baseShutter, 1)
        XCTAssertEqual(vm.targetNDProposalModel.session.phase, .interacting)
        vm.baseWheelCommitted(1)
        await finishEvaluation(vm)
        XCTAssertEqual(vm.targetNDProposalModel.session.phase, .result)
        try vm.applyPendingTargetNDProposal().get()
        XCTAssertEqual(vm.ndStep.stops, 10)
        XCTAssertEqual(vm.baseShutter, 1)
        XCTAssertEqual(vm.targetShutterSeconds, 1024)
        XCTAssertEqual(vm.targetNDProposalModel.session.phase, .applied)
        guard case .failure = vm.applyPendingTargetNDProposal() else { return XCTFail("Duplicate commit") }
    }

    func testRealViewModelInvalidatesSettingsTargetCameraAndProgrammaticBase() async throws {
        for change in 0..<4 {
            let vm = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: RuntimeBackedTimerManaging())
            vm.baseShutter = 1
            vm.setTargetShutter(1024)
            vm.baseWheelInteractionBegan()
            vm.baseWheelCommitted(1)
        await finishEvaluation(vm)
            XCTAssertEqual(vm.targetNDProposalModel.session.phase, .result)
            switch change {
            case 0: vm.targetNDSettingsModel.settings.digital = .extended
            case 1: vm.setTargetShutter(512)
            case 2: vm.selectCameraSlot(try XCTUnwrap(vm.availableCameraSlots.first { $0 != vm.activeCameraSlotID }))
            default: vm.baseShutter = 2
            }
            XCTAssertEqual(vm.targetNDProposalModel.session.phase, .idle)
            guard case .failure = vm.applyPendingTargetNDProposal() else { return XCTFail("Stale action") }
            XCTAssertEqual(vm.ndStep.stops, 0)
        }
    }
}

@MainActor
extension TargetNDProposalModelTests {
    func testPresenterUsesInverseTotalAndSignedResidualWithVisibleSourceWarning() {
        let source = ReciprocitySourceProvenance(kind: .userDefined, authority: .userDefined, confidence: .high, publisher: "Test")
        let profile = ReciprocityProfile(id: "custom", name: "Custom", source: source,
                                        rules: [.formula(.init(formula: .init(coefficientSeconds: 1, exponent: 2, noCorrectionThroughSeconds: 1, sourceRangeThroughSeconds: 10)))])
        let input = TargetNDProposalInput(cameraID: "a", baseSeconds: 1, targetSeconds: 256, profile: profile,
                                          inventory: .empty, selectedSets: [], current: .init(standardSteps: [.init(stops: 0)]), settings: .init(), medium: .negative)
        var session = TargetNDProposalSession()
        session.begin(input)
        let token = session.settle(input, filtersAreQuiet: true)!
        session.complete(input.evaluate(), input: input, generation: token, now: 0)
        let en = TargetNDProposalPresenter.display(session, locale: Locale(identifier: "en"))
        XCTAssertEqual(en?.requiredText, "Required ND: 4.0 stops", "Inverse metered total, not log2(Target/Base) = 8.")
        XCTAssertEqual(en?.detailText, "ND 4 · Error +0.0 stop")
        XCTAssertEqual(en?.warningText, "Beyond source range")
        XCTAssertEqual(en?.canApply, true)
        XCTAssertEqual(en?.candidateTotalText, "4")
        XCTAssertEqual(en?.actionText, "Apply total 4 stops")
        XCTAssertEqual(TargetNDProposalPresenter.display(session, locale: Locale(identifier: "ko"))?.warningText, "출처 범위 밖")
    }

    func testPresenterExplainsNegativeAttenuationDuringLiveWithoutApply() {
        var session = TargetNDProposalSession()
        let input = TargetNDProposalInput(cameraID: "a", baseSeconds: 2, targetSeconds: 1, profile: nil,
                                          inventory: .empty, selectedSets: [], current: .init(standardSteps: [.init(stops: 0)]), settings: .init(), medium: .digital)
        session.begin(input)
        let display = TargetNDProposalPresenter.display(session, locale: Locale(identifier: "en"))
        XCTAssertEqual(display?.requiredText, "Attenuation cannot reach this Target")
        XCTAssertEqual(display?.canApply, false)
    }
}

@MainActor
extension TargetNDProposalModelTests {
    func testRealSchedulerExpiresFiveSecondsAfterBackgroundReadiness() async throws {
        let model = TargetNDProposalModel()
        let data = input()
        model.begin(data); model.settle(data, filtersAreQuiet: true)
        for _ in 0..<200 where model.session.phase == .evaluating { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(model.session.phase, .result)
        let now = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(try XCTUnwrap(model.session.expiresAt) - now, 5, accuracy: 0.1)
        try await Task.sleep(nanoseconds: 5_150_000_000)
        XCTAssertEqual(model.session.phase, .idle)
    }

    func testLateFocusCallbackCannotSuspendANewerOffer() {
        let model = TargetNDProposalModel(evaluate: { input, complete in complete(input.evaluate()); return {} })
        let data = input()
        model.begin(data); model.settle(data, filtersAreQuiet: true)
        let old = model.session.generation
        model.begin(data); model.settle(data, filtersAreQuiet: true)
        model.focusAction(true, generation: old)
        XCTAssertFalse(model.session.isActionFocused)
        XCTAssertNotNil(model.session.expiresAt)
    }
}
