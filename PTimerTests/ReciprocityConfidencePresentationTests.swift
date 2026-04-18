import XCTest
@testable import PTimer

final class ReciprocityConfidencePresentationTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let mapper = ReciprocityConfidencePresentationMapper()

    func testTriXExactTablePointMapsToTrustedExactPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 10
        )

        XCTAssertEqual(presentation.category, .exact)
        XCTAssertEqual(presentation.resultKind, .exact)
        XCTAssertEqual(presentation.level, .high)
        XCTAssertEqual(presentation.badgeStyle, .trusted)
        XCTAssertEqual(presentation.warningEmphasis, .none)
        XCTAssertEqual(presentation.shortLabel, "Exact")
        XCTAssertTrue(presentation.returnsCalculatedExposureTime)
        XCTAssertEqual(
            presentation.explanationTokens,
            [
                .exactTablePoint,
                .currentOfficialSource,
                .withinStatedRange,
                .calculatedExposureReturned
            ]
        )
    }

    func testTriXInterpolationMapsToEstimatedPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 5
        )

        XCTAssertEqual(presentation.category, .estimated)
        XCTAssertEqual(presentation.resultKind, .estimated)
        XCTAssertEqual(presentation.level, .medium)
        XCTAssertEqual(presentation.badgeStyle, .measured)
        XCTAssertEqual(presentation.warningEmphasis, .note)
        XCTAssertEqual(presentation.shortLabel, "Estimated")
        XCTAssertTrue(presentation.explanationTokens.contains(.interpolatedEstimate))
        XCTAssertTrue(presentation.explanationTokens.contains(.withinInterpretedRange))
        XCTAssertTrue(presentation.explanationTokens.contains(.logLogEstimation))
        XCTAssertEqual(
            presentation.supportingNotes,
            ["Interpolated between original representative table rows."]
        )
        XCTAssertEqual(
            presentation.defaultExplanation,
            "Interpolated between original representative table rows."
        )
    }

    func testTriXExtrapolationMapsToLowerConfidenceExtrapolatedPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 300
        )

        XCTAssertEqual(presentation.category, .extrapolated)
        XCTAssertEqual(presentation.resultKind, .extrapolated)
        XCTAssertEqual(presentation.level, .low)
        XCTAssertEqual(presentation.badgeStyle, .caution)
        XCTAssertEqual(presentation.warningEmphasis, .caution)
        XCTAssertEqual(presentation.shortLabel, "Extrapolated")
        XCTAssertNotEqual(presentation.category, .estimated)
        XCTAssertNotEqual(presentation.resultKind, .estimated)
        XCTAssertTrue(presentation.explanationTokens.contains(.extrapolatedEstimate))
        XCTAssertTrue(presentation.explanationTokens.contains(.beyondRepresentativePoint))
        XCTAssertTrue(presentation.explanationTokens.contains(.logLogEstimation))
    }

    func testVelviaStopSignalMapsToUnsupportedPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 64
        )

        XCTAssertEqual(presentation.category, .unsupported)
        XCTAssertEqual(presentation.resultKind, .unsupported)
        XCTAssertEqual(presentation.level, .none)
        XCTAssertEqual(presentation.badgeStyle, .unsupported)
        XCTAssertEqual(presentation.warningEmphasis, .strong)
        XCTAssertEqual(presentation.shortLabel, "Unsupported")
        XCTAssertFalse(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.explicitStopSignal))
        XCTAssertTrue(presentation.explanationTokens.contains(.unsupportedByPolicy))
        XCTAssertTrue(presentation.explanationTokens.contains(.beyondPolicyLimit))
    }

    func testPortraThresholdNoCorrectionRemainsDistinctFromInterpolation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(presentation.category, .exact)
        XCTAssertEqual(presentation.resultKind, .exact)
        XCTAssertEqual(presentation.level, .high)
        XCTAssertEqual(presentation.badgeStyle, .trusted)
        XCTAssertEqual(presentation.warningEmphasis, .none)
        XCTAssertEqual(presentation.shortLabel, "No correction")
        XCTAssertTrue(presentation.explanationTokens.contains(.thresholdGuidanceOnly))
        XCTAssertFalse(presentation.explanationTokens.contains(.interpolatedEstimate))
    }

    func testPortraAdvisoryOnlyDoesNotCollapseIntoUnsupported() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 4
        )

        XCTAssertEqual(presentation.category, .advisoryOnly)
        XCTAssertEqual(presentation.resultKind, .advisoryOnly)
        XCTAssertEqual(presentation.level, .none)
        XCTAssertEqual(presentation.badgeStyle, .advisory)
        XCTAssertEqual(presentation.warningEmphasis, .note)
        XCTAssertEqual(presentation.shortLabel, "Advisory")
        XCTAssertFalse(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.advisoryContinuationOnly))
        XCTAssertTrue(presentation.explanationTokens.contains(.officialRangeExceeded))
        XCTAssertFalse(presentation.explanationTokens.contains(.unsupportedByPolicy))
    }

    func testFormulaDerivedResultRoutesThroughEstimatedPresentationFamily() {
        let presentation = mapper.map(
            result: ReciprocityCalculationPolicyResult(
                meteredExposureSeconds: 2,
                correctedExposureSeconds: 3.5,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .formulaDerived,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .withinInterpretedRange,
                    warningLevel: .none,
                    notes: [
                        ReciprocityPolicyNote(
                            token: nil,
                            text: "Calculated from a formula-backed reciprocity profile."
                        )
                    ]
                )
            )
        )

        XCTAssertEqual(presentation.category, .estimated)
        XCTAssertEqual(presentation.resultKind, .estimated)
        XCTAssertEqual(presentation.level, .medium)
        XCTAssertEqual(presentation.badgeStyle, .measured)
        XCTAssertEqual(presentation.shortLabel, "Calculated")
        XCTAssertTrue(presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(presentation.explanationTokens.contains(.formulaDerived))
        XCTAssertTrue(presentation.explanationTokens.contains(.withinInterpretedRange))
        XCTAssertEqual(
            presentation.defaultExplanation,
            "Calculated from a formula-backed reciprocity profile."
        )
    }

    func testArchivalOfficialExactRemainsDistinctFromCurrentOfficialExact() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.agfaArchivalProfile(),
            meteredExposureSeconds: 10
        )

        XCTAssertEqual(presentation.category, .exact)
        XCTAssertEqual(presentation.level, .medium)
        XCTAssertEqual(presentation.badgeStyle, .measured)
        XCTAssertEqual(presentation.warningEmphasis, .note)
        XCTAssertEqual(presentation.shortLabel, "Archival exact")
        XCTAssertTrue(presentation.explanationTokens.contains(.archivalOfficialSource))
    }

    func testUnofficialSecondaryExactMapsMoreCautiouslyThanCurrentOfficial() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.portraSecondaryProfile(),
            meteredExposureSeconds: 2
        )

        XCTAssertEqual(presentation.category, .exact)
        XCTAssertEqual(presentation.level, .low)
        XCTAssertEqual(presentation.badgeStyle, .caution)
        XCTAssertEqual(presentation.warningEmphasis, .caution)
        XCTAssertEqual(presentation.shortLabel, "Secondary exact")
        XCTAssertTrue(presentation.explanationTokens.contains(.unofficialSecondarySource))
    }

    func testUserDefinedExactMapsToMostCautiousCalculatedPresentation() {
        let presentation = presentation(
            profile: ReciprocityPolicyScenarioFactory.customUserDefinedProfile(),
            meteredExposureSeconds: 1
        )

        XCTAssertEqual(presentation.category, .exact)
        XCTAssertEqual(presentation.level, .veryLow)
        XCTAssertEqual(presentation.badgeStyle, .caution)
        XCTAssertEqual(presentation.warningEmphasis, .caution)
        XCTAssertEqual(presentation.shortLabel, "Custom exact")
        XCTAssertTrue(presentation.explanationTokens.contains(.userDefinedSource))
    }

    func testCurrentArchivalUnofficialAndUserDefinedRemainDistinctAcrossLabelsAndTokens() {
        let currentOfficial = presentation(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 10
        )
        let archival = presentation(
            profile: ReciprocityPolicyScenarioFactory.agfaArchivalProfile(),
            meteredExposureSeconds: 10
        )
        let unofficial = presentation(
            profile: ReciprocityPolicyScenarioFactory.portraSecondaryProfile(),
            meteredExposureSeconds: 2
        )
        let userDefined = presentation(
            profile: ReciprocityPolicyScenarioFactory.customUserDefinedProfile(),
            meteredExposureSeconds: 1
        )

        XCTAssertNotEqual(currentOfficial.shortLabel, archival.shortLabel)
        XCTAssertNotEqual(archival.shortLabel, unofficial.shortLabel)
        XCTAssertNotEqual(unofficial.shortLabel, userDefined.shortLabel)
        XCTAssertTrue(archival.explanationTokens.contains(.archivalOfficialSource))
        XCTAssertTrue(unofficial.explanationTokens.contains(.unofficialSecondarySource))
        XCTAssertTrue(userDefined.explanationTokens.contains(.userDefinedSource))
    }

    func testDecodingRejectsContradictoryPresentationCategoryAndResultKind() {
        let json = """
        {
          "category": "unsupported",
          "level": "none",
          "badgeStyle": "unsupported",
          "warningEmphasis": "strong",
          "resultKind": "advisoryOnly",
          "shortLabel": "Unsupported",
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
          "category": "advisoryOnly",
          "level": "none",
          "badgeStyle": "advisory",
          "warningEmphasis": "note",
          "resultKind": "advisoryOnly",
          "shortLabel": "Advisory",
          "explanationTokens": ["advisoryContinuationOnly", "calculatedExposureReturned"],
          "supportingNotes": [],
          "defaultExplanation": "Advisory only.",
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
          "badgeStyle": "advisory",
          "warningEmphasis": "strong",
          "resultKind": "unsupported",
          "shortLabel": "Unsupported",
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
