package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.FilmIdentity
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.catalog.ReciprocityRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Policy evaluation order/forms/basis + confidence presentation vocabulary. */
class PolicyAndPresentationTest {

    private val films = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private val evaluator = ReciprocityCalculationPolicyEvaluator()
    private fun film(id: String): FilmIdentity = films.first { it.id == id }
    private fun profile(id: String) = film(id).profiles.first()

    @Test
    fun formulaFilmProducesFormulaDerivedQuantified() {
        val result = evaluator.evaluate(profile("ilford-pan-f-plus-50"), 10.0)
        assertTrue(result is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.FORMULA_DERIVED, result.metadata.basis)
        assertTrue(result.correctedExposureSeconds!! > 10.0)
    }

    @Test
    fun formulaFilmBelowBoundaryIsNoCorrection() {
        val result = evaluator.evaluate(profile("ilford-pan-f-plus-50"), 0.5)
        assertTrue(result is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, result.metadata.basis)
        assertEquals(0.5, result.correctedExposureSeconds!!, 1e-9)
    }

    @Test
    fun tableFilmProducesTableLogLogDerivedAndBeyondRangeContinuation() {
        val fomapan = profile("foma-fomapan-100")
        val rule = (fomapan.typedRules.first() as ReciprocityRule.Table).rule
        // Within range at an anchor -> table-derived quantified.
        val within = evaluator.evaluate(fomapan, rule.sortedAnchors.last().meteredSeconds)
        assertTrue(within is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED, within.metadata.basis)
        // Well beyond the source range -> unsupported, but still carries a value.
        val beyond = evaluator.evaluate(fomapan, rule.sourceRangeThroughSeconds * 3.0)
        assertTrue(beyond is ReciprocityResult.Unsupported)
        assertTrue((beyond as ReciprocityResult.Unsupported).correctedContinuation != null)
    }

    @Test
    fun thresholdLimitedFilmNoCorrectionThenLimitedGuidance() {
        val portra = profile("kodak-portra-400")
        val noCorr = evaluator.evaluate(portra, 0.5)
        assertTrue(noCorr is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.OFFICIAL_THRESHOLD_NO_CORRECTION, noCorr.metadata.basis)

        val limited = evaluator.evaluate(portra, 120.0)
        assertTrue(limited is ReciprocityResult.LimitedGuidance)
        assertNull(limited.correctedExposureSeconds) // never fabricates a value
    }

    @Test
    fun confidenceVocabularyIsConstrainedAcrossCatalog() {
        val meterPoints = listOf(0.5, 2.0, 30.0, 300.0, 5000.0)
        for (f in films) {
            for (m in meterPoints) {
                val presentation = ReciprocityConfidencePresentationMapper.map(evaluator.evaluate(f.profiles.first(), m))
                for (forbidden in ReciprocityConfidencePresentationMapper.FORBIDDEN_VOCABULARY) {
                    assertTrue(
                        "${f.id}@${m}s label '${presentation.shortLabel}' contains forbidden '$forbidden'",
                        !presentation.shortLabel.contains(forbidden),
                    )
                }
            }
        }
    }

    @Test
    fun tableDerivedAndFormulaDerivedLabelsAreDistinct() {
        val table = ReciprocityConfidencePresentationMapper.map(
            evaluator.evaluate(profile("foma-fomapan-100"), 10.0),
        )
        assertEquals("Table-derived", table.shortLabel)
        val formula = ReciprocityConfidencePresentationMapper.map(
            evaluator.evaluate(profile("ilford-pan-f-plus-50"), 10.0),
        )
        assertEquals("Formula-derived", formula.shortLabel)
    }
}
