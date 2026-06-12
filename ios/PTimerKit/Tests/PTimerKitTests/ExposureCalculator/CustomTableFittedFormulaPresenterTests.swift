import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-179 contract for the inspection-only fitted-formula
/// presenter: parameter mapping, boundary inheritance, per-anchor
/// comparison, PTIMER-170 quality classification, the two-anchor note,
/// and the non-shortening "unusable" outcome.
final class CustomTableFittedFormulaPresenterTests: XCTestCase {

    private func anchor(_ metered: Double, _ corrected: Double) -> TableAnchor {
        TableAnchor(meteredSeconds: metered, correctedSeconds: corrected)
    }

    private func rule(
        _ anchors: [TableAnchor],
        noCorrection: Double,
        sourceRange: Double
    ) -> TableInterpolationReciprocityRule {
        TableInterpolationReciprocityRule(
            anchors: anchors,
            noCorrectionThroughSeconds: noCorrection,
            sourceRangeThroughSeconds: sourceRange
        )
    }

    /// Clean `Tc = 2 × Tm^1.4` power law sampled at three decades.
    private func cleanPowerLawRule(noCorrection: Double = 0.5) -> TableInterpolationReciprocityRule {
        let a = 2.0, p = 1.4
        let anchors = [1.0, 10.0, 100.0].map { anchor($0, a * pow($0, p)) }
        return rule(anchors, noCorrection: noCorrection, sourceRange: 100)
    }

    private func available(
        _ outcome: CustomTableFittedFormulaPresenter.Outcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CustomTableFittedFormulaPresenter.FittedFormula {
        guard case let .available(formula) = outcome else {
            XCTFail("expected available outcome, got \(outcome)", file: file, line: line)
            throw XCTSkip("not available")
        }
        return formula
    }

    // MARK: - Parameter mapping + family

    func testMapsToPowerLawShapeWithZeroOffsetAndUnitReference() throws {
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(for: cleanPowerLawRule())
        )
        XCTAssertEqual(formula.coefficientSeconds, 2.0, accuracy: 1e-6)
        XCTAssertEqual(formula.exponent, 1.4, accuracy: 1e-6)
        XCTAssertEqual(formula.offsetSeconds, 0)
        XCTAssertEqual(formula.referenceMeteredTimeSeconds, 1)
    }

    func testLabelsAreAppDerivedPowerLaw() {
        XCTAssertEqual(CustomTableFittedFormulaPresenter.appDerivedLabel, "App-derived formula")
        XCTAssertEqual(CustomTableFittedFormulaPresenter.formulaFamilyLabel, "Power-law fit")
    }

    // MARK: - Boundary inheritance

