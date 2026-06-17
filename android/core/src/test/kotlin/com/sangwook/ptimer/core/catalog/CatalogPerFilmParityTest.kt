package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.testsupport.SharedFixtureLocator
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Per-film catalog parity, driven by the shared fixture's `perFilmExpectations`
 * (iOS LaunchPresetFilmCatalogTests protect the same per-film constants). This
 * closes the gap where Android only validated counts/shapes, not each film's
 * provenance and — crucially — its calculation parameters (formula
 * coefficient/exponent/offset/reference/no-correction/source-range, or
 * threshold no-correction band). Param asserts run only where the catalog
 * film actually has that rule kind, so the fixture's older two-shape `rule-11`
 * drift does not affect this test.
 */
class CatalogPerFilmParityTest {

    private val films = LaunchPresetFilmCatalogLoader.loadBundledCatalog().associateBy { it.id }
    private val evaluator = ReciprocityCalculationPolicyEvaluator()
    private val perFilm = Json.parseToJsonElement(
        SharedFixtureLocator.readText("catalog-validation-cases.json"),
    ).jsonObject["perFilmExpectations"]!!.jsonArray

    @Test
    fun everyExpectedFilmIsPresentWithMatchingIdentityAndProvenance() {
        assertTrue("fixture should describe films", perFilm.isNotEmpty())
        for (entry in perFilm) {
            val o = entry.jsonObject
            val id = o["filmId"]!!.jsonPrimitive.content
            val film = films[id] ?: error("Catalog missing expected film $id")
            assertEquals("$id iso", o["iso"]!!.jsonPrimitive.int, film.iso)
            assertEquals("$id kind", o["kind"]!!.jsonPrimitive.content, film.kind)
            assertEquals("$id status", o["productionStatus"]!!.jsonPrimitive.content, film.productionStatus)
            o["manufacturer"]?.let { assertEquals("$id manufacturer", it.jsonPrimitive.content, film.manufacturer) }

            val source = film.profiles.single().source
            assertEquals("$id source.authority", o["profileSourceAuthority"]!!.jsonPrimitive.content, source.authority)
            assertEquals("$id source.kind", o["profileSourceKind"]!!.jsonPrimitive.content, source.kind)
            o["profileSourceConfidence"]?.let { assertEquals("$id source.confidence", it.jsonPrimitive.content, source.confidence) }
            o["profileSourcePublisher"]?.let { assertEquals("$id source.publisher", it.jsonPrimitive.content, source.publisher) }
        }
    }

    @Test
    fun formulaFilmsMatchExpectedFormulaParameters() {
        var checked = 0
        for (entry in perFilm) {
            val o = entry.jsonObject
            if (!o.containsKey("formulaExponent")) continue
            val id = o["filmId"]!!.jsonPrimitive.content
            val rule = films[id]!!.profiles.single().typedRules.firstOrNull() as? ReciprocityRule.Formula ?: continue
            val f = rule.formula
            assertEquals("$id exponent", o["formulaExponent"]!!.jsonPrimitive.double, f.exponent, 1e-9)
            o["formulaCoefficientSeconds"]?.let { assertEquals("$id coefficient", it.jsonPrimitive.double, f.coefficientSeconds, 1e-9) }
            o["formulaReferenceMeteredTimeSeconds"]?.let { assertEquals("$id reference", it.jsonPrimitive.double, f.referenceMeteredTimeSeconds, 1e-9) }
            o["formulaOffsetSeconds"]?.let { assertEquals("$id offset", it.jsonPrimitive.double, f.offsetSeconds, 1e-9) }
            o["formulaNoCorrectionThroughSeconds"]?.let { assertEquals("$id noCorrection", it.jsonPrimitive.double, f.noCorrectionThroughSeconds, 1e-6) }
            o["formulaSourceRangeThroughSeconds"]?.let { assertEquals("$id sourceRange", it.jsonPrimitive.double, f.sourceRangeThroughSeconds ?: Double.NaN, 1e-6) }
            checked++
        }
        assertTrue("should have checked formula films", checked >= 10)
    }

    @Test
    fun thresholdFilmsMatchExpectedNoCorrectionBand() {
        // NOTE: the shared fixture's thresholdNoCorrectionMaxSeconds is stale for
        // Portra 160/400 (fixture max=1 vs catalog max=10, which matches current
        // iOS behavior). Per the owner decision the catalog JSON is authoritative,
        // so we assert the min against the fixture and validate the max via the
        // band-driven policy behavior using the catalog's own value. (iOS-side
        // fixture reconciliation is tracked separately, out of PTIMER-146.)
        var checked = 0
        for (entry in perFilm) {
            val o = entry.jsonObject
            if (!o.containsKey("thresholdNoCorrectionMaxSeconds")) continue
            val id = o["filmId"]!!.jsonPrimitive.content
            val profile = films[id]!!.profiles.single()
            val threshold = profile.typedRules.firstNotNullOfOrNull { it as? ReciprocityRule.Threshold } ?: continue
            val max = threshold.noCorrectionRange.maximumSeconds!!
            assertEquals("$id thr.min", o["thresholdNoCorrectionMinSeconds"]!!.jsonPrimitive.double, threshold.noCorrectionRange.minimumSeconds, 1e-9)
            assertTrue("$id band positive/ordered", threshold.noCorrectionRange.minimumSeconds < max)
            // Inside the band → no-correction; beyond it → limited guidance (no quantified prediction).
            assertEquals("$id within band", ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, evaluator.evaluate(profile, max * 0.5).metadata.basis)
            assertEquals("$id beyond band", ReciprocityCalculationBasis.LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION, evaluator.evaluate(profile, max * 3.0).metadata.basis)
            checked++
        }
        assertTrue("should have checked threshold films", checked >= 1)
    }

    /** Spot-check that each rule shape evaluates to the expected basis (iOS LaunchPresetFilmCatalogTests parity). */
    @Test
    fun representativeFilmsEvaluateToExpectedBasis() {
        fun basis(id: String, metered: Double) = evaluator.evaluate(films[id]!!.profiles.single(), metered).metadata.basis

        // Formula film: no-correction below boundary, formula-derived above.
        assertEquals(ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, basis("ilford-pan-f-plus-50", 0.5))
        assertEquals(ReciprocityCalculationBasis.FORMULA_DERIVED, basis("ilford-pan-f-plus-50", 10.0))

        // Table film: reproduces an anchor as table-derived; far beyond source range → unsupported (still numeric).
        val fomapan = films["foma-fomapan-100"]!!.profiles.single()
        val tableRule = (fomapan.typedRules.first() as ReciprocityRule.Table).rule
        assertEquals(ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED, evaluator.evaluate(fomapan, tableRule.sortedAnchors.last().meteredSeconds).metadata.basis)
        val beyond = evaluator.evaluate(fomapan, tableRule.sourceRangeThroughSeconds * 5.0)
        assertEquals(ReciprocityCalculationBasis.UNSUPPORTED_OUT_OF_POLICY_RANGE, beyond.metadata.basis)
        assertTrue("beyond-source keeps a numeric continuation", (beyond as ReciprocityResult.Unsupported).correctedContinuation != null)

        // Threshold+limited film: no-correction in band, limited guidance beyond.
        assertEquals(ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, basis("kodak-portra-400", 0.5))
        assertEquals(ReciprocityCalculationBasis.LIMITED_GUIDANCE_NO_QUANTIFIED_PREDICTION, basis("kodak-portra-400", 120.0))
    }
}
