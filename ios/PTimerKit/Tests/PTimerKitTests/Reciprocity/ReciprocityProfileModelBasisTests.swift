// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit
import PTimerCore
import XCTest

/// PTIMER-163: catalog-level vocabulary distinguishing the
/// manufacturer's source data shape from the app's calculation
/// strategy. The vocabulary is descriptive metadata; this file pins
/// the decoding contract, the inferred-fallback semantics, and the
/// guarantee that adding the metadata does not change calculation
/// behavior for shipped profiles, custom (PTIMER-84) profiles, or
/// `sourceEvidence` treatment.
final class ReciprocityProfileModelBasisTests: XCTestCase {

    // MARK: - Bundled representative profiles declare the expected basis

    private struct ModelBasisDeclaration {
        let film: String
        let sourceModel: ReciprocitySourceModel
        let calculationModel: ReciprocityCalculationModel
    }

    /// Each bundled representative profile declares the model basis its
    /// archetype implies. Provenance / archetype is case data, not a
    /// per-film test.
    func testBundledProfilesDeclareExpectedModelBasis() throws {
        let declarations: [ModelBasisDeclaration] = [
            .init(film: "HP5 Plus", sourceModel: .manufacturerFormula, calculationModel: .guardedFormula),
            .init(film: "Tri-X 400", sourceModel: .manufacturerGraphTable, calculationModel: .tableLogLogInterpolation),
            .init(film: "Fomapan 100 Classic", sourceModel: .manufacturerTable, calculationModel: .tableLogLogInterpolation),
            .init(film: "Ektar 100", sourceModel: .manufacturerLimitedGuidance, calculationModel: .limitedGuidance),
        ]
        for d in declarations {
            let film = try XCTUnwrap(film(named: d.film), "\(d.film) must remain in the launch catalog.")
            let basis = try XCTUnwrap(film.profiles[0].modelBasis, "\(d.film): must declare a modelBasis.")
            XCTAssertEqual(basis.sourceModel, d.sourceModel, "\(d.film): sourceModel")
            XCTAssertEqual(basis.calculationModel, d.calculationModel, "\(d.film): calculationModel")
        }
    }

    // MARK: - Adding model-basis metadata does not change calculation

    private struct CalcCheck {
        let film: String
        let sample: Double
        let expectedBasis: ReciprocityCalculationBasis
        let expectedCorrected: Double?
        var correctedAccuracy: Double = 1e-4
        var requiresSourceEvidence = false
    }

