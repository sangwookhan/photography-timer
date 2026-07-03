// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
import PTimerCore

final class LaunchPresetFilmCatalogV2Tests: XCTestCase {
    private let meteredInputs = [0.5, 1, 2, 5, 10, 30, 60, 120, 300, 1_000]

    func testBundledV2CatalogDeclaresExpectedLaunchInvariants() throws {
        let document = try bundledV2Document()
        let v2Films = try LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()

        XCTAssertEqual(document.schema, "ptimer.catalog.v2")
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.films.count, 40)
        XCTAssertEqual(v2Films.count, 40)

        let filmIDs = document.films.map(\.id)
        let profileIDs = document.films.flatMap { film in film.profiles.map(\.id) }
        XCTAssertEqual(filmIDs.count, Set(filmIDs).count)
        XCTAssertEqual(profileIDs.count, Set(profileIDs).count)
        XCTAssertEqual(document.sources.count, Set(document.sources.keys).count)

        for film in document.films {
            XCTAssertEqual(
                film.profiles.filter { $0.role == "primary" }.count,
                1,
                "\(film.id) must declare exactly one primary profile."
            )

            for profile in film.profiles {
                XCTAssertNotNil(document.sources[profile.sourceId], "\(profile.id) sourceId must resolve.")
                assertCalculationMatchesModel(profile, filmID: film.id)
                assertEvidenceGrammarDecodes(profile, filmID: film.id)
            }
        }

