package com.sangwook.ptimer.core.reciprocity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

/**
 * Parity tests for the self-contained reciprocity calculation primitives:
 * formula evaluator, log-log table evaluator, OLS fitter, no-shortening
 * guard, no-correction boundary, and duration parser. iOS behavior is the
 * source of truth; table goldens are derived from the anchors themselves.
 */
class ReciprocityCoreTest {

    // MARK: - Formula evaluator

    @Test
    fun formulaNoCorrectionUsesStrictInclusiveBoundary() {
        val acrosLike = ReciprocityFormula(exponent = 1.3, noCorrectionThroughSeconds = 119.999999)
        assertTrue(acrosLike.evaluate(119.999999) is FormulaEvaluationResult.NoCorrection)
        assertTrue(acrosLike.evaluate(120.0) is FormulaEvaluationResult.WithinSourceRange)
    }

    @Test
    fun formulaWithinSourceRangeComputesPowerLaw() {
        val panF = ReciprocityFormula(exponent = 1.33, noCorrectionThroughSeconds = 0.999999)
        assertTrue(panF.evaluate(0.5) is FormulaEvaluationResult.NoCorrection)
        val result = panF.evaluate(10.0)
        assertTrue(result is FormulaEvaluationResult.WithinSourceRange)
        assertEquals(10.0.pow(1.33), (result as FormulaEvaluationResult.WithinSourceRange).correctedExposureSeconds, 1e-6)
    }

    @Test
    fun formulaBeyondSourceRangeStillComputes() {
        val f = ReciprocityFormula(exponent = 1.4, noCorrectionThroughSeconds = 1.0, sourceRangeThroughSeconds = 100.0)
        val result = f.evaluate(200.0)
        assertTrue(result is FormulaEvaluationResult.BeyondSourceRange)
        assertEquals(200.0.pow(1.4), (result as FormulaEvaluationResult.BeyondSourceRange).correctedExposureSeconds, 1e-6)
    }

    @Test
    fun formulaUnsafeShorteningIsFlagged() {
        val shortening = ReciprocityFormula(coefficientSeconds = 0.5, exponent = 1.0, noCorrectionThroughSeconds = 0.0)
        assertTrue(shortening.evaluate(10.0) is FormulaEvaluationResult.UnsafeShorteningFormula)
    }

    @Test
    fun formulaInvalidInputAndParameters() {
        val f = ReciprocityFormula(exponent = 1.3, noCorrectionThroughSeconds = 1.0)
        assertTrue(f.evaluate(0.0) is FormulaEvaluationResult.InvalidInput)
        assertTrue(f.evaluate(-1.0) is FormulaEvaluationResult.InvalidInput)

        val badParams = ReciprocityFormula(coefficientSeconds = 0.0, exponent = 1.3, noCorrectionThroughSeconds = 1.0)
        assertTrue(badParams.evaluate(10.0) is FormulaEvaluationResult.InvalidFormula)
    }

    @Test
    fun formulaOutputUnusableWhenNonPositive() {
        val f = ReciprocityFormula(coefficientSeconds = 1.0, exponent = 1.0, offsetSeconds = -100.0, noCorrectionThroughSeconds = 0.0)
        assertTrue(f.evaluate(10.0) is FormulaEvaluationResult.FormulaOutputUnusable)
    }

    // MARK: - Table evaluator (Fomapan 100 official anchors)

