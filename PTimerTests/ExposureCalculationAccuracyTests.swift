import XCTest
@testable import PTimer

final class ExposureCalculationAccuracyTests: XCTestCase {
    private let tolerance = 0.0001

    func testFullStopMatrixFromOneThirtiethMatchesCameraScale() throws {
        let cases: [(stop: Double, expected: Double)] = [
            (1, 1.0 / 15.0),
            (2, 1.0 / 8.0),
            (3, 1.0 / 4.0),
            (4, 1.0 / 2.0),
            (5, 1.0),
            (6, 2.0),
            (7, 4.0),
            (8, 8.0),
            (9, 15.0),
            (10, 30.0)
        ]

        for testCase in cases {
            let result = try calculate(baseShutter: 1.0 / 30.0, stop: testCase.stop)
            XCTAssertEqual(
                result,
                testCase.expected,
                accuracy: tolerance,
                "Expected 1/30 + \(Int(testCase.stop)) stop to match the camera full-stop scale."
            )
        }
    }

    func testCriticalCaseOneEighthPlusTenStopsReturnsOneHundredTwentyEightSeconds() throws {
        let result = try calculate(baseShutter: 1.0 / 8.0, stop: 10)

        XCTAssertEqual(result, 128.0, accuracy: tolerance)
    }

    func testBoundaryRangeCalculationsStayPositive() throws {
        XCTAssertTrue(try calculate(baseShutter: 1.0 / 8000.0, stop: 10) > 0)
        XCTAssertTrue(try calculate(baseShutter: 30.0, stop: 5) > 0)
    }

    func testRepeatedCalculationDoesNotDrift() throws {
        let first = try calculate(baseShutter: 1.0 / 30.0, stop: 6)

        for _ in 0..<100 {
            let repeated = try calculate(baseShutter: 1.0 / 30.0, stop: 6)
            XCTAssertEqual(repeated, first, accuracy: tolerance)
        }
    }

    func testNonExactRawResultMapsToNearestCameraFullStop() throws {
        let result = try calculate(baseShutter: 1.0 / 30.0, stop: 6)

        XCTAssertEqual(result, 2.0, accuracy: tolerance)
        XCTAssertNotEqual(result, 2.1, accuracy: tolerance)
    }

    private func calculate(baseShutter: Double, stop: Double) throws -> Double {
        let calculator = ExposureCalculator()
        let ndFactor = pow(2.0, stop)

        return try calculator.calculate(
            baseShutterSeconds: baseShutter,
            ndFactor: ndFactor
        )
    }
}
