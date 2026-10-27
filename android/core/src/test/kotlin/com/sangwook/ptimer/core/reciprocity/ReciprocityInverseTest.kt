// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import org.junit.Assert.*
import org.junit.Test

class ReciprocityInverseTest {
    private val inverse = ReciprocityInverse()
    private fun formula(a: Double = 1.0, p: Double = 2.0, threshold: Double = 1.0) = ReciprocityProfile(
        id = "custom", name = "Custom", source = ReciprocitySourceProvenance(ReciprocitySourceKind.userDefined, ReciprocityAuthority.userDefined, publisher = "Custom"),
        rules = listOf(ReciprocityRule(kind = ReciprocityRuleKind.formula, formula = FormulaReciprocityRule(ReciprocityFormula(FormulaFamily.modifiedSchwarzschild, coefficientSeconds = a, exponent = p, noCorrectionThroughSeconds = threshold, sourceRangeThroughSeconds = 10.0)))),
    )

    @Test fun formulaGapMultipleFlatAndContinuation() {
        assertEquals(ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.noQuantifiedSolution), inverse.evaluate(formula(2.0), 1.5))
        assertEquals(ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.multipleSolutions), inverse.evaluate(formula(10.0, -1.0), 5.0))
        assertEquals(ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.multipleSolutions), inverse.evaluate(formula(5.0, 0.0), 5.0))
        assertEquals(ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.multipleSolutions), inverse.evaluate(formula(1.0, 0.0), 1.0))
        val result = inverse.evaluate(formula(), 400.0) as ReciprocityInverseResult.Available
        assertEquals(20.0, result.meteredSeconds, 1e-10)
        assertEquals(ReciprocityCalculationRangeStatus.beyondPolicyLimit, result.evaluation.metadata.rangeStatus)
    }

    @Test fun knownForwardPointsHaveVerifiedUniqueOrMultipleInverses() {
        val evaluator = ReciprocityCalculationPolicyEvaluator()
        for (film in LaunchPresetFilmCatalogV2.films) {
            for (profile in film.profiles + AlternateReciprocityModels.alternates(film.id)) {
                for (metered in listOf(0.01, 0.1, 1.0, 10.0, 120.0, 1000.0)) {
                    val target = evaluator.evaluate(profile, metered).calculatedCorrectedSeconds ?: continue
                    val result = inverse.evaluate(profile, target)
                    if (result is ReciprocityInverseResult.Available) {
                        assertTrue(result.meteredSeconds > 0 && result.meteredSeconds.isFinite())
                        assertEquals(result.evaluation, evaluator.evaluate(profile, result.meteredSeconds))
                        assertEquals(target, result.evaluation.calculatedCorrectedSeconds!!, maxOf(1e-9, target * 1e-10))
                    } else assertEquals("${profile.id} M=$metered T=$target", ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.multipleSolutions), result)
                }
            }
        }
    }

    @Test fun actualAcrosGapIsNotSilentlyInterpolated() {
        val acros = LaunchPresetFilmCatalogV2.films.first { it.canonicalStockName == "Acros II" }.profiles.first()
        assertEquals(ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.noQuantifiedSolution), inverse.evaluate(acros, 150.0))
        val identity = inverse.evaluate(acros, 119.999999) as ReciprocityInverseResult.Available
        assertEquals(119.999999, identity.meteredSeconds, 1e-12)
    }
    @Test fun unresolvedAdditionalRootIsNumericalFailureDespiteIdentityHandoff() {
        val profile = formula(1e-300, -0.001, threshold = 0.0)
        assertEquals(ReciprocityInverseResult.Unavailable(ReciprocityInverseFailure.numericalFailure), inverse.evaluate(profile, 1e300))
    }

}