    func testInheritsTableNoCorrectionAndSourceRangeBoundaries() throws {
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(
                for: cleanPowerLawRule(noCorrection: 0.7)
            )
        )
        XCTAssertEqual(formula.noCorrectionThroughSeconds, 0.7)
        XCTAssertEqual(formula.sourceRangeThroughSeconds, 100)
    }

    // MARK: - Fitting input comes from rule anchors, not sourceEvidence

    func testFitDerivesFromRuleAnchorsMatchingTheRuntimeFitter() throws {
        let tableRule = cleanPowerLawRule()
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(for: tableRule)
        )
        // The presenter input type carries no sourceEvidence; the fit
        // must equal fitting the rule's calculation anchors directly.
        let direct = try ReciprocityFormulaFitter.fit(anchors: tableRule.anchors).get()
        XCTAssertEqual(formula.coefficientSeconds, direct.coefficient, accuracy: 1e-12)
        XCTAssertEqual(formula.exponent, direct.exponent, accuracy: 1e-12)
    }

    // MARK: - Per-anchor comparison

    func testComparisonRowsCoverEveryAnchorWithErrors() throws {
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(for: cleanPowerLawRule())
        )
        XCTAssertEqual(formula.comparisonRows.count, 3)
        for row in formula.comparisonRows {
            // Clean power law → fitted reproduces source, ~0 error.
            XCTAssertEqual(row.fittedCorrectedSeconds, row.sourceCorrectedSeconds, accuracy: 1e-6)
            XCTAssertEqual(row.percentError, 0, accuracy: 1e-3)
            XCTAssertEqual(row.stopError, 0, accuracy: 1e-3)
            XCTAssertEqual(row.stopError, log2(row.fittedCorrectedSeconds / row.sourceCorrectedSeconds), accuracy: 1e-12)
        }
        XCTAssertEqual(formula.worstAbsoluteStopError, 0, accuracy: 1e-3)
    }

    func testWorstErrorIsTheMaxAbsoluteStopResidual() throws {
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(for: cleanPowerLawRule())
        )
        let expected = formula.comparisonRows.map { abs($0.stopError) }.max() ?? -1
        XCTAssertEqual(formula.worstAbsoluteStopError, expected)
    }

    // MARK: - Quality classification (PTIMER-170 thresholds)

    func testQualityThresholdBoundaries() {
        let presenter = CustomTableFittedFormulaPresenter.self
        XCTAssertEqual(presenter.quality(forWorstAbsoluteStopError: 0), .good)
        XCTAssertEqual(presenter.quality(forWorstAbsoluteStopError: 0.1), .good)
        XCTAssertEqual(presenter.quality(forWorstAbsoluteStopError: 0.1000001), .borderline)
        XCTAssertEqual(presenter.quality(forWorstAbsoluteStopError: 0.25), .borderline)
        XCTAssertEqual(presenter.quality(forWorstAbsoluteStopError: 0.2500001), .poor)
        XCTAssertEqual(presenter.quality(forWorstAbsoluteStopError: 1.0), .poor)
    }

    func testGoodFitClassifiedGood() throws {
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(for: cleanPowerLawRule())
        )
        XCTAssertEqual(formula.quality, .good)
    }

    func testCurvedTableClassifiedPoorEndToEnd() throws {
        // A table a single power law cannot follow: the mid anchor
        // misses by > 0.25 stop. noCorrection 0.5 keeps the fit
        // non-shortening so the poor classification (not "unusable")
        // is what surfaces.
        let curved = rule(
            [anchor(1, 2), anchor(10, 60), anchor(100, 1_000)],
            noCorrection: 0.5,
            sourceRange: 100
        )
        let formula = try available(CustomTableFittedFormulaPresenter.outcome(for: curved))
        XCTAssertEqual(formula.quality, .poor)
        XCTAssertGreaterThan(formula.worstAbsoluteStopError, 0.25)
    }

    // MARK: - Two-anchor note

    func testTwoAnchorFitIsFlaggedExact() throws {
        let twoAnchor = rule(
            [anchor(1, 2), anchor(100, 2 * pow(100, 1.4))],
            noCorrection: 0.5,
            sourceRange: 100
        )
        let formula = try available(CustomTableFittedFormulaPresenter.outcome(for: twoAnchor))
        XCTAssertTrue(formula.isTwoAnchorExactFit)
        XCTAssertEqual(formula.anchorCount, 2)
    }

    func testThreeAnchorFitIsNotFlaggedTwoAnchor() throws {
        let formula = try available(
            CustomTableFittedFormulaPresenter.outcome(for: cleanPowerLawRule())
        )
        XCTAssertFalse(formula.isTwoAnchorExactFit)
    }

    // MARK: - Unusable (non-shortening guard failure)

    func testShorteningFitMarkedUnusable() {
        // Fit of (2,2),(10,20) is Tc ≈ 0.742 × Tm^1.43, which crosses
        // below Tm for Tm < 2 — so over the usable range (noCorrection
        // 0.2 → first anchor) it would shorten exposure. The shared
        // non-shortening guard must reject it.
        let shortening = rule(
            [anchor(2, 2), anchor(10, 20)],
            noCorrection: 0.2,
            sourceRange: 10
        )
        XCTAssertEqual(
            CustomTableFittedFormulaPresenter.outcome(for: shortening),
            .unavailable(.unusableShorteningFit)
        )
    }

    func testInsufficientAnchorsSurfaceFitReason() {
        // A single-anchor rule never passes the table contract, but the
        // presenter must degrade gracefully rather than crash.
        let single = rule([anchor(1, 2)], noCorrection: 0.1, sourceRange: 1)
        XCTAssertEqual(
            CustomTableFittedFormulaPresenter.outcome(for: single),
            .unavailable(.fit(.insufficientAnchors))
        )
    }
}
