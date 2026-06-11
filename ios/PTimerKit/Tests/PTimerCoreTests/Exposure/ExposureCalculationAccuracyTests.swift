import XCTest
import PTimerCore

final class ExposureCalculationAccuracyTests: XCTestCase {
    private let tolerance = 0.0001

    func testFullStopMatrixFromOneThirtiethMatchesCameraScale() throws {
        let cases: [(stop: Int, expected: Double)] = [
            (1, 1.0 / 15.0),
            (2, 1.0 / 8.0),
            (3, 1.0 / 4.0),
            (4, 1.0 / 2.0),
            (5, 1.0),
            (6, 2.0),
            (7, 4.0),
            (8, 8.0),
            (9, 15.0),
            (10, 30.0),
        ]

        for testCase in cases {
            let result = try calculate(baseShutter: 1.0 / 30.0, stop: testCase.stop)
            XCTAssertEqual(
                result,
                testCase.expected,
                accuracy: tolerance,
                "Expected 1/30 + \(testCase.stop) stop to match the camera full-stop scale."
            )
        }
    }

    func testCriticalCaseOneEighthPlusTenStopsReturnsOneHundredTwentyEightSeconds() throws {
        let result = try calculate(baseShutter: 1.0 / 8.0, stop: 10)

        XCTAssertEqual(result, 128.0, accuracy: tolerance)
    }

    func testBoundaryValuesClampToCanonicalRange() throws {
        XCTAssertEqual(try calculate(baseShutter: 1.0 / 10000.0, stop: 0), 1.0 / 8000.0, accuracy: tolerance)
    }

    func testOneSecondTransitionsFromCameraStopsToExactDoubling() throws {
        XCTAssertEqual(try calculate(baseShutter: 1.0, stop: 3), 8.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0, stop: 4), 15.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0, stop: 5), 30.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0 / 30.0, stop: 10), 30.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0 / 30.0, stop: 11), 64.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0, stop: 6), 64.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0, stop: 7), 128.0, accuracy: tolerance)
        XCTAssertEqual(try calculate(baseShutter: 1.0, stop: 20), 1_048_576.0, accuracy: tolerance)
    }

    func testNoIntermediateSnapDriftAbove30() throws {
        let calculator = ExposureCalculator()

        let base = 1.0 / 30.0
        let result11 = try calculator.calculate(baseShutterSeconds: base, stop: 11)
        let result12 = try calculator.calculate(baseShutterSeconds: base, stop: 12)

        XCTAssertEqual(result12, result11 * 2, accuracy: tolerance)
    }

    func testDoesNotSnapToNearestPowerOfTwo() throws {
        let calculator = ExposureCalculator()

        let base = 1.0 / 30.0
        let stop = 11
        let raw = base * pow(2.0, Double(stop))

        let result = try calculator.calculate(
            baseShutterSeconds: base,
            stop: stop
        )

        XCTAssertEqual(result, 64, accuracy: tolerance)
        XCTAssertTrue(result < raw)
    }

    func testHighStopDoesNotSnap() throws {
        let calculator = ExposureCalculator()

        let result = try calculator.calculate(
            baseShutterSeconds: 1.0,
            stop: 24
        )

        XCTAssertEqual(result, pow(2.0, 24), accuracy: tolerance)
    }

    func testResultMonotonicIncreaseAcrossStops() throws {
        var previous = -Double.infinity

        for stop in 0...15 {
            let result = try calculate(baseShutter: 1.0 / 30.0, stop: stop)
            XCTAssertGreaterThan(result, previous)
            previous = result
        }
    }

    func testExactPowerOfTwoSequenceFromOneSecond() throws {
        var previous = try calculate(baseShutter: 1.0, stop: 6)

        for stop in 7...15 {
            let result = try calculate(baseShutter: 1.0, stop: stop)
            XCTAssertEqual(result, previous * 2, accuracy: tolerance)
            previous = result
        }
    }

    func testInverseConsistencyUsingReconstructedStops() throws {
        let cases: [(base: Double, stop: Int)] = [
            (1.0, 6),
            (1.0, 10),
            (1.0, 20),
            (1.0 / 8.0, 10),
        ]

        for testCase in cases {
            let result = try calculate(baseShutter: testCase.base, stop: testCase.stop)
            let reconstructed = log2(result / testCase.base)

            XCTAssertEqual(
                reconstructed,
                Double(testCase.stop),
                accuracy: tolerance,
                "Expected reconstructed stop to stay stable for base \(testCase.base) stop \(testCase.stop)."
            )
        }
    }

    private func calculate(baseShutter: Double, stop: Int) throws -> Double {
        let calculator = ExposureCalculator()

        return try calculator.calculate(
            baseShutterSeconds: baseShutter,
            stop: stop
        )
    }

    func testInverseConsistencyAtSnapBoundary() throws {
        let base = 1.0 / 30.0
        let stop = 10

        let result = try calculate(baseShutter: base, stop: stop)
        let reconstructed = log2(result / base)

        XCTAssertEqual(result, 30.0, accuracy: tolerance)
        XCTAssertLessThan(reconstructed, Double(stop))
        XCTAssertGreaterThan(reconstructed, Double(stop) - 0.25)
    }
}
