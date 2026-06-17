package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.FormulaEvaluationResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Preset-only alternates + reference-table resolver + display-only invariants. */
class CustomReferenceAndAlternatesTest {

    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - alternate models

    @Test
    fun presetFilmsExposeAlternatesCustomFilmsDoNot() {
        assertTrue(AlternateReciprocityModels.alternates("foma-fomapan-100").isNotEmpty())
        assertTrue(AlternateReciprocityModels.alternates("kodak-tri-x-400").isNotEmpty())
        assertTrue(AlternateReciprocityModels.alternates("custom-anything").isEmpty())
        assertTrue(AlternateReciprocityModels.isAppDerivedModel("foma-fomapan-100-app-formula"))
    }

    // MARK: - reference-table resolver

    private fun customTableFilm(id: String, anchors: List<TableAnchor>): FilmIdentity = FilmIdentity(
        id = id, kind = "custom", canonicalStockName = id, iso = 100, productionStatus = "current",
        profiles = listOf(
            ReciprocityProfile(
                id = "$id-profile", name = "Custom table",
                source = SourceProvenance(kind = "userDefined", authority = "userDefined", publisher = "User"),
                rules = listOf(RawRule(kind = "tableInterpolation", tableInterpolation = TableRulePayload(anchors, 0.5, anchors.last().meteredSeconds))),
            ),
        ),
    )

    private fun customFormulaFilm(id: String, referenceTableFilmId: String?): FilmIdentity = FilmIdentity(
        id = id, kind = "custom", canonicalStockName = id, iso = 100, productionStatus = "current",
        userMetadata = UserEditableMetadata(referenceTableFilmID = referenceTableFilmId),
        profiles = listOf(
            ReciprocityProfile(
                id = "$id-profile", name = "Custom formula",
                source = SourceProvenance(kind = "userDefined", authority = "userDefined", publisher = "User"),
                rules = listOf(RawRule(kind = "formula", formula = FormulaRulePayload(ReciprocityFormula(coefficientSeconds = 2.0, exponent = 1.4, noCorrectionThroughSeconds = 1.0)))),
            ),
        ),
    )

    private val table = customTableFilm("custom-table", listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0)))

    @Test
    fun unlinkedFormulaResolvesEmptyNotMissing() {
        val r = CustomFilmReferenceTableResolver.resolve(customFormulaFilm("f", null)) { null }
        assertTrue(r.anchors.isEmpty())
        assertFalse(r.isLinkedButMissing)
    }

    @Test
    fun linkedFormulaResolvesCurrentAnchors() {
        val linked = customFormulaFilm("f", "custom-table")
        val r = CustomFilmReferenceTableResolver.resolve(linked) { id -> if (id == "custom-table") table else null }
        assertEquals(2, r.anchors.size)
        assertFalse(r.isLinkedButMissing)
    }

    @Test
    fun linkedButMissingReportsUnavailableWithoutCrashing() {
        val linked = customFormulaFilm("f", "deleted-table")
        val r = CustomFilmReferenceTableResolver.resolve(linked) { null }
        assertTrue(r.anchors.isEmpty())
        assertTrue(r.isLinkedButMissing)
    }

    // MARK: - hard invariant: fitted formula / reference link are display-only

    @Test
    fun savedCustomTableCalculatesByTableInterpolation() {
        val result = evaluator.evaluate(table.profiles.first(), 10.0)
        assertTrue(result is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED, result.metadata.basis)
        assertEquals(80.0, result.correctedExposureSeconds!!, 1e-9)
    }

    @Test
    fun linkedReferenceTableDoesNotAlterActiveFormulaCalculation() {
        val formula = ReciprocityFormula(coefficientSeconds = 2.0, exponent = 1.4, noCorrectionThroughSeconds = 1.0)
        val expected = (formula.evaluate(20.0) as FormulaEvaluationResult.WithinSourceRange).correctedExposureSeconds

        val linked = evaluator.evaluate(customFormulaFilm("f", "custom-table").profiles.first(), 20.0)
        val unlinked = evaluator.evaluate(customFormulaFilm("f", null).profiles.first(), 20.0)

        assertEquals(expected, linked.correctedExposureSeconds!!, 1e-9)
        assertEquals(expected, unlinked.correctedExposureSeconds!!, 1e-9)
    }
}
