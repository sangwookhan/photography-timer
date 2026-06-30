// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.calc

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.exposure.ExposureScale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShootingCalculatorTest {

    private val calc = ShootingCalculator()
    private val films = LaunchPresetFilmCatalogV2.films
    private val oneSecIndex = ExposureScale.oneThirdStopShutterCameraLabels.indexOf("1s")

    @Test
    fun digitalYieldsAdjustedShutterAndEnablesStart() {
        // 1 s + 0 ND, no film → adjusted = 1 s, startable.
        val r = calc.result(shutterIndex = oneSecIndex, ndStops = 0, profile = null)
        assertTrue(r.isDigital)
        assertEquals(1.0, r.adjustedShutterSeconds, 1e-9)
        assertTrue(r.startEnabled)
        assertEquals(1.0, r.startDurationSeconds!!, 1e-9)
        assertNull(r.correctedSeconds)
    }

    @Test
    fun ndExtendsTheAdjustedShutter() {
        // 1 s + 6 ND (one-third-stop scale, no snap) → 64 s.
        val r = calc.result(shutterIndex = oneSecIndex, ndStops = 6, profile = null)
        assertEquals(64.0, r.adjustedShutterSeconds, 1e-6)
    }

    @Test
    fun formulaFilmYieldsCorrectedExposureAndEnablesStart() {
        val panF = films.first { it.id == "ilford-pan-f-plus-50" }.profiles.first()
        // 6 ND → 64 s metered → corrected (formula) > 64 s, quantified → startable.
        val r = calc.result(shutterIndex = oneSecIndex, ndStops = 6, profile = panF)
        assertFalse(r.isDigital)
        assertNotNull(r.correctedSeconds)
        assertTrue(r.correctedSeconds!! > 64.0)
        assertTrue(r.startEnabled)
        assertEquals(r.correctedSeconds!!, r.startDurationSeconds!!, 1e-9)
    }

    @Test
    fun limitedGuidanceFilmBlocksStartWithHint() {
        // A limited-guidance film (Kodak Portra/Ektar/Ektachrome) past its
        // threshold produces no quantified prediction → Start disabled + hint.
        val limited = films.first { film ->
            film.profiles.first().rules.any {
                it.kind == com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind.limitedGuidance
            }
        }.profiles.first()
        val r = calc.result(shutterIndex = oneSecIndex, ndStops = 8, profile = limited)
        assertFalse(r.startEnabled)
        assertNull(r.startDurationSeconds)
        assertNotNull(r.hint)
    }
}
