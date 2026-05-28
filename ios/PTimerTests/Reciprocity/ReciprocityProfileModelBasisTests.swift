import Foundation
import XCTest
@testable import PTimer

/// PTIMER-163: catalog-level vocabulary distinguishing the
/// manufacturer's source data shape from the app's calculation
/// strategy. The vocabulary is descriptive metadata; this file pins
/// the decoding contract, the inferred-fallback semantics, and the
/// guarantee that adding the metadata does not change calculation
/// behavior for shipped profiles, custom (PTIMER-84) profiles, or
/// `sourceEvidence` treatment.
final class ReciprocityProfileModelBasisTests: XCTestCase {

    // MARK: - Bundled representative profiles carry explicit metadata

    func testBundledHP5PlusProfileDeclaresManufacturerFormulaSource() throws {
        let film = try XCTUnwrap(film(named: "HP5 Plus"))
        let basis = try XCTUnwrap(film.profiles[0].modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerFormula)
        XCTAssertEqual(basis.calculationModel, .guardedFormula)
    }

    func testBundledTriX400ProfileDeclaresTableSourceWithGuardedFormulaCalculation() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let basis = try XCTUnwrap(film.profiles[0].modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .guardedFormula)
    }

    func testBundledFomapan100ProfileDeclaresTableSourceWithGuardedFormulaCalculation() throws {
        let film = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        let basis = try XCTUnwrap(film.profiles[0].modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .guardedFormula)
    }

    func testBundledEktar100ProfileDeclaresLimitedGuidanceSource() throws {
        let film = try XCTUnwrap(film(named: "Ektar 100"))
        let basis = try XCTUnwrap(film.profiles[0].modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerLimitedGuidance)
        XCTAssertEqual(basis.calculationModel, .limitedGuidance)
    }

    // MARK: - Calculation behavior is unchanged by adding metadata

    func testAddingModelBasisDoesNotChangeHP5PlusFormulaCalculation() throws {
        let film = try XCTUnwrap(film(named: "HP5 Plus"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: film.profiles[0], meteredExposureSeconds: 4)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, pow(4.0, 1.31), accuracy: 0.0001)
    }

    func testAddingModelBasisDoesNotChangeTriX400FormulaCalculation() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: film.profiles[0], meteredExposureSeconds: 1)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, 2, accuracy: 0.05)
    }

    func testAddingModelBasisDoesNotChangeEktar100LimitedGuidanceCalculation() throws {
        let film = try XCTUnwrap(film(named: "Ektar 100"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: film.profiles[0], meteredExposureSeconds: 30)

        guard case let .limitedGuidance(payload) = result else {
            return XCTFail("Expected limited-guidance result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .limitedGuidanceNoQuantifiedPrediction)
    }

    // MARK: - `sourceEvidence` remains display-only

    func testTriX400SourceEvidenceIsNotPromotedToCalculationAnchor() throws {
        // Source evidence rows publish the 1 sec / 10 sec / 100 sec
        // anchors; the metered/corrected mappings shall never be
        // consumed by the policy. The 10 sec input still evaluates
        // through the formula (≈ 50 sec is the published row, but the
        // free LSQ fit predicts a nearby value, never the row itself).
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        XCTAssertFalse(film.profiles[0].sourceEvidence.isEmpty)

        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: film.profiles[0], meteredExposureSeconds: 10)
        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        // Formula prediction at 10 s: 2.013654 × 10^1.3891 ≈ 49.4 s.
        let expected = 2.013654 * pow(10.0, 1.3891)
        XCTAssertEqual(payload.correctedExposureSeconds, expected, accuracy: 0.01)
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
        // T-MAX 100 ships as a converted-formula profile with
        // `sourceEvidence` but does not yet declare `modelBasis`.
        // The inferred basis treats source-evidence + formula as a
        // table-origin source converted to a derived guarded formula.
        let film = try XCTUnwrap(film(named: "T-MAX 100"))
        XCTAssertNil(film.profiles[0].modelBasis)
        XCTAssertFalse(film.profiles[0].sourceEvidence.isEmpty)

        let basis = film.profiles[0].effectiveModelBasis
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .guardedFormula)
    }

    func testEffectiveModelBasisInfersLimitedGuidanceForThresholdPlusLimitedGuidanceProfile() throws {
        // Portra 400 ships as threshold + limited-guidance and does
        // not declare `modelBasis`. The inferred basis must classify
        // it as manufacturer limited guidance.
        let film = try XCTUnwrap(film(named: "Portra 400"))
        XCTAssertNil(film.profiles[0].modelBasis)

        let basis = film.profiles[0].effectiveModelBasis
        XCTAssertEqual(basis.sourceModel, .manufacturerLimitedGuidance)
        XCTAssertEqual(basis.calculationModel, .limitedGuidance)
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
    /// source shape (e.g. Rollei RETRO 80S's "1 to 2 sec" row). No
    /// shipped profile declares this value yet; the fixture-level
    /// round-trip pins the contract that the loader will accept it on
    /// an otherwise valid official manufacturer profile.
    func testLoaderAcceptsManufacturerRangeGuidanceSourceModelOnFormulaProfile() throws {
        let probeFilm = try shapeProbeFilm(
            profile: ReciprocityProfile(
                id: "range-source.formula",
                name: "Range-source compatibility probe",
                source: officialSource(),
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
