import XCTest
@testable import PTimer

/// Baseline snapshot tests covering display-state outputs that B1
/// will move between models. These lock the *serialized form* of
/// the display states so an internal restructure cannot silently
/// alter what views render.
///
/// Inputs are drawn from `ReciprocityPolicyScenarioFactory` and
/// `LaunchPresetFilmCatalog`. The same inputs appear in unit
/// tests, so any disagreement between snapshot and unit-test
/// assertion is visible.
@MainActor
final class DisplayStateSnapshotTests: XCTestCase {

    // MARK: - Reciprocity policy results

    /// Tri-X 400 exact table point at metered=10s. Locks the full
    /// `ReciprocityCalculationResult` shape including metadata.
    func testTriXExactTablePointSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 10
        )
        DisplayStateSnapshot.assert(result, named: "trix-exact-10s")
    }

    /// Tri-X log-log interpolation between table anchors. Most
    /// arithmetic-heavy quantified path.
    func testTriXInterpolatedSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 7
        )
        DisplayStateSnapshot.assert(result, named: "trix-interpolated-7s")
    }

    /// Tri-X extrapolation beyond the last table anchor.
    func testTriXExtrapolatedSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 1_500
        )
        DisplayStateSnapshot.assert(result, named: "trix-extrapolated-1500s")
    }

    /// Velvia threshold no-correction range.
    func testVelviaThresholdNoCorrectionSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 0.5
        )
        DisplayStateSnapshot.assert(result, named: "velvia-threshold-0p5s")
    }

    /// HP5+ formula-derived correction.
    func testHP5FormulaDerivedSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(),
            meteredExposureSeconds: 100
        )
        DisplayStateSnapshot.assert(result, named: "hp5-formula-100s")
    }

    /// Portra advisory-only path.
    func testPortraAdvisoryOnlySnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 4
        )
        DisplayStateSnapshot.assert(result, named: "portra-advisory-4s")
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

    /// Trusted exact-match confidence presentation.
    func testTrustedExactConfidencePresentationSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let mapper = ReciprocityConfidencePresentationMapper()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 10
        )
        DisplayStateSnapshot.assert(mapper.map(result: result), named: "confidence-trusted-exact")
    }

    /// Caution-tier extrapolation presentation.
    func testCautionExtrapolatedConfidencePresentationSnapshot() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let mapper = ReciprocityConfidencePresentationMapper()
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 1_500
        )
        DisplayStateSnapshot.assert(mapper.map(result: result), named: "confidence-extrapolated")
    }
}