        for film in v2Films {
            XCTAssertEqual(film.profiles.count, 1, "\(film.id) must adapt exactly one primary profile.")
            XCTAssertFalse(film.profiles[0].id.isEmpty)
        }
    }

    func testBundledV2CatalogPrimaryProfileExposureGolden() throws {
        XCTAssertEqual(goldenExposureRows(), expectedGoldenExposureRows)
    }

    func testProvidesUserVisibleOfficialSourceTreatsBlankUrlsAsMissing() {
        // PTIMER-158: the per-profile visibility predicate must match Android —
        // nil, empty, and whitespace-only source-page URLs all count as missing,
        // and an unofficial profile never qualifies regardless of its URL.
        func profile(_ authority: ReciprocityAuthority, _ url: String?) -> ReciprocityProfile {
            ReciprocityProfile(
                id: "t", name: "t",
                source: ReciprocitySourceProvenance(
                    kind: .manufacturerPublished, authority: authority, confidence: .high,
                    publisher: "p", title: nil, citation: nil, sourceVersion: nil
                ),
                rules: [],
                sourcePageUrl: url
            )
        }
        XCTAssertFalse(profile(.official, nil).providesUserVisibleOfficialSource)
        XCTAssertFalse(profile(.official, "").providesUserVisibleOfficialSource)
        XCTAssertFalse(profile(.official, "   \n\t ").providesUserVisibleOfficialSource)
        XCTAssertTrue(profile(.official, "https://example.com/x").providesUserVisibleOfficialSource)
        XCTAssertFalse(
            profile(.unofficial, "https://example.com/x").providesUserVisibleOfficialSource,
            "An unofficial profile never counts, even with a URL."
        )
        XCTAssertFalse(
            profile(.userDefined, "https://example.com/x").providesUserVisibleOfficialSource,
            "Only official authority qualifies; other authorities never count."
        )
    }

    func testUserSelectableFilmsRequireOfficialSourceLinks() throws {
        // PTIMER-158 (0.7): the user-facing list ships official sources only —
        // a film is selectable only with an official profile that also carries
        // a verified source-page link. That hides the community/practical
        // Retro 400S. PTIMER-200 added source-page links to the previously
        // official-but-unlinked Rollei RPX 25 / ORTHO 25 plus, so they are no
        // longer hidden. PTIMER-200 also found ILFORD SFX 200's official
        // datasheet has no reciprocity formula/table/graph at all -- the
        // shipped exponent has no verified source, so its source-page link
        // was removed to hide it from selection rather than present a
        // fabricated official formula. The full catalog keeps Retro 400S and
        // SFX 200 for later restoration.
        let hidden = ["rollei-retro-400s", "ilford-sfx-200"]
        let selectable = LaunchPresetFilmCatalogV2.userSelectableFilms
        for id in hidden {
            XCTAssertTrue(
                LaunchPresetFilmCatalogV2.films.contains { $0.id == id },
                "The full catalog must keep \(id) so the data is available for restoration."
            )
            XCTAssertFalse(
                selectable.contains { $0.id == id },
                "\(id) lacks a verified official source link and must be hidden from selection."
            )
        }
        XCTAssertTrue(selectable.contains { $0.id == "kodak-portra-400" })
        XCTAssertTrue(selectable.contains { $0.id == "ilford-pan-f-plus-50" })
        XCTAssertTrue(selectable.contains { $0.id == "adox-chs-100-ii" }, "A source-page-only official film stays visible.")
        XCTAssertEqual(selectable.count, LaunchPresetFilmCatalogV2.films.count - hidden.count)
        for film in selectable {
            XCTAssertTrue(
                film.profiles.contains { $0.source.authority != .unofficial && ($0.sourcePageUrl?.isEmpty == false) },
                "\(film.id) must expose an official profile with a source-page link to be user-selectable."
            )
        }
    }

    func testBundledPromotedRolleiRetro400SPrimaryLoads() throws {
        let films = try LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        let film = try XCTUnwrap(films.first { $0.id == "rollei-retro-400s" })
        let profile = try XCTUnwrap(film.profiles.first)

        XCTAssertEqual(profile.id, "rollei-retro-400s-unofficial-practical")
        XCTAssertEqual(profile.source.kind, .thirdPartyPublication)
        XCTAssertEqual(profile.source.authority, .unofficial)
        XCTAssertEqual(profile.source.confidence, .medium)
        XCTAssertEqual(profile.source.publisher, "Stéphane Lafitte")
        XCTAssertEqual(
            profile.modelBasis,
            ReciprocityProfileModelBasis(
                sourceModel: .practicalCommunityGuidance,
                calculationModel: .guardedFormula
            )
        )
        XCTAssertEqual(profile.sourceEvidence.count, 3)
    }

    func testRejectsCalculationKindDiscriminator() {
        XCTAssertThrowsError(try LaunchPresetFilmCatalogV2Loader().loadCatalog(from: invalidCalculationKindData())) { error in
            guard case .malformedResource = error as? LaunchPresetFilmCatalogV2LoaderError else {
                return XCTFail("Expected malformedResource, got \(error)")
            }
        }
    }

    func testRejectsExplicitNullCorrectedReferencePoint() {
        assertThrowsMalformedResource(explicitNullReferencePointData())
    }

    func testRejectsFormulaCalculationWithTableOnlyAnchorsKey() {
        assertThrowsMalformedResource(catalogData(profileJSON: formulaProfileJSON(calculationFields: """
        ,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 }
            ]
        """)))
    }

    func testRejectsFormulaCalculationWithLimitedGuidanceOnlyNoCorrectionRangeKey() {
        assertThrowsMalformedResource(catalogData(profileJSON: formulaProfileJSON(calculationFields: """
        ,
            "noCorrectionRange": [0, 1]
        """)))
    }

    func testRejectsTableCalculationWithFormulaOnlyFamilyKey() {
        assertThrowsMalformedResource(catalogData(profileJSON: tableProfileJSON(calculationFields: """
        ,
            "family": "modifiedSchwarzschild"
        """)))
    }

    func testRejectsTableCalculationWithLimitedGuidanceOnlyGuidanceKey() {
        assertThrowsMalformedResource(catalogData(profileJSON: tableProfileJSON(calculationFields: """
        ,
            "guidance": [
              { "fromSeconds": 1, "message": "No quantified guidance." }
            ]
        """)))
    }

    func testRejectsLimitedGuidanceCalculationWithTableOnlyAnchorsKey() {
        assertThrowsMalformedResource(catalogData(profileJSON: limitedGuidanceProfileJSON(calculationFields: """
        ,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 }
            ]
        """)))
    }

    func testRejectsLimitedGuidanceCalculationWithFormulaOnlyExponentKey() {
        assertThrowsMalformedResource(catalogData(profileJSON: limitedGuidanceProfileJSON(calculationFields: """
        ,
            "exponent": 1.2
        """)))
    }

    func testRejectsTableProfileWithReferencePointsCarrier() {
        assertThrowsInvalidRuleShape(catalogData(profileJSON: tableProfileJSON(carriers: """
        ,
              "referencePoints": [
                { "meteredSeconds": 2, "correctedSeconds": 3 }
              ]
        """)))
    }

    func testRejectsFormulaProfileWithTableEvidenceCarrier() {
        assertThrowsInvalidRuleShape(catalogData(profileJSON: formulaProfileJSON(carriers: """
        ,
              "evidence": [
                { "anchor": 0 }
              ]
        """)))
    }

    func testRejectsLimitedGuidanceProfileWithSourceEvidenceCarrier() {
        assertThrowsInvalidRuleShape(catalogData(profileJSON: limitedGuidanceProfileJSON(carriers: """
        ,
              "referenceRanges": [
                { "fromSeconds": 2, "throughSeconds": 4, "note": "source range" }
              ]
        """)))
    }

    func testRejectsPromotedUnofficialPrimaryWithHighConfidenceSource() {
        assertThrowsInvalidRuleShape(catalogData(
            sourceJSON: unofficialSourceJSON(confidence: "high"),
            profileJSON: promotedUnofficialFormulaProfileJSON()
        ))
    }

    func testRejectsPromotedUnofficialPrimaryWithoutPracticalCommunityBasis() {
        assertThrowsInvalidRuleShape(catalogData(
            sourceJSON: unofficialSourceJSON(),
            profileJSON: promotedUnofficialFormulaProfileJSON(basis: "manufacturerFormula")
        ))
    }

    func testRejectsPromotedUnofficialPrimaryWithEmptyReferencePoints() {
        assertThrowsInvalidRuleShape(catalogData(
            sourceJSON: unofficialSourceJSON(),
            profileJSON: promotedUnofficialFormulaProfileJSON(referencePoints: "[]")
        ))
    }

    func testRejectsPromotedUnofficialPrimaryBackedByOfficialManufacturerSource() {
        assertThrowsInvalidRuleShape(catalogData(
            sourceJSON: sourceJSON(
                sourceType: "manufacturerPublished",
                authority: "official",
                confidence: "medium"
            ),
            profileJSON: promotedUnofficialFormulaProfileJSON()
        ))
    }

    func testRejectsPromotedUnofficialPrimaryWithNonFormulaModel() {
        assertThrowsInvalidRuleShape(catalogData(
            sourceJSON: unofficialSourceJSON(),
            profileJSON: promotedUnofficialTableProfileJSON()
        ))
    }

    func testRejectsExplicitNullSourceLink() {
        assertThrowsMalformedResource(catalogData(sourceJSON: sourceJSON(additionalFields: """
        ,
              "links": { "landingPageUrl": null }
        """)))
    }

    func testRejectsExplicitNullSourceTitle() {
        assertThrowsMalformedResource(catalogData(sourceJSON: sourceJSON(additionalFields: """
        ,
              "title": null
        """)))
    }

    func testSourceLinksAreDroppedFromAdaptedOutput() throws {
        let withoutLinks = try LaunchPresetFilmCatalogV2Loader().loadCatalog(from: catalogData())
        let withLinks = try LaunchPresetFilmCatalogV2Loader().loadCatalog(from: catalogData(sourceJSON: sourceJSON(additionalFields: """
        ,
              "links": {
                "landingPageUrl": "https://example.com/landing",
                "downloadUrl": "https://example.com/download.pdf",
                "archiveUrl": "https://web.archive.org/example",
                "accessedDate": "2026-01-01"
              }
        """)))

        XCTAssertEqual(withLinks, withoutLinks)
    }

    private func goldenExposureRows() -> String {
        let evaluator = ReciprocityCalculationPolicyEvaluator()

        return LaunchPresetFilmCatalogV2.films.flatMap { film in
            let profile = film.profiles[0]
            return meteredInputs.map { input in
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: input)
                if let corrected = result.correctedExposureSeconds {
                    XCTAssertTrue(corrected.isFinite, "\(film.id) @ \(input)s corrected exposure must be finite.")
                }
                return [
                    film.id,
                    format(input),
                    resultKind(result),
                    result.metadata.basis.rawValue,
                    result.metadata.rangeStatus.rawValue,
                    result.metadata.warningLevel.rawValue,
                    result.hasCalculatedExposureTime ? "true" : "false",
                    result.correctedExposureSeconds.map(format) ?? "nil",
                ].joined(separator: "|")
            }
        }.joined(separator: "\n")
    }

    private func assertCalculationMatchesModel(
        _ profile: V2ProfileDocument,
        filmID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let calculationKeys = Set(profile.calculation.keys)
        switch profile.model {
        case "table":
            XCTAssertNotNil(profile.calculation["anchors"], "\(filmID)/\(profile.id)", file: file, line: line)
            XCTAssertNil(profile.calculation["family"], "\(filmID)/\(profile.id)", file: file, line: line)
        case "formula":
            XCTAssertNotNil(profile.calculation["family"], "\(filmID)/\(profile.id)", file: file, line: line)
            XCTAssertNil(profile.calculation["anchors"], "\(filmID)/\(profile.id)", file: file, line: line)
        case "limitedGuidance":
            XCTAssertNotNil(profile.calculation["guidance"], "\(filmID)/\(profile.id)", file: file, line: line)
            XCTAssertNil(profile.calculation["anchors"], "\(filmID)/\(profile.id)", file: file, line: line)
            XCTAssertNil(profile.calculation["family"], "\(filmID)/\(profile.id)", file: file, line: line)
        default:
            XCTFail("\(filmID)/\(profile.id) unsupported model \(profile.model)", file: file, line: line)
        }
        XCTAssertFalse(calculationKeys.isEmpty, "\(filmID)/\(profile.id)", file: file, line: line)
    }

    private func assertEvidenceGrammarDecodes(
        _ profile: V2ProfileDocument,
        filmID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for evidence in profile.evidence ?? [] {
            XCTAssertNotNil(evidence["anchor"], "\(filmID)/\(profile.id)", file: file, line: line)
        }
        for point in profile.referencePoints ?? [] {
            XCTAssertNotNil(point["meteredSeconds"], "\(filmID)/\(profile.id)", file: file, line: line)
        }
        for range in profile.referenceRanges ?? [] {
            XCTAssertNotNil(range["fromSeconds"], "\(filmID)/\(profile.id)", file: file, line: line)
            XCTAssertNotNil(range["throughSeconds"], "\(filmID)/\(profile.id)", file: file, line: line)
        }
    }

    private func resultKind(_ result: ReciprocityResult) -> String {
        switch result {
        case .quantified:
            return "quantified"
        case .limitedGuidance:
            return "limitedGuidance"
        case .unsupported:
            return "unsupported"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func bundledV2Document() throws -> V2CatalogDocument {
        for bundle in LaunchPresetFilmCatalogV2.defaultResourceBundles() {
            guard let url = bundle.url(
                forResource: LaunchPresetFilmCatalogV2.resourceName,
                withExtension: LaunchPresetFilmCatalogV2.resourceExtension
            ) else {
                continue
            }
            return try JSONDecoder().decode(V2CatalogDocument.self, from: Data(contentsOf: url))
        }
        throw XCTSkip("Bundled v2 catalog resource not found.")
    }

    private let expectedGoldenExposureRows = """
ilford-pan-f-plus-50|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-pan-f-plus-50|1.000000000|quantified|formulaDerived|withinStatedRange|none|true|1.000000000
ilford-pan-f-plus-50|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.514026749
ilford-pan-f-plus-50|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.504134215
ilford-pan-f-plus-50|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|21.379620895
ilford-pan-f-plus-50|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|92.166112315
ilford-pan-f-plus-50|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|231.708071715
ilford-pan-f-plus-50|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|582.520290261
ilford-pan-f-plus-50|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1970.476540663
ilford-pan-f-plus-50|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|9772.372209558
ilford-fp4-plus-125|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-fp4-plus-125|1.000000000|quantified|formulaDerived|withinStatedRange|none|true|1.000000000
ilford-fp4-plus-125|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.394957409
ilford-fp4-plus-125|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|7.598051020
ilford-fp4-plus-125|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|18.197008586
ilford-fp4-plus-125|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|72.639489096
ilford-fp4-plus-125|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|173.968482613
ilford-fp4-plus-125|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|416.647106408
ilford-fp4-plus-125|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1321.821406765
ilford-fp4-plus-125|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|6025.595860744
ilford-delta-100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-delta-100|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-delta-100|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.394957409
ilford-delta-100|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|7.598051020
ilford-delta-100|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|18.197008586
ilford-delta-100|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|72.639489096
ilford-delta-100|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|173.968482613
ilford-delta-100|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|416.647106408
ilford-delta-100|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1321.821406765
ilford-delta-100|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|6025.595860744
ilford-delta-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-delta-400|1.000000000|quantified|formulaDerived|withinStatedRange|none|true|1.000000000
ilford-delta-400|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.657371628
ilford-delta-400|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|9.672699729
ilford-delta-400|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|25.703957828
ilford-delta-400|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|120.987629901
ilford-delta-400|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|321.509095060
ilford-delta-400|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|854.369147418
ilford-delta-400|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|3109.860936635
ilford-delta-400|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|16982.436524617
ilford-delta-3200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-delta-3200|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-delta-3200|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.514026749
ilford-delta-3200|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.504134215
ilford-delta-3200|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|21.379620895
ilford-delta-3200|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|92.166112315
ilford-delta-3200|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|231.708071715
ilford-delta-3200|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|582.520290261
ilford-delta-3200|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1970.476540663
ilford-delta-3200|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|9772.372209558
ilford-hp5-plus-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-hp5-plus-400|1.000000000|quantified|formulaDerived|withinStatedRange|none|true|1.000000000
ilford-hp5-plus-400|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.479415400
ilford-hp5-plus-400|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.234755438
ilford-hp5-plus-400|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|20.417379447
ilford-hp5-plus-400|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|86.105093701
ilford-hp5-plus-400|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|213.490295331
ilford-hp5-plus-400|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|529.331125968
ilford-hp5-plus-400|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1758.040370392
ilford-hp5-plus-400|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|8511.380382024
ilford-xp2-super-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-xp2-super-400|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-xp2-super-400|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.479415400
ilford-xp2-super-400|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.234755438
ilford-xp2-super-400|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|20.417379447
ilford-xp2-super-400|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|86.105093701
ilford-xp2-super-400|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|213.490295331
ilford-xp2-super-400|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|529.331125968
ilford-xp2-super-400|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1758.040370392
ilford-xp2-super-400|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|8511.380382024
ilford-sfx-200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-sfx-200|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-sfx-200|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.694467154
ilford-sfx-200|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|9.989117144
ilford-sfx-200|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|26.915348039
ilford-sfx-200|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|129.504063079
ilford-sfx-200|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|348.944444242
ilford-sfx-200|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|940.219343487
ilford-sfx-200|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|3485.646930278
ilford-sfx-200|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|19498.445997580
ilford-ortho-plus-80|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-ortho-plus-80|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-ortho-plus-80|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.378414230
ilford-ortho-plus-80|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|7.476743906
ilford-ortho-plus-80|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|17.782794100
ilford-ortho-plus-80|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|70.210419580
ilford-ortho-plus-80|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|166.989461023
ilford-ortho-plus-80|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|397.170110358
ilford-ortho-plus-80|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1248.537435086
ilford-ortho-plus-80|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|5623.413251903
ilford-kentmere-pan-100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-kentmere-pan-100|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-kentmere-pan-100|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.394957409
ilford-kentmere-pan-100|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|7.598051020
ilford-kentmere-pan-100|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|18.197008586
ilford-kentmere-pan-100|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|72.639489096
ilford-kentmere-pan-100|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|173.968482613
ilford-kentmere-pan-100|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|416.647106408
ilford-kentmere-pan-100|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1321.821406765
ilford-kentmere-pan-100|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|6025.595860744
ilford-kentmere-pan-200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-kentmere-pan-200|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-kentmere-pan-200|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.394957409
ilford-kentmere-pan-200|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|7.598051020
ilford-kentmere-pan-200|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|18.197008586
ilford-kentmere-pan-200|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|72.639489096
ilford-kentmere-pan-200|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|173.968482613
ilford-kentmere-pan-200|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|416.647106408
ilford-kentmere-pan-200|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1321.821406765
ilford-kentmere-pan-200|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|6025.595860744
ilford-kentmere-pan-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
ilford-kentmere-pan-400|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
ilford-kentmere-pan-400|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.462288827
ilford-kentmere-pan-400|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.103282983
ilford-kentmere-pan-400|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|19.952623150
ilford-kentmere-pan-400|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|83.225733440
ilford-kentmere-pan-400|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|204.925793543
ilford-kentmere-pan-400|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|504.586491741
ilford-kentmere-pan-400|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1660.571695688
ilford-kentmere-pan-400|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|7943.282347243
harman-phoenix-200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
harman-phoenix-200|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
harman-phoenix-200|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.479415400
harman-phoenix-200|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.234755438
harman-phoenix-200|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|20.417379447
harman-phoenix-200|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|86.105093701
harman-phoenix-200|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|213.490295331
harman-phoenix-200|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|529.331125968
harman-phoenix-200|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1758.040370392
harman-phoenix-200|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|8511.380382024
harman-phoenix-ii|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
harman-phoenix-ii|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
harman-phoenix-ii|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.479415400
harman-phoenix-ii|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|8.234755438
harman-phoenix-ii|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|20.417379447
harman-phoenix-ii|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|86.105093701
harman-phoenix-ii|60.000000000|quantified|formulaDerived|withinStatedRange|none|true|213.490295331
harman-phoenix-ii|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|529.331125968
harman-phoenix-ii|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|1758.040370392
harman-phoenix-ii|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|8511.380382024
kodak-tri-x-400|0.500000000|quantified|tableLogLogDerived|withinStatedRange|none|true|0.811672705
kodak-tri-x-400|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|2.000000000
kodak-tri-x-400|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|5.000000000
kodak-tri-x-400|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|20.000000000
kodak-tri-x-400|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|50.000000000
kodak-tri-x-400|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|200.000000000
kodak-tri-x-400|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|562.458016282
kodak-tri-x-400|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|1558.058239525
kodak-tri-x-400|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|5787.735123545
kodak-tri-x-400|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|32461.559779763
kodak-tmax-100|0.500000000|quantified|tableLogLogDerived|withinStatedRange|none|true|0.587634092
kodak-tmax-100|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|1.259921050
kodak-tmax-100|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|2.655679895
kodak-tmax-100|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|7.116375654
kodak-tmax-100|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|15.000000000
kodak-tmax-100|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|51.620646640
kodak-tmax-100|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|112.580647864
kodak-tmax-100|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|245.529707560
kodak-tmax-100|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|688.275288533
kodak-tmax-100|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2666.666666667
kodak-tmax-400|0.500000000|quantified|tableLogLogDerived|withinStatedRange|none|true|0.587634092
kodak-tmax-400|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|1.259921050
kodak-tmax-400|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|2.655679895
kodak-tmax-400|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|7.116375654
kodak-tmax-400|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|15.000000000
kodak-tmax-400|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|62.638352000
kodak-tmax-400|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|154.343866968
kodak-tmax-400|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|380.310600617
kodak-tmax-400|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|1252.767039995
kodak-tmax-400|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|6000.000000000
kodak-ektar-100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
kodak-ektar-100|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
kodak-ektar-100|2.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|5.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|10.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|30.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|60.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|120.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|300.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektar-100|1000.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-160|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
kodak-portra-160|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
kodak-portra-160|2.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|2.000000000
kodak-portra-160|5.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|5.000000000
kodak-portra-160|10.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|10.000000000
kodak-portra-160|30.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-160|60.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-160|120.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-160|300.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-160|1000.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
kodak-portra-400|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
kodak-portra-400|2.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|2.000000000
kodak-portra-400|5.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|5.000000000
kodak-portra-400|10.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|10.000000000
kodak-portra-400|30.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-400|60.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-400|120.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-400|300.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-portra-400|1000.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
kodak-gold-200|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
kodak-gold-200|2.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|5.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|10.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|30.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|60.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|120.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|300.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-gold-200|1000.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
kodak-ultra-max-400|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
kodak-ultra-max-400|2.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|5.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|10.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|30.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|60.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|120.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|300.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ultra-max-400|1000.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektachrome-e100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
kodak-ektachrome-e100|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
kodak-ektachrome-e100|2.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|2.000000000
kodak-ektachrome-e100|5.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|5.000000000
kodak-ektachrome-e100|10.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|10.000000000
kodak-ektachrome-e100|30.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektachrome-e100|60.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektachrome-e100|120.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektachrome-e100|300.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
kodak-ektachrome-e100|1000.000000000|limitedGuidance|limitedGuidanceNoQuantifiedPrediction|beyondLastRepresentativePoint|note|false|nil
fujifilm-acros-ii|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
fujifilm-acros-ii|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
fujifilm-acros-ii|2.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|2.000000000
fujifilm-acros-ii|5.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|5.000000000
fujifilm-acros-ii|10.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|10.000000000
fujifilm-acros-ii|30.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|30.000000000
fujifilm-acros-ii|60.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|60.000000000
fujifilm-acros-ii|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|169.705627485
fujifilm-acros-ii|300.000000000|quantified|formulaDerived|withinStatedRange|none|true|424.264068712
fujifilm-acros-ii|1000.000000000|quantified|formulaDerived|withinStatedRange|none|true|1414.213562373
fujifilm-velvia-50|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
fujifilm-velvia-50|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
fujifilm-velvia-50|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.269068244
fujifilm-velvia-50|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|6.702741061
fujifilm-velvia-50|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|15.208976891
fujifilm-velvia-50|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|55.732052199
fujifilm-velvia-50|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|126.459829832
fujifilm-velvia-50|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|286.945984045
fujifilm-velvia-50|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|847.627493960
fujifilm-velvia-50|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|3518.033737737
fujifilm-velvia-100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
fujifilm-velvia-100|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
fujifilm-velvia-100|2.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|2.000000000
fujifilm-velvia-100|5.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|5.000000000
fujifilm-velvia-100|10.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|10.000000000
fujifilm-velvia-100|30.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|30.000000000
fujifilm-velvia-100|60.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|60.000000000
fujifilm-velvia-100|120.000000000|quantified|formulaDerived|withinStatedRange|none|true|144.366339862
fujifilm-velvia-100|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|460.825555073
fujifilm-velvia-100|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2117.712799571
fujifilm-provia-100f|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
fujifilm-provia-100f|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
fujifilm-provia-100f|2.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|2.000000000
fujifilm-provia-100f|5.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|5.000000000
fujifilm-provia-100f|10.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|10.000000000
fujifilm-provia-100f|30.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|30.000000000
fujifilm-provia-100f|60.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|60.000000000
fujifilm-provia-100f|120.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|120.000000000
fujifilm-provia-100f|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|410.299174426
fujifilm-provia-100f|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2129.068405072
foma-fomapan-100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
foma-fomapan-100|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|2.000000000
foma-fomapan-100|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|6.071529478
foma-fomapan-100|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|26.352503201
foma-fomapan-100|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|80.000000000
foma-fomapan-100|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|334.071210665
foma-fomapan-100|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|823.167290497
foma-fomapan-100|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2028.323203293
foma-fomapan-100|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|6681.424213305
foma-fomapan-100|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|32000.000000000
foma-fomapan-200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
foma-fomapan-200|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|3.000000000
foma-fomapan-200|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|8.351780267
foma-fomapan-200|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|32.328436738
foma-fomapan-200|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|90.000000000
foma-fomapan-200|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|375.830111998
foma-fomapan-200|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|926.063201809
foma-fomapan-200|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2281.863603705
foma-fomapan-200|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|7516.602239968
foma-fomapan-200|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|36000.000000000
foma-fomapan-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
foma-fomapan-400|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|1.500000000
foma-fomapan-400|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|4.553647108
foma-fomapan-400|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|19.764377400
foma-fomapan-400|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|60.000000000
foma-fomapan-400|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|206.482586560
foma-fomapan-400|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|450.322591458
foma-fomapan-400|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|982.118830240
foma-fomapan-400|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2753.101154131
foma-fomapan-400|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|10666.666666667
rollei-rpx-25|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
rollei-rpx-25|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
rollei-rpx-25|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|3.000000000
rollei-rpx-25|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|8.834700167
rollei-rpx-25|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|20.000000000
rollei-rpx-25|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|88.132843532
rollei-rpx-25|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|232.254629149
rollei-rpx-25|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|612.055739938
rollei-rpx-25|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2203.400663778
rollei-rpx-25|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|11859.183658636
rollei-rpx-100|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
rollei-rpx-100|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
rollei-rpx-100|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|3.000000000
rollei-rpx-100|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|8.000000000
rollei-rpx-100|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|25.000000000
rollei-rpx-100|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|150.000000000
rollei-rpx-100|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|490.575026156
rollei-rpx-100|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|1604.425708585
rollei-rpx-100|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|7684.268836963
rollei-rpx-100|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|60182.423085650
rollei-rpx-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
rollei-rpx-400|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|2.000000000
rollei-rpx-400|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|4.000000000
rollei-rpx-400|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|10.000000000
rollei-rpx-400|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|30.000000000
rollei-rpx-400|30.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|135.656694722
rollei-rpx-400|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|334.595251327
rollei-rpx-400|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|825.274288452
rollei-rpx-400|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2722.061634826
rollei-rpx-400|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|13059.450146631
rollei-ortho-25-plus|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
rollei-ortho-25-plus|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
rollei-ortho-25-plus|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|2.381597540
rollei-ortho-25-plus|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|7.500000000
rollei-ortho-25-plus|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|20.000000000
rollei-ortho-25-plus|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|75.000000000
rollei-ortho-25-plus|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|208.914360488
rollei-ortho-25-plus|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|736.135403314
rollei-ortho-25-plus|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|3890.795233613
rollei-ortho-25-plus|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|34684.877318004
rollei-retro-80s|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
rollei-retro-80s|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
rollei-retro-80s|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.784380900
rollei-retro-80s|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|11.376385322
rollei-retro-80s|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|32.992594529
rollei-retro-80s|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|178.370253307
rollei-retro-80s|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|517.290622337
rollei-retro-80s|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|1500.191780837
rollei-retro-80s|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|6129.463017809
rollei-retro-80s|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|38959.777656282
rollei-retro-400s|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|caution|true|0.500000000
rollei-retro-400s|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|caution|true|1.000000000
rollei-retro-400s|2.000000000|quantified|formulaDerived|withinStatedRange|caution|true|3.073750363
rollei-retro-400s|5.000000000|quantified|formulaDerived|withinStatedRange|caution|true|13.562239424
rollei-retro-400s|10.000000000|quantified|formulaDerived|withinStatedRange|caution|true|41.686938347
rollei-retro-400s|30.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|247.136238710
rollei-retro-400s|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|759.635103341
rollei-retro-400s|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2334.928674321
rollei-retro-400s|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|10302.353146431
rollei-retro-400s|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|72443.596007499
rollei-superpan-200|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
rollei-superpan-200|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
rollei-superpan-200|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|2.784380900
rollei-superpan-200|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|11.376385322
rollei-superpan-200|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|32.992594529
rollei-superpan-200|30.000000000|quantified|formulaDerived|withinStatedRange|none|true|178.370253307
rollei-superpan-200|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|517.290622337
rollei-superpan-200|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|1500.191780837
rollei-superpan-200|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|6129.463017809
rollei-superpan-200|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|38959.777656282
adox-chs-100-ii|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
adox-chs-100-ii|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
adox-chs-100-ii|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|3.000000000
adox-chs-100-ii|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|10.744793067
adox-chs-100-ii|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|26.671520426
adox-chs-100-ii|30.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|110.040663939
adox-chs-100-ii|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|269.087727114
adox-chs-100-ii|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|658.013158876
adox-chs-100-ii|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2145.818795077
adox-chs-100-ii|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|10142.089981300
adox-cms-20-ii|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
adox-cms-20-ii|1.000000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|1.000000000
adox-cms-20-ii|2.000000000|quantified|formulaDerived|withinStatedRange|none|true|3.139456970
adox-cms-20-ii|5.000000000|quantified|formulaDerived|withinStatedRange|none|true|9.009288284
adox-cms-20-ii|10.000000000|quantified|formulaDerived|withinStatedRange|none|true|20.000000632
adox-cms-20-ii|30.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|70.788900970
adox-cms-20-ii|60.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|157.146493653
adox-cms-20-ii|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|348.854412613
adox-cms-20-ii|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|1001.106243169
adox-cms-20-ii|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|4000.000166329
bergger-pancro-400|0.500000000|quantified|officialThresholdNoCorrection|withinStatedRange|none|true|0.500000000
bergger-pancro-400|1.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|1.414213600
bergger-pancro-400|2.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|3.139456940
bergger-pancro-400|5.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|9.009288085
bergger-pancro-400|10.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|20.000000000
bergger-pancro-400|30.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|91.775539710
bergger-pancro-400|60.000000000|quantified|tableLogLogDerived|withinStatedRange|none|true|240.000000000
bergger-pancro-400|120.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|627.618210498
bergger-pancro-400|300.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|2236.555885014
bergger-pancro-400|1000.000000000|unsupported|unsupportedOutOfPolicyRange|beyondPolicyLimit|strongWarning|true|11877.789110460
"""

    private func invalidCalculationKindData() -> Data {
        Data(
            """
            {
              "schema": "ptimer.catalog.v2",
              "schemaVersion": 2,
              "catalogVersion": "test",
              "license": "Apache-2.0",
              "copyright": "Copyright © 2026 Sangwook Han",
              "sources": {
                "test-source": {
                  "publisher": "Test",
                  "sourceType": "manufacturerPublished",
                  "authority": "official",
                  "confidence": "high"
                }
              },
              "films": [
                {
                  "id": "test-film",
                  "canonicalStockName": "Test Film",
                  "manufacturer": "Test",
                  "brandLabel": "Test Film",
                  "aliases": [],
                  "iso": 100,
                  "kind": "preset",
                  "productionStatus": "current",
                  "profiles": [
                    {
                      "id": "test-profile",
                      "label": "Test profile",
                      "role": "primary",
                      "authority": "official",
                      "sourceId": "test-source",
                      "model": "formula",
                      "calculation": {
                        "kind": "formula",
                        "family": "modifiedSchwarzschild",
                        "exponent": 1.2,
                        "noCorrectionThroughSeconds": 1
                      }
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
    }

    private func explicitNullReferencePointData() -> Data {
        Data(
            """
            {
              "schema": "ptimer.catalog.v2",
              "schemaVersion": 2,
              "catalogVersion": "test",
              "license": "Apache-2.0",
              "copyright": "Copyright © 2026 Sangwook Han",
              "sources": {
                "test-source": {
                  "publisher": "Test",
                  "sourceType": "manufacturerPublished",
                  "authority": "official",
                  "confidence": "high"
                }
              },
              "films": [
                {
                  "id": "test-film",
                  "canonicalStockName": "Test Film",
                  "manufacturer": "Test",
                  "brandLabel": "Test Film",
                  "aliases": [],
                  "iso": 100,
                  "kind": "preset",
                  "productionStatus": "current",
                  "profiles": [
                    {
                      "id": "test-profile",
                      "label": "Test profile",
                      "role": "primary",
                      "authority": "official",
                      "sourceId": "test-source",
                      "model": "formula",
                      "calculation": {
                        "family": "modifiedSchwarzschild",
                        "exponent": 1.2,
                        "noCorrectionThroughSeconds": 1
                      },
                      "referencePoints": [
                        {
                          "meteredSeconds": 2,
                          "correctedSeconds": null
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
    }

    private func assertThrowsMalformedResource(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try LaunchPresetFilmCatalogV2Loader().loadCatalog(from: data),
            file: file,
            line: line
        ) { error in
            guard case .malformedResource = error as? LaunchPresetFilmCatalogV2LoaderError else {
                return XCTFail("Expected malformedResource, got \(error)", file: file, line: line)
            }
        }
    }

    private func assertThrowsInvalidRuleShape(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try LaunchPresetFilmCatalogV2Loader().loadCatalog(from: data),
            file: file,
            line: line
        ) { error in
            guard case .invalidRuleShape = error as? LaunchPresetFilmCatalogV2LoaderError else {
                return XCTFail("Expected invalidRuleShape, got \(error)", file: file, line: line)
            }
        }
    }

    private func catalogData(
        sourceJSON: String? = nil,
        profileJSON: String? = nil
    ) -> Data {
        let sourceJSON = sourceJSON ?? self.sourceJSON()
        let profileJSON = profileJSON ?? formulaProfileJSON()

        return Data(
            """
            {
              "schema": "ptimer.catalog.v2",
              "schemaVersion": 2,
              "catalogVersion": "test",
              "license": "Apache-2.0",
              "copyright": "Copyright © 2026 Sangwook Han",
              "sources": {
                "test-source": \(sourceJSON)
              },
              "films": [
                {
                  "id": "test-film",
                  "canonicalStockName": "Test Film",
                  "manufacturer": "Test",
                  "brandLabel": "Test Film",
                  "aliases": [],
                  "iso": 100,
                  "kind": "preset",
                  "productionStatus": "current",
                  "profiles": [
                    \(profileJSON)
                  ]
                }
              ]
            }
            """.utf8
        )
    }

    private func sourceJSON(
        sourceType: String = "manufacturerPublished",
        authority: String = "official",
        confidence: String = "high",
        additionalFields: String = ""
    ) -> String {
        """
        {
          "publisher": "Test",
          "sourceType": "\(sourceType)",
          "authority": "\(authority)",
          "confidence": "\(confidence)"\(additionalFields)
        }
        """
    }

    private func unofficialSourceJSON(confidence: String = "medium") -> String {
        sourceJSON(
            sourceType: "thirdPartyPublication",
            authority: "unofficial",
            confidence: confidence
        )
    }

    private func formulaProfileJSON(
        calculationFields: String = "",
        carriers: String = ""
    ) -> String {
        """
        {
          "id": "test-profile",
          "label": "Test profile",
          "role": "primary",
          "authority": "official",
          "sourceId": "test-source",
          "model": "formula",
          "calculation": {
            "family": "modifiedSchwarzschild",
            "exponent": 1.2,
            "noCorrectionThroughSeconds": 1
          \(calculationFields)}\(carriers)
        }
        """
    }

    private func tableProfileJSON(
        calculationFields: String = "",
        carriers: String = ""
    ) -> String {
        """
        {
          "id": "test-profile",
          "label": "Test profile",
          "role": "primary",
          "authority": "official",
          "sourceId": "test-source",
          "model": "table",
          "calculation": {
            "interpolation": "logLog",
            "noCorrectionThroughSeconds": 0.5,
            "sourceRangeThroughSeconds": 10,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 },
              { "meteredSeconds": 10, "correctedSeconds": 20 }
            ]
          \(calculationFields)},
          "evidence": [
            { "anchor": 0 }
          ]\(carriers)
        }
        """
    }

    private func limitedGuidanceProfileJSON(
        calculationFields: String = "",
        carriers: String = ""
    ) -> String {
        """
        {
          "id": "test-profile",
          "label": "Test profile",
          "role": "primary",
          "authority": "official",
          "sourceId": "test-source",
          "model": "limitedGuidance",
          "calculation": {
            "noCorrectionRange": [0, 1],
            "guidance": [
              { "fromSeconds": 1, "message": "No quantified guidance." }
            ]
          \(calculationFields)}\(carriers)
        }
        """
    }

    private func promotedUnofficialFormulaProfileJSON(
        basis: String = "practicalCommunityGuidance",
        referencePoints: String = """
        [
          { "meteredSeconds": 2, "correctedSeconds": 3 }
        ]
        """
    ) -> String {
        """
        {
          "id": "test-profile",
          "label": "Test profile",
          "role": "primary",
          "authority": "unofficial",
          "basis": "\(basis)",
          "sourceId": "test-source",
          "model": "formula",
          "calculation": {
            "family": "modifiedSchwarzschild",
            "exponent": 1.2,
            "noCorrectionThroughSeconds": 1,
            "sourceRangeThroughSeconds": 10
          },
          "referencePoints": \(referencePoints)
        }
        """
    }

    private func promotedUnofficialTableProfileJSON() -> String {
        """
        {
          "id": "test-profile",
          "label": "Test profile",
          "role": "primary",
          "authority": "unofficial",
          "basis": "practicalCommunityGuidance",
          "sourceId": "test-source",
          "model": "table",
          "calculation": {
            "interpolation": "logLog",
            "noCorrectionThroughSeconds": 0.5,
            "sourceRangeThroughSeconds": 10,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 },
              { "meteredSeconds": 10, "correctedSeconds": 20 }
            ]
          },
          "evidence": [
            { "anchor": 0 }
          ]
        }
        """
    }
}

private struct V2CatalogDocument: Decodable {
    let schema: String
    let schemaVersion: Int
    let sources: [String: V2SourceDocument]
    let films: [V2FilmDocument]
}

private struct V2SourceDocument: Decodable {}

private struct V2FilmDocument: Decodable {
    let id: String
    let profiles: [V2ProfileDocument]
}

private struct V2ProfileDocument: Decodable {
    let id: String
    let role: String
    let sourceId: String
    let model: String
    let calculation: [String: JSONValue]
    let evidence: [[String: JSONValue]]?
    let referencePoints: [[String: JSONValue]]?
    let referenceRanges: [[String: JSONValue]]?
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}
