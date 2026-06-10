import XCTest
import PTimerCore

final class ReciprocityConfidencePresentationTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let mapper = ReciprocityConfidencePresentationMapper()

    // MARK: - No-correction (threshold-derived)

    func testThresholdNoCorrectionMapsToTrustedNoCorrectionPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.limitedGuidanceProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(presentation.category, .noCorrection)
        XCTAssertEqual(presentation.resultKind, .noCorrection)
        XCTAssertEqual(presentation.level, .high)
        XCTAssertEqual(presentation.badgeStyle, .trusted)
        XCTAssertEqual(presentation.warningEmphasis, .none)
        XCTAssertEqual(presentation.shortLabel, "No correction")
        XCTAssertTrue(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.thresholdGuidanceOnly))
    }

    // MARK: - Formula-derived

    func testFormulaDerivedMapsToMeasuredFormulaDerivedPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(presentation.category, .formulaDerived)
        XCTAssertEqual(presentation.resultKind, .formulaDerived)
        XCTAssertEqual(presentation.level, .medium)
        XCTAssertEqual(presentation.badgeStyle, .measured)
        XCTAssertEqual(presentation.warningEmphasis, .none)
        XCTAssertEqual(presentation.shortLabel, "Formula-derived")
        XCTAssertTrue(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.formulaDerived))
    }

    // MARK: - Limited guidance

    func testLimitedGuidanceMapsToLimitedGuidancePresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.limitedGuidanceProfile(),
            meteredExposureSeconds: 4
        )

        XCTAssertEqual(presentation.category, .limitedGuidance)
        XCTAssertEqual(presentation.resultKind, .limitedGuidance)
        XCTAssertEqual(presentation.level, .none)
        XCTAssertEqual(presentation.badgeStyle, .limitedGuidance)
        XCTAssertEqual(presentation.warningEmphasis, .note)
        XCTAssertEqual(presentation.shortLabel, "No quantified prediction")
        XCTAssertFalse(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.limitedGuidanceContinuationOnly))
        XCTAssertTrue(presentation.explanationTokens.contains(.officialRangeExceeded))
        XCTAssertFalse(presentation.explanationTokens.contains(.unsupportedByPolicy))
    }

    // MARK: - Unsupported

    func testBoundedFormulaPastSupportedRangeMapsToUnsupportedPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.formulaBoundedProfile(),
            meteredExposureSeconds: 601
        )

        XCTAssertEqual(presentation.category, .unsupported)
        XCTAssertEqual(presentation.resultKind, .unsupported)
        XCTAssertEqual(presentation.level, .none)
        XCTAssertEqual(presentation.badgeStyle, .unsupported)
        XCTAssertEqual(presentation.warningEmphasis, .strong)
        XCTAssertEqual(presentation.shortLabel, "Outside guidance")
        XCTAssertTrue(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.unsupportedByPolicy))
        XCTAssertTrue(presentation.explanationTokens.contains(.beyondPolicyLimit))
    }

    // MARK: - Authority impact

    func testArchivalOfficialPropagatesShortLabelPrefixAndExplanationToken() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(authority: .archivalOfficial),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(presentation.shortLabel, "Archival formula")
        XCTAssertEqual(presentation.level, .medium)
        XCTAssertTrue(presentation.explanationTokens.contains(.archivalOfficialSource))
    }

    func testUnofficialSecondaryPropagatesShortLabelPrefixAndExplanationToken() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(authority: .unofficialSecondary),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(presentation.shortLabel, "Secondary formula")
        XCTAssertEqual(presentation.level, .low)
        XCTAssertEqual(presentation.badgeStyle, .caution)
        XCTAssertTrue(presentation.explanationTokens.contains(.unofficialSecondarySource))
    }

    func testUserDefinedPropagatesShortLabelPrefixAndExplanationToken() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.barePowerLawFormulaProfile(authority: .userDefined),
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(presentation.shortLabel, "Custom formula")
        XCTAssertEqual(presentation.level, .veryLow)
        XCTAssertEqual(presentation.badgeStyle, .caution)
        XCTAssertTrue(presentation.explanationTokens.contains(.userDefinedSource))
    }

    // MARK: - Decoder validation

    func testDecodingRejectsContradictoryPresentationCategoryAndResultKind() {
        let json = """
        {
          "category": "unsupported",
          "level": "none",
          "badgeStyle": "unsupported",
          "warningEmphasis": "strong",
          "resultKind": "limitedGuidance",
          "shortLabel": "Outside guidance",
          "explanationTokens": ["unsupportedByPolicy", "noCalculatedExposureReturned"],
          "supportingNotes": [],
          "defaultExplanation": "Unsupported.",
          "returnsCalculatedExposureTime": false
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityConfidencePresentation.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("resultKind must remain aligned with category"))
        }
    }

    func testDecodingRejectsPresentationThatClaimsCalculatedExposureWithoutOne() {
        let json = """
        {
          "category": "limitedGuidance",
          "level": "none",
          "badgeStyle": "limitedGuidance",
          "warningEmphasis": "note",
          "resultKind": "limitedGuidance",
          "shortLabel": "No quantified prediction",
          "explanationTokens": ["limitedGuidanceContinuationOnly", "calculatedExposureReturned"],
          "supportingNotes": [],
          "defaultExplanation": "Limited guidance only.",
          "returnsCalculatedExposureTime": false
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityConfidencePresentation.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("calculated exposure time"))
        }
    }

    func testDecodingRejectsUnsupportedPresentationWithNonUnsupportedBadgeStyle() {
        let json = """
        {
          "category": "unsupported",
          "level": "none",
          "badgeStyle": "limitedGuidance",
          "warningEmphasis": "strong",
          "resultKind": "unsupported",
          "shortLabel": "Outside guidance",
          "explanationTokens": ["unsupportedByPolicy", "noCalculatedExposureReturned"],
          "supportingNotes": [],
          "defaultExplanation": "Unsupported.",
          "returnsCalculatedExposureTime": false
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityConfidencePresentation.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("unsupported badge styling"))
        }
    }

    private func presentation(
        profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> ReciprocityConfidencePresentation {
        let result = evaluator.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )

        return mapper.map(result: result)
    }
}
