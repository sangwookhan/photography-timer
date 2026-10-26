// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FilmClassificationBadgeVisibilityTest {
    @Test
    fun repeatedQualifyingEventMakesEarlierHideStale() {
        val first = FilmClassificationBadgeVisibility().reveal(isActiveFilm = true)
        val second = first.reveal(isActiveFilm = true)

        assertTrue(second.isVisible)
        assertTrue(second.generation > first.generation)
        assertEquals(second, second.hide(ifGeneration = first.generation))
        assertFalse(second.hide(ifGeneration = second.generation).isVisible)
    }

    @Test
    fun digitalOrInactivePageClearsAndInvalidatesPreviousHide() {
        val pendingHide = FilmClassificationBadgeVisibility().reveal(isActiveFilm = true)
        val cleared = pendingHide.reveal(isActiveFilm = false)

        assertFalse(cleared.isVisible)
        assertEquals(cleared, cleared.hide(ifGeneration = pendingHide.generation))
    }

    @Test
    fun displayWindowIsThreeSecondsBeforeTheFade() {
        assertEquals(3_000L, FilmClassificationBadgeVisibility.DISPLAY_DURATION_MILLIS)
        val visibility = FilmClassificationBadgeVisibility()
        assertFalse(visibility.shouldBeginFade(2_999L))
        assertTrue(visibility.shouldBeginFade(3_000L))
        assertTrue(visibility.shouldBeginFade(3_001L))
    }

    @Test
    fun onlyCoveredToMainTransitionCountsAsReturn() {
        assertTrue(FilmClassificationBadgeVisibility.isMainReturn(wasCovered = true, isCovered = false))
        assertFalse(FilmClassificationBadgeVisibility.isMainReturn(wasCovered = false, isCovered = false))
        assertFalse(FilmClassificationBadgeVisibility.isMainReturn(wasCovered = true, isCovered = true))
    }
}
