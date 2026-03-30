import XCTest
@testable import PTimer

final class ExposureCalculatorTests: XCTestCase {
    func testCalculateRepresentativeExposureCases() {
        let calculator = ExposureCalculator()
        let cases: [(base: String, nd: String, expectedBase: Double, expectedND: Double, expectedResult: Double)] = [
            ("1/30", "ND64", 1.0 / 30.0, 64, 64.0 / 30.0),
            ("1/125", "8", 1.0 / 125.0, 8, 8.0 / 125.0),
            ("0.5", "ND1000", 0.5, 1000, 500)
        ]

        for testCase in cases {
            let result = calculator.calculate(
                baseShutterInput: testCase.base,
                ndInput: testCase.nd
            )

            switch result {
            case .success(let value):
                XCTAssertEqual(value.baseShutterSeconds, testCase.expectedBase, accuracy: 0.0001)
                XCTAssertEqual(value.ndFactor, testCase.expectedND, accuracy: 0.0001)
                XCTAssertEqual(value.resultShutterSeconds, testCase.expectedResult, accuracy: 0.0001)
            case .failure(let error):
                XCTFail("Expected valid result for \(testCase.base), \(testCase.nd), got \(error)")
            }
        }
    }

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

    func testCalculateRejectsEmptyAndInvalidInputs() {
        let calculator = ExposureCalculator()

        XCTAssertEqual(
            calculator.calculate(baseShutterInput: "", ndInput: "ND64"),
            .failure(.emptyBaseShutter)
        )
        XCTAssertEqual(
            calculator.calculate(baseShutterInput: "abc", ndInput: "ND64"),
            .failure(.invalidBaseShutter)
        )
        XCTAssertEqual(
            calculator.calculate(baseShutterInput: "1/30", ndInput: ""),
            .failure(.emptyND)
        )
        XCTAssertEqual(
            calculator.calculate(baseShutterInput: "1/30", ndInput: "NDfoo"),
            .failure(.invalidND)
        )
    }

    func testParseBaseShutterSupportsFractionAndSecondsSuffix() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.parseBaseShutter("1/30"), 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(try calculator.parseBaseShutter("2s"), 2, accuracy: 0.0001)
        XCTAssertEqual(try calculator.parseBaseShutter("0.5"), 0.5, accuracy: 0.0001)
    }

    func testParseNDFactorSupportsPlainAndPrefixedValues() throws {
        let calculator = ExposureCalculator()

        XCTAssertEqual(try calculator.parseNDFactor("64"), 64, accuracy: 0.0001)
        XCTAssertEqual(try calculator.parseNDFactor("ND1000"), 1000, accuracy: 0.0001)
    }

    func testFormatShutterReturnsExpectedReadableStrings() {
        let calculator = ExposureCalculator()

        XCTAssertEqual(calculator.formatShutter(2), "2s")
        XCTAssertEqual(calculator.formatShutter(2.1), "2.1s")
        XCTAssertEqual(calculator.formatShutter(1.0 / 30.0), "1/30s")
    }
}
