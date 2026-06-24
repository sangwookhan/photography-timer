package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocityDetailsPresenterTest {

    private val films = LaunchPresetFilmCatalogLoader().loadBundledCatalog()
    private val policy = ReciprocityCalculationPolicyEvaluator()

    private fun film(id: String) = films.first { it.id == id }

    @Test
    fun formulaFilmRendersEquationModelAndResult() {
        val f = film("ilford-pan-f-plus-50")
        val profile = f.profiles.first()
        val result = policy.evaluate(profile, 30.0)
        val state = ReciprocityDetailsPresenter.make(f, profile, result, 30.0, { "${it}s" })

        assertEquals("Reciprocity Details", state.title)
        assertTrue(state.subtitle.startsWith("Pan F Plus"))
        // Status mirrors the confidence short label (e.g. "Formula-derived").
        assertEquals(result.confidencePresentation.shortLabel, state.statusText)
        // Formula profile → an equation + a guarded-formula calculation label.
        assertNotNull(state.equationText)
        assertTrue(state.equationText!!.startsWith("Tc ="))
        assertEquals("Guarded formula", state.calculationText)
        assertTrue(state.sourceText.isNotEmpty())
    }

    @Test
    fun correctedTextReflectsQuantifiedConfidence() {
        val f = film("ilford-pan-f-plus-50")
        val profile = f.profiles.first()
        val result = policy.evaluate(profile, 30.0)
        val state = ReciprocityDetailsPresenter.make(f, profile, result, 30.0, { "${it}s" })
        assertTrue(state.statusText.isNotEmpty())
        assertTrue(state.correctedExposureText.endsWith("s"))
    }
}
