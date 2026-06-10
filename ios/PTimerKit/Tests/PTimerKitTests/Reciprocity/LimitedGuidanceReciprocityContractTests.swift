import XCTest
import PTimerKit
import PTimerCore

/// Behavior contract for Kodak still-film profiles whose official
/// guidance is limited to a no-correction threshold band plus a
/// qualitative note past that band.
///
/// These profiles cover both color negative stocks (Ektar 100,
/// Portra 160/400, Gold 200, Ultra Max 400) and the Ektachrome E100
/// color reversal stock. Kodak publishes only a no-correction range
/// for them, so the calculation policy must:
///
/// - Stay `officialThresholdNoCorrection` inside the official range.
/// - Stay `limitedGuidanceNoQuantifiedPrediction` past the upper bound,
///   with no fabricated corrected exposure.
/// - Never carry a formula rule that could quietly produce
///   a corrected time outside Kodak's published guidance.
///
/// Ektachrome E100 additionally publishes a 120 sec CC10R filtration
/// note. The catalog keeps it as limited-guidance color-filter
/// advice so it never becomes a corrected-time anchor for a formula
/// fit.
final class LimitedGuidanceReciprocityContractTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    private struct LimitedGuidanceProfile {
        let canonicalStockName: String
        let officialUpperBoundSeconds: Double
        /// Optional published color-filter advice carried by the
        /// limited-guidance rule (e.g. Ektachrome E100's CC10R at 120 s).
        /// It is filter advice, never a corrected-time anchor.
        var colorFilterName: String?
        var colorFilterNoteSubstring: String?
        var colorFilterAnchorSample: Double?
    }

    private let limitedGuidanceProfiles: [LimitedGuidanceProfile] = [
        LimitedGuidanceProfile(canonicalStockName: "Ektar 100", officialUpperBoundSeconds: 1),
        LimitedGuidanceProfile(canonicalStockName: "Portra 160", officialUpperBoundSeconds: 10),
        LimitedGuidanceProfile(canonicalStockName: "Portra 400", officialUpperBoundSeconds: 10),
        LimitedGuidanceProfile(canonicalStockName: "Gold 200", officialUpperBoundSeconds: 1),
        LimitedGuidanceProfile(canonicalStockName: "Ultra Max 400", officialUpperBoundSeconds: 1),
        LimitedGuidanceProfile(
            canonicalStockName: "Ektachrome E100",
            officialUpperBoundSeconds: 10,
            colorFilterName: "CC10R",
            colorFilterNoteSubstring: "120",
            colorFilterAnchorSample: 120
        ),
    ]

    // MARK: - Catalog shape

    func testLimitedGuidanceProfilesDoNotCarryFormulaRules() throws {
        for entry in limitedGuidanceProfiles {
            let profile = try profile(for: entry.canonicalStockName)
            for rule in profile.rules {
                switch rule {
                case .formula:
                    XCTFail("\(entry.canonicalStockName) must not ship with a formula rule — Kodak limited-guidance profiles stay out of the formula path.")
                case .threshold, .limitedGuidance, .tableInterpolation:
                    continue
                }
            }
            XCTAssertFalse(
                profile.isConvertedFormulaProfile,
                "\(entry.canonicalStockName) must not be flagged as a converted formula profile."
            )
        }
    }

    func testLimitedGuidanceProfilesCarryNoSourceEvidence() throws {
        // Source evidence rows exist to let users verify a formula
        // prediction against published anchors. These profiles have
        // no published long-exposure anchors and no formula curve, so
        // they must not advertise source-evidence rows that imply
        // quantified continuation.
        for entry in limitedGuidanceProfiles {
            let profile = try profile(for: entry.canonicalStockName)
            XCTAssertTrue(
                profile.sourceEvidence.isEmpty,
                "\(entry.canonicalStockName) has no quantified long-exposure source; sourceEvidence must remain empty."
            )
        }
    }

    // MARK: - Threshold band

    func testLimitedGuidanceProfilesStayNoCorrectionInsideThresholdBand() throws {
        for entry in limitedGuidanceProfiles {
            let profile = try profile(for: entry.canonicalStockName)
            let samples: [Double] = [
                0.001,
                0.01,
                0.1,
                entry.officialUpperBoundSeconds / 2,
                entry.officialUpperBoundSeconds,
            ]
            for metered in samples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .officialThresholdNoCorrection,
                    "\(entry.canonicalStockName) at \(metered) sec sits inside the official no-correction range."
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                XCTAssertEqual(
                    corrected,
                    metered,
                    accuracy: 1e-6,
                    "\(entry.canonicalStockName) no-correction range must return corrected == metered."
                )
            }
        }
    }

    // MARK: - Beyond the official threshold

    func testLimitedGuidanceProfilesLandOnLimitedGuidanceJustPastTheOfficialUpperBound() throws {
        for entry in limitedGuidanceProfiles {
            let profile = try profile(for: entry.canonicalStockName)
            // A small epsilon past the inclusive upper bound flips the
            // policy from threshold-no-correction to limited guidance.
            let metered = entry.officialUpperBoundSeconds + 0.001
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .limitedGuidanceNoQuantifiedPrediction,
                "\(entry.canonicalStockName) at \(metered) sec must land on limited guidance with no quantified prediction."
            )
            XCTAssertNil(
                result.correctedExposureSeconds,
                "\(entry.canonicalStockName) beyond the official threshold must not return a fabricated corrected exposure."
            )
            XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
        }
    }

    func testLimitedGuidanceProfilesStayLimitedGuidanceFarPastTheUpperBound() throws {
        for entry in limitedGuidanceProfiles {
            let profile = try profile(for: entry.canonicalStockName)
            for metered in [entry.officialUpperBoundSeconds * 10, entry.officialUpperBoundSeconds * 60, entry.officialUpperBoundSeconds * 600] {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .limitedGuidanceNoQuantifiedPrediction,
                    "\(entry.canonicalStockName) at \(metered) sec must stay limited-guidance — there is no quantified prediction to extend into."
                )
                XCTAssertNil(result.correctedExposureSeconds)
            }
        }
    }

    // MARK: - Published color-filter advice stays advice, not an anchor

    /// A limited-guidance profile's published color-filter advice (e.g.
    /// Ektachrome E100's CC10R at 120 s) is carried on the limited-guidance
    /// rule as filter advice only: it names the filter and its note, never
    /// surfaces an exposure adjustment that could anchor a future fit, and
    /// the anchor metered value still evaluates as limited guidance with no
    /// corrected exposure.
    func testColorFilterGuidanceStaysAdviceNotCorrectedTimeAnchor() throws {
        for entry in limitedGuidanceProfiles {
            guard let filterName = entry.colorFilterName else { continue }
            let profile = try profile(for: entry.canonicalStockName)
            let rule = try XCTUnwrap(
                profile.rules.compactMap { rule -> LimitedGuidanceReciprocityRule? in
                    guard case let .limitedGuidance(rule) = rule else { return nil }
                    return rule
                }.first,
                "\(entry.canonicalStockName) must carry a limited-guidance rule for its color-filter advice."
            )
            let filter = try XCTUnwrap(
                rule.adjustments.compactMap { adjustment -> ColorFilterRecommendation? in
                    guard case let .colorFilter(filter) = adjustment else { return nil }
                    return filter
                }.first,
                "\(entry.canonicalStockName) limited-guidance rule must carry the published color-filter recommendation."
            )
            XCTAssertEqual(filter.filterName, filterName, "\(entry.canonicalStockName): color-filter name")
            if let noteSubstring = entry.colorFilterNoteSubstring {
                let note = try XCTUnwrap(filter.note, "\(entry.canonicalStockName): color-filter note")
                XCTAssertTrue(note.contains(noteSubstring), "\(entry.canonicalStockName): note must reference '\(noteSubstring)'; got: \(note)")
            }
            XCTAssertFalse(
                rule.adjustments.contains { if case .exposure = $0 { return true }; return false },
                "\(entry.canonicalStockName): color-filter advice must not carry an exposure adjustment that promotes it to a corrected-time anchor."
            )
            if let sample = entry.colorFilterAnchorSample {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: sample)
                XCTAssertEqual(result.metadata.basis, .limitedGuidanceNoQuantifiedPrediction, "\(entry.canonicalStockName) @ \(sample)s: filter-advice anchor must stay limited-guidance.")
                XCTAssertNil(result.correctedExposureSeconds, "\(entry.canonicalStockName) @ \(sample)s: filter advice is not a corrected-time anchor.")
            }
        }
    }

    // MARK: - Presentation wording

    @MainActor
    func testLimitedGuidanceBeyondThresholdSurfacesNoQuantifiedPredictionWording() throws {
        for entry in limitedGuidanceProfiles {
            let metered = entry.officialUpperBoundSeconds + 0.5
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: entry.canonicalStockName,
                meteredExposureSeconds: metered
            )
            XCTAssertEqual(
                displayState.summary.badgeText,
                "No quantified prediction",
                "\(entry.canonicalStockName) past the official threshold must surface the no-quantified-prediction badge."
            )
            let detail = try XCTUnwrap(displayState.summary.detailText)
            XCTAssertTrue(
                detail.contains("No official quantified prediction is available"),
                "\(entry.canonicalStockName) detail text must communicate the lack of an official quantified prediction; got: \(detail)"
            )
        }
    }

    @MainActor
    func testLimitedGuidanceWithinThresholdSurfacesNoCorrectionWording() throws {
        for entry in limitedGuidanceProfiles {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: entry.canonicalStockName,
                meteredExposureSeconds: entry.officialUpperBoundSeconds
            )
            XCTAssertEqual(
                displayState.summary.badgeText,
                "No correction",
                "\(entry.canonicalStockName) at the threshold upper bound must surface the no-correction badge."
            )
        }
    }

    // MARK: - Graph behavior

    @MainActor
    func testLimitedGuidanceProfilesSuppressGraphWhenNoQuantifiedPredictionExists() throws {
        for entry in limitedGuidanceProfiles {
            let metered = entry.officialUpperBoundSeconds + 0.5
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: entry.canonicalStockName,
                meteredExposureSeconds: metered
            )
            XCTAssertNil(
                displayState.graph,
                "\(entry.canonicalStockName) has no source-backed curve and no quantified prediction; the graph must stay suppressed past the threshold."
            )
        }
    }

    // Cross-archetype regression guards (the Kodak B/W stocks use the
    // table-log-log model; the Fujifilm stocks stay formula-based) are not
    // duplicated here — they are owned by `TableLogLogReciprocityContractTests`
    // / `TableProfileSourceDataContractTests` and the `GuardedFormula*`
    // contracts respectively.

    // MARK: - Helpers

    private func profile(
        for canonicalStockName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(
            for: canonicalStockName,
            file: file,
            line: line
        )
    }
}
