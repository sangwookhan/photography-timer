package com.sangwook.ptimer.core.reciprocity

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocityEvaluatorsTest {

    private val json = Json { ignoreUnknownKeys = true }

    // MARK: - Guarded formula

    private fun formula(
        exponent: Double = 1.31,
        coefficient: Double = 1.0,
        offset: Double = 0.0,
        ref: Double = 1.0,
        noCorrectionThrough: Double = 1.0,
        sourceRangeThrough: Double? = null,
    ) = ReciprocityFormula(
        formulaFamily = FormulaFamily.modifiedSchwarzschild,
        coefficientSeconds = coefficient,
        referenceMeteredTimeSeconds = ref,
        exponent = exponent,
        offsetSeconds = offset,
        noCorrectionThroughSeconds = noCorrectionThrough,
        sourceRangeThroughSeconds = sourceRangeThrough,
    )

    @Test
    fun formulaBelowThresholdIsNoCorrection() {
        assertEquals(FormulaEvaluationResult.NoCorrection, formula().evaluate(0.5))
        assertEquals(FormulaEvaluationResult.NoCorrection, formula().evaluate(1.0))
    }

    @Test
    fun formulaAboveThresholdComputesModifiedSchwarzschild() {
        val r = formula(exponent = 1.31, noCorrectionThrough = 1.0).evaluate(10.0)
        assertTrue(r is FormulaEvaluationResult.WithinSourceRange)
        // Tc = 10^1.31 ≈ 20.418
        assertEquals(20.418, (r as FormulaEvaluationResult.WithinSourceRange).correctedExposureSeconds, 0.01)
    }

    @Test
    fun formulaBeyondSourceRangeIsClassified() {
        val r = formula(exponent = 1.31, noCorrectionThrough = 1.0, sourceRangeThrough = 5.0).evaluate(10.0)
        assertTrue(r is FormulaEvaluationResult.BeyondSourceRange)
        assertEquals(20.418, (r as FormulaEvaluationResult.BeyondSourceRange).correctedExposureSeconds, 0.01)
    }

    @Test
    fun formulaRejectsBadInputAndBadParameters() {
        assertEquals(FormulaEvaluationResult.InvalidInput, formula().evaluate(0.0))
        assertEquals(FormulaEvaluationResult.InvalidInput, formula().evaluate(-1.0))
        assertEquals(
            FormulaEvaluationResult.InvalidFormula,
            formula(noCorrectionThrough = -1.0).evaluate(10.0),
        )
    }

    @Test
    fun formulaThatWouldShortenIsRejected() {
        // Tc = 0.1 × Tm < Tm
        val r = formula(coefficient = 0.1, exponent = 1.0, noCorrectionThrough = 0.5).evaluate(10.0)
        assertEquals(FormulaEvaluationResult.UnsafeShorteningFormula, r)
    }

    // MARK: - Table interpolation (log-log)

    private fun fomapanLikeTable() = TableInterpolationReciprocityRule(
        anchors = listOf(
            TableAnchor(1.0, 2.0),
            TableAnchor(10.0, 80.0),
            TableAnchor(100.0, 1600.0),
        ),
        noCorrectionThroughSeconds = 0.5,
        sourceRangeThroughSeconds = 100.0,
    )

    @Test
    fun tableNoCorrectionBandIncludesTolerance() {
        // 0.5 × 1.10 = 0.55 admitted as no correction.
        assertEquals(TableEvaluationResult.NoCorrection, fomapanLikeTable().evaluate(0.4))
        assertEquals(TableEvaluationResult.NoCorrection, fomapanLikeTable().evaluate(0.55))
    }

    @Test
    fun tablePassesThroughPublishedAnchorsExactly() {
        val at10 = fomapanLikeTable().evaluate(10.0)
        assertTrue(at10 is TableEvaluationResult.WithinSourceRange)
        assertEquals(80.0, (at10 as TableEvaluationResult.WithinSourceRange).correctedExposureSeconds, 1e-6)

        val at100 = fomapanLikeTable().evaluate(100.0)
        assertTrue(at100 is TableEvaluationResult.WithinSourceRange)
        assertEquals(1600.0, (at100 as TableEvaluationResult.WithinSourceRange).correctedExposureSeconds, 1e-6)
    }

    @Test
    fun tableBeyondLastAnchorExtrapolatesAndIsClassified() {
        val r = fomapanLikeTable().evaluate(200.0)
        assertTrue(r is TableEvaluationResult.BeyondSourceRange)
        // Extrapolate the 10→80 / 100→1600 segment in log-log space.
        assertEquals(3942.0, (r as TableEvaluationResult.BeyondSourceRange).correctedExposureSeconds, 5.0)
    }

    @Test
    fun tableRejectsBadInputAndBadRule() {
        assertEquals(TableEvaluationResult.InvalidInput, fomapanLikeTable().evaluate(0.0))
        val badRule = TableInterpolationReciprocityRule(
            anchors = listOf(TableAnchor(1.0, 2.0)), // only one anchor
            noCorrectionThroughSeconds = 0.5,
            sourceRangeThroughSeconds = 1.0,
        )
        assertEquals(TableEvaluationResult.InvalidRule, badRule.evaluate(10.0))
    }

    // MARK: - Serialization shape

    @Test
    fun ruleDecodesIosTaggedShape() {
        val ruleJson = """
            {
              "kind": "formula",
              "formula": {
                "formula": { "formulaFamily": "modifiedSchwarzschild", "exponent": 1.31,
                             "noCorrectionThroughSeconds": 1.0 }
              }
            }
        """.trimIndent()
        val rule = json.decodeFromString<ReciprocityRule>(ruleJson)
        assertEquals(ReciprocityRuleKind.formula, rule.kind)
        assertEquals(1.31, rule.formula!!.formula.exponent, 1e-12)
    }

    @Test
    fun filmIdentityRoundTrips() {
        val identity = FilmIdentity(
            id = "test-film",
            kind = FilmIdentityKind.preset,
            canonicalStockName = "Test Film",
            manufacturer = "ACME",
            aliases = listOf("tf"),
            iso = 100,
            productionStatus = FilmProductionStatus.current,
            profiles = listOf(
                ReciprocityProfile(
                    id = "p1",
                    name = "Official",
                    source = ReciprocitySourceProvenance(
                        kind = ReciprocitySourceKind.manufacturerPublished,
                        authority = ReciprocityAuthority.official,
                        publisher = "ACME",
                    ),
                    rules = listOf(
                        ReciprocityRule(
                            kind = ReciprocityRuleKind.formula,
                            formula = FormulaReciprocityRule(formula = formula()),
                        ),
                    ),
                ),
            ),
        )
        val encoded = json.encodeToString(FilmIdentity.serializer(), identity)
        val decoded = json.decodeFromString(FilmIdentity.serializer(), encoded)
        assertEquals(identity, decoded)
    }
}
