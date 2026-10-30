// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
import XCTest
import PTimerCore
@testable import PTimerKit

@MainActor
final class RequiredNDGuidanceTests: XCTestCase {
    func testReleaseTracksUntilFinalCommitAndRetainsOutgoingThroughCrossfade() {
        let model = RequiredNDGuidanceModel()
        model.begin(base: 1, target: 1024, profile: nil)
        model.settle(base: 2)
        XCTAssertEqual(model.phase, .tracking)
        model.release()
        model.update(base: 4)
        XCTAssertEqual(model.phase, .tracking)
        XCTAssertEqual(model.result, .value(stops: 8, beyondSourceRange: false))
        model.settle(base: 8)
        XCTAssertEqual(model.phase, .crossfading)
        XCTAssertEqual(model.result, .value(stops: 7, beyondSourceRange: false))
        model.update(base: 16)
        model.settle(base: 32)
        XCTAssertEqual(model.result, .value(stops: 7, beyondSourceRange: false))
        model.complete(.crossfading, token: model.generation)
        XCTAssertEqual(model.phase, .ordinary)
        XCTAssertNil(model.result)
        model.settle(base: 64)
        XCTAssertEqual(model.phase, .ordinary)
    }

    func testRetouchRejectsPreviousCrossfadeCompletion() {
        let model = RequiredNDGuidanceModel()
        model.begin(base: 1, target: 1024, profile: nil)
        model.release()
        model.settle(base: 1)
        let old = model.generation
        model.begin(base: 4, target: 1024, profile: nil)
        model.complete(.crossfading, token: old)
        XCTAssertEqual(model.phase, .tracking)
        XCTAssertEqual(model.result, .value(stops: 8, beyondSourceRange: false))
    }

    func testContextCancellationRejectsLateInputsAndCrossfadeCompletion() {
        for phase in [RequiredNDGuidanceModel.Phase.tracking, .crossfading] {
            let model = RequiredNDGuidanceModel()
            model.begin(base: 1, target: 1024, profile: nil)
            let token = model.generation
            if phase == .crossfading {
                model.release()
                model.settle(base: 1)
            }
            model.invalidate()
            model.update(base: 2)
            model.complete(.crossfading, token: token)
            XCTAssertNil(model.result)
            XCTAssertEqual(model.phase, .ordinary)
            XCTAssertNotEqual(model.generation, token)
        }
    }

