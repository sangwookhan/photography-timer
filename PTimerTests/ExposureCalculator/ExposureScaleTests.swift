import XCTest
@testable import PTimer

/// Focused tests for the `ExposureScale` abstraction introduced by
/// PTIMER-79. Coverage:
///
/// 1. `.fullStop` reproduces the shipping ladders byte-for-byte.
/// 2. `.oneThirdStop` exposes a 1/3-stop densified ladder without
///    affecting the full-stop scale or the shipping calculator.
/// 3. `NDStep` represents fractional-stop values losslessly so future
///    PTIMER-80 calculation can route through it.
/// 4. `CalculatorModel`'s default scale is `.fullStop`, and the
///    integer ND picker bridge filters fractional steps out so the
///    `Int`-binding picker stays well-formed.
final class ExposureScaleTests: XCTestCase {

    // MARK: - Full-stop scale parity with shipping behavior

    func testDefaultScaleIsFullStop() {
        XCTAssertEqual(ExposureScale.default.mode, .fullStop)
    }

    func testFullStopShutterLadderMatchesShippingFullStopSpeeds() {
        let ladder = ExposureScale.fullStop.shutterSteps.map(\.seconds)
        XCTAssertEqual(ladder.count, ExposureCalculator.fullStopShutterSpeeds.count)
        for (lhs, rhs) in zip(ladder, ExposureCalculator.fullStopShutterSpeeds) {
            XCTAssertEqual(lhs, rhs, accuracy: ExposureCalculator.stabilityEpsilon)
        }
    }

    func testFullStopNDLadderSpansZeroThroughThirty() {
        let stops = ExposureScale.fullStop.ndSteps.map(\.stops)
        XCTAssertEqual(stops, (0...30).map { Double($0) })
        for step in ExposureScale.fullStop.ndSteps {
            XCTAssertTrue(step.isWholeStop)
            XCTAssertEqual(step.wholeStops, Int(step.stops))
        }
    }

    func testFullStopModeStopsPerStepIsOne() {
        XCTAssertEqual(ExposureScaleMode.fullStop.stopsPerStep, 1.0, accuracy: 1e-9)
    }

    // MARK: - One-third-stop scale representation

    func testOneThirdStopModeStopsPerStepIsOneThird() {
        XCTAssertEqual(
            ExposureScaleMode.oneThirdStop.stopsPerStep,
            1.0 / 3.0,
            accuracy: 1e-9
        )
    }

    func testOneThirdStopShutterLadderEmbedsFullStopBoundaries() {
        let oneThirdLadder = ExposureScale.oneThirdStop.shutterSteps.map(\.seconds)

        for fullStopValue in ExposureCalculator.fullStopShutterSpeeds {
            XCTAssertTrue(
                oneThirdLadder.contains { abs($0 - fullStopValue) <= 1e-9 },
                "1/3-stop shutter ladder must include full-stop value \(fullStopValue)"
            )
        }
    }

    func testOneThirdStopShutterLadderDensifiesByExactlyTwoStepsBetweenFullStops() {
        let ladder = ExposureScale.oneThirdStop.shutterSteps.map(\.seconds)
        let fullStopCount = ExposureCalculator.fullStopShutterSpeeds.count
        // (fullStopCount - 1) gaps × 2 inserted steps + the full-stop
        // anchors themselves.
        XCTAssertEqual(ladder.count, fullStopCount * 3 - 2)
    }

    func testOneThirdStopShutterLadderUsesGeometricMeanRatios() {
        let ladder = ExposureScale.oneThirdStop.shutterSteps.map(\.seconds)
        let oneThirdRatio = pow(2.0, 1.0 / 3.0)
        let twoThirdsRatio = pow(2.0, 2.0 / 3.0)

        // Pick the well-known 1/30-second neighborhood as a sanity
        // check: its 1/3-stop neighbors are 1/30 · 2^(1/3) and
        // 1/30 · 2^(2/3), regardless of where the ladder snaps next.
        guard let baseIndex = ladder.firstIndex(where: { abs($0 - 1.0 / 30.0) <= 1e-9 }) else {
            XCTFail("1/3-stop ladder is missing the 1/30s anchor")
            return
        }

        XCTAssertLessThan(baseIndex + 2, ladder.count)
        XCTAssertEqual(ladder[baseIndex + 1], (1.0 / 30.0) * oneThirdRatio, accuracy: 1e-9)
        XCTAssertEqual(ladder[baseIndex + 2], (1.0 / 30.0) * twoThirdsRatio, accuracy: 1e-9)
    }

