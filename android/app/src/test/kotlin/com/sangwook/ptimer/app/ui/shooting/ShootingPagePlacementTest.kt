// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Arrangement and compact-timer placement rules (SHELL-059, WORKSPACE-032).
 * The needed heights are the measured busy-page values: a film with a
 * model choice, Target Shutter on, two ND wheels plus auxiliary filters and
 * three result rows need 606dp stacked and 436dp side by side.
 */
class ShootingPagePlacementTest {
    private val busy = ShootingContentHeights(singleColumn = 606.dp, sideBySide = 436.dp)
    private val strip = 128.dp

    @Test
    fun singleColumnWhenTheStackFits() {
        assertEquals(ShootingArrangement.SingleColumn, chooseShootingArrangement(411.dp, 725.dp, busy))
        assertEquals(ShootingArrangement.SingleColumn, chooseShootingArrangement(704.dp, 780.dp, busy))
    }

    @Test
    fun sideBySideWhenTheStackDoesNotFitAndTwoColumnsDo() {
        assertEquals(ShootingArrangement.SideBySide, chooseShootingArrangement(933.dp, 500.dp, busy))
        assertTrue(shootingContentFits(ShootingArrangement.SideBySide, 500.dp, busy))
    }

    @Test
    fun narrowWindowsStayInOneColumnEvenWhenItOverflows() {
        // 703dp leaves 671dp of content, short of two 328dp columns and the gap.
        assertEquals(ShootingArrangement.SingleColumn, chooseShootingArrangement(703.dp, 500.dp, busy))
        assertFalse(shootingContentFits(ShootingArrangement.SingleColumn, 500.dp, busy))
    }

    @Test
    fun phoneKeepsTheBottomStrip() {
        assertFalse(prefersSideRail(PageSpace(411.dp, 725.dp), null, busy, strip))
    }

    @Test
    fun railIsTriedWhenTheEstimateFits() {
        // Only the bottom room is known: the rail estimate (363 x 653) fits.
        assertTrue(prefersSideRail(PageSpace(475.dp, 525.dp), null, busy, strip))
    }

    @Test
    fun aMeasuredRailThatDoesNotFitIsNotKept() {
        // Measured with the rail the page got 363 x 587, short of 606:
        // back to the bottom strip, and it stays there for this window.
        assertFalse(prefersSideRail(PageSpace(475.dp, 525.dp), PageSpace(363.dp, 587.dp), busy, strip))
    }

    @Test
    fun aMeasuredRailThatFitsIsKept() {
        assertTrue(prefersSideRail(PageSpace(475.dp, 525.dp), PageSpace(363.dp, 640.dp), busy, strip))
        // Measured with the rail only: the bottom estimate (475 x 512) does not fit.
        assertTrue(prefersSideRail(null, PageSpace(363.dp, 640.dp), busy, strip))
    }

    @Test
    fun shortWideWindowUsesTheRailOnlyWhenThatMakesItFit() {
        // 1000 x 376 above the strip: side by side still needs 436.
        assertTrue(prefersSideRail(PageSpace(1000.dp, 376.dp), null, busy, strip))
        // Plenty of room: bottom strip.
        assertFalse(prefersSideRail(PageSpace(1240.dp, 616.dp), null, busy, strip))
    }

    @Test
    fun noRailWhenItWouldLeaveNoReadableColumn() {
        // 360 x 496: the rail would leave 248dp, below one readable column.
        assertFalse(prefersSideRail(PageSpace(360.dp, 496.dp), null, busy, strip))
    }

    @Test
    fun noRailWhenItStillWouldNotFit() {
        assertFalse(prefersSideRail(PageSpace(562.dp, 284.dp), null, busy, strip))
    }
}
