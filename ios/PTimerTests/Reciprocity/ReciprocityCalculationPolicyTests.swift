import XCTest
import PTimerCore
@testable import PTimer

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
            profile: ReciprocityPolicyScenarioFactory.portraLimitedGuidanceProfile(),
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
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - Formula-derived

    func testFormulaProfileWithinSupportedRangeIsFormulaDerived() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(),
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
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(),
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
            profile: ReciprocityPolicyScenarioFactory.portraLimitedGuidanceProfile(),
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
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(authority: .archivalOfficial),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .archivalOfficial)
        XCTAssertEqual(result.metadata.notes.last?.token, .archivalOfficialSource)
    }

    func testUnofficialSecondaryProfilePropagatesAuthorityImpact() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(authority: .unofficialSecondary),
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

enum ReciprocityPolicyScenarioFactory {
    /// HP5+-shaped formula profile (Tc = Tm^1.31 above 1s). Used as
    /// the canonical formula profile for tests that don't care about
    /// the manufacturer. Authority maps from the policy
    /// authority-impact enum so a single scenario can stand in for
    /// archival/secondary/user-defined variants.
    static func hp5FormulaProfile(
        authority: ReciprocitySourceAuthorityImpact = .currentOfficial
    ) -> ReciprocityProfile {
        ReciprocityProfile(
            id: "ilford-hp5-plus-official-formula",
            name: "Official formula",
            source: provenance(for: authority, publisher: "Ilford Photo"),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.31,
                            noCorrectionThroughSeconds: 1
                        ),
                        notes: ["Exponent p = 1.31."]
                    )
                ),
            ]
        )
    }

    /// Threshold + limited-guidance profile shape used by Kodak
    /// color negatives (Portra / Ektar / Gold).
    static func portraLimitedGuidanceProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "kodak-portra-official-threshold",
            name: "Official threshold guidance",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Kodak",
                title: "Reciprocity statement"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 1.0 / 10_000.0, maximumSeconds: 1),
                        notes: ["No correction required in the official range."]
                    )
                ),
                .limitedGuidance(
                    LimitedGuidanceReciprocityRule(
                        appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1),
                        adjustments: [
                            .note(ReciprocityNote(text: "Longer exposures: test under your conditions.")),
                        ]
                    )
                ),
            ]
        )
    }

    /// Formula profile whose `sourceRangeThroughSeconds = 600`
    /// triggers the beyond-source-range path: past the boundary the
    /// result is reclassified as `unsupported` but the formula still
    /// produces a numeric prediction (per the PTIMER-160 shared
    /// guarded formula contract — `sourceRangeThroughSeconds` is a
    /// confidence boundary, not a calculation stop).
    static func formulaBoundedProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "bounded-formula-profile",
            name: "Bounded formula",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Test Publisher"
            ),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.31,
                            noCorrectionThroughSeconds: 1,
                            sourceRangeThroughSeconds: 600
                        )
                    )
                ),
            ]
        )
    }

    private static func provenance(
        for authority: ReciprocitySourceAuthorityImpact,
        publisher: String
    ) -> ReciprocitySourceProvenance {
        switch authority {
        case .currentOfficial:
            return ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: publisher
            )
        case .archivalOfficial:
            return ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: publisher
            )
        case .unofficialSecondary:
            return ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .low,
                publisher: publisher
            )
        case .userDefined:
            return ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: publisher
            )
        }
    }
}
