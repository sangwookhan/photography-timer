// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.reciprocity.*
import kotlin.math.pow
import org.junit.Assert.*
import org.junit.Test

class RequiredNDEvaluatorTest {
    private val inverse = RequiredNDEvaluator()
    private val forward = ReciprocityCalculationPolicyEvaluator()
    private val source = ReciprocitySourceProvenance(ReciprocitySourceKind.userDefined,
        ReciprocityAuthority.userDefined, publisher = "Test")
    private fun profile(rule: ReciprocityRule) = ReciprocityProfile("test", "Test", source, listOf(rule))
    private fun formula(exponent: Double = 1.31) = profile(ReciprocityRule(ReciprocityRuleKind.formula,
        formula = FormulaReciprocityRule(ReciprocityFormula(formulaFamily = FormulaFamily.modifiedSchwarzschild, exponent = exponent,
            noCorrectionThroughSeconds = 0.5, sourceRangeThroughSeconds = 100.0))))
    private fun value(base: Double, target: Double, profile: ReciprocityProfile? = null) =
        inverse.evaluate(base, target, profile) as RequiredNDResult.Value

    @Test fun exactForwardMatchDoesNotBecomeNegativeFromInverseRoundoff() {
        val profile = formula(2.0)
        assertEquals(64.0, forward.evaluate(profile, 8.0).calculatedCorrectedSeconds!!, 0.0)
        assertEquals(RequiredNDResult.Value(0.0, false), inverse.evaluate(8.0, 64.0, profile))
        assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.NegativeAttenuation), inverse.evaluate(9.0, 64.0, profile))
    }

    @Test fun constantFormulaBoundaryUsesRealForwardToleranceBeforeClaimingUniqueness() {
        fun constant(boundary: Double) = profile(ReciprocityRule(ReciprocityRuleKind.formula,
            formula = FormulaReciprocityRule(ReciprocityFormula(formulaFamily = FormulaFamily.modifiedSchwarzschild, coefficientSeconds = 1.0,
                referenceMeteredTimeSeconds = 1.0, exponent = 0.0, offsetSeconds = 0.0,
                noCorrectionThroughSeconds = boundary))))
        for (boundary in listOf(1.0, 1.0000008)) {
            val p = constant(boundary)
            val secondRoot = boundary + (1.000001 - boundary) / 2
            assertEquals(1.0, forward.evaluate(p, 1.0).calculatedCorrectedSeconds!!, 0.0)
            assertEquals(1.0, forward.evaluate(p, secondRoot).calculatedCorrectedSeconds!!, 0.0)
            assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.MultipleSolutions), inverse.evaluate(1.0, 1.0, p))
        }
        // No formula segment survives beyond this identity boundary.
        assertEquals(RequiredNDResult.Value(0.0, false), inverse.evaluate(1.0, 1.0, constant(1.000002)))
    }

    @Test fun digitalExamplesAndUnboundedTotal() {
        assertEquals(10.0, value(1.0, 1024.0).stops, 1e-10)
        assertEquals(10.3, value(1.0, 2.0.pow(10.3)).stops, 1e-10)
        assertTrue(value(java.lang.Double.MIN_NORMAL, Double.MAX_VALUE).stops > 2000)
        assertEquals(40.0, value(1.0, 2.0.pow(40)).stops, 1e-10)
    }

    @Test fun selectedHp5ProfileIsIndependentlyForwardVerified() {
        val hp5 = LaunchPresetFilmCatalogV2.films.first { it.id == "ilford-hp5-plus-400" }.profiles.first()
        val target = forward.evaluate(hp5, 1024.0).calculatedCorrectedSeconds!!
        val required = value(1.0, target, hp5)
        assertEquals(10.0, required.stops, 1e-9)
        assertEquals(target, forward.evaluate(hp5, 2.0.pow(required.stops)).calculatedCorrectedSeconds!!, target * 1e-10)
    }

    @Test fun noCorrectionBoundaryAndSourceContinuationStayDistinct() {
        val p = formula()
        assertEquals(1.0, value(0.25, 0.5, p).stops, 1e-10)
        val target = forward.evaluate(p, 256.0).calculatedCorrectedSeconds!!
        val result = value(1.0, target, p)
        assertEquals(8.0, result.stops, 1e-9)
        assertTrue(result.beyondSourceRange)
        assertEquals(target, forward.evaluate(p, 2.0.pow(result.stops)).calculatedCorrectedSeconds!!, target * 1e-10)
    }

    @Test fun tableInterpolationContinuationAndPlateau() {
        fun table(anchors: List<TableAnchor>) = profile(ReciprocityRule(ReciprocityRuleKind.tableInterpolation,
            tableInterpolation = TableInterpolationReciprocityRule(anchors, noCorrectionThroughSeconds = 0.5,
                sourceRangeThroughSeconds = anchors.last().meteredSeconds)))
        val p = table(listOf(TableAnchor(1.0, 2.0), TableAnchor(4.0, 8.0), TableAnchor(16.0, 128.0)))
        for (metered in listOf(1.0, 2.0, 4.0, 32.0)) {
            val target = forward.evaluate(p, metered).calculatedCorrectedSeconds!!
            val result = value(1.0, target, p)
            assertEquals(target, forward.evaluate(p, 2.0.pow(result.stops)).calculatedCorrectedSeconds!!, target * 1e-9)
            assertEquals(metered > 16, result.beyondSourceRange)
        }
        val plateau = table(listOf(TableAnchor(1.0, 4.0), TableAnchor(2.0, 4.0), TableAnchor(4.0, 16.0)))
        assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.MultipleSolutions), inverse.evaluate(1.0, 4.0, plateau))
    }

    @Test fun unavailableInvalidNegativeAndNumericalReasonsAreDistinct() {
        val limited = profile(ReciprocityRule(ReciprocityRuleKind.limitedGuidance,
            limitedGuidance = LimitedGuidanceReciprocityRule()))
        assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.NoQuantifiedInverse), inverse.evaluate(1.0, 20.0, limited))
        assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.InvalidInput), inverse.evaluate(0.0, 20.0, null))
        assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.NegativeAttenuation), inverse.evaluate(1.0, 0.5, null))
        assertEquals(RequiredNDResult.Unavailable(RequiredNDResult.Reason.NumericalFailure), inverse.evaluate(1.0, 20.0, formula(Double.NaN)))
    }
}
