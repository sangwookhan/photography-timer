import XCTest
@testable import PTimer

/// Performance baseline for the reciprocity policy evaluator.
///
/// Hot path: film picker scroll triggers per-frame `evaluate` calls
/// against the active film's profile. With 60 fps the per-evaluation
/// budget is roughly 16.67 ms minus all other main-thread work.
///
/// These measurements run in `XCTMeasure` blocks. Use the Xcode
/// Test Navigator to inspect baselines and set thresholds. They
/// are intentionally separate from the correctness tests so
/// `xcodebuild test` continues to pass-fast on CI.
///
/// See `Docs/StructureImprovement/HotPathConcurrency.md` for the
/// procedure to expand this with Instruments-based picker-scroll
/// measurements.
final class ReciprocityCalculationPolicyPerformanceTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// Picker-scroll worst case approximation: evaluate against a
    /// table-based profile (Tri-X) at a metered point that triggers
    /// log-log interpolation between two reference rows.
    func testInterpolatedTriXEvaluationPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 7)
            }
        }
    }

    /// Extrapolation path — typically more arithmetic than interpolation.
    func testExtrapolatedTriXEvaluationPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1_500)
            }
        }
    }

    /// Formula-based profile path (HP5+). No table lookup; just power
    /// formula evaluation.
    func testFormulaBasedHP5EvaluationPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 100)
            }
        }
    }

    /// Threshold no-correction path — should be the cheapest.
    func testThresholdNoCorrectionPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.velviaProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
            }
        }
    }

    /// Mixed workload approximating a picker scroll across the four
    /// preset films at varying metered exposures.
    func testMixedPickerScrollWorkloadPerformance() {
        let triX = ReciprocityPolicyScenarioFactory.triXProfile()
        let velvia = ReciprocityPolicyScenarioFactory.velviaProfile()
        let portra = ReciprocityPolicyScenarioFactory.portraOfficialProfile()
        let hp5 = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        let inputs: [(ReciprocityProfile, Double)] = [
            (triX, 1.0), (triX, 7.0), (triX, 100.0), (triX, 1_500.0),
            (velvia, 0.5), (velvia, 8.0), (velvia, 30.0),
            (portra, 0.5), (portra, 4.0),
            (hp5, 2.0), (hp5, 100.0),
        ]

        measure {
            for _ in 0 ..< 100 {
                for (profile, metered) in inputs {
                    _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                }
            }
        }
    }
}
