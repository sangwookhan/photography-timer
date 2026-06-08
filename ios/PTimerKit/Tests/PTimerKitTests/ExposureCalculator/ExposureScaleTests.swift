import XCTest
import PTimerKit
import PTimerCore

/// Focused tests for the `ExposureScale` abstraction. Coverage:
///
/// 1. `.fullStop` (the reserved scale, retained on the model for
///    tests and the future Settings preference) reproduces the
///    legacy ladders byte-for-byte.
/// 2. `.oneThirdStop` (the shipping calculator scale) pairs the
///    1/3-stop densified shutter ladder with the **whole-stop** ND
///    ladder; one-third-stop applies to the Base Shutter only, so
///    the shipping ND picker enumerates `0…30` whole stops in
///    every shipping mode.
/// 3. `NDStep` represents fractional-stop values losslessly as
///    reserved domain infrastructure so a future custom /
///    variable-ND workflow can round-trip via `thirdStopCount`
///    rather than `Double` drift; the shipping ND picker does not
///    enumerate fractional stops.
/// 4. `CalculatorModel`'s default scale is `.oneThirdStop`,
///    matching the shipping calculator UI.
final class ExposureScaleTests: XCTestCase {

    // MARK: - Default scale is the shipping one-third-stop scale

    func testDefaultScaleIsOneThirdStop() {
        // The shipping calculator scale is one-third-stop per
        // docs/specs/Calculator.md §1.4. The full-stop scale is kept
        // on the model only for tests and the future Settings
        // preference.
        XCTAssertEqual(ExposureScale.default.mode, .oneThirdStop)
    }

    // MARK: - Reserved full-stop scale parity

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

    func testOneThirdStopNDLadderIsWholeStopOnly() {
        // Per docs/specs/Calculator.md §2.2: in the shipping product
        // one-third-stop applies to the **shutter** ladder only; the
        // ND picker stays whole-stop because real-world fixed ND
        // filters are sold in whole-stop strengths. Fractional ND
        // domain primitives (`NDStep.thirdStopCount`,
        // `fromThirdStopCount`) are retained as reserved
        // infrastructure but shall never appear as shipping ND
        // options.
        let ndSteps = ExposureScale.oneThirdStop.ndSteps

        XCTAssertEqual(ndSteps.count, 31)
        XCTAssertEqual(ndSteps.map(\.stops), (0...30).map { Double($0) })
        XCTAssertTrue(
            ndSteps.allSatisfy { $0.isWholeStop },
            "Shipping 1/3-stop scale ND ladder must not enumerate fractional stops"
        )

        // The shipping ND ladder is identical to the reserved
        // full-stop scale's ND ladder so a future Settings flip
        // between scales does not reshuffle the ND wheel.
        XCTAssertEqual(
            ndSteps.map(\.stops),
            ExposureScale.fullStop.ndSteps.map(\.stops)
        )
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
    func testCalculatorModelDefaultsToOneThirdStopScale() {
        let model = CalculatorModel(calculator: ExposureCalculator())
        XCTAssertEqual(model.exposureScale.mode, .oneThirdStop)

        // Shipping picker bridges: the 1/3-stop densified shutter
        // ladder is paired with the whole-stop `[0, 30]` ND ladder,
        // so the calculator surfaces both pickers without any UI
        // flip. One-third-stop applies to the shutter ladder only.
        XCTAssertEqual(
            model.pickerShutterStepSeconds.count,
            ExposureScale.oneThirdStop.shutterSteps.count
        )
        // The integer-ND picker bridge surfaces the same shipping
        // whole-stop ladder for any caller still bound to Int.
        XCTAssertEqual(model.pickerWholeNDStops, Array(0...30))
    }

    @MainActor
    func testCalculatorModelAcceptsReservedFullStopScale() {
        // The reserved full-stop scale is still constructible from a
        // test/Settings call site even though the shipping default is
        // 1/3 stop. Proves scales are per-instance, not global, and
        // both ladders behave correctly under the same model.
        let fullStopModel = CalculatorModel(
            calculator: ExposureCalculator(),
            exposureScale: .fullStop
        )
        XCTAssertEqual(fullStopModel.exposureScale.mode, .fullStop)
        XCTAssertEqual(fullStopModel.pickerShutterStepSeconds, ExposureCalculator.fullStopShutterSpeeds)
        XCTAssertEqual(fullStopModel.pickerWholeNDStops, Array(0...30))

        let defaultModel = CalculatorModel(calculator: ExposureCalculator())
        XCTAssertEqual(defaultModel.exposureScale.mode, .oneThirdStop)
    }

    @MainActor
    func testCalculatorModelStaticShutterSpeedsRemainFullStopForLegacyCallers() {
        // The legacy static (`CalculatorModel.shutterSpeeds`) is the
        // 19-value full-stop ladder — kept stable for the persistence
        // sanitizer and any other legacy caller. The shipping picker
        // reads `pickerShutterStepSeconds` instead.
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
