import XCTest
@testable import PTimer

/// Locks the JSON shape of the surviving reciprocity rule kinds.
/// PTIMER-140 removed the table rule so this file no longer
/// round-trips synthetic table fixtures — the launch catalog shape
/// guard (`LaunchPresetFilmCatalogShapeTests`) is the structural
/// gate for "no table rules in the bundled catalog."
final class ReciprocityDomainTests: XCTestCase {

    // MARK: - Threshold + formula

    func testThresholdAndFormulaRulesRoundTripThroughJSON() throws {
        let film = FilmIdentity(
            id: "ilford-hp5-plus-400",
            kind: .preset,
            canonicalStockName: "HP5 Plus",
            manufacturer: "Ilford Photo",
            brandLabel: nil,
            aliases: [],
            iso: 400,
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "ilford-hp5-plus-400-official-formula",
                    name: "Official formula",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Ilford Photo"
                    ),
                    rules: [
                        .threshold(
                            ThresholdReciprocityRule(
                                noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1)
                            )
                        ),
                        .formula(
                            FormulaReciprocityRule(
                                meteredRange: ReciprocityTimeRange(minimumSeconds: 1.000_001),
                                formula: ReciprocityFormula(exponent: 1.31, equation: "Tc = Tm^P")
                            )
                        ),
                    ]
                ),
            ],
            userMetadata: nil
        )

        let data = try JSONEncoder().encode(film)
        let decoded = try JSONDecoder().decode(FilmIdentity.self, from: data)

        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].rules.count, 2)
        XCTAssertEqual(decoded.profiles[0].rules[0].kind, .threshold)
        XCTAssertEqual(decoded.profiles[0].rules[1].kind, .formula)
    }

    // MARK: - Limited guidance

    func testLimitedGuidanceRuleRoundTripsThroughJSON() throws {
        let profile = ReciprocityProfile(
            id: "kodak-portra-official-threshold",
            name: "Official threshold guidance",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Kodak"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 1.0 / 10_000.0, maximumSeconds: 1)
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

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ReciprocityProfile.self, from: data)

        XCTAssertEqual(decoded.rules.map(\.kind), [.threshold, .limitedGuidance])
        guard case let .limitedGuidance(rule) = decoded.rules[1] else {
            return XCTFail("Expected limited-guidance rule.")
        }
        XCTAssertEqual(rule.appliesWhenMetered, ReciprocityTimeRange(minimumSeconds: 1))
        XCTAssertEqual(rule.adjustments.count, 1)
        guard case let .note(note) = rule.adjustments[0] else {
            return XCTFail("Expected note payload.")
        }
        XCTAssertEqual(note.text, "Longer exposures: test under your conditions.")
    }

    // MARK: - Source evidence

    func testSourceEvidenceRowsRoundTripThroughJSON() throws {
        let profile = ReciprocityProfile(
            id: "fujifilm-provia-100f-official",
            name: "Official formula",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Fujifilm"
            ),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        meteredRange: ReciprocityTimeRange(minimumSeconds: 128.000_001, maximumSeconds: 480),
                        formula: ReciprocityFormula(
                            kind: .exponentPower,
                            exponent: 1.3676,
                            coefficient: pow(128.0, 1 - 1.3676)
                        )
                    )
                ),
            ],
            sourceEvidence: [
                ReciprocitySourceEvidenceRow(
                    meteredExposure: .exactSeconds(240),
                    adjustments: [
                        .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1.0 / 3.0))),
                        .colorFilter(ColorFilterRecommendation(filterName: "2.5G", note: nil)),
                    ]
                ),
                ReciprocitySourceEvidenceRow(
                    meteredExposure: .exactSeconds(480),
                    adjustments: [
                        .warning(ReciprocityWarning(severity: .notRecommended, message: "480 sec is not recommended.")),
                    ]
                ),
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ReciprocityProfile.self, from: data)

        XCTAssertEqual(decoded.sourceEvidence.count, 2)
        guard case let .exactSeconds(firstSeconds) = decoded.sourceEvidence[0].meteredExposure else {
            return XCTFail("Expected exactSeconds metered.")
        }
        XCTAssertEqual(firstSeconds, 240, accuracy: 1e-6)
        XCTAssertTrue(decoded.isConvertedFormulaProfile)
    }

    func testSourceEvidenceOnlyFlagRoundTripsThroughJSON() throws {
        let row = ReciprocitySourceEvidenceRow(
            meteredExposure: .exactSeconds(1.0 / 1000),
            adjustments: [.exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 0.5)))],
            isSourceEvidenceOnly: true
        )

        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(ReciprocitySourceEvidenceRow.self, from: data)

        XCTAssertEqual(decoded.isSourceEvidenceOnly, true)
    }

    func testSourceEvidenceOnlyFlagDefaultsToFalseWhenAbsent() throws {
        let json = #"""
        {
          "meteredExposure": { "kind": "exactSeconds", "exactSeconds": 240 },
          "adjustments": [],
          "notes": []
        }
        """#

        let decoded = try JSONDecoder().decode(ReciprocitySourceEvidenceRow.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.isSourceEvidenceOnly)
    }

    // MARK: - Rule discriminator validation

    func testReciprocityRuleKindRawValuesMatchTheJSONDiscriminator() {
        XCTAssertEqual(ReciprocityRuleKind.threshold.rawValue, "threshold")
        XCTAssertEqual(ReciprocityRuleKind.formula.rawValue, "formula")
        XCTAssertEqual(ReciprocityRuleKind.limitedGuidance.rawValue, "limitedGuidance")
    }

    func testDecoderRejectsUnknownReciprocityRuleKind() {
        let json = #"""
        {
          "kind": "tableLegacy",
          "tableLegacy": { "entries": [] }
        }
        """#

        XCTAssertThrowsError(try JSONDecoder().decode(ReciprocityRule.self, from: Data(json.utf8)))
    }
}
