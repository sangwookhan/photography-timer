import XCTest
import PTimerCore
@testable import PTimerKit

/// Baseline snapshot tests covering display-state outputs. These lock
/// the *serialized form* of the display states so an internal
/// restructure cannot silently alter what views render.
///
/// PTIMER-140 removed the table calculation path. Snapshot inputs
/// now exercise threshold no-correction, formula-derived, formula
/// prediction past the supported range, and limited-guidance paths
/// across the surviving scenario factory.
@MainActor
final class DisplayStateSnapshotTests: XCTestCase {

    // MARK: - Reciprocity policy results

    func testThresholdNoCorrectionSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 0.5
        )
        DisplayStateSnapshot.assert(result, named: "hp5-threshold-0p5s")
    }

    func testFormulaDerivedSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 100
        )
        DisplayStateSnapshot.assert(result, named: "hp5-formula-100s")
    }

    func testLimitedGuidanceSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.limitedGuidanceProfile(),
            meteredExposureSeconds: 4
        )
        DisplayStateSnapshot.assert(result, named: "portra-limited-guidance-4s")
    }

    func testFormulaBeyondSourceRangeUnsupportedSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.formulaBoundedProfile(),
            meteredExposureSeconds: 1_500
        )
        DisplayStateSnapshot.assert(result, named: "formula-beyond-source-range-unsupported-1500s")
    }

    // MARK: - Launch catalog

    /// All bundled preset films. Locks the catalog shape so a
    /// reciprocity-data correction shows up as a snapshot diff.
    func testLaunchPresetFilmCatalogSnapshot() {
        DisplayStateSnapshot.assert(
            LaunchPresetFilmCatalog.films,
            named: "launch-preset-films"
        )
    }

    // MARK: - Confidence presentation

    func testTrustedNoCorrectionConfidencePresentationSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let mapper = ReciprocityConfidencePresentationMapper()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 0.5
        )
        DisplayStateSnapshot.assert(mapper.map(result: result), named: "confidence-trusted-no-correction")
    }

    func testUnsupportedBeyondSourceRangeConfidencePresentationSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let mapper = ReciprocityConfidencePresentationMapper()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.formulaBoundedProfile(),
            meteredExposureSeconds: 1_500
        )
        DisplayStateSnapshot.assert(mapper.map(result: result), named: "confidence-unsupported-beyond-source-range")
    }
}