    func testNumericWarningAndUnavailableShareSettlementCrossfade() throws {
        let source = try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first?.profiles.first?.source)
        let warningProfile = ReciprocityProfile(id: "warning", name: "Warning", source: source,
            rules: [.formula(.init(formula: .init(exponent: 2, noCorrectionThroughSeconds: 1, sourceRangeThroughSeconds: 2)))])
        for (target, profile) in [(1024.0, nil), (0.5, nil), (16.0, Optional(warningProfile))] {
            let model = RequiredNDGuidanceModel()
            model.begin(base: 1, target: target, profile: profile)
            let outgoing = model.result
            model.release()
            model.settle(base: 1)
            XCTAssertEqual(model.phase, .crossfading)
            XCTAssertEqual(model.result, outgoing)
            model.complete(.crossfading, token: model.generation)
            XCTAssertEqual(model.phase, .ordinary)
            XCTAssertNil(model.result)
        }
        XCTAssertEqual(RequiredNDGuidanceModel.crossfadeDuration, 0.5)
    }

    func testFacadeTracksInertiaAndFinalCommitStartsCrossfadeOnlyOnce() {
        let vm = makeViewModel()
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        vm.beginBaseShutterInteraction()
        vm.updateLiveBaseShutter(2)
        vm.releaseBaseShutterInteraction()
        let token = vm.requiredNDGuidanceGeneration
        XCTAssertEqual(vm.baseShutter, 1)
        XCTAssertEqual(vm.requiredNDGuidancePhase, .tracking)
        vm.updateLiveBaseShutter(4)
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "8")
        vm.baseShutter = 8
        vm.finishBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidancePhase, .crossfading)
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "7")
        vm.finishBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidanceGeneration, token)
        vm.completeRequiredNDTransition(.crossfading, token: token)
        vm.finishBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidancePhase, .ordinary)
        XCTAssertNil(vm.requiredNDGuidanceDisplayState)
    }

    func testRetouchReadsCurrentLiveBaseInsteadOfPreviousCommittedValue() {
        let vm = makeViewModel()
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        vm.beginBaseShutterInteraction()
        vm.releaseBaseShutterInteraction()
        vm.updateLiveBaseShutter(4)
        vm.beginBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "8")
        XCTAssertEqual(vm.requiredNDGuidancePhase, .tracking)
    }

    func testDisplayUsesDecimalStopsAndDistinctFailureReasons() {
        let whole = RequiredNDGuidanceDisplayState(result: .value(stops: 10, beyondSourceRange: false))
        let fraction = RequiredNDGuidanceDisplayState(result: .value(stops: 10.3, beyondSourceRange: false))
        XCTAssertEqual(whole.valueText, "10")
        XCTAssertEqual(fraction.valueText, "10.3")
        XCTAssertFalse(whole.label.contains(":"))
        let warning = RequiredNDGuidanceDisplayState(result: .value(stops: 10, beyondSourceRange: true))
        XCTAssertTrue(warning.isWarning)
        XCTAssertNotNil(warning.reason)
        let negative = RequiredNDGuidanceDisplayState(result: .unavailable(.negativeAttenuation))
        let inverse = RequiredNDGuidanceDisplayState(result: .unavailable(.noQuantifiedInverse))
        XCTAssertEqual(negative.valueText, "—")
        XCTAssertNotEqual(negative.reason, inverse.reason)
    }

    func testTargetConfirmationDoesNotActivateAndNDTargetCameraDisableInvalidate() {
        let vm = makeViewModel()
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        XCTAssertNil(vm.requiredNDGuidanceDisplayState)
        for invalidate in [
            { vm.setTargetShutter(1024) },
            { vm.ndWheelTouchBegan(wheelID: vm.ndFilterWheelIDs[0], generation: vm.ndWheelGeneration) },
            { vm.selectCameraSlot(.camera2) },
            { vm.showRequiredND = false },
        ] {
            vm.showRequiredND = true
            vm.setTargetShutter(1024)
            vm.beginBaseShutterInteraction()
            XCTAssertNotNil(vm.requiredNDGuidanceDisplayState)
            invalidate()
            XCTAssertNil(vm.requiredNDGuidanceDisplayState)
        }
    }

    func testGuidanceDoesNotMutateStackTargetOrStartTimers() {
        let vm = makeViewModel()
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        let wheels = vm.filterWheels
        vm.beginBaseShutterInteraction()
        vm.updateLiveBaseShutter(2)
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "9")
        XCTAssertEqual(vm.baseShutter, 1)
        XCTAssertEqual(vm.targetShutterSeconds, 1024)
        XCTAssertEqual(vm.filterWheels, wheels)
        XCTAssertTrue(vm.timers.isEmpty)
        vm.releaseBaseShutterInteraction()
        vm.baseShutter = 1
        vm.finishBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "10")
    }

    func testRunningTimerKeepsItsCapturedShotAndCompletesDuringGuidance() throws {
        let start = Date(timeIntervalSince1970: 100)
        let manager = RuntimeBackedTimerManaging(dateProvider: { start })
        let vm = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: manager)
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        vm.startTargetShutterTimer()
        let captured = try XCTUnwrap(vm.timers.first)
        let runtime = manager.timers
        vm.beginBaseShutterInteraction()
        vm.updateLiveBaseShutter(4)
        vm.releaseBaseShutterInteraction()
        vm.baseShutter = 4
        vm.finishBaseShutterInteraction()
        vm.completeRequiredNDTransition(.crossfading, token: vm.requiredNDGuidanceGeneration)
        XCTAssertEqual(manager.timers, runtime, "Guidance cannot pause, restart or replace a running timer")
        XCTAssertEqual(vm.timers.count, 1)
        XCTAssertEqual(vm.timers.first?.basisSummary, captured.basisSummary)
        manager.tick(now: start.addingTimeInterval(1024))
        XCTAssertEqual(manager.timers.first?.status, .completed)
        XCTAssertEqual(vm.timers.first?.id, captured.id)
        XCTAssertEqual(vm.timers.first?.duration, 1024)
        XCTAssertEqual(vm.timers.first?.basisSummary, captured.basisSummary)
    }

    func testLegacyPreferenceDefaultsOnAndNewPreferenceRoundTrips() throws {
        let old = try JSONDecoder().decode(PersistentDisplaySettings.self, from: Data("{\"ndNotationModeRaw\":\"od\"}".utf8))
        XCTAssertTrue(old.restoredShowRequiredND)
        let settings = PersistentDisplaySettings(ndNotationMode: .opticalDensity, showRequiredND: false)
        let restored = try JSONDecoder().decode(PersistentDisplaySettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(restored.restoredShowRequiredND)
        XCTAssertEqual(restored.restoredNDNotationMode, .opticalDensity)
    }

    func testAuxiliaryContributionIsIncludedInRequiredTotalWithoutChangingMounts() throws {
        let inventory = FilterInventoryModel()
        let set = try XCTUnwrap(inventory.createFilterSet(name: "Aux", color: .teal))
        let item = FilterItem(name: "Two stops", behavior: .effect(FilterExposureLoss(stops: 2)))
        inventory.addItem(item, to: set.id)
        let vm = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging(), filterInventoryModel: inventory)
        vm.assignAllFilterSetsAsCandidates()
        XCTAssertNil(vm.applyMounts([.mount(item, in: set)]))
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        vm.beginBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "10")
        XCTAssertEqual(vm.ndStackTotalDisplayState.totalStopsText, "2")
        XCTAssertEqual(vm.mountedAuxiliaryFilters.map(\.item.id), [item.id])
        inventory.renameFilterSet(id: set.id, name: "Changed")
        XCTAssertNil(vm.requiredNDGuidanceDisplayState)
    }

    func testSelectedAlternateIsUsedAndProfileChangeInvalidates() throws {
        let vm = makeViewModel()
        let film = try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first { $0.id == "kodak-tri-x-400" })
        let alternate = try XCTUnwrap(AlternateReciprocityModels.alternates(forFilmID: film.id).first { $0.source.authority != .unofficial })
        vm.selectPresetFilm(film)
        vm.selectProfileVariant(profileID: alternate.id)
        let target = try XCTUnwrap(ReciprocityCalculationPolicyEvaluator().evaluate(profile: alternate, meteredExposureSeconds: 16).correctedExposureSeconds)
        vm.baseShutter = 1
        vm.setTargetShutter(target)
        vm.beginBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "4")
        vm.selectProfileVariant(profileID: film.profiles[0].id)
        XCTAssertNil(vm.requiredNDGuidanceDisplayState)
    }

    func testDisabledPreferenceSurvivesNotationChangeCameraAndRelaunchWithoutTransientGuidance() {
        let store = RequiredNDSettingsMemoryStore()
        let first = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging(), displaySettingStore: store)
        first.showRequiredND = false
        first.ndNotationMode = .filterFactor
        first.selectCameraSlot(.camera2)
        XCTAssertFalse(first.showRequiredND)
        let restored = ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging(), displaySettingStore: store)
        XCTAssertFalse(restored.showRequiredND)
        XCTAssertEqual(restored.ndNotationMode, .filterFactor)
        restored.setTargetShutter(1024)
        restored.beginBaseShutterInteraction()
        XCTAssertNil(restored.requiredNDGuidanceDisplayState)
    }

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(calculator: ExposureCalculator(), timerManager: FakeTimerManaging())
    }
}

private final class RequiredNDSettingsMemoryStore: DisplaySettingStoring {
    var value: PersistentDisplaySettings?
    func loadSettings() -> PersistentDisplaySettings? { value }
    func saveSettings(_ settings: PersistentDisplaySettings) { value = settings }
    func clearSettings() { value = nil }
}
