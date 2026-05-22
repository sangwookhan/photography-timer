import XCTest
@testable import PTimer

final class ExposureCalculatorTests: XCTestCase {
    private struct ExposureCase {
        let base: String
        let stop: Int
        let expectedBase: Double
        let expectedStop: Int
        let expectedResult: Double
    }

    func testCalculateRepresentativeExposureCases() throws {
        let calculator = ExposureCalculator()
        let cases: [ExposureCase] = [
            .init(base: "1/30", stop: 6, expectedBase: 1.0 / 30.0, expectedStop: 6, expectedResult: 2),
            .init(base: "1/125", stop: 3, expectedBase: 1.0 / 125.0, expectedStop: 3, expectedResult: 1.0 / 15.0),
            .init(base: "0.5", stop: 10, expectedBase: 0.5, expectedStop: 10, expectedResult: 512),
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

    func testFormatShutterReturnsExpectedReadableStrings() {
        let calculator = ExposureCalculator()

        XCTAssertEqual(calculator.formatShutter(2), "2s")
        XCTAssertEqual(calculator.formatShutter(2.1), "2.1s")
        XCTAssertEqual(calculator.formatShutter(1.0 / 30.0), "1/30s")
        XCTAssertEqual(calculator.formatShutter(1.0 / 125.0), "1/125s")
    }

    func testFormatTimeDisplayReturnsExpectedReadableStrings() {
        let calculator = ExposureCalculator()
        XCTAssertEqual(calculator.formatTimeDisplay(0), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(calculator.formatTimeDisplay(-3), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(calculator.formatTimeDisplay(0.125), TimeDisplay(primary: "0.125s", secondary: "0.125s"))
        XCTAssertEqual(calculator.formatTimeDisplay(12.345), TimeDisplay(primary: "12.345s", secondary: "12.345s"))
        XCTAssertEqual(calculator.formatTimeDisplay(128), TimeDisplay(primary: "02:08", secondary: "128s"))
        XCTAssertEqual(calculator.formatTimeDisplay(3728), TimeDisplay(primary: "01:02:08", secondary: "3728s"))
        XCTAssertEqual(calculator.formatTimeDisplay(90_000), TimeDisplay(primary: "1d 01:00:00", secondary: "90000s"))
        XCTAssertEqual(calculator.formatTimeDisplay(2_592_000), TimeDisplay(primary: "1mo 00:00:00", secondary: "2592000s"))
        XCTAssertEqual(calculator.formatTimeDisplay(2_766_245), TimeDisplay(primary: "1mo 2d 00:24:05", secondary: "2766245s"))
        XCTAssertEqual(calculator.formatTimeDisplay(31_536_000), TimeDisplay(primary: "1y 00:00:00", secondary: "31536000s"))
        XCTAssertEqual(calculator.formatTimeDisplay(128.25), TimeDisplay(primary: "02:08.250", secondary: "128.25s"))
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

        var previous: Double = 64

        for stop in 7...12 {
            let result = try calculator.calculate(
                baseShutterSeconds: 1,
                stop: stop
            )

            XCTAssertEqual(result, previous * 2, accuracy: 0.0001)
            previous = result
        }
    }

    func testSubSecondToLargeStopChain() throws {
        let calculator = ExposureCalculator()

        let result = try calculator.calculate(
            baseShutterSeconds: 1.0 / 30.0,
            stop: 24
        )

        XCTAssertEqual(result, 524_288, accuracy: 0.0001)
    }
}
