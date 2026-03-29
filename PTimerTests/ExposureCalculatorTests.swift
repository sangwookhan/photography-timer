import XCTest
@testable import PTimer

final class ExposureCalculatorTests: XCTestCase {
    func testCalculateReturnsDeterministicShutter() {
        let calculator = ExposureCalculator()

        let result = calculator.calculate(
            baseShutterInput: "1/30",
            ndInput: "ND64"
        )

        switch result {
        case .success(let value):
            XCTAssertEqual(value.baseShutterSeconds, 1.0 / 30.0, accuracy: 0.0001)
            XCTAssertEqual(value.ndFactor, 64, accuracy: 0.0001)
            XCTAssertEqual(value.resultShutterSeconds, 64.0 / 30.0, accuracy: 0.0001)
        case .failure(let error):
            XCTFail("Expected valid result, got \(error)")
        }
    }

    func testCalculateRejectsNonPositiveInput() {
        let calculator = ExposureCalculator()

        let result = calculator.calculate(
            baseShutterInput: "0",
            ndInput: "-1"
        )

        XCTAssertEqual(result, .failure(.nonPositiveBaseShutter))
    }
}
