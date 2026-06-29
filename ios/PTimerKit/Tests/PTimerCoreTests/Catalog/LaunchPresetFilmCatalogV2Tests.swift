// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

final class LaunchPresetFilmCatalogV2Tests: XCTestCase {
    private let meteredInputs = [0.5, 1, 2, 5, 10, 30, 60, 120, 300, 1_000]

    func testV2CatalogAdaptsEquivalentLaunchFilms() throws {
        let v1Films = try LaunchPresetFilmCatalogLoader().loadBundledCatalog()
        let v2Films = try LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()

        XCTAssertEqual(v1Films.count, 37)
        XCTAssertEqual(v2Films.count, 37)
        XCTAssertEqual(v1Films.count, v2Films.count)

        for (v1Film, v2Film) in zip(v1Films, v2Films) {
            XCTAssertEqual(
                v1Film,
                v2Film,
                "v2-adapted catalog differs from v1 for film \(v1Film.id): \(firstDifferingField(v1Film, v2Film))"
            )
            try assertGoldenResultsMatch(v1Film: v1Film, v2Film: v2Film)
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

    private func assertGoldenResultsMatch(
        v1Film: FilmIdentity,
        v2Film: FilmIdentity
    ) throws {
        let v1Profile = try XCTUnwrap(v1Film.profiles.first)
        let v2Profile = try XCTUnwrap(v2Film.profiles.first)
        let evaluator = ReciprocityCalculationPolicyEvaluator()

        for input in meteredInputs {
            let v1Result = evaluator.evaluate(profile: v1Profile, meteredExposureSeconds: input)
            let v2Result = evaluator.evaluate(profile: v2Profile, meteredExposureSeconds: input)

            XCTAssertEqual(
                classification(of: v1Result),
                classification(of: v2Result),
                "classification differs for \(v1Film.id) at \(input)s"
            )
            XCTAssertEqual(
                v1Result.correctedExposureSeconds,
                v2Result.correctedExposureSeconds,
                "corrected exposure differs for \(v1Film.id) at \(input)s"
            )
        }
    }

    private func classification(of result: ReciprocityResult) -> ResultClassification {
        let kind: ResultKind
        switch result {
        case .quantified:
            kind = .quantified
        case .limitedGuidance:
            kind = .limitedGuidance
        case .unsupported:
            kind = .unsupported
        }

        return ResultClassification(
            kind: kind,
            basis: result.metadata.basis,
            rangeStatus: result.metadata.rangeStatus,
            warningLevel: result.metadata.warningLevel,
            hasCalculatedExposureTime: result.hasCalculatedExposureTime
        )
    }

    private func firstDifferingField(_ expected: FilmIdentity, _ actual: FilmIdentity) -> String {
        if expected.id != actual.id { return "id" }
        if expected.kind != actual.kind { return "kind" }
        if expected.canonicalStockName != actual.canonicalStockName { return "canonicalStockName" }
        if expected.manufacturer != actual.manufacturer { return "manufacturer" }
        if expected.brandLabel != actual.brandLabel { return "brandLabel" }
        if expected.aliases != actual.aliases { return "aliases" }
        if expected.iso != actual.iso { return "iso" }
        if expected.productionStatus != actual.productionStatus { return "productionStatus" }
        if expected.profiles.count != actual.profiles.count { return "profiles.count" }
        for index in expected.profiles.indices where expected.profiles[index] != actual.profiles[index] {
            return "profiles[\(index)].\(firstDifferingProfileField(expected.profiles[index], actual.profiles[index]))"
        }
        if expected.userMetadata != actual.userMetadata { return "userMetadata" }
        return "unknown"
    }

    private func firstDifferingProfileField(
        _ expected: ReciprocityProfile,
        _ actual: ReciprocityProfile
    ) -> String {
        if expected.id != actual.id { return "id" }
        if expected.name != actual.name { return "name" }
        if expected.source != actual.source { return "source" }
        if expected.rules.count != actual.rules.count { return "rules.count" }
        for index in expected.rules.indices where expected.rules[index] != actual.rules[index] {
            return "rules[\(index)].\(firstDifferingRuleField(expected.rules[index], actual.rules[index]))"
        }
        if expected.notes != actual.notes { return "notes" }
        if expected.userMetadata != actual.userMetadata { return "userMetadata" }
        if expected.sourceEvidence != actual.sourceEvidence { return "sourceEvidence" }
        if expected.modelBasis != actual.modelBasis { return "modelBasis" }
        if expected.selectorLabel != actual.selectorLabel { return "selectorLabel" }
        return "unknown"
    }

    private func firstDifferingRuleField(_ expected: ReciprocityRule, _ actual: ReciprocityRule) -> String {
        switch (expected, actual) {
        case let (.tableInterpolation(expectedTable), .tableInterpolation(actualTable)):
            if expectedTable.anchors != actualTable.anchors { return "anchors" }
            if expectedTable.additionalAdjustments != actualTable.additionalAdjustments {
                return "additionalAdjustments"
            }
            if expectedTable.notes != actualTable.notes { return "notes" }
            if expectedTable.noCorrectionThroughSeconds != actualTable.noCorrectionThroughSeconds {
                return "noCorrectionThroughSeconds"
            }
            if expectedTable.sourceRangeThroughSeconds != actualTable.sourceRangeThroughSeconds {
                return "sourceRangeThroughSeconds"
            }
            return "unknown"

        case let (.formula(expectedFormula), .formula(actualFormula)):
            if expectedFormula.formula != actualFormula.formula { return "formula" }
            if expectedFormula.additionalAdjustments != actualFormula.additionalAdjustments {
                return "additionalAdjustments"
            }
            if expectedFormula.notes != actualFormula.notes { return "notes" }
            return "unknown"

        case let (.threshold(expectedThreshold), .threshold(actualThreshold)):
            if expectedThreshold.noCorrectionRange != actualThreshold.noCorrectionRange { return "noCorrectionRange" }
            if expectedThreshold.adjustments != actualThreshold.adjustments { return "adjustments" }
            if expectedThreshold.notes != actualThreshold.notes { return "notes" }
            return "unknown"

        case let (.limitedGuidance(expectedGuidance), .limitedGuidance(actualGuidance)):
            if expectedGuidance.appliesWhenMetered != actualGuidance.appliesWhenMetered {
                return "appliesWhenMetered"
            }
            if expectedGuidance.adjustments != actualGuidance.adjustments { return "adjustments" }
            if expectedGuidance.notes != actualGuidance.notes { return "notes" }
            return "unknown"

        default:
            return "kind"
        }
    }

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

private struct ResultClassification: Equatable {
    let kind: ResultKind
    let basis: ReciprocityCalculationBasis
    let rangeStatus: ReciprocityCalculationRangeStatus
    let warningLevel: ReciprocityCalculationWarningLevel
    let hasCalculatedExposureTime: Bool
}

private enum ResultKind: Equatable {
    case quantified
    case limitedGuidance
    case unsupported
}
