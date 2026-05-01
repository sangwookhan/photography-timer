import XCTest
@testable import PTimer

final class ReciprocityCalculationPolicyTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    func testTriXExactTablePointIsEvaluatorBacked() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 10
        )

        XCTAssertEqual(result.meteredExposureSeconds, 10, accuracy: 0.0001)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 50, accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertEqual(result.metadata.warningLevel, .none)
        XCTAssertNil(result.metadata.estimationFamily)
        XCTAssertEqual(result.metadata.notes.map(\.token), [.exactManufacturerTablePoint])
        XCTAssertEqual(result.metadata.referencedRows?.count, 1)
        XCTAssertEqual(result.metadata.referencedRows?.first?.role, .exactMatch)
        XCTAssertEqual(try result.metadata.referencedRows?.map(exactSeconds), [10])
    }

    func testTriXBelowOneSecondRemainsUnsupportedWithoutThresholdGuidance() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondPolicyLimit)
        XCTAssertNil(result.metadata.referencedRows)
    }

    func testTriXAtOneSecondDoesNotBecomeUnsupported() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 1
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 2, accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
    }

    func testTriXInterpolationUsesLogLogEvaluatorMathAndOriginalBounds() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 5
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .interpolatedWithinTable)
        XCTAssertEqual(result.metadata.estimationFamily, .logLog)
        XCTAssertEqual(result.metadata.rangeStatus, .withinInterpretedRange)
        XCTAssertEqual(result.metadata.warningLevel, .note)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            logLogEstimate(
                meteredExposureSeconds: 5,
                lowerMeteredSeconds: 1,
                lowerCorrectedSeconds: 2,
                upperMeteredSeconds: 10,
                upperCorrectedSeconds: 50
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(referencedRows.map(\.role), [.lowerBound, .upperBound])
        XCTAssertEqual(try referencedRows.map(exactSeconds), [1, 10])
        XCTAssertFalse(try referencedRows.map(exactSeconds).contains(5))
    }

    func testTriXExtrapolationUsesLogLogEvaluatorMathWithinPolicyLimit() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 300
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(result.metadata.estimationFamily, .logLog)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
        XCTAssertEqual(result.metadata.warningLevel, .caution)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            logLogEstimate(
                meteredExposureSeconds: 300,
                lowerMeteredSeconds: 10,
                lowerCorrectedSeconds: 50,
                upperMeteredSeconds: 100,
                upperCorrectedSeconds: 1_200
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(referencedRows.map(\.role), [.representativeAnchor, .representativeAnchor])
        XCTAssertEqual(try referencedRows.map(exactSeconds), [10, 100])
        XCTAssertFalse(try referencedRows.map(exactSeconds).contains(300))
    }

    func testTriXLongerExtrapolationRemainsQuantifiedWithinExtendedPolicyLimit() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 1_000
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(result.metadata.estimationFamily, .logLog)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
        XCTAssertEqual(result.metadata.warningLevel, .caution)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            logLogEstimate(
                meteredExposureSeconds: 1_000,
                lowerMeteredSeconds: 10,
                lowerCorrectedSeconds: 50,
                upperMeteredSeconds: 100,
                upperCorrectedSeconds: 1_200
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(referencedRows.map(\.role), [.representativeAnchor, .representativeAnchor])
        XCTAssertEqual(try referencedRows.map(exactSeconds), [10, 100])
        XCTAssertFalse(try referencedRows.map(exactSeconds).contains(1_000))
    }

    func testTriXVeryLongExtrapolationRemainsQuantifiedWithoutGenericUpperBoundary() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 10_000
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
        XCTAssertEqual(result.metadata.warningLevel, .caution)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            logLogEstimate(
                meteredExposureSeconds: 10_000,
                lowerMeteredSeconds: 10,
                lowerCorrectedSeconds: 50,
                upperMeteredSeconds: 100,
                upperCorrectedSeconds: 1_200
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(referencedRows.map(\.role), [.representativeAnchor, .representativeAnchor])
        XCTAssertEqual(result.metadata.notes.map(\.token), [.estimatedFromRepresentativeRows, .beyondRepresentativeTablePoint])
    }

    func testVelviaInterpolationUsesStopSpaceEvaluatorMath() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 12
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .interpolatedWithinTable)
        XCTAssertEqual(result.metadata.estimationFamily, .stopSpace)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .withinInterpretedRange)
        XCTAssertEqual(result.metadata.warningLevel, .note)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            stopSpaceEstimate(
                meteredExposureSeconds: 12,
                lowerMeteredSeconds: 8,
                lowerStopDelta: 0.5,
                upperMeteredSeconds: 16,
                upperStopDelta: 2.0 / 3.0
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(try referencedRows.map(exactSeconds), [8, 16])
        XCTAssertEqual(referencedRows.map(\.annotationSummary), ["7.5M", "10M"])
    }

    func testMismatchedQuantifiedFamiliesDoNotAssembleEstimatedResult() {
        let result = evaluator.evaluate(
            profile: ReciprocityProfile(
                id: "mixed-estimation-families",
                name: "Mixed estimation families",
                source: ReciprocitySourceProvenance(
                    kind: .manufacturerPublished,
                    authority: .official,
                    confidence: .high,
                    publisher: "Test"
                ),
                rules: [
                    .table(
                        TableReciprocityRule(
                            entries: [
                                ReciprocityTableEntry(
                                    meteredExposure: .exactSeconds(1),
                                    adjustments: [
                                        .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 1, correctedSeconds: 2)))
                                    ]
                                ),
                                ReciprocityTableEntry(
                                    meteredExposure: .exactSeconds(10),
                                    adjustments: [
                                        .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2)))
                                    ]
                                )
                            ]
                        )
                    )
                ]
            ),
            meteredExposureSeconds: 5
        )

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNil(result.metadata.estimationFamily)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.notes.map(\.token), [.unsupportedByPolicy])
    }

    func testVelviaExplicitStopSignalOverridesAtExactBoundary() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 64
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondPolicyLimit)
        XCTAssertEqual(result.metadata.warningLevel, .strongWarning)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.explicitManufacturerStopSignal, .unsupportedByPolicy]
        )
        XCTAssertEqual(result.metadata.referencedRows?.map(\.role), [.stopSignal])
    }

    func testVelviaStopSignalAlsoOverridesBeyondBoundary() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 80
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(result.metadata.warningLevel, .strongWarning)
        XCTAssertEqual(result.metadata.referencedRows?.map(\.role), [.stopSignal])
    }

    // MARK: - Velvia 50 threshold-to-table transition range (PTIMER-109)

    func testVelviaAtOneSecondReturnsThresholdNoCorrection() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 1
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertNil(result.metadata.referencedRows)
    }

    func testVelviaAtTwoSecondsReturnsExtrapolatedNotUnsupported() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 2
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(result.metadata.estimationFamily, .stopSpace)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            stopSpaceEstimate(
                meteredExposureSeconds: 2,
                lowerMeteredSeconds: 4,
                lowerStopDelta: 1.0 / 3.0,
                upperMeteredSeconds: 8,
                upperStopDelta: 0.5
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(try referencedRows.map(exactSeconds), [4, 8])
        XCTAssertEqual(referencedRows.map(\.role), [.representativeAnchor, .representativeAnchor])
    }

    func testVelviaAtFourSecondsRemainsExactTablePoint() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 4
        )

        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 4 * pow(2.0, 1.0 / 3.0), accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
    }

    func testVelviaAtEightSecondsRemainsExactTablePoint() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 8
        )

        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 8 * pow(2.0, 0.5), accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
    }

    func testVelviaAtFifteenSecondsRemainsInterpolatedWithinTable() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 15
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .interpolatedWithinTable)
        XCTAssertEqual(result.metadata.estimationFamily, .stopSpace)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            stopSpaceEstimate(
                meteredExposureSeconds: 15,
                lowerMeteredSeconds: 8,
                lowerStopDelta: 0.5,
                upperMeteredSeconds: 16,
                upperStopDelta: 2.0 / 3.0
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(try referencedRows.map(exactSeconds), [8, 16])
    }

    func testVelviaAtSixtySecondsRemainsExtrapolatedBelowStopSignal() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.velviaProfile(),
            meteredExposureSeconds: 60
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(result.metadata.estimationFamily, .stopSpace)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            stopSpaceEstimate(
                meteredExposureSeconds: 60,
                lowerMeteredSeconds: 16,
                lowerStopDelta: 2.0 / 3.0,
                upperMeteredSeconds: 32,
                upperStopDelta: 1.0
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(try referencedRows.map(exactSeconds), [16, 32])
    }

    func testTableOnlyProfileBelowFirstEntryWithoutThresholdRemainsUnsupported() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
    }

    func testPortraThresholdNoCorrectionRemainsNonQuantifiedContinuationBoundary() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertEqual(result.metadata.warningLevel, .none)
        XCTAssertEqual(result.metadata.notes.map(\.token), [.thresholdGuidanceOnly])
        XCTAssertNil(result.metadata.referencedRows)
    }

    func testPortraAdvisoryOnlyBeyondOfficialRangeDoesNotFabricateCorrectedTime() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 4
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .advisoryOnlyBeyondOfficialRange)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
        XCTAssertEqual(result.metadata.warningLevel, .note)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.advisoryContinuationOnly, .beyondOfficialQuantifiedRange]
        )
    }

    func testHP5FormulaProfileRemainsQuantifiedAtLongMeteredExposureWithoutExplicitUpperBoundary() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.hp5FormulaProfile(),
            meteredExposureSeconds: 8_192
        )

        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, pow(8_192, 1.31), accuracy: 0.0001)
        XCTAssertNotEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
    }

    func testFormulaProfileBecomesUnsupportedOnlyWhenExplicitUpperBoundaryExists() {
        let result = evaluator.evaluate(
            profile: ReciprocityProfile(
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
                            meteredRange: ReciprocityTimeRange(minimumSeconds: 1, maximumSeconds: 600),
                            formula: ReciprocityFormula(exponent: 1.31, equation: "Tc = Tm^P"),
                            notes: ["Exponent P = 1.31."]
                        )
                    )
                ]
            ),
            meteredExposureSeconds: 601
        )

        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.beyondOfficialQuantifiedRange, .unsupportedByPolicy]
        )
    }

    func testAgfapanArchivalOfficialExactResultCarriesArchivalMetadata() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.agfaArchivalProfile(),
            meteredExposureSeconds: 10
        )
        let referencedRows = try XCTUnwrap(result.metadata.referencedRows)

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 40, accuracy: 0.0001)
        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .archivalOfficial)
        XCTAssertEqual(result.metadata.rangeStatus, .withinStatedRange)
        XCTAssertEqual(result.metadata.warningLevel, .note)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.exactManufacturerTablePoint, .archivalOfficialSource]
        )
        XCTAssertEqual(try referencedRows.map(exactSeconds), [10])
    }

    func testUnofficialSecondaryProfileMapsSourceAuthorityImpact() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.portraSecondaryProfile(),
            meteredExposureSeconds: 2
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 3, accuracy: 0.0001)
        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .unofficialSecondary)
        XCTAssertEqual(result.metadata.warningLevel, .caution)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.exactManufacturerTablePoint, .unofficialSecondarySource]
        )
    }

    func testUserDefinedProfileMapsSourceAuthorityImpact() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.customUserDefinedProfile(),
            meteredExposureSeconds: 1
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .userDefined)
        XCTAssertEqual(result.metadata.warningLevel, .caution)
        XCTAssertEqual(
            result.metadata.notes.map(\.token),
            [.exactManufacturerTablePoint, .userDefinedSource]
        )
    }

    func testPolicyResultRoundTripPreservesMetadataShape() throws {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.triXProfile(),
            meteredExposureSeconds: 5
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: data)

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.hasCalculatedExposureTime, true)
    }

    func testDecodingRejectsContradictoryCalculatedExposureFlag() throws {
        let json = """
        {
          "meteredExposureSeconds": 10,
          "correctedExposureSeconds": 50,
          "hasCalculatedExposureTime": false,
          "metadata": {
            "basis": "exactTablePoint",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "withinStatedRange",
            "warningLevel": "none",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityResult.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("hasCalculatedExposureTime"))
        }
    }

    func testDecodingRejectsExactTablePointWithEstimationFamily() {
        let json = """
        {
          "meteredExposureSeconds": 10,
          "correctedExposureSeconds": 50,
          "hasCalculatedExposureTime": true,
          "metadata": {
            "basis": "exactTablePoint",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "withinStatedRange",
            "warningLevel": "none",
            "estimationFamily": "logLog",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityResult.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("must not carry an estimation family"))
        }
    }

    func testDecodingRejectsInterpolatedResultWithoutEstimationFamily() {
        let json = """
        {
          "meteredExposureSeconds": 5,
          "correctedExposureSeconds": 15,
          "hasCalculatedExposureTime": true,
          "metadata": {
            "basis": "interpolatedWithinTable",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "withinInterpretedRange",
            "warningLevel": "note",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityResult.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("must carry an estimation family"))
        }
    }

    func testDecodingRejectsThresholdNoCorrectionWhenCorrectedExposureDiffersFromMetered() {
        let json = """
        {
          "meteredExposureSeconds": 0.5,
          "correctedExposureSeconds": 0.75,
          "hasCalculatedExposureTime": true,
          "metadata": {
            "basis": "officialThresholdNoCorrection",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "withinStatedRange",
            "warningLevel": "none",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityResult.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("corrected exposure equal to metered exposure"))
        }
    }

    func testDecodingRejectsAdvisoryOnlyResultThatReturnsCorrectedExposure() {
        let json = """
        {
          "meteredExposureSeconds": 4,
          "correctedExposureSeconds": 8,
          "hasCalculatedExposureTime": true,
          "metadata": {
            "basis": "advisoryOnlyBeyondOfficialRange",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "beyondLastRepresentativePoint",
            "warningLevel": "note",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityResult.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("must not return a corrected exposure time"))
        }
    }

    func testDecodingRejectsUnsupportedResultThatReturnsCorrectedExposure() {
        let json = """
        {
          "meteredExposureSeconds": 1000,
          "correctedExposureSeconds": 1200,
          "hasCalculatedExposureTime": true,
          "metadata": {
            "basis": "unsupportedOutOfPolicyRange",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "beyondPolicyLimit",
            "warningLevel": "strongWarning",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReciprocityResult.self,
                from: Data(json.utf8)
            )
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertTrue(context.debugDescription.contains("must not return a corrected exposure time"))
        }
    }

    private func exactSeconds(_ row: ReciprocityTableRowReference) throws -> Double {
        guard case let .exactSeconds(value) = row.meteredExposure else {
            throw NSError(domain: "ReciprocityCalculationPolicyTests", code: 1)
        }

        return value
    }

    private func logLogEstimate(
        meteredExposureSeconds: Double,
        lowerMeteredSeconds: Double,
        lowerCorrectedSeconds: Double,
        upperMeteredSeconds: Double,
        upperCorrectedSeconds: Double
    ) -> Double {
        let slope = log(upperCorrectedSeconds / lowerCorrectedSeconds)
            / log(upperMeteredSeconds / lowerMeteredSeconds)
        return lowerCorrectedSeconds * pow(meteredExposureSeconds / lowerMeteredSeconds, slope)
    }

    private func stopSpaceEstimate(
        meteredExposureSeconds: Double,
        lowerMeteredSeconds: Double,
        lowerStopDelta: Double,
        upperMeteredSeconds: Double,
        upperStopDelta: Double
    ) -> Double {
        let intervalStops = log2(upperMeteredSeconds / lowerMeteredSeconds)
        let progressStops = log2(meteredExposureSeconds / lowerMeteredSeconds)
        let interpolatedStopDelta = lowerStopDelta
            + ((upperStopDelta - lowerStopDelta) * (progressStops / intervalStops))
        return meteredExposureSeconds * pow(2.0, interpolatedStopDelta)
    }
}

