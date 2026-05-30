import XCTest
@testable import PTimer

/// PTIMER-159: the log-log table interpolation evaluator. Anchors must
/// reproduce exactly, intermediate values follow log-log interpolation,
/// and inputs past the last anchor extrapolate a real value classified
/// beyond source range (never a value-less result).
final class TableInterpolationModelTests: XCTestCase {

    private func fomapanRule() -> TableInterpolationReciprocityRule {
        TableInterpolationReciprocityRule(
            anchors: [
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
                TableAnchor(meteredSeconds: 10, correctedSeconds: 80),
                TableAnchor(meteredSeconds: 100, correctedSeconds: 1600),
            ],
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 100
        )
    }

    func testNoCorrectionWithinThreshold() {
        XCTAssertEqual(fomapanRule().evaluate(meteredExposureSeconds: 0.5), .noCorrection)
        XCTAssertEqual(fomapanRule().evaluate(meteredExposureSeconds: 0.25), .noCorrection)
    }

    func testAnchorsReproduceExactly() {
        assertWithin(fomapanRule().evaluate(meteredExposureSeconds: 1), expected: 2)
        assertWithin(fomapanRule().evaluate(meteredExposureSeconds: 10), expected: 80)
        assertWithin(fomapanRule().evaluate(meteredExposureSeconds: 100), expected: 1600)
    }

    func testIntermediateUsesLogLogInterpolation() {
        // Tm = 10^1.5 ≈ 31.62 sits halfway (in log space) between the
        // 10s and 100s anchors; log-log interpolation gives ≈ 357.8 s.
        guard case let .withinSourceRange(corrected) = fomapanRule().evaluate(meteredExposureSeconds: 31.6228) else {
            return XCTFail("Expected a within-source-range value.")
        }
        XCTAssertEqual(corrected, 357.8, accuracy: 1.0)
        XCTAssertGreaterThan(corrected, 80)
        XCTAssertLessThan(corrected, 1600)
    }

    func testBeyondLastAnchorStillReturnsAValue() {
        // 1000 s is past the 100 s source range; the model extrapolates
        // the last log-log segment (slope ≈ 1.301) → ≈ 32010 s, flagged
        // beyond source range. It must NOT dead-end.
        guard case let .beyondSourceRange(corrected) = fomapanRule().evaluate(meteredExposureSeconds: 1000) else {
            return XCTFail("1000 s must compute a value classified beyond source range.")
        }
        XCTAssertGreaterThan(corrected, 1600)
        XCTAssertEqual(corrected, 32010, accuracy: 200)
    }

    func testInvalidInput() {
        XCTAssertEqual(fomapanRule().evaluate(meteredExposureSeconds: 0), .invalidInput)
        XCTAssertEqual(fomapanRule().evaluate(meteredExposureSeconds: -1), .invalidInput)
    }

    func testInvalidRuleParameters() {
        let badAnchorsOrder = TableInterpolationReciprocityRule(
            anchors: [TableAnchor(meteredSeconds: 1, correctedSeconds: 2)],
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 1
        )
        XCTAssertFalse(badAnchorsOrder.hasValidParameters)
        XCTAssertEqual(badAnchorsOrder.evaluate(meteredExposureSeconds: 1), .invalidRule)
    }

    private func assertWithin(
        _ result: TableInterpolationReciprocityRule.EvaluationResult,
        expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .withinSourceRange(corrected) = result else {
            return XCTFail("Expected within-source-range, got \(result).", file: file, line: line)
        }
        XCTAssertEqual(corrected, expected, accuracy: 0.0001, file: file, line: line)
    }
}
