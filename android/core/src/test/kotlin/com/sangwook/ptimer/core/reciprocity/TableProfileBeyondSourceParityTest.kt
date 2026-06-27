// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Locks the beyond-source-range behavior of the real bundled table-profile
 * films against the iOS oracle (see iOS `TableLogLogReciprocityContractTests`):
 * past the published source range, a table profile must still produce an
 * extrapolated value classified "outside guidance" — never a value-less
 * unsupported. The synthetic-table cases live in [ReciprocityPolicyTest];
 * this exercises the actual catalog films so a catalog/policy regression that
 * silently stopped computing out-of-range would fail here.
 */
class TableProfileBeyondSourceParityTest {

    private val films = LaunchPresetFilmCatalogLoader().loadBundledCatalog()
    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    @Test
    fun everyBundledTableFilmExtrapolatesBeyondSourceRange() {
        val tableFilms = films.mapNotNull { f ->
            val profile = f.profiles.first()
            val rule = profile.rules.firstNotNullOfOrNull { it.tableInterpolation }
            rule?.let { Triple(f.canonicalStockName, profile, it) }
        }
        assertTrue("catalog must ship at least one table-profile film", tableFilms.isNotEmpty())

        for ((name, profile, rule) in tableFilms) {
            val beyondSourceSeconds = rule.sourceRangeThroughSeconds * 3.0
            val result = evaluator.evaluate(profile, beyondSourceSeconds)
            assertTrue(
                "$name @ ${beyondSourceSeconds}s must be Unsupported (beyond source range)",
                result is ReciprocityResult.Unsupported,
            )
            val corrected = (result as ReciprocityResult.Unsupported).correctedExposureSeconds
            assertNotNull("$name: beyond-source must still carry an extrapolated value", corrected)
            assertTrue(
                "$name: extrapolated value must be finite and not shorten the exposure",
                corrected!!.isFinite() && corrected >= beyondSourceSeconds,
            )
        }
    }

    @Test
    fun tmax100BeyondSourceLocksExtrapolatedValue() {
        // T-MAX 100 official table: anchors 1->1.26, 10->15, 100->200; source
        // range 100 s. At 300 s (3x past the range) the last published segment
        // (10->15, 100->200) is extrapolated in log-log space to ~688 s.
        val tmax = films.first { it.canonicalStockName == "T-MAX 100" }
        val result = evaluator.evaluate(tmax.profiles.first(), 300.0)

        assertTrue(result is ReciprocityResult.Unsupported)
        val corrected = (result as ReciprocityResult.Unsupported).correctedExposureSeconds!!
        assertEquals(688.2, corrected, 1.0)

        val confidence = result.confidencePresentation
        assertEquals("Outside guidance", confidence.shortLabel)
        assertTrue(confidence.returnsCalculatedExposureTime)
    }
}