enum ReciprocityPolicyScenarioFactory {
    static func triXProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "kodak-tri-x-official-table",
            name: "Official table",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Kodak",
                title: "Reciprocity data",
                citation: "Data sheet"
            ),
            rules: [
                .table(
                    TableReciprocityRule(
                        entries: [
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(1),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1))),
                                    .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 1, correctedSeconds: 2))),
                                    .development(DevelopmentAdjustment(instruction: "-10% development", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(10),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2))),
                                    .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 10, correctedSeconds: 50))),
                                    .development(DevelopmentAdjustment(instruction: "-20% development", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(100),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 3))),
                                    .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 100, correctedSeconds: 1_200))),
                                    .development(DevelopmentAdjustment(instruction: "-30% development", note: nil))
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    static func velviaProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "fujifilm-velvia-official-table",
            name: "Official table and color guidance",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Fujifilm",
                title: "Long exposure guide"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 1.0 / 4000.0, maximumSeconds: 1)
                    )
                ),
                .table(
                    TableReciprocityRule(
                        entries: [
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(4),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1.0 / 3.0))),
                                    .colorFilter(ColorFilterRecommendation(filterName: "5M", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(8),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 0.5))),
                                    .colorFilter(ColorFilterRecommendation(filterName: "7.5M", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(16),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2.0 / 3.0))),
                                    .colorFilter(ColorFilterRecommendation(filterName: "10M", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(32),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1))),
                                    .colorFilter(ColorFilterRecommendation(filterName: "12.5M", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(64),
                                adjustments: [
                                    .warning(ReciprocityWarning(
                                        severity: .notRecommended,
                                        message: "64 sec is not recommended."
                                    ))
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    static func portraOfficialProfile() -> ReciprocityProfile {
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
                .advisory(
                    AdvisoryReciprocityRule(
                        appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1),
                        adjustments: [
                            .note(ReciprocityNote(text: "Longer exposures: test under your conditions."))
                        ]
                    )
                )
            ]
        )
    }

    static func portraSecondaryProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "kodak-portra-secondary-table",
            name: "Secondary reference table",
            source: ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .medium,
                publisher: "Independent reciprocity notes",
                title: "Field-tested secondary profile"
            ),
            rules: [
                .table(
                    TableReciprocityRule(
                        entries: [
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(2),
                                adjustments: [
                                    .exposure(.multiplier(MultiplierAdjustment(factor: 1.5)))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(8),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 0.5)))
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    static func agfaArchivalProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "agfa-archival-official",
            name: "Archival official profile",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: "Agfa archive",
                title: "Archived reciprocity data",
                sourceVersion: "legacy"
            ),
            rules: [
                .table(
                    TableReciprocityRule(
                        entries: [
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(1),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1))),
                                    .development(DevelopmentAdjustment(instruction: "-10% development", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(10),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2))),
                                    .development(DevelopmentAdjustment(instruction: "-25% development", note: nil))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(100),
                                adjustments: [
                                    .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 3))),
                                    .development(DevelopmentAdjustment(instruction: "-35% development", note: nil))
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    static func hp5FormulaProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "ilford-hp5-plus-official-formula",
            name: "Official formula",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Ilford Photo",
                title: "Reciprocity characteristics",
                citation: "Technical information sheet",
                sourceVersion: "2026"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1),
                        notes: ["No compensation required at 1 second or less."]
                    )
                ),
                .formula(
                    FormulaReciprocityRule(
                        meteredRange: ReciprocityTimeRange(minimumSeconds: 1.000_001),
                        formula: ReciprocityFormula(
                            exponent: 1.31,
                            equation: "Tc = Tm^P"
                        ),
                        notes: ["Exponent P = 1.31."]
                    )
                )
            ]
        )
    }

    static func customUserDefinedProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "custom-user-profile",
            name: "User-defined table",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: "Local User"
            ),
            rules: [
                .table(
                    TableReciprocityRule(
                        entries: [
                            ReciprocityTableEntry(
                                meteredExposure: .exactSeconds(1),
                                adjustments: [
                                    .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 1, correctedSeconds: 1.5)))
                                ]
                            ),
                            ReciprocityTableEntry(
                                meteredExposure: .range(ReciprocityTimeRange(minimumSeconds: 5, maximumSeconds: 10)),
                                adjustments: [
                                    .exposure(.multiplier(MultiplierAdjustment(factor: 1.8))),
                                    .note(ReciprocityNote(text: "User-entered estimate."))
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    }

    /// Synthetic formula profile with an explicit upper boundary so the
    /// `unsupportedFormulaBoundary` evaluator branch can be reached without
    /// modifying any catalog film. Mirrors the HP5 shape (exponent 1.31)
    /// but caps `meteredRange` at 30s.
    static func formulaBoundedProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-formula-bounded-30s",
            name: "Bounded formula profile",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Synthetic Vendor",
                title: "Bounded reciprocity formula"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1)
                    )
                ),
                .formula(
                    FormulaReciprocityRule(
                        meteredRange: ReciprocityTimeRange(minimumSeconds: 1.000_001, maximumSeconds: 30),
                        formula: ReciprocityFormula(
                            exponent: 1.31,
                            equation: "Tc = Tm^P"
                        ),
                        notes: ["Exponent P = 1.31 within bounded range."]
                    )
                )
            ]
        )
    }

    /// Variant of `triXProfile` with archival-official source. Used to
    /// exercise the warning-level matrix on quantified table paths.
    static func triXArchivalProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-tri-x-archival",
            name: "Archival Tri-X variant",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: "Kodak archive",
                title: "Archived Tri-X reciprocity",
                sourceVersion: "legacy"
            ),
            rules: triXProfile().rules
        )
    }

    /// Variant of `triXProfile` with unofficial-secondary source.
    static func triXSecondaryProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-tri-x-secondary",
            name: "Secondary Tri-X variant",
            source: ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .medium,
                publisher: "Independent reciprocity notes"
            ),
            rules: triXProfile().rules
        )
    }

    /// Variant of `triXProfile` with user-defined source.
    static func triXUserDefinedProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-tri-x-user-defined",
            name: "User-defined Tri-X variant",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: "Local User"
            ),
            rules: triXProfile().rules
        )
    }

    /// Variant of `hp5FormulaProfile` with archival source. Used to
    /// exercise the warning-level matrix on the `formulaDerived` branch.
    static func hp5ArchivalFormulaProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-hp5-archival",
            name: "Archival HP5 formula",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: "Ilford archive",
                title: "Archived reciprocity",
                sourceVersion: "legacy"
            ),
            rules: hp5FormulaProfile().rules
        )
    }

    /// Variant of `hp5FormulaProfile` with user-defined source.
    static func hp5UserDefinedFormulaProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-hp5-user-defined",
            name: "User-defined HP5 formula",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: "Local User"
            ),
            rules: hp5FormulaProfile().rules
        )
    }

    /// Variant of `velviaProfile` with archival source so stop-signal
    /// extrapolation can be re-exercised under a non-current authority.
    static func velviaArchivalProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-velvia-archival",
            name: "Archival Velvia variant",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: "Fujifilm archive",
                title: "Archived long exposure guide",
                sourceVersion: "legacy"
            ),
            rules: velviaProfile().rules
        )
    }

    /// Variant of `portraOfficialProfile` with archival source so the
    /// advisory-only branch can be exercised across authorities.
    static func portraArchivalAdvisoryProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-portra-archival-advisory",
            name: "Archival Portra advisory",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: "Kodak archive",
                title: "Archived advisory"
            ),
            rules: portraOfficialProfile().rules
        )
    }

    /// Variant of `portraOfficialProfile` with secondary source.
    static func portraSecondaryAdvisoryProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-portra-secondary-advisory",
            name: "Secondary Portra advisory",
            source: ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .medium,
                publisher: "Independent reciprocity notes"
            ),
            rules: portraOfficialProfile().rules
        )
    }

    /// Variant of `portraOfficialProfile` with user-defined source.
    static func portraUserDefinedAdvisoryProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "synthetic-portra-user-defined-advisory",
            name: "User-defined Portra advisory",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: "Local User"
            ),
            rules: portraOfficialProfile().rules
        )
    }
}
