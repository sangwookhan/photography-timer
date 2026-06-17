package com.sangwook.ptimer.details

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.customfilm.CreateFormulaFromTable
import com.sangwook.ptimer.customfilm.CustomFilmFactory
import com.sangwook.ptimer.customfilm.CustomFilmResult
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Details transparency: model/source/calc rows, fitted comparison, reference columns, vocabulary. */
class DetailsPresenterTest {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private val evaluator = ReciprocityCalculationPolicyEvaluator()
    private fun film(id: String) = catalog.first { it.id == id }

    @Test
    fun tableFilmShowsLogLogCalculationAndOfficialSource() {
        val f = film("foma-fomapan-100")
        val profile = f.profiles.first()
        val details = DetailsPresenter.build(f, profile, evaluator.evaluate(profile, 10.0), 10.0) { null }
        assertTrue(details.rows.any { it.label == "Calculation" && it.value == "Log-log table interpolation" })
        assertTrue(details.rows.any { it.label == "Source" && it.value.startsWith("Official guidance") })
        // No forbidden table-era vocabulary in any row value.
        details.rows.forEach { row ->
            listOf("Exact", "Estimated", "Interpolated", "Extrapolated", "Advisory").forEach {
                assertTrue(!row.value.contains(it))
            }
        }
    }

    @Test
    fun customTableShowsInspectionOnlyFittedComparison() {
        val table = (CustomFilmFactory.buildTable("t", "Acme", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0), TableAnchor(100.0, 1600.0))) as CustomFilmResult.Success).film
        val profile = table.profiles.first()
        val details = DetailsPresenter.build(table, profile, evaluator.evaluate(profile, 10.0), 10.0) { null }
        assertNotNull(details.comparisonTitle)
        assertTrue(details.comparisonTitle!!.contains("inspection-only"))
        assertEquals(3, details.comparisonLines.size)
    }

    @Test
    fun linkedFormulaShowsReferenceTableComparison() {
        val table = (CustomFilmFactory.buildTable("table-1", "Acme", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0))) as CustomFilmResult.Success).film
        val formula = CreateFormulaFromTable.create(table, "formula-1")!!
        val profile = formula.profiles.first()
        val details = DetailsPresenter.build(formula, profile, evaluator.evaluate(profile, 10.0), 10.0) { id -> if (id == "table-1") table else null }
        assertEquals("Custom formula", details.rows.first { it.label == "Calculation" }.value)
        assertEquals("Reference table comparison (display-only)", details.comparisonTitle)
        assertEquals(2, details.comparisonLines.size)
    }
}
