// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Shared region-basis contract for the **converted guarded formula
/// reciprocity archetype** — manufacturer films whose mid-region is a
/// log-log formula fitted to published anchors, with a bounded source
/// range above which the formula keeps producing a numeric continuation.
/// Members covered here: Velvia 50, Velvia 100, Provia 100F, and
/// ADOX CMS 20 II. (The Rollei RETRO 80S / SUPERPAN 200 fit-from-
/// quantified-rows pair joins these contracts when the Rollei suite is
/// split by archetype.)
///
/// Film identity is case data, never part of a test-function name; the
/// film and sample seconds appear in every failure message. Per-film
/// source data (exact fitted parameters, published rows, presentation)
/// is verified by the sibling `GuardedFormulaFitContractTests`,
/// `GuardedFormulaEvidenceContractTests`, and
/// `GuardedFormulaPresentationContractTests`.
final class GuardedFormulaRegionBasisContractTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// One converted guarded-formula film.
    ///
    /// - `thresholdBoundarySeconds`: inclusive no-correction boundary —
    ///   evaluating exactly here returns official no-correction with
    ///   corrected == metered.
    /// - `insideFormulaSamples`: samples that classify as
    ///   `.formulaDerived`. Empty for CMS 20 II, whose formula region is
    ///   verified at exact anchor values in its own suite.
    /// - `publishedUpperBoundarySeconds`: the published reference row at
    ///   the top of the source-backed range — still `.formulaDerived`
    ///   (source-backed), with the exact continuation value. `nil` when
    ///   the film has no distinct published upper row to pin.
    /// - `aboveSourceSamples`: samples that classify as
    ///   `.unsupportedOutOfPolicyRange` while the formula keeps producing
    ///   the numeric continuation `coefficient × (metered / reference)^
    ///   exponent`. Empty for CMS 20 II.
    /// - `coefficientSeconds` / `referenceMeteredTimeSeconds` /
    ///   `exponent`: published formula parameters used to verify the
    ///   continuation value (kept explicit as case data).
    /// - `toleranceFloorSeconds` / `toleranceFraction`: the per-film
    ///   tolerance `max(floor, expected × fraction)`.
    private struct GuardedFormulaFilmCase {
        let film: String
        /// `nil` for fit-from-quantified-rows films (Rollei RETRO 80S /
        /// SUPERPAN 200) whose just-above-threshold region goes through the
        /// runtime safety handoff rather than a clean no-correction band.
        let thresholdBoundarySeconds: Double?
        let insideFormulaSamples: [Double]
        let publishedUpperBoundarySeconds: Double?
        let aboveSourceSamples: [Double]
        let coefficientSeconds: Double
        let referenceMeteredTimeSeconds: Double
        let exponent: Double
        let toleranceFloorSeconds: Double
        let toleranceFraction: Double

        func continuation(at metered: Double) -> Double {
            coefficientSeconds * pow(metered / referenceMeteredTimeSeconds, exponent)
        }

        func tolerance(forExpected expected: Double) -> Double {
            max(toleranceFloorSeconds, expected * toleranceFraction)
        }
    }

    private let cases: [GuardedFormulaFilmCase] = [
        GuardedFormulaFilmCase(
            film: "Velvia 50",
            thresholdBoundarySeconds: 1,
            insideFormulaSamples: [2, 4, 8, 16, 24, 32],
            publishedUpperBoundarySeconds: nil,
            aboveSourceSamples: [50, 64, 90],
            coefficientSeconds: 1, referenceMeteredTimeSeconds: 1, exponent: 1.1821,
            toleranceFloorSeconds: 1, toleranceFraction: 0
        ),
        GuardedFormulaFilmCase(
            film: "Velvia 100",
            thresholdBoundarySeconds: 60,
            insideFormulaSamples: [80, 120, 150, 200, 239],
            publishedUpperBoundarySeconds: 240,
            aboveSourceSamples: [300, 400],
            coefficientSeconds: 60, referenceMeteredTimeSeconds: 60, exponent: 1.2667,
            toleranceFloorSeconds: 1, toleranceFraction: 0
        ),
        GuardedFormulaFilmCase(
            film: "Provia 100F",
            thresholdBoundarySeconds: 128,
            insideFormulaSamples: [150, 200, 230],
            publishedUpperBoundarySeconds: 240,
            aboveSourceSamples: [360, 470, 480, 500],
            coefficientSeconds: 128, referenceMeteredTimeSeconds: 128, exponent: 1.3676,
            toleranceFloorSeconds: 1.5, toleranceFraction: 0.005
        ),
        // CMS 20 II shares only the inclusive-threshold contract; its
        // formula-region and beyond-source values are exact anchor
        // checks kept in its own suite (1 s / 10 s anchors, 100 s
        // not-recommended marker).
        GuardedFormulaFilmCase(
            film: "CMS 20 II",
            thresholdBoundarySeconds: 1,
            insideFormulaSamples: [],
            publishedUpperBoundarySeconds: nil,
            aboveSourceSamples: [],
            coefficientSeconds: 1.4142136, referenceMeteredTimeSeconds: 1, exponent: 1.150515,
            toleranceFloorSeconds: 0.5, toleranceFraction: 0.005
        ),
        // Rollei RETRO 80S / SUPERPAN 200 — fit-from-quantified-rows
        // formula (Tc = 0.9601 × Tm^1.5361). A runtime fit-gap just above
        // the 0.5 s threshold means no clean no-correction boundary, so
        // threshold is nil. Published quantified rows (4/8/15/30 s) are
        // formula-derived; above the 30 s upper row the bare-power
        // continuation carries through.
        GuardedFormulaFilmCase(
            film: "RETRO 80S",
            thresholdBoundarySeconds: nil,
            insideFormulaSamples: [4, 8, 15, 30],
            publishedUpperBoundarySeconds: nil,
            aboveSourceSamples: [90],
            coefficientSeconds: 0.9601, referenceMeteredTimeSeconds: 1, exponent: 1.5361,
            toleranceFloorSeconds: 0.5, toleranceFraction: 0.01
        ),
        GuardedFormulaFilmCase(
            film: "SUPERPAN 200",
            thresholdBoundarySeconds: nil,
            insideFormulaSamples: [4, 8, 15, 30],
            publishedUpperBoundarySeconds: nil,
            aboveSourceSamples: [90],
            coefficientSeconds: 0.9601, referenceMeteredTimeSeconds: 1, exponent: 1.5361,
            toleranceFloorSeconds: 0.5, toleranceFraction: 0.01
        ),
    ]

    // MARK: - Region 1: inclusive no-correction threshold

    func testAtThresholdBoundaryReturnsOfficialNoCorrection() throws {
        for c in cases {
            guard let threshold = c.thresholdBoundarySeconds else { continue }
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: threshold)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(c.film) @ \(threshold)s: inclusive threshold boundary must read as official no-correction."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(threshold)s: no-correction must report corrected.")
            XCTAssertEqual(corrected, threshold, accuracy: 1e-6, "\(c.film) @ \(threshold)s: corrected must equal metered at the boundary.")
        }
    }

    // MARK: - Region 2: source-backed formula range

    func testInsideSourceRangeIsFormulaDerived() throws {
        for c in cases where !c.insideFormulaSamples.isEmpty {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            for metered in c.insideFormulaSamples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .formulaDerived,
                    "\(c.film) @ \(metered)s: inside the source-backed range must be formula-derived."
                )
            }
        }
    }

    /// The published reference row at the top of the source-backed range
    /// stays `.formulaDerived` (source-backed, never beyond-source) and
    /// carries the exact formula continuation value.
    func testAtPublishedUpperBoundaryIsFormulaDerivedWithExactValue() throws {
        for c in cases {
            guard let boundary = c.publishedUpperBoundarySeconds else { continue }
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: boundary)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "\(c.film) @ \(boundary)s: the published upper reference row must stay source-backed formula-derived, not beyond-source."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(boundary)s: must report a corrected value.")
            let expected = c.continuation(at: boundary)
            XCTAssertEqual(corrected, expected, accuracy: c.tolerance(forExpected: expected), "\(c.film) @ \(boundary)s: corrected must match the published formula value (\(expected)s).")
        }
    }

    // MARK: - Region 3: beyond the source-backed range

    func testAboveSourceRangeIsBeyondSourceWithFormulaContinuation() throws {
        for c in cases where !c.aboveSourceSamples.isEmpty {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            for metered in c.aboveSourceSamples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .unsupportedOutOfPolicyRange,
                    "\(c.film) @ \(metered)s: above the source-backed boundary must classify as outside manufacturer guidance."
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(metered)s: beyond-source must still carry a numeric continuation.")
                let expected = c.continuation(at: metered)
                XCTAssertEqual(corrected, expected, accuracy: c.tolerance(forExpected: expected), "\(c.film) @ \(metered)s: beyond-source continuation must match the published formula (\(expected)s).")
            }
        }
    }
}