    func testOneThirdStopNDLadderIncludesFractionalStops() {
        let oneThirdNDStops = ExposureScale.oneThirdStop.ndSteps

        // Whole-stop boundaries 0…30 must appear.
        for whole in 0...30 {
            XCTAssertTrue(
                oneThirdNDStops.contains { $0.wholeStops == whole },
                "1/3-stop ND ladder must include whole stop \(whole)"
            )
        }

        // The first fractional steps land at 1/3 and 2/3.
        let fractional = oneThirdNDStops.filter { $0.wholeStops == nil }
        XCTAssertFalse(fractional.isEmpty)
        XCTAssertEqual(fractional[0].stops, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(fractional[1].stops, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertNil(fractional[0].wholeStops)
        XCTAssertNil(fractional[1].wholeStops)
    }

    func testOneThirdStopNDLadderHasThreeStepsPerWholeStopExceptTheLast() {
        let count = ExposureScale.oneThirdStop.ndSteps.count
        // Whole 0…30 contributes 31 anchors; gaps 0→30 is 30, each
        // adding two fractional steps. 31 + 30·2 = 91.
        XCTAssertEqual(count, 31 + 30 * 2)
    }

    // MARK: - NDStep fractional representation

    func testNDStepWholeStopsRoundTripsForIntegerValues() {
        let zero = NDStep(stops: 0)
        let three = NDStep(stops: 3)
        XCTAssertTrue(zero.isWholeStop)
        XCTAssertEqual(zero.wholeStops, 0)
        XCTAssertTrue(three.isWholeStop)
        XCTAssertEqual(three.wholeStops, 3)
    }

    func testNDStepWholeStopsIsNilForFractionalValues() {
        let oneThird = NDStep(stops: 1.0 / 3.0)
        let twoThirds = NDStep(stops: 2.0 / 3.0)
        let oneAndOneThird = NDStep(stops: 1.0 + 1.0 / 3.0)
        XCTAssertFalse(oneThird.isWholeStop)
        XCTAssertNil(oneThird.wholeStops)
        XCTAssertFalse(twoThirds.isWholeStop)
        XCTAssertNil(twoThirds.wholeStops)
        XCTAssertFalse(oneAndOneThird.isWholeStop)
        XCTAssertNil(oneAndOneThird.wholeStops)
    }

    func testNDStepFactoryProducesWholeStopEntry() {
        let step = ExposureScale.ndStep(forWholeStops: 6)
        XCTAssertEqual(step.stops, 6.0, accuracy: 1e-9)
        XCTAssertEqual(step.wholeStops, 6)
    }

    // MARK: - CalculatorModel integration with the abstraction

    @MainActor
    func testCalculatorModelDefaultsToFullStopScale() {
        let model = CalculatorModel(calculator: ExposureCalculator())
        XCTAssertEqual(model.exposureScale.mode, .fullStop)

        // Picker bridges return the full-stop ladders verbatim so the
        // shipping picker behavior is preserved.
        XCTAssertEqual(model.pickerShutterStepSeconds, ExposureCalculator.fullStopShutterSpeeds)
        XCTAssertEqual(model.pickerWholeNDStops, Array(0...30))
    }

    @MainActor
    func testCalculatorModelAcceptsAlternativeScaleWithoutMutatingDefaultBehavior() {
        let oneThirdModel = CalculatorModel(
            calculator: ExposureCalculator(),
            exposureScale: .oneThirdStop
        )
        XCTAssertEqual(oneThirdModel.exposureScale.mode, .oneThirdStop)
        XCTAssertEqual(
            oneThirdModel.pickerShutterStepSeconds.count,
            ExposureScale.oneThirdStop.shutterSteps.count
        )
        // The integer-ND picker bridge filters fractional steps so the
        // legacy `Int` binding stays well-formed.
        XCTAssertEqual(oneThirdModel.pickerWholeNDStops, Array(0...30))

        // A second model built without a scale override still shows
        // full-stop behavior — proving scales are per-instance, not
        // global.
        let defaultModel = CalculatorModel(calculator: ExposureCalculator())
        XCTAssertEqual(defaultModel.exposureScale.mode, .fullStop)
    }

    @MainActor
    func testCalculatorModelStaticShutterSpeedsMatchDefaultScale() {
        // The legacy static (`CalculatorModel.shutterSpeeds`) is now
        // sourced from `ExposureScale.default`. Existing call sites
        // (the screen, the persistence sanitizer) must keep seeing the
        // same full-stop ladder.
        XCTAssertEqual(CalculatorModel.shutterSpeeds, ExposureCalculator.fullStopShutterSpeeds)
    }

    // MARK: - Current calculation behavior is unchanged

    func testFullStopScaleDoesNotChangeCalculatorOutput() throws {
        // Sanity check that introducing the abstraction left the calc
        // engine alone. Cases lifted from `ExposureCalculatorTests` so
        // any drift would surface here too.
        let calculator = ExposureCalculator()
        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: 6),
            2,
            accuracy: 1e-4
        )
        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1.0, stop: 5),
            30,
            accuracy: 1e-4
        )
        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1.0, stop: 6),
            64,
            accuracy: 1e-4
        )
    }
}
