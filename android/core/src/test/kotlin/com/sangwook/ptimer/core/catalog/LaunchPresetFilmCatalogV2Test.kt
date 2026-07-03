// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationModel
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityConfidence
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfileModelBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceProvenance
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceModel
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import com.sangwook.ptimer.core.reciprocity.hasCalculatedExposureTime
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LaunchPresetFilmCatalogV2Test {

    private val meteredInputs = listOf(0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 1_000.0)

    @Test
    fun bundledV2CatalogDeclaresExpectedLaunchInvariants() {
        val document = bundledV2Document()
        val v2Films = LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        val films = document["films"]!!.jsonArray
        val sources = document["sources"]!!.jsonObject

        assertEquals("ptimer.catalog.v2", document["schema"]!!.jsonPrimitive.content)
        assertEquals(2, document["schemaVersion"]!!.jsonPrimitive.int)
        assertEquals(40, films.size)
        assertEquals(40, v2Films.size)

        val filmIDs = films.map { it.jsonObject["id"]!!.jsonPrimitive.content }
        val profileIDs = films.flatMap { film ->
            film.jsonObject["profiles"]!!.jsonArray.map { it.jsonObject["id"]!!.jsonPrimitive.content }
        }
        assertEquals(filmIDs.size, filmIDs.toSet().size)
        assertEquals(profileIDs.size, profileIDs.toSet().size)

        films.forEach { filmElement ->
            val film = filmElement.jsonObject
            val filmID = film["id"]!!.jsonPrimitive.content
            val profiles = film["profiles"]!!.jsonArray
            assertEquals(
                "$filmID must declare exactly one primary profile.",
                1,
                profiles.count { it.jsonObject["role"]!!.jsonPrimitive.content == "primary" },
            )

            profiles.forEach { profileElement ->
                val profile = profileElement.jsonObject
                val profileID = profile["id"]!!.jsonPrimitive.content
                val sourceID = profile["sourceId"]!!.jsonPrimitive.content
                assertNotNull("$profileID sourceId must resolve.", sources[sourceID])
                assertCalculationMatchesModel(profile, filmID)
                assertEvidenceGrammarDecodes(profile, filmID)
            }
        }

        v2Films.forEach { film ->
            assertEquals("${film.id} must adapt exactly one primary profile.", 1, film.profiles.size)
            assertTrue(film.profiles[0].id.isNotEmpty())
        }
    }

    @Test
    fun bundledV2CatalogPrimaryProfileExposureGolden() {
        assertEquals(expectedGoldenExposureRows, goldenExposureRows())
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

    private fun sourceLinkProfile(authority: ReciprocityAuthority, url: String?) = ReciprocityProfile(
        id = "t",
        name = "t",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = authority,
            confidence = ReciprocityConfidence.high,
            publisher = "p",
        ),
        rules = emptyList(),
        sourcePageUrl = url,
    )

    @Test
    fun providesUserVisibleOfficialSourceTreatsBlankUrlsAsMissing() {
        // PTIMER-158: the per-profile visibility predicate must match iOS — nil,
        // empty, and whitespace-only source-page URLs all count as missing, and
        // an unofficial profile never qualifies regardless of its URL.
        assertFalse(sourceLinkProfile(ReciprocityAuthority.official, null).providesUserVisibleOfficialSource)
        assertFalse(sourceLinkProfile(ReciprocityAuthority.official, "").providesUserVisibleOfficialSource)
        assertFalse(sourceLinkProfile(ReciprocityAuthority.official, "   \n\t ").providesUserVisibleOfficialSource)
        assertTrue(sourceLinkProfile(ReciprocityAuthority.official, "https://example.com/x").providesUserVisibleOfficialSource)
        assertFalse(sourceLinkProfile(ReciprocityAuthority.unofficial, "https://example.com/x").providesUserVisibleOfficialSource)
        // Only official authority qualifies; other authorities never count.
        assertFalse(sourceLinkProfile(ReciprocityAuthority.userDefined, "https://example.com/x").providesUserVisibleOfficialSource)
    }

    @Test
    fun userSelectableFilmsRequireOfficialSourceLinks() {
        // PTIMER-158 (0.7): the user-facing list ships official sources only —
        // a film is selectable only with an official profile that also carries
        // a verified source-page link. That hides community/practical Retro
        // 400S. PTIMER-200 added source-page links to the previously
        // official-but-unlinked Rollei RPX 25 / ORTHO 25 plus, so they are no
        // longer hidden. The full catalog keeps Retro 400S for later
        // restoration.
        val hidden = listOf("rollei-retro-400s")
        val selectable = LaunchPresetFilmCatalogV2.userSelectableFilms
        hidden.forEach { id ->
            assertTrue(LaunchPresetFilmCatalogV2.films.any { it.id == id })
            assertFalse(selectable.any { it.id == id })
        }
        assertTrue(selectable.any { it.id == "kodak-portra-400" })
        assertTrue(selectable.any { it.id == "ilford-pan-f-plus-50" })
        assertTrue(selectable.any { it.id == "adox-chs-100-ii" })
        assertEquals(LaunchPresetFilmCatalogV2.films.size - hidden.size, selectable.size)
        selectable.forEach { film ->
            assertTrue(
                "${film.id} must expose an official profile with a source-page link to be user-selectable.",
                film.profiles.any { it.source.authority != ReciprocityAuthority.unofficial && !it.sourcePageUrl.isNullOrBlank() },
            )
        }
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

    private fun goldenExposureRows(): String {
        val evaluator = ReciprocityCalculationPolicyEvaluator()
        return LaunchPresetFilmCatalogV2.films.flatMap { film ->
            val profile = film.profiles[0]
            meteredInputs.map { input ->
                val result = evaluator.evaluate(profile, input)
                result.calculatedCorrectedSeconds?.let { corrected ->
                    assertTrue("${film.id} @ ${input}s corrected exposure must be finite.", corrected.isFinite())
                }
                listOf(
                    film.id,
                    format(input),
                    resultKind(result),
                    result.metadata.basis.name,
                    result.metadata.rangeStatus.name,
                    result.metadata.warningLevel.name,
                    result.hasCalculatedExposureTime.toString(),
                    result.calculatedCorrectedSeconds?.let(::format) ?: "nil",
                ).joinToString("|")
            }
        }.joinToString("\n")
    }

    private fun bundledV2Document(): JsonObject {
        val text = javaClass.classLoader!!
            .getResourceAsStream(LaunchPresetFilmCatalogV2.RESOURCE_NAME)!!
            .bufferedReader()
            .use { it.readText() }
        return Json.parseToJsonElement(text).jsonObject
    }

    private fun assertCalculationMatchesModel(profile: JsonObject, filmID: String) {
        val profileID = profile["id"]!!.jsonPrimitive.content
        val model = profile["model"]!!.jsonPrimitive.content
        val calculation = profile["calculation"]!!.jsonObject
        val calculationKeys = calculation.keys

        when (model) {
            "table" -> {
                assertNotNull("$filmID/$profileID", calculation["anchors"])
                assertNull("$filmID/$profileID", calculation["family"])
            }
            "formula" -> {
                assertNotNull("$filmID/$profileID", calculation["family"])
                assertNull("$filmID/$profileID", calculation["anchors"])
            }
            "limitedGuidance" -> {
                assertNotNull("$filmID/$profileID", calculation["guidance"])
                assertNull("$filmID/$profileID", calculation["anchors"])
                assertNull("$filmID/$profileID", calculation["family"])
            }
            else -> fail("$filmID/$profileID unsupported model $model")
        }
        assertTrue("$filmID/$profileID", calculationKeys.isNotEmpty())
    }

    private fun assertEvidenceGrammarDecodes(profile: JsonObject, filmID: String) {
        val profileID = profile["id"]!!.jsonPrimitive.content
        profile["evidence"]?.jsonArray?.forEach { evidence ->
            assertNotNull("$filmID/$profileID", evidence.jsonObject["anchor"])
        }
        profile["referencePoints"]?.jsonArray?.forEach { point ->
            assertNotNull("$filmID/$profileID", point.jsonObject["meteredSeconds"])
        }
        profile["referenceRanges"]?.jsonArray?.forEach { range ->
            assertNotNull("$filmID/$profileID", range.jsonObject["fromSeconds"])
            assertNotNull("$filmID/$profileID", range.jsonObject["throughSeconds"])
        }
    }

    private fun resultKind(result: ReciprocityResult): String =
        when (result) {
            is ReciprocityResult.Quantified -> "quantified"
            is ReciprocityResult.LimitedGuidance -> "limitedGuidance"
            is ReciprocityResult.Unsupported -> "unsupported"
        }

    private fun format(value: Double): String = String.format(Locale.US, "%.9f", value)

    private val expectedGoldenExposureRows = """
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
""".trimIndent()

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
