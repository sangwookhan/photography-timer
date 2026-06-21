// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Direct unit tests for `CalculatorModel`.
/// These cover the calculation slice in isolation; integration tests
/// continue to cover end-to-end behavior through the view-model facade.
final class CalculatorModelTests: XCTestCase {
    @MainActor
    func testDefaultInputsProduceFullStopSnappedResult() {
        let model = CalculatorModel(calculator: ExposureCalculator())
        model.scaleMode = .fullStop

        guard case .success(let result) = model.calculationResult else {
            XCTFail("Default inputs should produce a calculation success.")
            return
        }

        XCTAssertEqual(result.baseShutterSeconds, 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(result.stop, 0)
        // 0 ND stops snaps the base back to itself within the
        // full-stop table.
        XCTAssertEqual(result.resultShutterSeconds, 1.0 / 30.0, accuracy: 1e-9)
    }

    @MainActor
    func testNDStopChangeUpdatesCalculationResult() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        model.ndStop = 3

        guard case .success(let result) = model.calculationResult else {
            XCTFail("3 ND stops on 1/30 should succeed.")
            return
        }

        XCTAssertEqual(result.stop, 3)
        // 1/30 * 2^3 = 8/30 ≈ 0.2666… → snaps to 1/4 (0.25) — the
        // nearest entry in `fullStopShutterSpeeds`.
        XCTAssertEqual(result.resultShutterSeconds, 1.0 / 4.0, accuracy: 1e-9)
    }

    @MainActor
    func testBaseShutterChangePropagatesToCalculationResult() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        model.baseShutterSeconds = 1.0

        guard case .success(let result) = model.calculationResult else {
            XCTFail("1s base shutter with 0 ND should succeed.")
            return
        }

        XCTAssertEqual(result.baseShutterSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.resultShutterSeconds, 1.0, accuracy: 1e-9)
    }

    @MainActor
    func testNonPositiveBaseShutterSurfacesAsFailure() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        guard case .failure(let error) = model.calculationResult else {
            XCTFail("Zero base shutter must surface as a failure.")
            return
        }

        XCTAssertEqual(error, .nonPositiveBaseShutter)
    }

    @MainActor
    func testCalculateOverloadDoesNotMutateStoredInputs() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        // This overload serves the live-preview overlay
        // (effectiveBaseShutter / effectiveNDStop) and must NOT mutate
        // stored inputs.
        let preview = model.calculate(baseShutterSeconds: 1.0 / 60.0, ndStop: 6)

        XCTAssertEqual(model.baseShutterSeconds, 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(model.ndStop, 0)

        guard case .success(let previewResult) = preview else {
            XCTFail("Preview calculation should succeed.")
            return
        }

        XCTAssertEqual(previewResult.baseShutterSeconds, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(previewResult.stop, 6)
    }

    // MARK: - Live preview overlay

    @MainActor
    func testEffectiveBaseShutterFallsBackToCommittedValueWhenPreviewIsNil() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        XCTAssertNil(model.liveBaseShutter)
        XCTAssertEqual(model.effectiveBaseShutter, 1.0 / 30.0, accuracy: 1e-9)

        XCTAssertNil(model.liveNDStop)
        XCTAssertEqual(model.effectiveNDStop, 0)
    }

    @MainActor
    func testUpdateLivePreviewSetsOverlayWhenDifferentFromCommitted() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        model.updateLiveBaseShutter(1.0 / 60.0)
        model.updateLiveNDStop(6)

        XCTAssertEqual(model.liveBaseShutter, 1.0 / 60.0)
        XCTAssertEqual(model.liveNDStop, 6)
        XCTAssertEqual(model.effectiveBaseShutter, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(model.effectiveNDStop, 6)
    }

    @MainActor
    func testUpdateLivePreviewClearsOverlayWhenEqualToCommitted() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        // Preview equal to committed clears the overlay so wheel-gesture
        // idle state does not keep transient preview values.
        model.updateLiveBaseShutter(1.0 / 30.0)
        model.updateLiveNDStop(0)

        XCTAssertNil(model.liveBaseShutter)
        XCTAssertNil(model.liveNDStop)
    }

    @MainActor
    func testClearLivePreviewExplicitlyDropsOverlay() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )
        model.scaleMode = .fullStop

        model.updateLiveBaseShutter(1.0 / 60.0)
        model.updateLiveNDStop(6)
        model.clearLiveBaseShutterPreview()
        model.clearLiveNDStopPreview()

        XCTAssertNil(model.liveBaseShutter)
        XCTAssertNil(model.liveNDStop)
        XCTAssertEqual(model.effectiveBaseShutter, 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(model.effectiveNDStop, 0)
    }
}
