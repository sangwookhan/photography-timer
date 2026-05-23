import XCTest
@testable import PTimer

/// Provia 100F is calculated by a constrained, threshold-anchored
/// formula. These tests lock the invariants:
///
/// - Below the 128 s no-correction threshold, the threshold rule wins.
/// - In (128, 480) the formula wins (basis == `.formulaDerived`).
/// - 240 s — the manufacturer's published +1/3-stop reference point —
///   produces a formula-derived corrected exposure of ≈302 s. The
///   reference is preserved as `sourceEvidence`, never as a
///   calculation rule.
/// - At and beyond 480 s — the manufacturer's "not recommended"
///   boundary — the basis is `.unsupportedOutOfPolicyRange` and the
///   result still carries a numeric formula prediction outside the
///   source range (visibly marked outside manufacturer guidance).
///   480 s is never used as a formula fitting point.
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

    // MARK: - Formula range (128 s … 480 s exclusive)

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

    func testProvia100FBetweenThresholdAndStopSignalIsFormulaDerived() throws {
        let profile = try proviaProfile()

        for metered in [150.0, 200.0, 360.0, 470.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "Metered \(metered) s in the formula range must be formula-derived."
            )
        }
    }

    func testProvia100FFormulaExponentMatchesPublishedReference() throws {
        let profile = try proviaProfile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, 1.3676, accuracy: 0.0001)

        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        // coefficient = 128^(1 - 1.3676) = 128^(-0.3676) ≈ 0.16803
        XCTAssertEqual(coefficient, pow(128.0, 1 - 1.3676), accuracy: 0.0005)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("128"),
            "Equation text must communicate the 128 s anchor; got: \(equation)"
        )
    }

    // MARK: - Unsupported boundary (≥ 480 s) with formula prediction outside source range

    func testProvia100FAt480SecondsIsUnsupportedWithFormulaPredictionOutsideSourceRange() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 480)

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)

        // The boundary itself sits outside manufacturer guidance, but
        // the formula can still produce a value the user can act on.
        // Tc = 128 × (480 / 128)^1.3676 = 128 × 3.75^1.3676 ≈ 781 s.
        let corrected = try XCTUnwrap(
            result.correctedExposureSeconds,
            "480 s must carry a numeric formula prediction outside the source range, not nil."
        )
        let expected = 128.0 * pow(480.0 / 128.0, 1.3676)
        XCTAssertEqual(corrected, expected, accuracy: 1.5)
    }

    func testProvia100FBeyond480SecondsProducesFormulaPredictionAndStaysUnsupported() throws {
        let profile = try proviaProfile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 500)

        XCTAssertEqual(
            result.metadata.basis,
            .unsupportedOutOfPolicyRange,
            "Beyond the 480 s boundary the result remains classified as outside manufacturer guidance."
        )

        let corrected = try XCTUnwrap(
            result.correctedExposureSeconds,
            "Formula must keep producing a numeric prediction past the manufacturer boundary."
        )
        let expected = 128.0 * pow(500.0 / 128.0, 1.3676)
        XCTAssertEqual(corrected, expected, accuracy: 1.5)
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
            case .threshold, .formula, .limitedGuidance:
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

    @MainActor
    func testProvia100FCorrectedExposureNoLongerCarriesSecondaryDescription() throws {
        // Detail surfaces the long-form note via the graph note;
        // the Main corrected-exposure card no longer renders a
        // per-state caption. The model state therefore returns an
        // empty secondary text for every numeric reciprocity case
        // — both supported and outside-guidance.
        let film = try proviaFilm()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()

        for metered in [240.0, 600.0] {
            let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: metered)
            let bindingState = FilmModeReciprocityBindingState(
                film: film,
                profile: profile,
                policyResult: policyResult,
                presentation: policyResult.confidencePresentation
            )
            let correctedDisplay = model.correctedExposureDisplayState(for: bindingState)
            XCTAssertEqual(
                correctedDisplay.secondaryText,
                "",
                "Metered \(metered) s: numeric reciprocity results must not surface a Main secondary description; the detail/graph note carries any long-form explanation."
            )
        }
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
