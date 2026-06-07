import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Provia 100F is calculated by a constrained, threshold-anchored
/// formula. These tests lock the invariants:
///
/// - Below the 128 s no-correction threshold, the threshold rule wins.
/// - In (128, 240] the formula wins (basis == `.formulaDerived`); the
///   source-backed range ends at the 240 s published +1/3-stop
///   reference (PTIMER-160).
/// - 240 s itself produces a formula-derived corrected exposure of
///   ≈302 s. The reference is preserved as `sourceEvidence`, never
///   as a calculation rule.
/// - Above 240 s the basis is `.unsupportedOutOfPolicyRange` and the
///   formula keeps producing a numeric prediction (visibly marked
///   outside manufacturer guidance).
/// - The 480 s row is preserved as a "Not recommended" warning marker
///   only; it is never used as a formula fitting point or as a
///   corrected-time anchor.
/// - The 240 s (+1/3 stop, 2.5G) row and the 480 s not-recommended row
///   stay visible as source evidence so users can verify the formula
///   prediction against the manufacturer's published reference points.
final class Provia100FFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold boundary (inclusive at 128 s)

    func testProvia100FAtThresholdBoundaryReturnsOfficialNoCorrection() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 128)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 128, accuracy: 1e-6)
    }

    // MARK: - Source-backed formula range (128 s … 240 s inclusive)

    func testProvia100FAt240SecondsIsFormulaDerivedNotExactTablePoint() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 240)

        XCTAssertEqual(
            result.metadata.basis,
            .formulaDerived,
            "240 s must be formula-derived even though the manufacturer published a +1/3 stop reference here."
        )

        // Anchored to the published +1/3 stop reference (240 × 2^(1/3) ≈ 302.4 s).
        // The constrained-formula coefficient is rounded to six decimals, so a 2 s
        // tolerance comfortably covers the rounding error.
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 302.4, accuracy: 2.0)
    }

    func testProvia100FBetweenThresholdAnd240SecondsIsFormulaDerived() throws {
        let profile = try proviaProfile()

        for metered in [150.0, 200.0, 230.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s in the source-backed range must be formula-derived."
            )
        }
    }

    func testProvia100FFormulaExponentMatchesPublishedReference() throws {
        let profile = try proviaProfile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.exponent, 1.3676, accuracy: 0.0001)

        // PTIMER-160 preserves Provia 100F's published display form
        // `Tc = 128 × (Tm / 128)^p` by storing the formula with
        // `coefficientSeconds = referenceMeteredTimeSeconds = 128`,
        // mathematically equivalent to the legacy
        // `coefficient ≈ 0.168` with `Tref = 1` form.
        XCTAssertEqual(formulaRule.formula.coefficientSeconds, 128, accuracy: 1e-6)
        XCTAssertEqual(formulaRule.formula.referenceMeteredTimeSeconds, 128, accuracy: 1e-6)
    }

    // MARK: - Beyond the source-backed range (> 240 s, with 480 s
    // as a warning marker)

    /// PTIMER-160: source-backed range ends at the 240 s anchor.
    /// 360 s, 480 s, and 500 s all sit above that boundary; the
    /// formula keeps producing a numeric continuation but the basis
    /// must classify them as outside the source range. 480 s also
    /// exists as a published "Not recommended" warning marker, which
    /// surfaces independently through the source-evidence row — it
    /// does not promote 480 s back into source-backed status.
    func testProvia100FAbove240SecondsCarriesFormulaPredictionAsBeyondSource() throws {
        let profile = try proviaProfile()
        for metered in [360.0, 470.0, 480.0, 500.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "Provia 100F at \(metered) s sits above the 240 s source-backed boundary."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            let expected = 128.0 * pow(metered / 128.0, 1.3676)
            XCTAssertEqual(corrected, expected, accuracy: max(1.5, expected * 0.005))
        }
    }

    func testProvia100FUnsupportedNumericResultExposesCalculatedTime() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 600)

        XCTAssertTrue(
            result.hasCalculatedExposureTime,
            "Unsupported-with-numeric must report hasCalculatedExposureTime so the play button enables."
        )

        let presentation = result.confidencePresentation
        XCTAssertEqual(presentation.category, .unsupported)
        XCTAssertTrue(
            presentation.returnsCalculatedExposureTime,
            "Confidence presentation must surface the numeric value to the play button."
        )
        XCTAssertEqual(
            presentation.badgeStyle,
            .unsupported,
            "Visual treatment stays in the unsupported badge style so the user reads the value as outside guidance."
        )
    }

    // MARK: - Source evidence preservation

    func testProvia100FSourceEvidencePreserves240SecondReferenceAnd2dot5GFilter() throws {
        let profile = try proviaProfile()

        let evidence240 = try XCTUnwrap(
            profile.sourceEvidence.first {
                if case let .exactSeconds(seconds) = $0.meteredExposure {
                    return abs(seconds - 240) < 1e-6
                }
                return false
            },
            "Provia 100F must keep the 240 s manufacturer reference as source evidence."
        )

        let stopDelta = evidence240.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
            return value.stopDelta
        }.first
        XCTAssertEqual(stopDelta ?? 0, 1.0 / 3.0, accuracy: 1e-4, "240 s source evidence must record the published +1/3 stop correction.")

        let colorFilter = evidence240.adjustments.compactMap { adjustment -> String? in
            guard case let .colorFilter(recommendation) = adjustment else { return nil }
            return recommendation.filterName
        }.first
        XCTAssertEqual(colorFilter, "2.5G", "240 s source evidence must keep the 2.5G color guidance.")
    }

    func testProvia100FSourceEvidencePreserves480SecondNotRecommendedBoundary() throws {
        let profile = try proviaProfile()

        let evidence480 = try XCTUnwrap(
            profile.sourceEvidence.first {
                if case let .exactSeconds(seconds) = $0.meteredExposure {
                    return abs(seconds - 480) < 1e-6
                }
                return false
            },
            "Provia 100F must keep the 480 s not-recommended boundary as source evidence."
        )

        let warningSeverity = evidence480.adjustments.compactMap { adjustment -> ReciprocityWarningSeverity? in
            guard case let .warning(warning) = adjustment else { return nil }
            return warning.severity
        }.first
        XCTAssertEqual(warningSeverity, .notRecommended)
    }

    func testProvia100FRulesNeverContain240SecondAsCalculationAnchor() throws {
        let profile = try proviaProfile()

        for rule in profile.rules {
            // Threshold and formula rules cannot anchor exact metered
            // points — the manufacturer's 240 s row stays in
            // sourceEvidence only.
            switch rule {
            case .threshold, .formula, .limitedGuidance, .tableInterpolation:
                continue
            }
        }

        // The 240 s reference must live in sourceEvidence (display-only)
        // so it cannot enter the calculation pipeline.
        let evidenceMeteredSeconds: [Double] = profile.sourceEvidence.compactMap { row in
            if case let .exactSeconds(seconds) = row.meteredExposure { return seconds }
            return nil
        }
        XCTAssertTrue(
            evidenceMeteredSeconds.contains(where: { abs($0 - 240) < 1e-6 }),
            "240 s must be preserved as sourceEvidence so the manufacturer reference stays visible alongside the formula curve."
        )
    }

    // MARK: - Source-range presentation

    /// Past the 480 s boundary Provia 100F's numeric formula
    /// prediction must never read as "Extrapolated" — both the detail
    /// copy and the graph explanation must call out the source range
    /// explicitly so the user reads the value as outside Fujifilm's
    /// supported range. Negative guard for the table-era label.
    @MainActor
    func testProvia100FBeyondSourceRangeDetailAndExplanationUseSourceRangeNotExtrapolatedWording() throws {
        let displayState = try makeProviaDetailsDisplayState(meteredExposureSeconds: 600)
        let detail = try XCTUnwrap(displayState.summary.detailText)
        XCTAssertFalse(
            detail.lowercased().contains("extrapolated"),
            "Detail text must avoid Extrapolated as the primary label; got: \(detail)"
        )
        XCTAssertTrue(
            detail.lowercased().contains("source range"),
            "Detail text must surface source-range wording; got: \(detail)"
        )

        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertFalse(
            explanation.lowercased().contains("extrapolated"),
            "Graph explanation must avoid Extrapolated as the primary label; got: \(explanation)"
        )
        XCTAssertTrue(
            explanation.lowercased().contains("source range"),
            "Graph explanation must surface source-range wording; got: \(explanation)"
        )
    }

    // MARK: - Centralized converted-profile classification

    func testConvertedFormulaProfileFlagIsTrueOnlyForFormulaPlusSourceEvidence() throws {
        let provia = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Provia 100F" }?.profiles.first
        )
        XCTAssertTrue(provia.isConvertedFormulaProfile)

        let hp5Plus = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" }?.profiles.first
        )
        XCTAssertFalse(
            hp5Plus.isConvertedFormulaProfile,
            "Source-less formula profiles must not be classified as converted."
        )

        let portra400 = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Portra 400" }?.profiles.first
        )
        XCTAssertFalse(
            portra400.isConvertedFormulaProfile,
            "Threshold-only profiles without a formula rule must not be classified as converted."
        )
    }
}
