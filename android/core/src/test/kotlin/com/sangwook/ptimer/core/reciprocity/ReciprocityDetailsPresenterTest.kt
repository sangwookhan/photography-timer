package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

    @Test
    fun customFilmSurfacesNotesReferenceUrlAndSourceType() {
        val custom = CustomFilmBuilder.buildFormulaFilm(
            input = CustomFormulaFilmInput(
                filmLabel = "Noted", profileName = "Noted", iso = 100,
                coefficientSeconds = 1.0, referenceMeteredTimeSeconds = 1.0,
                exponent = 1.3, noCorrectionThroughSeconds = 1.0,
                notes = "Pushed one stop", sourceType = CustomProfileSourceType.personalTest,
                referenceUrl = "https://example.com/recip",
            ),
            filmId = "c", profileId = "cp",
        )!!
        val profile = custom.profiles.first()
        val state = ReciprocityDetailsPresenter.make(custom, profile, policy.evaluate(profile, 30.0), 30.0, { "${it}s" })

        assertEquals("Pushed one stop", state.notesText)
        assertEquals("https://example.com/recip", state.referenceUrlText)
        assertEquals("Personal test", state.sourceText)
    }

    @Test
    fun guidanceAndLegendSurfaceFromProfileAdjustments() {
        val profile = ReciprocityProfile(
            id = "gp",
            name = "Guided",
            source = ReciprocitySourceProvenance(
                kind = ReciprocitySourceKind.manufacturerPublished,
                authority = ReciprocityAuthority.official,
                publisher = "Test",
            ),
            rules = listOf(
                ReciprocityRule(
                    kind = ReciprocityRuleKind.formula,
                    formula = FormulaReciprocityRule(
                        formula = ReciprocityFormula(
                            formulaFamily = FormulaFamily.modifiedSchwarzschild,
                            exponent = 1.3,
                            noCorrectionThroughSeconds = 1.0,
                        ),
                        additionalAdjustments = listOf(
                            ReciprocityAdjustment(
                                kind = ReciprocityAdjustmentKind.colorFilter,
                                colorFilter = ColorFilterRecommendation("CC30M"),
                            ),
                            ReciprocityAdjustment(
                                kind = ReciprocityAdjustmentKind.development,
                                development = DevelopmentAdjustment("Dev -10%"),
                            ),
                            ReciprocityAdjustment(
                                kind = ReciprocityAdjustmentKind.warning,
                                warning = ReciprocityWarning(ReciprocityWarningSeverity.notRecommended, "Beyond data"),
                            ),
                        ),
                    ),
                ),
            ),
        )
        val film = FilmIdentity(
            id = "gf",
            kind = FilmIdentityKind.preset,
            canonicalStockName = "Guided Stock",
            aliases = emptyList(),
            iso = 100,
            productionStatus = FilmProductionStatus.current,
            profiles = listOf(profile),
        )
        val state = ReciprocityDetailsPresenter.make(film, profile, policy.evaluate(profile, 30.0), 30.0, { "${it}s" })

        // The glossary derives from the profile's rule adjustments. The source
        // reference table is empty here because the adjustments live on the rule,
        // not as published source-evidence rows (the table needs evidence).
        assertTrue(state.sourceReferenceRows.isEmpty())
        assertTrue(state.legendLines.contains("Color correction: CC30M = color-compensating magenta filtration."))
        assertTrue(state.legendLines.contains("Development adjustment: Dev -10% means adjust development time by -10%."))
        assertTrue(state.legendLines.contains("Warning: Not recommended marks a manufacturer stop-signal."))
    }

    @Test
    fun presetWithoutAdjustmentsHasNoReferenceTableOrLegend() {
        val f = film("ilford-pan-f-plus-50")
        val profile = f.profiles.first()
        val state = ReciprocityDetailsPresenter.make(f, profile, policy.evaluate(profile, 30.0), 30.0, { "${it}s" })
        assertTrue(state.sourceReferenceRows.isEmpty())
        assertTrue(state.guidanceBoundaryRows.isEmpty())
        assertTrue(state.legendLines.isEmpty())
    }

    @Test
    fun presetFilmHasNoUserProvenanceRows() {
        val f = film("ilford-pan-f-plus-50")
        val profile = f.profiles.first()
        val state = ReciprocityDetailsPresenter.make(f, profile, policy.evaluate(profile, 30.0), 30.0, { "${it}s" })
        assertNull(state.notesText)
        assertNull(state.referenceUrlText)
    }

    @Test
    fun tableSourcedGuardedFormulaReadsAppDerived() {
        // Velvia 50 guards a manufacturer TABLE source as a fitted formula, so the
        // calculation label is "App-derived guarded formula" (iOS), not the plain
        // "Guarded formula" used for a guarded manufacturer formula like Pan F.
        val velvia = films.first { it.canonicalStockName.contains("Velvia 50") }
        val profile = velvia.profiles.first()
        val state = ReciprocityDetailsPresenter.make(velvia, profile, policy.evaluate(profile, 4.0), 4.0, { "${it}s" })
        assertEquals("App-derived guarded formula", state.calculationText)
    }

    @Test
    fun beyondRangeStatusLeadsWithManufacturerStopSignal() {
        // Past the 64s not-recommended boundary, the status detail leads with the
        // manufacturer stop-signal sentence (iOS ReciprocityDetailsVocabularyPresenter).
        val velvia = films.first { it.canonicalStockName.contains("Velvia 50") }
        val profile = velvia.profiles.first()
        val state = ReciprocityDetailsPresenter.make(velvia, profile, policy.evaluate(profile, 100.0), 100.0, { "${it}s" })
        assertNotNull(state.statusDetailText)
        assertTrue(
            state.statusDetailText!!.startsWith("Manufacturer guidance: 64 sec is not recommended."),
        )
    }
}
