// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationModel
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationRangeStatus
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationWarningLevel
import com.sangwook.ptimer.core.reciprocity.ReciprocityConfidence
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfileModelBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceModel
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import com.sangwook.ptimer.core.reciprocity.hasCalculatedExposureTime
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class LaunchPresetFilmCatalogV2Test {

    private val meteredInputs = listOf(0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 1_000.0)

    @Test
    fun v2CatalogAdaptsEquivalentLaunchFilms() {
        val v1Films = LaunchPresetFilmCatalogLoader().loadBundledCatalog()
        val v2Films = LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()

        assertEquals(37, v1Films.size)
        assertEquals(37, v2Films.size)
        assertEquals(v1Films.size, v2Films.size)

        v1Films.zip(v2Films).forEach { (v1Film, v2Film) ->
            assertEquals(
                "v2-adapted catalog differs from v1 for film ${v1Film.id}: " +
                    firstDifferingField(v1Film, v2Film),
                v1Film,
                v2Film,
            )
            assertGoldenResultsMatch(v1Film, v2Film)
        }
    }

    @Test
    fun bundledPromotedRolleiRetro400SPrimaryLoads() {
        val films = LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        val film = films.first { it.id == "rollei-retro-400s" }
        val profile = film.profiles.first()

        assertEquals("rollei-retro-400s-unofficial-practical", profile.id)
        assertEquals(ReciprocitySourceKind.thirdPartyPublication, profile.source.kind)
        assertEquals(ReciprocityAuthority.unofficial, profile.source.authority)
        assertEquals(ReciprocityConfidence.medium, profile.source.confidence)
        assertEquals("Stéphane Lafitte", profile.source.publisher)
        assertEquals(
            ReciprocityProfileModelBasis(
                sourceModel = ReciprocitySourceModel.practicalCommunityGuidance,
                calculationModel = ReciprocityCalculationModel.guardedFormula,
            ),
            profile.modelBasis,
        )
        assertEquals(3, profile.sourceEvidence.size)
    }

    @Test
    fun rejectsCalculationKindDiscriminator() {
        val error = runCatching {
            LaunchPresetFilmCatalogV2Loader().loadCatalog(invalidCalculationKindJson())
        }.exceptionOrNull()

        if (error !is CatalogV2LoadException || error.error !is CatalogV2LoadError.MalformedResource) {
            fail("Expected malformedResource, got $error")
        }
    }

    @Test
    fun rejectsExplicitNullCorrectedReferencePoint() {
        assertThrowsMalformedResource(explicitNullReferencePointJson())
    }

    @Test
    fun rejectsFormulaCalculationWithTableOnlyAnchorsKey() {
        assertThrowsMalformedResource(catalogJson(profileJSON = formulaProfileJson(calculationFields = """
        ,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 }
            ]
        """)))
    }

    @Test
    fun rejectsFormulaCalculationWithLimitedGuidanceOnlyNoCorrectionRangeKey() {
        assertThrowsMalformedResource(catalogJson(profileJSON = formulaProfileJson(calculationFields = """
        ,
            "noCorrectionRange": [0, 1]
        """)))
    }

    @Test
    fun rejectsTableCalculationWithFormulaOnlyFamilyKey() {
        assertThrowsMalformedResource(catalogJson(profileJSON = tableProfileJson(calculationFields = """
        ,
            "family": "modifiedSchwarzschild"
        """)))
    }

    @Test
    fun rejectsTableCalculationWithLimitedGuidanceOnlyGuidanceKey() {
        assertThrowsMalformedResource(catalogJson(profileJSON = tableProfileJson(calculationFields = """
        ,
            "guidance": [
              { "fromSeconds": 1, "message": "No quantified guidance." }
            ]
        """)))
    }

    @Test
    fun rejectsLimitedGuidanceCalculationWithTableOnlyAnchorsKey() {
        assertThrowsMalformedResource(catalogJson(profileJSON = limitedGuidanceProfileJson(calculationFields = """
        ,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 }
            ]
        """)))
    }

    @Test
    fun rejectsLimitedGuidanceCalculationWithFormulaOnlyExponentKey() {
        assertThrowsMalformedResource(catalogJson(profileJSON = limitedGuidanceProfileJson(calculationFields = """
        ,
            "exponent": 1.2
        """)))
    }

    @Test
    fun rejectsTableProfileWithReferencePointsCarrier() {
        assertThrowsInvalidRuleShape(catalogJson(profileJSON = tableProfileJson(carriers = """
        ,
              "referencePoints": [
                { "meteredSeconds": 2, "correctedSeconds": 3 }
              ]
        """)))
    }

    @Test
    fun rejectsTableProfileWithReferenceRangesCarrier() {
        assertThrowsInvalidRuleShape(catalogJson(profileJSON = tableProfileJson(carriers = """
        ,
              "referenceRanges": [
                { "fromSeconds": 2, "throughSeconds": 4, "note": "source range" }
              ]
        """)))
    }

    @Test
    fun rejectsFormulaProfileWithTableEvidenceCarrier() {
        assertThrowsInvalidRuleShape(catalogJson(profileJSON = formulaProfileJson(carriers = """
        ,
              "evidence": [
                { "anchor": 0 }
              ]
        """)))
    }

    @Test
    fun rejectsLimitedGuidanceProfileWithSourceEvidenceCarrier() {
        assertThrowsInvalidRuleShape(catalogJson(profileJSON = limitedGuidanceProfileJson(carriers = """
        ,
              "referenceRanges": [
                { "fromSeconds": 2, "throughSeconds": 4, "note": "source range" }
              ]
        """)))
    }

    @Test
    fun rejectsPromotedUnofficialPrimaryWithHighConfidenceSource() {
        assertThrowsInvalidRuleShape(
            catalogJson(
                sourceJSON = unofficialSourceJson(confidence = "high"),
                profileJSON = promotedUnofficialFormulaProfileJson(),
            ),
        )
    }

    @Test
    fun rejectsPromotedUnofficialPrimaryWithoutPracticalCommunityBasis() {
        assertThrowsInvalidRuleShape(
            catalogJson(
                sourceJSON = unofficialSourceJson(),
                profileJSON = promotedUnofficialFormulaProfileJson(basis = "manufacturerFormula"),
            ),
        )
    }

    @Test
    fun rejectsPromotedUnofficialPrimaryWithEmptyReferencePoints() {
        assertThrowsInvalidRuleShape(
            catalogJson(
                sourceJSON = unofficialSourceJson(),
                profileJSON = promotedUnofficialFormulaProfileJson(referencePoints = "[]"),
            ),
        )
    }

    @Test
    fun rejectsPromotedUnofficialPrimaryBackedByOfficialManufacturerSource() {
        assertThrowsInvalidRuleShape(
            catalogJson(
                sourceJSON = sourceJson(
                    sourceType = "manufacturerPublished",
                    authority = "official",
                    confidence = "medium",
                ),
                profileJSON = promotedUnofficialFormulaProfileJson(),
            ),
        )
    }

    @Test
    fun rejectsPromotedUnofficialPrimaryWithNonFormulaModel() {
        assertThrowsInvalidRuleShape(
            catalogJson(
                sourceJSON = unofficialSourceJson(),
                profileJSON = promotedUnofficialTableProfileJson(),
            ),
        )
    }

    @Test
    fun rejectsExplicitNullSourceLink() {
        assertThrowsMalformedResource(catalogJson(sourceJSON = sourceJson(additionalFields = """
        ,
              "links": { "landingPageUrl": null }
        """)))
    }

    @Test
    fun rejectsExplicitNullSourceTitle() {
        assertThrowsMalformedResource(catalogJson(sourceJSON = sourceJson(additionalFields = """
        ,
              "title": null
        """)))
    }

    @Test
    fun sourceLinksAreDroppedFromAdaptedOutput() {
        val withoutLinks = LaunchPresetFilmCatalogV2Loader().loadCatalog(catalogJson())
        val withLinks = LaunchPresetFilmCatalogV2Loader().loadCatalog(catalogJson(sourceJSON = sourceJson(additionalFields = """
        ,
              "links": {
                "landingPageUrl": "https://example.com/landing",
                "downloadUrl": "https://example.com/download.pdf",
                "archiveUrl": "https://web.archive.org/example",
                "accessedDate": "2026-01-01"
              }
        """)))

        assertEquals(withoutLinks, withLinks)
    }

    private fun assertGoldenResultsMatch(v1Film: FilmIdentity, v2Film: FilmIdentity) {
        val v1Profile = v1Film.profiles.first()
        val v2Profile = v2Film.profiles.first()
        val evaluator = ReciprocityCalculationPolicyEvaluator()

        for (input in meteredInputs) {
            val v1Result = evaluator.evaluate(v1Profile, input)
            val v2Result = evaluator.evaluate(v2Profile, input)

            assertEquals(
                "classification differs for ${v1Film.id} at ${input}s",
                classification(v1Result),
                classification(v2Result),
            )
            assertEquals(
                "corrected exposure differs for ${v1Film.id} at ${input}s",
                v1Result.calculatedCorrectedSeconds,
                v2Result.calculatedCorrectedSeconds,
            )
        }
    }

    private fun firstDifferingField(expected: FilmIdentity, actual: FilmIdentity): String {
        if (expected.id != actual.id) return "id"
        if (expected.kind != actual.kind) return "kind"
        if (expected.canonicalStockName != actual.canonicalStockName) return "canonicalStockName"
        if (expected.manufacturer != actual.manufacturer) return "manufacturer"
        if (expected.brandLabel != actual.brandLabel) return "brandLabel"
        if (expected.aliases != actual.aliases) return "aliases"
        if (expected.iso != actual.iso) return "iso"
        if (expected.productionStatus != actual.productionStatus) return "productionStatus"
        if (expected.profiles.size != actual.profiles.size) return "profiles.size"
        expected.profiles.indices.firstOrNull { expected.profiles[it] != actual.profiles[it] }?.let { index ->
            return "profiles[$index].${firstDifferingProfileField(expected.profiles[index], actual.profiles[index])}"
        }
        if (expected.userMetadata != actual.userMetadata) return "userMetadata"
        return "unknown"
    }

    private fun firstDifferingProfileField(expected: ReciprocityProfile, actual: ReciprocityProfile): String {
        if (expected.id != actual.id) return "id"
        if (expected.name != actual.name) return "name"
        if (expected.source != actual.source) return "source"
        if (expected.rules.size != actual.rules.size) return "rules.size"
        expected.rules.indices.firstOrNull { expected.rules[it] != actual.rules[it] }?.let { index ->
            return "rules[$index].${firstDifferingRuleField(expected.rules[index], actual.rules[index])}"
        }
        if (expected.notes != actual.notes) return "notes"
        if (expected.userMetadata != actual.userMetadata) return "userMetadata"
        if (expected.sourceEvidence != actual.sourceEvidence) return "sourceEvidence"
        if (expected.modelBasis != actual.modelBasis) return "modelBasis"
        if (expected.selectorLabel != actual.selectorLabel) return "selectorLabel"
        return "unknown"
    }

    private fun firstDifferingRuleField(expected: ReciprocityRule, actual: ReciprocityRule): String {
        if (expected.kind != actual.kind) return "kind"

        return when (expected.kind) {
            ReciprocityRuleKind.tableInterpolation -> {
                val expectedTable = expected.tableInterpolation ?: return "tableInterpolation"
                val actualTable = actual.tableInterpolation ?: return "tableInterpolation"
                when {
                    expectedTable.anchors != actualTable.anchors -> "anchors"
                    expectedTable.additionalAdjustments != actualTable.additionalAdjustments -> "additionalAdjustments"
                    expectedTable.notes != actualTable.notes -> "notes"
                    expectedTable.noCorrectionThroughSeconds != actualTable.noCorrectionThroughSeconds ->
                        "noCorrectionThroughSeconds"
                    expectedTable.sourceRangeThroughSeconds != actualTable.sourceRangeThroughSeconds ->
                        "sourceRangeThroughSeconds"
                    else -> "unknown"
                }
            }
            ReciprocityRuleKind.formula -> {
                val expectedFormula = expected.formula ?: return "formula"
                val actualFormula = actual.formula ?: return "formula"
                when {
                    expectedFormula.formula != actualFormula.formula -> "formula"
                    expectedFormula.additionalAdjustments != actualFormula.additionalAdjustments ->
                        "additionalAdjustments"
                    expectedFormula.notes != actualFormula.notes -> "notes"
                    else -> "unknown"
                }
            }
            ReciprocityRuleKind.threshold -> {
                val expectedThreshold = expected.threshold ?: return "threshold"
                val actualThreshold = actual.threshold ?: return "threshold"
                when {
                    expectedThreshold.noCorrectionRange != actualThreshold.noCorrectionRange -> "noCorrectionRange"
                    expectedThreshold.adjustments != actualThreshold.adjustments -> "adjustments"
                    expectedThreshold.notes != actualThreshold.notes -> "notes"
                    else -> "unknown"
                }
            }
            ReciprocityRuleKind.limitedGuidance -> {
                val expectedGuidance = expected.limitedGuidance ?: return "limitedGuidance"
                val actualGuidance = actual.limitedGuidance ?: return "limitedGuidance"
                when {
                    expectedGuidance.appliesWhenMetered != actualGuidance.appliesWhenMetered ->
                        "appliesWhenMetered"
                    expectedGuidance.adjustments != actualGuidance.adjustments -> "adjustments"
                    expectedGuidance.notes != actualGuidance.notes -> "notes"
                    else -> "unknown"
                }
            }
        }
    }

    private fun classification(result: ReciprocityResult): ResultClassification {
        val kind = when (result) {
            is ReciprocityResult.Quantified -> ResultKind.Quantified
            is ReciprocityResult.LimitedGuidance -> ResultKind.LimitedGuidance
            is ReciprocityResult.Unsupported -> ResultKind.Unsupported
        }
        return ResultClassification(
            kind = kind,
            basis = result.metadata.basis,
            rangeStatus = result.metadata.rangeStatus,
            warningLevel = result.metadata.warningLevel,
            hasCalculatedExposureTime = result.hasCalculatedExposureTime,
        )
    }

    private fun invalidCalculationKindJson(): String =
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
        """.trimIndent()

    private fun explicitNullReferencePointJson(): String =
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
        """.trimIndent()

    private fun assertThrowsMalformedResource(jsonText: String) {
        val error = runCatching {
            LaunchPresetFilmCatalogV2Loader().loadCatalog(jsonText)
        }.exceptionOrNull()

        if (error !is CatalogV2LoadException || error.error !is CatalogV2LoadError.MalformedResource) {
            fail("Expected malformedResource, got $error")
        }
    }

    private fun assertThrowsInvalidRuleShape(jsonText: String) {
        val error = runCatching {
            LaunchPresetFilmCatalogV2Loader().loadCatalog(jsonText)
        }.exceptionOrNull()

        if (error !is CatalogV2LoadException || error.error !is CatalogV2LoadError.InvalidRuleShape) {
            fail("Expected invalidRuleShape, got $error")
        }
    }

    private fun catalogJson(
        sourceJSON: String = sourceJson(),
        profileJSON: String = formulaProfileJson(),
    ): String =
        """
        {
          "schema": "ptimer.catalog.v2",
          "schemaVersion": 2,
          "catalogVersion": "test",
          "license": "Apache-2.0",
          "copyright": "Copyright © 2026 Sangwook Han",
          "sources": {
            "test-source": $sourceJSON
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
                $profileJSON
              ]
            }
          ]
        }
        """.trimIndent()

    private fun sourceJson(
        sourceType: String = "manufacturerPublished",
        authority: String = "official",
        confidence: String = "high",
        additionalFields: String = "",
    ): String =
        """
        {
          "publisher": "Test",
          "sourceType": "$sourceType",
          "authority": "$authority",
          "confidence": "$confidence"$additionalFields
        }
        """.trimIndent()

    private fun unofficialSourceJson(confidence: String = "medium"): String =
        sourceJson(
            sourceType = "thirdPartyPublication",
            authority = "unofficial",
            confidence = confidence,
        )

    private fun formulaProfileJson(
        calculationFields: String = "",
        carriers: String = "",
    ): String =
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
          $calculationFields}$carriers
        }
        """.trimIndent()

    private fun tableProfileJson(
        calculationFields: String = "",
        carriers: String = "",
    ): String =
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
          $calculationFields},
          "evidence": [
            { "anchor": 0 }
          ]$carriers
        }
        """.trimIndent()

    private fun limitedGuidanceProfileJson(
        calculationFields: String = "",
        carriers: String = "",
    ): String =
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
          $calculationFields}$carriers
        }
        """.trimIndent()

    private fun promotedUnofficialFormulaProfileJson(
        basis: String = "practicalCommunityGuidance",
        referencePoints: String = """
        [
          { "meteredSeconds": 2, "correctedSeconds": 3 }
        ]
        """.trimIndent(),
    ): String =
        """
        {
          "id": "test-profile",
          "label": "Test profile",
          "role": "primary",
          "authority": "unofficial",
          "basis": "$basis",
          "sourceId": "test-source",
          "model": "formula",
          "calculation": {
            "family": "modifiedSchwarzschild",
            "exponent": 1.2,
            "noCorrectionThroughSeconds": 1,
            "sourceRangeThroughSeconds": 10
          },
          "referencePoints": $referencePoints
        }
        """.trimIndent()

    private fun promotedUnofficialTableProfileJson(): String =
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
        """.trimIndent()
}

private data class ResultClassification(
    val kind: ResultKind,
    val basis: ReciprocityCalculationBasis,
    val rangeStatus: ReciprocityCalculationRangeStatus,
    val warningLevel: ReciprocityCalculationWarningLevel,
    val hasCalculatedExposureTime: Boolean,
)

private enum class ResultKind { Quantified, LimitedGuidance, Unsupported }
