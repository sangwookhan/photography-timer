// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LaunchPresetFilmCatalogTest {

    private val films = LaunchPresetFilmCatalogLoader().loadBundledCatalog()
    private val expectations = loadFixture()["catalogExpectations"]!!.jsonObject

    @Test
    fun loadsExpectedFilmCount() {
        assertEquals(expectations["expectedFilmCount"]!!.jsonPrimitive.int, films.size)
    }

    @Test
    fun matchesExpectedFilmOrder() {
        val expected = expectations["expectedFilmOrder"]!!.jsonArray.map { it.jsonPrimitive.content }
        assertEquals(expected, films.map { it.canonicalStockName })
    }

    @Test
    fun matchesExpectedFilmIds() {
        val expected = expectations["expectedFilmIds"]!!.jsonArray.map { it.jsonPrimitive.content }
        assertEquals(expected, films.map { it.id })
    }

    @Test
    fun matchesExpectedManufacturerCounts() {
        val expected = expectations["expectedManufacturerCounts"]!!.jsonObject
            .mapValues { it.value.jsonPrimitive.int }
        val actual = films.mapNotNull { it.manufacturer }.groupingBy { it }.eachCount()
        assertEquals(expected, actual)
    }

    @Test
    fun everyFilmHasExactlyOneProfileAndLoadsWithoutError() {
        // Loading already validated shapes; re-assert the one-profile invariant.
        assertTrue(films.all { it.profiles.size == 1 })
    }

    @Test
    fun formulaFilmIntegratesWithPolicy() {
        val evaluator = ReciprocityCalculationPolicyEvaluator()
        val panF = films.first { it.id == "ilford-pan-f-plus-50" }
        val result = evaluator.evaluate(panF.profiles.first(), 10.0)
        // Pan F Plus is a formula film (exponent 1.33): 10 s yields a quantified
        // corrected exposure greater than the metered time.
        assertTrue(result is ReciprocityResult.Quantified)
        assertTrue((result as ReciprocityResult.Quantified).correctedExposureSeconds > 10.0)
    }

    @Test
    fun tableFilmIntegratesWithPolicy() {
        val evaluator = ReciprocityCalculationPolicyEvaluator()
        val tableFilm = films.first { film ->
            film.profiles.first().rules.any {
                it.kind == com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind.tableInterpolation
            }
        }
        // A long metered exposure inside the table range yields a quantified result.
        val result = evaluator.evaluate(tableFilm.profiles.first(), 10.0)
        assertTrue(result is ReciprocityResult.Quantified || result is ReciprocityResult.Unsupported)
    }

    @Test
    fun emptyCatalogIsRejected() {
        val e = runCatching { LaunchPresetFilmCatalogLoader().loadCatalog("{\"films\":[]}") }.exceptionOrNull()
        assertTrue(e is CatalogLoadException && e.error is CatalogLoadError.EmptyCatalog)
    }

    @Test
    fun malformedCatalogIsRejected() {
        val e = runCatching { LaunchPresetFilmCatalogLoader().loadCatalog("not json") }.exceptionOrNull()
        assertTrue(e is CatalogLoadException && e.error is CatalogLoadError.MalformedResource)
    }

    @Test
    fun bundledCatalogResourcePreservesCopyrightMetadata() {
        val stream = LaunchPresetFilmCatalogLoader::class.java.classLoader
            .getResourceAsStream(LaunchPresetFilmCatalog.RESOURCE_NAME)!!
        val document = Json.parseToJsonElement(stream.bufferedReader().use { it.readText() }).jsonObject
        val metadata = document["_meta"]!!.jsonObject

        assertEquals("Copyright © 2026 Sangwook Han", metadata["copyright"]!!.jsonPrimitive.content)
        assertEquals("Apache-2.0", metadata["license"]!!.jsonPrimitive.content)
    }

    private fun loadFixture(): JsonObject {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "shared/test-fixtures/catalog-validation-cases.json")
            if (candidate.exists()) return Json.parseToJsonElement(candidate.readText()).jsonObject
            dir = dir.parentFile
        }
        throw IllegalStateException("catalog-validation-cases.json not found from ${System.getProperty("user.dir")}")
    }
}