    private val fomapan = TableInterpolationRule(
        anchors = listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0), TableAnchor(100.0, 1600.0)),
        noCorrectionThroughSeconds = 0.5,
        sourceRangeThroughSeconds = 100.0,
    )

    @Test
    fun tableReproducesAnchorsExactly() {
        assertEquals(2.0, withinValue(fomapan.evaluate(1.0)), 1e-9)
        assertEquals(80.0, withinValue(fomapan.evaluate(10.0)), 1e-9)
        assertEquals(1600.0, withinValue(fomapan.evaluate(100.0)), 1e-9)
    }

    @Test
    fun tableNoCorrectionUsesTenPercentTolerance() {
        // 0.5 * 1.1 = 0.55 boundary
        assertTrue(fomapan.evaluate(0.4) is TableEvaluationResult.NoCorrection)
        assertTrue(fomapan.evaluate(0.55) is TableEvaluationResult.NoCorrection)
    }

    @Test
    fun tableInterpolatesBetweenAnchorsInLogLog() {
        val result = fomapan.evaluate(31.62277660168379) // 10^1.5, midpoint of 10..100 in log space
        assertTrue(result is TableEvaluationResult.WithinSourceRange)
        // log-log midpoint between (10,80) and (100,1600): 10^((log80+log1600)/2)
        val expected = 10.0.pow((kotlin.math.log10(80.0) + kotlin.math.log10(1600.0)) / 2.0)
        assertEquals(expected, (result as TableEvaluationResult.WithinSourceRange).correctedExposureSeconds, 1e-6)
    }

    @Test
    fun tableBeyondLastAnchorExtrapolates() {
        val result = fomapan.evaluate(200.0)
        assertTrue(result is TableEvaluationResult.BeyondSourceRange)
        assertTrue((result as TableEvaluationResult.BeyondSourceRange).correctedExposureSeconds > 1600.0)
    }

    @Test
    fun tableRejectsInvalidInputAndRule() {
        assertTrue(fomapan.evaluate(0.0) is TableEvaluationResult.InvalidInput)
        val oneAnchor = TableInterpolationRule(listOf(TableAnchor(1.0, 2.0)), 0.5, 1.0)
        assertTrue(oneAnchor.evaluate(2.0) is TableEvaluationResult.InvalidRule)
    }

    private fun withinValue(r: TableEvaluationResult): Double =
        (r as TableEvaluationResult.WithinSourceRange).correctedExposureSeconds

    // MARK: - Fitter

    @Test
    fun fitterRecoversGeneratingPowerLaw() {
        val anchors = listOf(TableAnchor(1.0, 2.0 * 1.0.pow(1.4)), TableAnchor(100.0, 2.0 * 100.0.pow(1.4)))
        val result = ReciprocityFormulaFitter.fit(anchors)
        assertTrue(result is PowerLawFitResult.Success)
        val fit = (result as PowerLawFitResult.Success).fit
        assertEquals(2.0, fit.coefficient, 1e-9)
        assertEquals(1.4, fit.exponent, 1e-9)
    }

    @Test
    fun fitterIsOrderIndependentAndDeterministic() {
        val asc = listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 50.0), TableAnchor(100.0, 1200.0))
        val shuffled = listOf(asc[2], asc[0], asc[1])
        // Same input twice is bit-identical (determinism).
        assertEquals(ReciprocityFormulaFitter.fit(asc), ReciprocityFormulaFitter.fit(asc))
        // Reordered anchors agree to numerical precision (order-independence).
        val a = (ReciprocityFormulaFitter.fit(asc) as PowerLawFitResult.Success).fit
        val b = (ReciprocityFormulaFitter.fit(shuffled) as PowerLawFitResult.Success).fit
        assertEquals(a.coefficient, b.coefficient, 1e-9)
        assertEquals(a.exponent, b.exponent, 1e-9)
    }

    @Test
    fun fitterRejectsBadAnchors() {
        assertEquals(FitUnavailable.INSUFFICIENT_ANCHORS, failureReason(ReciprocityFormulaFitter.fit(listOf(TableAnchor(1.0, 2.0)))))
        assertEquals(FitUnavailable.NON_POSITIVE_ANCHORS, failureReason(ReciprocityFormulaFitter.fit(listOf(TableAnchor(0.0, 2.0), TableAnchor(10.0, 50.0)))))
        assertEquals(FitUnavailable.DEGENERATE_ANCHORS, failureReason(ReciprocityFormulaFitter.fit(listOf(TableAnchor(10.0, 20.0), TableAnchor(10.0, 40.0)))))
    }

    private fun failureReason(r: PowerLawFitResult): FitUnavailable = (r as PowerLawFitResult.Failure).reason

    // MARK: - No-shortening guard

    @Test
    fun guardAcceptsPowerLawThatNeverShortens() {
        val ok = CustomFilmFormulaGuard.UsableRangeInput(
            exponent = 1.33, referenceMeteredTimeSeconds = 1.0, coefficientSeconds = 1.0,
            offsetSeconds = 0.0, noCorrectionThroughSeconds = 1.0, sourceRangeThroughSeconds = null,
        )
        assertTrue(CustomFilmFormulaGuard.passesUsableRangeCheck(ok))
    }

    @Test
    fun guardRejectsShorteningFormulas() {
        val linearShorten = CustomFilmFormulaGuard.UsableRangeInput(
            exponent = 1.0, referenceMeteredTimeSeconds = 1.0, coefficientSeconds = 0.5,
            offsetSeconds = 0.0, noCorrectionThroughSeconds = 0.0, sourceRangeThroughSeconds = null,
        )
        assertTrue(!CustomFilmFormulaGuard.passesUsableRangeCheck(linearShorten))

        val concaveUnlimited = CustomFilmFormulaGuard.UsableRangeInput(
            exponent = 0.8, referenceMeteredTimeSeconds = 1.0, coefficientSeconds = 1.0,
            offsetSeconds = 0.0, noCorrectionThroughSeconds = 1.0, sourceRangeThroughSeconds = null,
        )
        assertTrue(!CustomFilmFormulaGuard.passesUsableRangeCheck(concaveUnlimited))
    }

    // MARK: - Duration parser

    @Test
    fun durationParserHandlesAcceptedShapes() {
        assertEquals(CustomFilmDurationParser.ParsedDuration.Empty, CustomFilmDurationParser.parse("  "))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Unlimited, CustomFilmDurationParser.parse("Unlimited"))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Seconds(100.0), CustomFilmDurationParser.parse("100"))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Seconds(100.0), CustomFilmDurationParser.parse("100s"))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Seconds(300.0), CustomFilmDurationParser.parse("5m"))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Seconds(3600.0), CustomFilmDurationParser.parse("1h"))
        assertEquals(null, CustomFilmDurationParser.parse("abc"))
    }

    // MARK: - No-correction boundary

    @Test
    fun noCorrectionBoundaryAppliesTenPercentTolerance() {
        assertTrue(ReciprocityNoCorrectionBoundary.isWithinNoCorrection(0.55, 0.5))
        assertTrue(!ReciprocityNoCorrectionBoundary.isWithinNoCorrection(0.56, 0.5))
    }
}
