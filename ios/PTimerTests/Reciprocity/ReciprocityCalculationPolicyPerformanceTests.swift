import XCTest
import PTimerCore
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
final class ReciprocityPolicyPerformanceTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// Formula-based profile within the supported range.
    func testFormulaDerivedEvaluationPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 100)
            }
        }
    }

    /// Bounded formula past its supported range — exercises the
    /// beyond-source-range unsupported path that still carries a
    /// numeric continuation past the formula's
    /// `sourceRangeThroughSeconds` confidence boundary.
    func testFormulaBoundedBeyondSourceRangeEvaluationPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.formulaBoundedProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1_500)
            }
        }
    }

    /// Threshold no-correction path — should be the cheapest.
    func testThresholdNoCorrectionPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
            }
        }
    }

    /// Limited-guidance evaluation — no quantified prediction at all.
    func testLimitedGuidanceEvaluationPerformance() {
        let profile = ReciprocityPolicyScenarioFactory.portraLimitedGuidanceProfile()

        measure {
            for _ in 0 ..< 1_000 {
                _ = evaluator.evaluate(profile: profile, meteredExposureSeconds: 4)
            }
        }
    }

    /// Mixed workload approximating a picker scroll across the four
    /// supported profile shapes at varying metered exposures.
    func testMixedPickerScrollWorkloadPerformance() {
        let hp5 = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()
        let bounded = ReciprocityPolicyScenarioFactory.formulaBoundedProfile()
        let portra = ReciprocityPolicyScenarioFactory.portraLimitedGuidanceProfile()

        let inputs: [(ReciprocityProfile, Double)] = [
            (hp5, 0.5), (hp5, 1.0), (hp5, 100.0), (hp5, 1_500.0),
            (bounded, 60.0), (bounded, 600.0), (bounded, 1_500.0),
            (portra, 0.5), (portra, 4.0),
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
