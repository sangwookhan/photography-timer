package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.catalog.CustomFilmReferenceTableResolver
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.catalog.ReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

/** Custom film: formula/table authoring, library, fitted preview, create-from-table, persistence. */
class CustomFilmTest {

    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - factory / validation

    @Test
    fun buildFormulaAcceptsValidAndRejectsShortening() {
        val ok = CustomFilmFactory.buildFormula("c1", "My Film", 100, exponent = 1.4, noCorrectionThroughSeconds = 1.0)
        assertTrue(ok is CustomFilmResult.Success)

        val shortening = CustomFilmFactory.buildFormula("c2", "Bad", 100, coefficientSeconds = 0.5, exponent = 1.0, noCorrectionThroughSeconds = 0.0)
        assertTrue(shortening is CustomFilmResult.Failure)
    }

    @Test
    fun buildTableAcceptsValidAndRejectsBadAnchors() {
        val ok = CustomFilmFactory.buildTable("t1", "My Table", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0)))
        assertTrue(ok is CustomFilmResult.Success)

        assertTrue(CustomFilmFactory.buildTable("t2", "One", 100, listOf(TableAnchor(1.0, 2.0))) is CustomFilmResult.Failure)
        assertTrue(CustomFilmFactory.buildTable("t3", "Short", 100, listOf(TableAnchor(1.0, 0.5), TableAnchor(10.0, 80.0))) is CustomFilmResult.Failure)
    }

    // MARK: - library

    @Test
    fun libraryUpsertsRemovesAndRejectsNonCustom() {
        val lib = CustomFilmLibrary()
        val film = (CustomFilmFactory.buildFormula("c1", "F", 100, exponent = 1.3, noCorrectionThroughSeconds = 1.0) as CustomFilmResult.Success).film
        assertTrue(lib.upsert(film))
        assertEquals(1, lib.all.size)
        // Reject a preset (non-custom) film.
        val preset = LaunchPresetFilmCatalogLoader.loadBundledCatalog().first()
        assertFalse(lib.upsert(preset))
        lib.remove("c1")
        assertTrue(lib.all.isEmpty())
    }

    @Test
    fun libraryRejectsMalformedCustomShapes() {
        val lib = CustomFilmLibrary()
        val formula = (CustomFilmFactory.buildFormula("f", "F", 100, exponent = 1.3, noCorrectionThroughSeconds = 1.0) as CustomFilmResult.Success).film
        val table = (CustomFilmFactory.buildTable("t", "T", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0))) as CustomFilmResult.Success).film
        val profile = formula.profiles.single()

        // Zero rules in the single profile.
        assertFalse(lib.upsert(formula.copy(id = "m0", profiles = listOf(profile.copy(rules = emptyList())))))
        // Two rules in one profile (must be exactly one).
        assertFalse(lib.upsert(formula.copy(id = "m2", profiles = listOf(profile.copy(rules = profile.rules + profile.rules)))))
        // Mixed formula + table rule in one profile.
        assertFalse(lib.upsert(formula.copy(id = "mix", profiles = listOf(profile.copy(rules = profile.rules + table.profiles.single().rules)))))
        // More than one profile (custom films are single-profile).
        assertFalse(lib.upsert(formula.copy(id = "m2p", profiles = listOf(profile, profile.copy(id = "p2")))))

        assertTrue("no malformed film should have been retained", lib.all.isEmpty())
        // Sanitizing constructor drops malformed seeds too.
        val seeded = CustomFilmLibrary(listOf(formula.copy(id = "bad", profiles = emptyList()), formula))
        assertEquals(listOf("f"), seeded.all.map { it.id })
    }

    // MARK: - fitted preview (inspection-only)

    @Test
    fun fittedPreviewAvailableForCleanTable() {
        val table = (CustomFilmFactory.buildTable(
            "t", "Fits", 100,
            listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 2.0 * 10.0.pow(1.4)), TableAnchor(100.0, 2.0 * 100.0.pow(1.4))),
        ) as CustomFilmResult.Success).film
        val rule = (table.profiles.first().typedRules.first() as ReciprocityRule.Table).rule

        val preview = FittedFormulaPreviewPresenter.preview(rule)
        assertTrue(preview is FittedPreview.Available)
        val available = preview as FittedPreview.Available
        assertEquals(FitQuality.GOOD, available.quality)
        assertEquals(3, available.rows.size)
        assertFalse(available.parameterText.contains("E")) // no scientific notation
    }

    // MARK: - create formula from table (PTIMER-180)

    @Test
    fun createFormulaFromTableProducesSeparateLinkedFormula() {
        val table = (CustomFilmFactory.buildTable("table-1", "Acme 100", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0))) as CustomFilmResult.Success).film
        val formula = CreateFormulaFromTable.create(table, "formula-1")
        assertNotNull(formula)
        assertEquals("formula-1", formula!!.id)
        assertEquals("Acme 100 Formula", formula.canonicalStockName)
        assertEquals("table-1", formula.userMetadata?.referenceTableFilmID)
        // Saved profile is a formula rule, never a table rule.
        assertTrue(formula.profiles.first().typedRules.first() is ReciprocityRule.Formula)

        // Ineligible (preset) film returns null.
        val preset = LaunchPresetFilmCatalogLoader.loadBundledCatalog().first()
        assertNull(CreateFormulaFromTable.create(preset, "x"))
    }

    @Test
    fun savedTableCalculatesByTableAndLinkedFormulaIndependentOfTable() {
        val table = (CustomFilmFactory.buildTable("table-1", "Acme", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0))) as CustomFilmResult.Success).film
        // Table calculates by log-log interpolation.
        val tableResult = evaluator.evaluate(table.profiles.first(), 10.0)
        assertEquals(ReciprocityCalculationBasis.TABLE_LOG_LOG_DERIVED, tableResult.metadata.basis)
        assertEquals(80.0, (tableResult as ReciprocityResult.Quantified).corrected, 1e-9)

        // Created formula calculates by formula only; the linked table never alters it.
        val formula = CreateFormulaFromTable.create(table, "formula-1")!!
        val formulaResult = evaluator.evaluate(formula.profiles.first(), 10.0)
        assertEquals(ReciprocityCalculationBasis.FORMULA_DERIVED, formulaResult.metadata.basis)

        // Resolver re-hydrates the linked table's anchors (display-only).
        val resolution = CustomFilmReferenceTableResolver.resolve(formula) { id -> if (id == "table-1") table else null }
        assertEquals(2, resolution.anchors.size)
        assertFalse(resolution.isLinkedButMissing)
    }

    // MARK: - persistence

    @Test
    fun libraryCodecRoundTripsAndFailsSafe() {
        val film = (CustomFilmFactory.buildFormula("c1", "F", 100, exponent = 1.3, noCorrectionThroughSeconds = 1.0) as CustomFilmResult.Success).film
        val json = CustomFilmLibraryCodec.encode(listOf(film))
        val restored = CustomFilmLibraryCodec.decode(json)
        assertEquals(1, restored.size)
        assertEquals("c1", restored.first().id)

        assertTrue(CustomFilmLibraryCodec.decode("{ not json").isEmpty())
        assertTrue(CustomFilmLibraryCodec.decode("""{"schemaVersion":999,"films":[]}""").isEmpty())
    }
}
