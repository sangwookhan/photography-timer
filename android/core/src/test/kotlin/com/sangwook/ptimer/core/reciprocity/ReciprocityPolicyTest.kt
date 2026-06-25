package com.sangwook.ptimer.core.reciprocity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocityPolicyTest {

    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    private fun provenance(
        kind: ReciprocitySourceKind = ReciprocitySourceKind.manufacturerPublished,
        authority: ReciprocityAuthority = ReciprocityAuthority.official,
    ) = ReciprocitySourceProvenance(kind = kind, authority = authority, publisher = "ACME")

    private fun profile(vararg rules: ReciprocityRule, source: ReciprocitySourceProvenance = provenance()) =
        ReciprocityProfile(id = "p", name = "n", source = source, rules = rules.toList())

    private fun formulaRule(exponent: Double = 1.31, noCorr: Double = 1.0, sourceRange: Double? = null) =
        ReciprocityRule(
            kind = ReciprocityRuleKind.formula,
            formula = FormulaReciprocityRule(
                formula = ReciprocityFormula(
                    formulaFamily = FormulaFamily.modifiedSchwarzschild,
                    exponent = exponent,
                    noCorrectionThroughSeconds = noCorr,
                    sourceRangeThroughSeconds = sourceRange,
                ),
            ),
        )

    private fun tableRule() = ReciprocityRule(
        kind = ReciprocityRuleKind.tableInterpolation,
        tableInterpolation = TableInterpolationReciprocityRule(
            anchors = listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0), TableAnchor(100.0, 1600.0)),
            noCorrectionThroughSeconds = 0.5,
            sourceRangeThroughSeconds = 100.0,
        ),
    )

    @Test
    fun formulaWithinRangeIsQuantifiedFormulaDerived() {
        val r = evaluator.evaluate(profile(formulaRule()), 10.0)
        assertTrue(r is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.formulaDerived, r.metadata.basis)
        assertEquals(20.418, (r as ReciprocityResult.Quantified).correctedExposureSeconds, 0.01)

        val c = r.confidencePresentation
        assertEquals(ReciprocityConfidenceCategory.formulaDerived, c.category)
        assertEquals(ReciprocityConfidenceLevel.medium, c.level)
        assertEquals(ReciprocityConfidenceBadgeStyle.measured, c.badgeStyle)
        assertEquals("Formula-derived", c.shortLabel)
        assertTrue(c.returnsCalculatedExposureTime)
    }

    @Test
    fun formulaBelowThresholdIsNoCorrection() {
        val r = evaluator.evaluate(profile(formulaRule(noCorr = 1.0)), 0.5)
        assertTrue(r is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.officialThresholdNoCorrection, r.metadata.basis)
        assertEquals(0.5, (r as ReciprocityResult.Quantified).correctedExposureSeconds, 1e-9)
        assertEquals("No correction", r.confidencePresentation.shortLabel)
        assertEquals(ReciprocityConfidenceBadgeStyle.trusted, r.confidencePresentation.badgeStyle)
    }

    @Test
    fun formulaBeyondSourceRangeIsUnsupportedWithPrediction() {
        val r = evaluator.evaluate(profile(formulaRule(sourceRange = 5.0)), 10.0)
        assertTrue(r is ReciprocityResult.Unsupported)
        assertEquals(ReciprocityCalculationBasis.unsupportedOutOfPolicyRange, r.metadata.basis)
        assertNotNull((r as ReciprocityResult.Unsupported).correctedExposureSeconds)
        val c = r.confidencePresentation
        assertEquals(ReciprocityConfidenceCategory.unsupported, c.category)
        assertEquals(ReciprocityConfidenceBadgeStyle.unsupported, c.badgeStyle)
        assertEquals("Outside guidance", c.shortLabel)
        assertTrue(c.returnsCalculatedExposureTime)
    }

    @Test
    fun officialTableWithinRangeIsTableDerivedHighConfidence() {
        val r = evaluator.evaluate(profile(tableRule()), 10.0)
        assertTrue(r is ReciprocityResult.Quantified)
        assertEquals(ReciprocityCalculationBasis.tableLogLogDerived, r.metadata.basis)
        assertEquals(80.0, (r as ReciprocityResult.Quantified).correctedExposureSeconds, 1e-6)
        val c = r.confidencePresentation
        assertEquals(ReciprocityConfidenceLevel.high, c.level)
        assertEquals("Table-derived", c.shortLabel)
    }

    @Test
    fun tableBeyondRangeIsUnsupported() {
        val r = evaluator.evaluate(profile(tableRule()), 200.0)
        assertTrue(r is ReciprocityResult.Unsupported)
        assertNotNull((r as ReciprocityResult.Unsupported).correctedExposureSeconds)
    }

    @Test
    fun formulaWinsOverTableWhenBothPresent() {
        // Evaluation order: formula is selected before table.
        val r = evaluator.evaluate(profile(tableRule(), formulaRule()), 10.0)
        assertEquals(ReciprocityCalculationBasis.formulaDerived, r.metadata.basis)
    }

    @Test
    fun limitedGuidanceProfileIsNoQuantifiedPrediction() {
        val rule = ReciprocityRule(
            kind = ReciprocityRuleKind.limitedGuidance,
            limitedGuidance = LimitedGuidanceReciprocityRule(),
        )
        val r = evaluator.evaluate(profile(rule), 10.0)
        assertTrue(r is ReciprocityResult.LimitedGuidance)
        assertNull(r.calculatedCorrectedSeconds)
        val c = r.confidencePresentation
        assertEquals(ReciprocityConfidenceCategory.limitedGuidance, c.category)
        assertEquals("No quantified prediction", c.shortLabel)
        assertEquals(false, c.returnsCalculatedExposureTime)
    }

    @Test
    fun thresholdProfileWithinRangeIsNoCorrection() {
        val rule = ReciprocityRule(
            kind = ReciprocityRuleKind.threshold,
            threshold = ThresholdReciprocityRule(noCorrectionRange = ReciprocityTimeRange(0.0, 30.0)),
        )
        val r = evaluator.evaluate(profile(rule), 10.0)
        assertEquals(ReciprocityCalculationBasis.officialThresholdNoCorrection, r.metadata.basis)
        assertEquals(10.0, (r as ReciprocityResult.Quantified).correctedExposureSeconds, 1e-9)
    }

    @Test
    fun emptyRulesAreUnsupported() {
        val r = evaluator.evaluate(profile(), 10.0)
        assertTrue(r is ReciprocityResult.Unsupported)
        assertEquals(ReciprocityConfidenceCategory.unsupported, r.confidencePresentation.category)
    }

    @Test
    fun userDefinedSourceLowersConfidenceAndPrefixesLabel() {
        val r = evaluator.evaluate(
            profile(formulaRule(), source = provenance(ReciprocitySourceKind.userDefined, ReciprocityAuthority.userDefined)),
            10.0,
        )
        val c = r.confidencePresentation
        assertEquals(ReciprocityConfidenceLevel.veryLow, c.level)
        assertEquals("Custom formula", c.shortLabel)
    }
}
