import XCTest
@testable import PTimer

/// PR1 of B1 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`)
/// — direct unit tests for the newly extracted `CalculatorModel`.
/// These cover the calc slice in isolation; the legacy
/// `ExposureCalculatorViewModelTests` continue to cover the same
/// behavior end-to-end via the ViewModel surface.
final class CalculatorModelTests: XCTestCase {
    @MainActor
    func testDefaultInputsProduceFullStopSnappedResult() {
        let model = CalculatorModel(calculator: ExposureCalculator())

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

        // The overload is the path used by the legacy ViewModel for
        // the live-preview overlay (effectiveBaseShutter /
        // effectiveNDStop). It must NOT mutate stored inputs.
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

    // MARK: - Live preview overlay (B1 PR4c-2)

    @MainActor
    func testEffectiveBaseShutterFallsBackToCommittedValueWhenPreviewIsNil() {
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            baseShutterSeconds: 1.0 / 30.0,
            ndStop: 0
        )

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

        // Preview equal to committed clears the overlay (matches the
        // legacy ViewModel behavior where the wheel gesture's idle
        // state has the preview equal to the committed value).
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
