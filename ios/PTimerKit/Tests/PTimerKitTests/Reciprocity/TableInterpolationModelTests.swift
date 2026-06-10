import XCTest
import PTimerCore

/// PTIMER-159: the log-log table interpolation evaluator. Anchors must
/// reproduce exactly, intermediate values follow log-log interpolation,
/// and inputs past the last anchor extrapolate a real value classified
/// beyond source range (never a value-less result).
final class TableInterpolationModelTests: XCTestCase {

    private func sampleTableRule() -> TableInterpolationReciprocityRule {
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
        XCTAssertEqual(sampleTableRule().evaluate(meteredExposureSeconds: 0.5), .noCorrection)
        XCTAssertEqual(sampleTableRule().evaluate(meteredExposureSeconds: 0.25), .noCorrection)
    }

    /// A `0.1 s` (nominal 1/10 s) boundary rule, matching the migrated
    /// Kodak Tri-X / T-MAX profiles.
    private func tenthSecondRule() -> TableInterpolationReciprocityRule {
        TableInterpolationReciprocityRule(
            anchors: [
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
                TableAnchor(meteredSeconds: 10, correctedSeconds: 50),
                TableAnchor(meteredSeconds: 100, correctedSeconds: 1200),
            ],
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100
        )
    }

    /// PTIMER-168: a nominal 1/10 s UI input can evaluate to ~0.102 s
    /// after Base Shutter / ND stop arithmetic. The boundary tolerance
    /// must keep that classified as no correction while values clearly
    /// above the threshold stay corrected.
    func testNoCorrectionBoundaryTolerance() {
        let rule = tenthSecondRule()
        // Below and exactly at the published threshold.
        XCTAssertEqual(rule.evaluate(meteredExposureSeconds: 0.084), .noCorrection)
        XCTAssertEqual(rule.evaluate(meteredExposureSeconds: 0.1), .noCorrection)
        // Nominal 1/10 s drifted upward by stop arithmetic.
        XCTAssertEqual(rule.evaluate(meteredExposureSeconds: 0.102), .noCorrection)
        // Top of the tolerance band (0.1 × 1.10).
        XCTAssertEqual(rule.evaluate(meteredExposureSeconds: 0.11), .noCorrection)
    }

    func testValuesAboveToleranceRemainCorrected() {
        let rule = tenthSecondRule()
        for metered in [0.12, 0.15] {
            guard case let .withinSourceRange(corrected) =
                rule.evaluate(meteredExposureSeconds: metered) else {
                return XCTFail("\(metered)s must be corrected, not no-correction.")
            }
            XCTAssertGreaterThan(corrected, metered)
        }
    }

    /// The tolerance is relative, so a `0.5 s` threshold band never
    /// stretches anywhere near `1 s`.
    func testToleranceDoesNotExpandBandTowardOneSecond() {
        let rule = sampleTableRule() // noCorrectionThroughSeconds: 0.5
        XCTAssertEqual(rule.evaluate(meteredExposureSeconds: 0.55), .noCorrection)
        guard case .withinSourceRange = rule.evaluate(meteredExposureSeconds: 0.7) else {
            return XCTFail("0.7s must be corrected for a 0.5s threshold.")
        }
        guard case .withinSourceRange = rule.evaluate(meteredExposureSeconds: 1.0) else {
            return XCTFail("1.0s must be corrected for a 0.5s threshold.")
        }
    }

    func testAnchorsReproduceExactly() {
        assertWithin(sampleTableRule().evaluate(meteredExposureSeconds: 1), expected: 2)
        assertWithin(sampleTableRule().evaluate(meteredExposureSeconds: 10), expected: 80)
        assertWithin(sampleTableRule().evaluate(meteredExposureSeconds: 100), expected: 1600)
    }

    func testIntermediateUsesLogLogInterpolation() {
        // Tm = 10^1.5 ≈ 31.62 sits halfway (in log space) between the
        // 10s and 100s anchors; log-log interpolation gives ≈ 357.8 s.
        guard case let .withinSourceRange(corrected) = sampleTableRule().evaluate(meteredExposureSeconds: 31.6228) else {
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
        guard case let .beyondSourceRange(corrected) = sampleTableRule().evaluate(meteredExposureSeconds: 1000) else {
            return XCTFail("1000 s must compute a value classified beyond source range.")
        }
        XCTAssertGreaterThan(corrected, 1600)
        XCTAssertEqual(corrected, 32010, accuracy: 200)
    }

    func testInvalidInput() {
        XCTAssertEqual(sampleTableRule().evaluate(meteredExposureSeconds: 0), .invalidInput)
        XCTAssertEqual(sampleTableRule().evaluate(meteredExposureSeconds: -1), .invalidInput)
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