    /// The descriptive model-basis metadata is additive: each bundled
    /// profile's calculation (basis + corrected exposure) is unchanged, and
    /// table profiles keep their `sourceEvidence` display-only alongside the
    /// table anchors (the calculation reads the table rule's own anchors).
    func testModelBasisMetadataDoesNotChangeCalculation() throws {
        let checks: [CalcCheck] = [
            .init(film: "HP5 Plus", sample: 4, expectedBasis: .formulaDerived, expectedCorrected: pow(4.0, 1.31)),
            .init(film: "Tri-X 400", sample: 1, expectedBasis: .tableLogLogDerived, expectedCorrected: 2),
            .init(film: "Tri-X 400", sample: 10, expectedBasis: .tableLogLogDerived, expectedCorrected: 50, requiresSourceEvidence: true),
            .init(film: "Ektar 100", sample: 30, expectedBasis: .limitedGuidanceNoQuantifiedPrediction, expectedCorrected: nil),
        ]
        for c in checks {
            let film = try XCTUnwrap(film(named: c.film), "\(c.film) must remain in the launch catalog.")
            if c.requiresSourceEvidence {
                XCTAssertFalse(film.profiles[0].sourceEvidence.isEmpty, "\(c.film): table profile keeps display-only source evidence.")
            }
            let result = ReciprocityCalculationPolicyEvaluator().evaluate(profile: film.profiles[0], meteredExposureSeconds: c.sample)
            XCTAssertEqual(result.metadata.basis, c.expectedBasis, "\(c.film) @ \(c.sample)s: basis")
            if let expected = c.expectedCorrected {
                XCTAssertEqual(try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(c.sample)s: corrected"), expected, accuracy: c.correctedAccuracy, "\(c.film) @ \(c.sample)s: corrected")
            } else {
                XCTAssertNil(result.correctedExposureSeconds, "\(c.film) @ \(c.sample)s: must not surface a corrected exposure")
            }
        }
    }

    // MARK: - Optional / inferred basis behavior

    func testProfileWithoutExplicitBasisDecodesUnchanged() throws {
        // FP4 Plus does not declare an explicit `modelBasis`; this
        // pins the additive-field contract so older catalog entries
        // continue to decode without being forced to migrate.
        let film = try XCTUnwrap(film(named: "FP4 Plus"))
        XCTAssertNil(film.profiles[0].modelBasis)
    }

    func testEffectiveModelBasisInfersManufacturerFormulaForBareFormulaProfile() throws {
        let film = try XCTUnwrap(film(named: "FP4 Plus"))
        let basis = film.profiles[0].effectiveModelBasis
        XCTAssertEqual(basis.sourceModel, .manufacturerFormula)
        XCTAssertEqual(basis.calculationModel, .guardedFormula)
    }

    func testEffectiveModelBasisInfersManufacturerTableForFormulaWithSourceEvidence() throws {
        // A converted-formula profile with `sourceEvidence` and no
        // declared `modelBasis` infers as a table-origin source
        // converted to a derived guarded formula. (Provia 100F
        // previously covered this case but declared an explicit basis
        // in PTIMER-169, so the inference contract is pinned on a
        // fixture.)
        let profile = inferenceProbeProfile(
            rules: [probeFormulaRule()],
            sourceEvidence: [
                ReciprocitySourceEvidenceRow(
                    meteredExposure: .exactSeconds(4),
                    adjustments: [
                        .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 4, correctedSeconds: 8))),
                    ]
                ),
            ]
        )
        XCTAssertNil(profile.modelBasis)
        XCTAssertEqual(profile.effectiveModelBasis.sourceModel, .manufacturerTable)
        XCTAssertEqual(profile.effectiveModelBasis.calculationModel, .guardedFormula)
    }

    func testEffectiveModelBasisInfersLimitedGuidanceForThresholdPlusLimitedGuidanceProfile() throws {
        // A threshold + limited-guidance profile with no declared
        // `modelBasis` infers as manufacturer limited guidance.
        // (Portra 400 previously covered this case but declared an
        // explicit basis in PTIMER-169, so the inference contract is
        // pinned on a fixture.)
        let profile = inferenceProbeProfile(rules: [
            .threshold(ThresholdReciprocityRule(
                noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1)
            )),
            .limitedGuidance(LimitedGuidanceReciprocityRule(
                appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1)
            )),
        ])
        XCTAssertNil(profile.modelBasis)
        XCTAssertEqual(profile.effectiveModelBasis.sourceModel, .manufacturerLimitedGuidance)
        XCTAssertEqual(profile.effectiveModelBasis.calculationModel, .limitedGuidance)
    }

    // MARK: - JSON round-trip

    func testExplicitModelBasisRoundTripsThroughJSON() throws {
        let profile = ReciprocityProfile(
            id: "test.formula",
            name: "Test",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                publisher: "Test"
            ),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.3,
                            noCorrectionThroughSeconds: 1
                        )
                    )
                ),
            ],
            modelBasis: ReciprocityProfileModelBasis(
                sourceModel: .manufacturerTable,
                calculationModel: .guardedFormula
            )
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ReciprocityProfile.self, from: data)
        XCTAssertEqual(decoded.modelBasis?.sourceModel, .manufacturerTable)
        XCTAssertEqual(decoded.modelBasis?.calculationModel, .guardedFormula)
    }

    func testAbsentModelBasisDecodesAsNil() throws {
        let json = #"""
        {
          "id": "legacy.profile",
          "name": "Legacy",
          "rules": [
            {
              "kind": "formula",
              "formula": {
                "additionalAdjustments": [],
                "formula": {
                  "exponent": 1.3,
                  "formulaFamily": "modifiedSchwarzschild",
                  "noCorrectionThroughSeconds": 1
                },
                "notes": []
              }
            }
          ],
          "source": {
            "authority": "official",
            "confidence": "high",
            "kind": "manufacturerPublished",
            "publisher": "Test"
          }
        }
        """#

        let decoded = try JSONDecoder().decode(ReciprocityProfile.self, from: Data(json.utf8))
        XCTAssertNil(decoded.modelBasis)
        XCTAssertEqual(decoded.effectiveModelBasis.sourceModel, .manufacturerFormula)
        XCTAssertEqual(decoded.effectiveModelBasis.calculationModel, .guardedFormula)
    }

    // MARK: - PTIMER-84 custom formula compatibility

    func testCustomUserDefinedFormulaProfileDecodesWithoutModelBasisField() throws {
        // PTIMER-84 custom profiles persist without a `modelBasis`
        // field. The catalog domain must continue to accept that shape
        // and the inferred basis must classify it as user-defined +
        // guarded formula.
        let profile = ReciprocityProfile(
            id: "custom.user-defined.formula",
            name: "Custom",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.34,
                            noCorrectionThroughSeconds: 1
                        )
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ReciprocityProfile.self, from: data)

        XCTAssertNil(decoded.modelBasis)
        XCTAssertEqual(decoded.effectiveModelBasis.sourceModel, .userDefined)
        XCTAssertEqual(decoded.effectiveModelBasis.calculationModel, .guardedFormula)

        // Calculation must still work for the custom profile.
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: decoded, meteredExposureSeconds: 4)
        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified result for custom formula profile, got \(result).")
        }
        XCTAssertEqual(payload.correctedExposureSeconds, pow(4.0, 1.34), accuracy: 0.0001)
    }

    // MARK: - Loader rejects inconsistent and unimplemented metadata

    func testLoaderRejectsExplicitGuardedFormulaBasisOnLimitedGuidanceProfile() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.guarded-on-limited",
                name: "Mismatched basis",
                source: officialSource(),
                rules: [
                    .threshold(
                        ThresholdReciprocityRule(
                            noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1)
                        )
                    ),
                    .limitedGuidance(
                        LimitedGuidanceReciprocityRule(
                            appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1)
                        )
                    ),
                ],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .manufacturerFormula,
                    calculationModel: .guardedFormula
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.calculationModel = guardedFormula requires a formula rule"
            )
        )
    }

    func testLoaderRejectsExplicitLimitedGuidanceBasisOnFormulaProfile() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.limited-on-formula",
                name: "Mismatched basis",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .manufacturerLimitedGuidance,
                    calculationModel: .limitedGuidance
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.calculationModel = limitedGuidance requires a limited-guidance rule"
            )
        )
    }

    func testLoaderRejectsTableLookupCalculationModelAsUnimplemented() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.table-lookup",
                name: "Reserved",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .manufacturerTable,
                    calculationModel: .tableLookup
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.calculationModel = tableLookup is not yet implemented"
            )
        )
    }

    func testLoaderRejectsUnsupportedCalculationModelAsUnimplemented() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.unsupported-calc",
                name: "Reserved",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .manufacturerFormula,
                    calculationModel: .unsupported
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.calculationModel = unsupported is not implemented for launch preset modelBasis yet"
            )
        )
    }

    func testLoaderRejectsPracticalCommunitySourceModelForOfficialBundledCatalog() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.practical-source-on-official",
                name: "Mismatched provenance",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .practicalCommunityGuidance,
                    calculationModel: .guardedFormula
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.sourceModel = practicalCommunityGuidance is not allowed for the official manufacturer launch catalog"
            )
        )
    }

    func testLoaderRejectsUserDefinedSourceModelForOfficialBundledCatalog() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.user-defined-source-on-official",
                name: "Mismatched provenance",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .userDefined,
                    calculationModel: .guardedFormula
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.sourceModel = userDefined is not allowed for the official manufacturer launch catalog"
            )
        )
    }

    func testLoaderRejectsExplicitUnknownSourceModelForBundledCatalog() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "bad.unknown-source-on-official",
                name: "Unknown source",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .unknown,
                    calculationModel: .guardedFormula
                )
            )
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )
        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "modelBasis.sourceModel = unknown is not allowed for the launch catalog; omit modelBasis to rely on the inferred fallback"
            )
        )
    }

    // MARK: - Range-guidance source model compatibility

    /// PTIMER-163 lists `manufacturerRangeGuidance` as a representable
    /// source shape; PTIMER-169 ships it on Acros II. The fixture-level
    /// round-trip pins the contract that the loader accepts it on
    /// an otherwise valid official manufacturer profile.
    func testLoaderAcceptsManufacturerRangeGuidanceSourceModelOnFormulaProfile() throws {
        let probeFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "range-source.formula",
                name: "Range-source compatibility probe",
                source: officialSource(),
                rules: [probeFormulaRule()],
                modelBasis: ReciprocityProfileModelBasis(
                    sourceModel: .manufacturerRangeGuidance,
                    calculationModel: .guardedFormula
                )
            )
        )
        let data = try JSONEncoder().encode([probeFilm])

        let loaded = try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
        XCTAssertEqual(loaded.count, 1)
        let basis = try XCTUnwrap(loaded[0].profiles[0].modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerRangeGuidance)
        XCTAssertEqual(basis.calculationModel, .guardedFormula)
    }

    func testManufacturerRangeGuidanceSourceModelRoundTripsThroughJSON() throws {
        let basis = ReciprocityProfileModelBasis(
            sourceModel: .manufacturerRangeGuidance,
            calculationModel: .guardedFormula
        )

        let data = try JSONEncoder().encode(basis)
        let decoded = try JSONDecoder().decode(ReciprocityProfileModelBasis.self, from: data)
        XCTAssertEqual(decoded.sourceModel, .manufacturerRangeGuidance)
        XCTAssertEqual(decoded.calculationModel, .guardedFormula)
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }

    private func officialSource() -> ReciprocitySourceProvenance {
        ReciprocitySourceProvenance(
            kind: .manufacturerPublished,
            authority: .official,
            confidence: .high,
            publisher: "Test"
        )
    }

    private func probeFormulaRule() -> ReciprocityRule {
        .formula(FormulaReciprocityRule(
            formula: ReciprocityFormula(exponent: 1.3, noCorrectionThroughSeconds: 1)
        ))
    }

    private func inferenceProbeProfile(
        rules: [ReciprocityRule],
        sourceEvidence: [ReciprocitySourceEvidenceRow] = []
    ) -> ReciprocityProfile {
        ReciprocityProfile(
            id: "inference.probe",
            name: "Inference probe",
            source: officialSource(),
            rules: rules,
            sourceEvidence: sourceEvidence
        )
    }

    private func shapeProbeFilm(profile: ReciprocityProfile) throws -> FilmIdentity {
        // Carries the profile (and its provenance) through unchanged
        // so source-mismatch probes exercise the validator instead of
        // being silently overwritten by the base film's source.
        let baseFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        return FilmIdentity(
            id: baseFilm.id,
            kind: baseFilm.kind,
            canonicalStockName: baseFilm.canonicalStockName,
            manufacturer: baseFilm.manufacturer,
            brandLabel: baseFilm.brandLabel,
            aliases: baseFilm.aliases,
            iso: baseFilm.iso,
            productionStatus: baseFilm.productionStatus,
            profiles: [profile],
            userMetadata: baseFilm.userMetadata
        )
    }

    private func assertThrowsAndReturn<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Error? {
        do {
            _ = try expression()
            XCTFail("Expected expression to throw an error.", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }
}
