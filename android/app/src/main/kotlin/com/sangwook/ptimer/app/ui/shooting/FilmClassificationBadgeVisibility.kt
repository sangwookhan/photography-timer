// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

internal data class FilmClassificationBadgeVisibility(
    val generation: Int = 0,
    val isVisible: Boolean = false,
) {
    fun reveal(isActiveFilm: Boolean): FilmClassificationBadgeVisibility =
        copy(generation = generation + 1, isVisible = isActiveFilm)

    fun hide(ifGeneration: Int): FilmClassificationBadgeVisibility =
        if (generation == ifGeneration) copy(isVisible = false) else this

    fun shouldBeginFade(elapsedMillis: Long): Boolean =
        elapsedMillis >= DISPLAY_DURATION_MILLIS

    companion object {
        const val DISPLAY_DURATION_MILLIS = 3_000L

        fun isMainReturn(wasCovered: Boolean, isCovered: Boolean): Boolean =
            wasCovered && !isCovered
    }
}
