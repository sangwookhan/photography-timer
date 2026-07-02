// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.target

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TargetShutterPresenterTest {

    @Test
    fun nullTargetIsInactive() {
        val s = TargetShutterPresenter.makeDisplayState(null, TargetShutterPresenter.ComparisonSource.AdjustedShutter(1.0))
        assertEquals(TargetShutterDisplayState.Unavailable(TargetShutterUnavailableReason.inactive), s)
    }

    @Test
    fun equalTargetAndComparisonIsAMatch() {
        val s = TargetShutterPresenter.makeDisplayState(8.0, TargetShutterPresenter.ComparisonSource.CorrectedExposure(8.0))
        val available = s as TargetShutterDisplayState.Available
        assertEquals(TargetShutterStopDifferenceKind.match, available.state.stopDifference!!.kind)
        assertEquals("0 stops", available.state.stopDifference!!.formattedText)
        assertEquals("Corrected Exposure", available.state.comparison!!.label)
    }

    @Test
    fun targetOneStopLongerIsPositive() {
        val s = TargetShutterPresenter.makeDisplayState(16.0, TargetShutterPresenter.ComparisonSource.AdjustedShutter(8.0))
        val diff = (s as TargetShutterDisplayState.Available).state.stopDifference!!
        assertEquals(TargetShutterStopDifferenceKind.longerThanComparison, diff.kind)
        assertEquals("+1 stops", diff.formattedText)
    }

    @Test
    fun targetTwoThirdsShorterUsesAsciiSignAndFraction() {
        // 2/3 stop shorter → factor 2^(-2/3) ≈ 0.62996
        val s = TargetShutterPresenter.makeDisplayState(0.62996 * 8.0, TargetShutterPresenter.ComparisonSource.AdjustedShutter(8.0))
        val diff = (s as TargetShutterDisplayState.Available).state.stopDifference!!
        assertEquals(TargetShutterStopDifferenceKind.shorterThanComparison, diff.kind)
        assertEquals("-2/3 stop", diff.formattedText)
    }

    @Test
    fun unavailableComparisonKeepsTargetButNoStopDifference() {
        val s = TargetShutterPresenter.makeDisplayState(4.0, TargetShutterPresenter.ComparisonSource.Unavailable)
        val available = s as TargetShutterDisplayState.Available
        assertEquals(4.0, available.state.targetSeconds, 0.0)
        assertNull(available.state.comparison)
        assertNull(available.state.stopDifference)
    }

    @Test
    fun nonFiniteStopsFormatsAsMatch() {
        val diff = TargetShutterPresenter.formatStopDifference(Double.NaN)
        assertEquals(TargetShutterStopDifferenceKind.match, diff.kind)
        assertTrue(diff.formattedText == "0 stops")
    }

    // PTIMER-183: the display decomposition (signed magnitude + plurality)
    // must stay consistent with the canonical formattedText so the app layer
    // can attach a localized unit without changing the English rendering.

    @Test
    fun stopDifferenceDecompositionMatchesFormattedText() {
        val plural = TargetShutterPresenter.formatStopDifference(-(7.0 + 1.0 / 3.0))
        assertEquals("-7 1/3 stops", plural.formattedText)
        assertEquals("-7 1/3", plural.signedMagnitudeText)
        assertTrue(plural.isPluralStops)

        val singular = TargetShutterPresenter.formatStopDifference(2.0 / 3.0)
        assertEquals("+2/3 stop", singular.formattedText)
        assertEquals("+2/3", singular.signedMagnitudeText)
        assertTrue(!singular.isPluralStops)
    }

    @Test
    fun matchDecompositionIsZeroWithPluralUnit() {
        val match = TargetShutterPresenter.formatStopDifference(0.001)
        assertEquals("0 stops", match.formattedText)
        assertEquals("0", match.signedMagnitudeText)
        assertTrue(match.isPluralStops)
    }
}
