import XCTest
import PTimerCore

/// Exercises every surviving evaluator path for the formula /
/// threshold / limited-guidance rule set. Table-rule tests were
/// removed with PTIMER-140; the catalog shape guard in
/// `LaunchPresetFilmCatalogShapeTests` makes sure no future preset
/// can reintroduce a table rule.
final class ReciprocityCalculationPolicyTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold no-correction

    func testThresholdRangeReturnsNoCorrectionBasis() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.limitedGuidanceProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertEqual(result.metadata.warningLevel, .none)
        XCTAssertEqual(result.metadata.notes.first?.token, .thresholdGuidanceOnly)
    }

    func testThresholdHandoffWithFormulaUsesNoCorrectionBasis() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - Formula-derived

    func testFormulaProfileWithinSupportedRangeIsFormulaDerived() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, pow(100, 1.31), accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
    }

    func testFormulaProfileWithoutExplicitMaxRemainsQuantifiedAtVeryLongInputs() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 8_192
        )

        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, pow(8_192, 1.31), accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
    }

    // MARK: - Formula past its supported boundary

    func testFormulaProfileBecomesUnsupportedPastSupportedRange() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.formulaBoundedProfile(),
            meteredExposureSeconds: 601
        )

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertTrue(
            result.hasCalculatedExposureTime,
            "Bounded formula past its supported range carries a numeric formula prediction."
        )
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, pow(601.0, 1.31), accuracy: 1.0)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.beyondOfficialQuantifiedRange, .unsupportedByPolicy]
        )
    }

    /// PTIMER-160 introduced the shared guarded formula model. Under
    /// the new contract `sourceRangeThroughSeconds` is purely a
    /// confidence boundary — the formula keeps producing a numeric
    /// corrected exposure past it, classified as outside source range
    /// with a strong warning. The legacy "hard stop" rule (a formula
    /// that returned nil past its boundary) no longer exists.
    func testFormulaProfileBeyondSourceRangeStillCarriesPrediction() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.formulaBoundedProfile(),
            meteredExposureSeconds: 1_000
        )

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, pow(1_000.0, 1.31), accuracy: 5.0)
    }

    // MARK: - Limited guidance

    func testLimitedGuidanceBeyondThresholdReturnsNoQuantifiedPrediction() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.limitedGuidanceProfile(),
            meteredExposureSeconds: 4
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .limitedGuidanceNoQuantifiedPrediction)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
        XCTAssertEqual(result.metadata.warningLevel, .note)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.limitedGuidanceContinuationOnly, .beyondOfficialQuantifiedRange]
        )
    }

    // MARK: - Unsupported

    func testProfileWithNoApplicableRuleIsUnsupported() {
        let result = evaluator.evaluate(
            profile: ReciprocityProfile(
                id: "empty-profile",
                name: "Empty profile",
                source: ReciprocitySourceProvenance(
                    kind: .manufacturerPublished,
                    authority: .official,
                    confidence: .high,
                    publisher: "Test"
                ),
                rules: []
            ),
            meteredExposureSeconds: 10
        )

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.notes.first?.token, .unsupportedByPolicy)
    }

    // MARK: - Authority impact

    func testArchivalOfficialProfilePropagatesAuthorityImpact() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(authority: .archivalOfficial),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .archivalOfficial)
        XCTAssertEqual(result.metadata.notes.last?.token, .archivalOfficialSource)
    }

    func testUnofficialSecondaryProfilePropagatesAuthorityImpact() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(authority: .unofficialSecondary),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .unofficialSecondary)
        XCTAssertEqual(result.metadata.notes.last?.token, .unofficialSecondarySource)
        XCTAssertEqual(result.metadata.warningLevel, .caution)
    }

    // MARK: - No-correction guard owned by the formula

    func testFormulaOnlyProfileBelowNoCorrectionThroughSecondsReturnsNoCorrection() {
        let profile = ReciprocityProfile(
            id: "unofficial-portra-400",
            name: "Unofficial practical",
            source: ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .low,
                publisher: ""
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        exponent: 1.34,
                        noCorrectionThroughSeconds: 1
                    )
                )),
            ]
        )

        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - Correction invariant

    func testCorrectedNeverShorterThanMetered() {
        // Synthetic formula with sub-unit exponent: `Tc = Tm^0.5` —
        // produces corrected values shorter than metered for inputs
        // above 1 s (e.g. 2 → √2 ≈ 1.414). The safety net must
        // reclassify those inputs to no-correction so a reciprocity
        // correction can never shorten the adjusted shutter.
        let profile = ReciprocityProfile(
            id: "shorter-corrected-formula",
            name: "Synthetic",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Test"
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        exponent: 0.5,
                        noCorrectionThroughSeconds: 1
                    )
                )),
            ]
        )

        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 2)

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 2, accuracy: 0.0001)
    }
}
