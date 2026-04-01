import XCTest
@testable import PTimer

final class ExposureCalculatorTests: XCTestCase {
    func testCalculateRepresentativeExposureCases() throws {
        let calculator = ExposureCalculator()
        let cases: [(base: String, stop: Int, expectedBase: Double, expectedStop: Int, expectedResult: Double)] = [
            ("1/30", 6, 1.0 / 30.0, 6, 2),
            ("1/125", 3, 1.0 / 125.0, 3, 1.0 / 15.0),
            ("0.5", 10, 0.5, 10, 512)
        ]

        for testCase in cases {
            let baseShutter = try calculator.parseBaseShutter(testCase.base)
            let resultShutter = try calculator.calculate(
                baseShutterSeconds: baseShutter,
                stop: testCase.stop
            )

            let value = ExposureCalculationResult(
                baseShutterSeconds: baseShutter,
                stop: testCase.stop,
                resultShutterSeconds: resultShutter
            )

            XCTAssertEqual(value.baseShutterSeconds, testCase.expectedBase, accuracy: 0.0001)
            XCTAssertEqual(value.stop, testCase.expectedStop)
            XCTAssertEqual(value.resultShutterSeconds, testCase.expectedResult, accuracy: 0.0001)
        }
    }

    func testCalculateReturnsDeterministicShutter() throws {
        let calculator = ExposureCalculator()
        let baseShutter = try calculator.parseBaseShutter("1/30")
        let resultShutter = try calculator.calculate(
            baseShutterSeconds: baseShutter,
            stop: 6
        )

        XCTAssertEqual(baseShutter, 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(resultShutter, 2, accuracy: 0.0001)
    }

    func testStopBasedCalculationMatchesRepresentativeCases() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: 6),
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1.0 / 8.0, stop: 10),
            128,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1, stop: 0),
            1,
            accuracy: 0.0001
        )
    }

    func testCalculateRejectsNonPositiveInput() {
        let calculator = ExposureCalculator()

        XCTAssertThrowsError(try calculator.parseBaseShutter("0")) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .nonPositiveBaseShutter)
        }
    }

    func testCalculateRejectsEmptyAndInvalidInputs() {
        let calculator = ExposureCalculator()

        XCTAssertThrowsError(try calculator.parseBaseShutter("")) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .emptyBaseShutter)
        }
        XCTAssertThrowsError(try calculator.parseBaseShutter("abc")) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .invalidBaseShutter)
        }
        XCTAssertThrowsError(try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: -1)) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .nonPositiveND)
        }
    }

    func testParseBaseShutterSupportsFractionAndSecondsSuffix() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.parseBaseShutter("1/30"), 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.parseBaseShutter("2s"), 2, accuracy: 0.0001)
        XCTAssertEqual(try calculator.parseBaseShutter("0.5"), 0.5, accuracy: 0.0001)
    }

    func testStopBasedInterfaceHandlesLargeStops() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1, stop: 20), 1_048_576, accuracy: 0.0001)
    }

    func testStopBasedInterfaceRejectsNegativeNDStop() {
        let calculator = ExposureCalculator()

        XCTAssertThrowsError(try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: -1)) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .nonPositiveND)
        }
    }

    func testFormatShutterReturnsExpectedReadableStrings() {
        let calculator = ExposureCalculator()

        XCTAssertEqual(calculator.formatShutter(2), "2s")
        XCTAssertEqual(calculator.formatShutter(2.1), "2.1s")
        XCTAssertEqual(calculator.formatShutter(1.0 / 30.0), "1/30s")
        XCTAssertEqual(calculator.formatShutter(1.0 / 125.0), "1/125s")
    }

    func testSnapToFullStopClampsToCanonicalBounds() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0 / 8000.0, stop: 0), 1.0 / 8000.0, accuracy: 0.0001)
    }

    func testCameraFullStopBehaviorPreservesFifteenAndThirtySeconds() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 3), 8.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 4), 15.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 5), 30.0, accuracy: 0.0001)
    }

    func testLongExposureUsesExactDoublingBeyondThirtySeconds() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: 10), 30.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: 11), 64.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 5), 30.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 6), 64.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 7), 128.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.calculate(baseShutterSeconds: 1.0, stop: 8), 256.0, accuracy: 0.0001)
    }

    func test24StopFromOneSecond() throws {
        let calculator = ExposureCalculator()

        let result = try calculator.calculate(
            baseShutterSeconds: 1,
            stop: 24
        )

        XCTAssertEqual(result, pow(2.0, 24), accuracy: 0.0001)
    }

    func testLargeStopDoublingSequence() throws {
        let calculator = ExposureCalculator()

        var previous: Double = 30

        for stop in 6...12 {
            let result = try calculator.calculate(
                baseShutterSeconds: 1,
                stop: stop
            )

            XCTAssertEqual(result, previous * 2, accuracy: 0.0001)
            previous = result
        }
    }

    func testNoOverflowAtHighStops() throws {
        let calculator = ExposureCalculator()

        let result = try calculator.calculate(
            baseShutterSeconds: 1,
            stop: 24
        )

        XCTAssertTrue(result.isFinite)
        XCTAssertGreaterThan(result, 1_000_000)
    }

    func testTransitionStillValidWithHighStop() throws {
        let calculator = ExposureCalculator()

        let beforeTransition = try calculator.calculate(
            baseShutterSeconds: 1,
            stop: 5
        )

        let afterTransition = try calculator.calculate(
            baseShutterSeconds: 1,
            stop: 6
        )

        XCTAssertEqual(beforeTransition, 30, accuracy: 0.0001)
        XCTAssertEqual(afterTransition, 64, accuracy: 0.0001)
    }

    func testSubSecondToLargeStopChain() throws {
        let calculator = ExposureCalculator()

        let result = try calculator.calculate(
            baseShutterSeconds: 1.0 / 30.0,
            stop: 24
        )

        XCTAssertEqual(result, pow(2.0, 24) / 30.0, accuracy: 0.0001)
    }
}
