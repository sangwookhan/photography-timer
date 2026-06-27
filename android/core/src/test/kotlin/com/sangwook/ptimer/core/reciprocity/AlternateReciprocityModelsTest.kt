// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlternateReciprocityModelsTest {

    private val evaluator = ReciprocityCalculationPolicyEvaluator()

    @Test
    fun filmsWithoutAlternatesReturnEmpty() {
        assertTrue(AlternateReciprocityModels.alternates("ilford-hp5-plus-400").isEmpty())
    }

    @Test
    fun fomapanExposesOhzartThenAppFormula() {
        val ids = AlternateReciprocityModels.alternates("foma-fomapan-100").map { it.id }
        assertEquals(
            listOf("foma-fomapan-100-ohzart-community-table", "foma-fomapan-100-app-formula"),
            ids,
        )
    }

    @Test
    fun triX400PickerOrderLeadsWithOfficialTableThenPrimary() {
        val primary = ReciprocityProfile(
            id = "kodak-tri-x-graph-table",
            name = "Graph table",
            source = ReciprocitySourceProvenance(
                kind = ReciprocitySourceKind.manufacturerPublished,
                authority = ReciprocityAuthority.official,
                publisher = "Kodak",
            ),
            rules = listOf(
                ReciprocityRule(
                    kind = ReciprocityRuleKind.tableInterpolation,
                    tableInterpolation = TableInterpolationReciprocityRule(
                        anchors = listOf(TableAnchor(1.0, 2.0), TableAnchor(100.0, 1200.0)),
                        noCorrectionThroughSeconds = 0.1,
                        sourceRangeThroughSeconds = 100.0,
                    ),
                ),
            ),
        )
        val order = AlternateReciprocityModels.modelPickerOrder(primary, "kodak-tri-x-400").map { it.id }
        assertEquals(
            listOf("kodak-tri-x-official-table", "kodak-tri-x-graph-table", "kodak-tri-x-app-formula"),
            order,
        )
    }

    @Test
    fun appDerivedModelsAreFlagged() {
        assertTrue(AlternateReciprocityModels.isAppDerivedModel("kodak-tmax-100-app-formula"))
        assertTrue(AlternateReciprocityModels.isAppDerivedModel("foma-fomapan-100-app-formula"))
        assertFalse(AlternateReciprocityModels.isAppDerivedModel("foma-fomapan-100-ohzart-community-table"))
    }

    @Test
    fun profileResolvesById() {
        assertEquals(
            "Ohzart community table",
            AlternateReciprocityModels.profile("foma-fomapan-100-ohzart-community-table")?.name,
        )
        assertNull(AlternateReciprocityModels.profile("nope"))
    }

    @Test
    fun ohzartTableReproducesPublishedAnchors() {
        val ohzart = AlternateReciprocityModels.fomapan100OhzartCommunityTable
        val r = evaluator.evaluate(ohzart, 15.0)
        assertTrue(r is ReciprocityResult.Quantified)
        assertEquals(90.0, (r as ReciprocityResult.Quantified).correctedExposureSeconds, 1e-6)
        // Unofficial source → table-derived label carries the "Secondary" prefix.
        assertEquals("Secondary table", r.confidencePresentation.shortLabel)
    }

    @Test
    fun portraUnofficialProfileIsResolvable() {
        val portra = UnofficialPracticalProfiles.profile("kodak-portra-400")
        assertEquals("kodak-portra-400-unofficial-practical", portra?.id)
        // Tc = Tm^1.34 above the ~1 s boundary.
        val r = evaluator.evaluate(portra!!, 10.0)
        assertTrue(r is ReciprocityResult.Quantified)
    }
}
