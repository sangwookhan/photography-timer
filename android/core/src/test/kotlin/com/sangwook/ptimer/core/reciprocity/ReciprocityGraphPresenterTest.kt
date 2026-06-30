// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocityGraphPresenterTest {

    private val films = LaunchPresetFilmCatalogV2.films
    private fun film(id: String) = films.first { it.id == id }

    @Test
    fun formulaFilmProducesACurveWithBandsAndCurrentMarker() {
        val profile = film("ilford-pan-f-plus-50").profiles.first()
        val graph = ReciprocityGraphPresenter.make(profile, 30.0)
        assertNotNull(graph)
        assertTrue(graph!!.curve.size >= 2)
        // Normalized points stay within [0,1].
        assertTrue(graph.curve.all { it.x in 0.0..1.0 && it.y in 0.0..1.0 })
        assertNotNull(graph.current)
        assertNotNull(graph.noCorrectionFraction)
    }

    @Test
    fun tableFilmExposesAnchorDots() {
        val tmax = films.first { it.id.contains("t-max") || it.canonicalStockName.contains("T-MAX") }
        val profile = tmax.profiles.first()
        val graph = ReciprocityGraphPresenter.make(profile, 30.0)
        assertNotNull(graph)
        assertTrue(graph!!.anchors.isNotEmpty())
    }

    @Test
    fun steepUnlimitedFormulaKeepsTheYAxisUnderADay() {
        // A steep p over an unlimited source used to blow the Y axis out to
        // multi-day ticks; the axis is now capped at 1 day.
        val profile = ReciprocityProfile(
            id = "p", name = "n",
            source = ReciprocitySourceProvenance(
                kind = ReciprocitySourceKind.userDefined,
                authority = ReciprocityAuthority.userDefined,
                publisher = "me",
            ),
            rules = listOf(
                ReciprocityRule(
                    kind = ReciprocityRuleKind.formula,
                    formula = FormulaReciprocityRule(
                        formula = ReciprocityFormula(
                            formulaFamily = FormulaFamily.modifiedSchwarzschild,
                            exponent = 1.9,
                            noCorrectionThroughSeconds = 1.0,
                            sourceRangeThroughSeconds = null,
                        ),
                    ),
                ),
            ),
        )
        val graph = ReciprocityGraphPresenter.make(profile, 30.0)!!
        assertTrue(graph.yTicks.none { it.label.endsWith("d") })
        assertTrue(graph.curve.all { it.y in 0.0..1.0 })
    }

    @Test
    fun formulaFilmPlotsSourceEvidenceMarkersAndNotRecommendedBoundary() {
        // Velvia 50 is formula-based (no table anchors) but publishes source
        // evidence + a 64s not-recommended boundary, so it should plot reference
        // markers and a boundary marker (iOS parity).
        val velvia = films.first { it.canonicalStockName.contains("Velvia 50") }
        val graph = ReciprocityGraphPresenter.make(velvia.profiles.first(), 30.0)!!
        assertTrue(graph.anchors.isEmpty())
        assertTrue(graph.referenceMarkers.isNotEmpty())
        assertNotNull(graph.notRecommendedBoundaryFraction)
    }

    @Test
    fun axisTicksUseRoundDurationLabels() {
        val graph = ReciprocityGraphPresenter.make(film("ilford-pan-f-plus-50").profiles.first(), 30.0)!!
        val allowed = setOf("1/10s", "1s", "10s", "1m", "10m", "1h", "10h", "100h")
        val labels = (graph.xTicks + graph.yTicks).map { it.label }
        assertTrue(labels.isNotEmpty())
        assertTrue(labels.all { it in allowed })
        // No decade-rounded labels like "17m" / "2m" / "3h".
        assertTrue(labels.none { it == "17m" || it == "2m" || it == "3h" })
    }

    @Test
    fun limitedGuidanceFilmHasNoGraph() {
        // A threshold/limited-guidance profile (no formula or table rule) → null.
        val limited = films.firstOrNull { f ->
            f.profiles.first().rules.none { it.formula != null || it.tableInterpolation != null }
        }
        if (limited != null) {
            assertNull(ReciprocityGraphPresenter.make(limited.profiles.first(), 30.0))
        }
    }
}
