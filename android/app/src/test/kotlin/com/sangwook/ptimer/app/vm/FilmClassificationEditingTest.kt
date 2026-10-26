// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.reciprocity.FilmColor
import com.sangwook.ptimer.core.reciprocity.FilmPolarity
import org.junit.Assert.*
import org.junit.Test

class FilmClassificationEditingTest {
    @Test fun detailsStateCarriesClassificationAndISOForAllFourCombinations() {
        for (polarity in FilmPolarity.entries) for (color in FilmColor.entries) {
            val input = CustomTableFilmInput("Stock", "Profile", 400,
                listOf(1.0 to 1.0, 10.0 to 10.0), 0.5, polarity = polarity, color = color)
            val film = CustomFilmBuilder.buildTableFilm(input, "film", "profile")!!
            val controller = CalculatorController(films = listOf(film))
            controller.selectFilm(film.id)
            val details = controller.detailsState()!!
            assertEquals(polarity, details.filmPolarity)
            assertEquals(color, details.filmColor)
            assertEquals(400, details.filmISO)
        }
    }

    @Test fun classificationEditPreservesCameraSelectionCalculationAndCapturedIdentity() {
        val input = CustomTableFilmInput("Source", "Profile", 100, listOf(1.0 to 2.0, 10.0 to 40.0), 0.5)
        val film = CustomFilmBuilder.buildTableFilm(input, "film", "profile")!!
        val captured = mutableListOf<com.sangwook.ptimer.core.timer.TimerIdentity>()
        val controller = CalculatorController(films = listOf(film), onStart = { _, identity -> captured += identity })
        controller.selectFilm(film.id)
        val before = controller.state.value
        controller.start()
        val firstIdentity = captured.single()
        controller.setFilms(listOf(film.copy(polarity = FilmPolarity.positive, color = FilmColor.color)))
        val after = controller.state.value
        assertEquals(before.selectedFilmId, after.selectedFilmId)
        assertEquals(before.shutterIndex, after.shutterIndex)
        assertEquals(before.adjustedText, after.adjustedText)
        val selectedOption = after.filmOptions.single { it.id == film.id }
        assertEquals(FilmPolarity.positive, selectedOption.polarity)
        assertEquals(FilmColor.color, selectedOption.color)
        controller.start()
        assertEquals(firstIdentity, captured.last())
        assertEquals(firstIdentity, captured.first())
    }

    @Test fun tableFormulaSeedAndEditPrefillRetainIndependentClassifications() {
        for (polarity in FilmPolarity.entries) for (color in FilmColor.entries) {
            val input = CustomTableFilmInput("Source", "Profile", 100,
                listOf(1.0 to 2.0, 10.0 to 40.0), 0.5, polarity = polarity, color = color)
            val table = CustomFilmBuilder.buildTableFilm(input, "table", "table-profile")!!
            val formula = CustomFilmEditingPresenter.buildFormulaFilmFromTableInput(input, "formula", "formula-profile", table.id)!!
            assertEquals(polarity, formula.polarity)
            assertEquals(color, formula.color)
            for (film in listOf(table, formula)) {
                val draft = CustomFilmEditingPresenter.customFilmDraft(listOf(table, formula), film.id)!!
                assertEquals(polarity, draft.polarity)
                assertEquals(color, draft.color)
                assertEquals(film.id, draft.filmId)
            }
            val seed = CustomFilmEditingPresenter.creatingFormulaDraft(input, table.id, "draft")!!
            assertTrue(seed.isSeededFormulaCreate)
            assertEquals(polarity, seed.polarity)
            assertEquals(color, seed.color)
            assertEquals(table.id, seed.referenceTableFilmId)
            assertEquals(listOf(1.0 to 2.0, 10.0 to 40.0), seed.linkedTableAnchors)
            val edited = formula.copy(polarity = FilmPolarity.negative, color = FilmColor.blackAndWhite)
            assertEquals(color, table.color)
            assertEquals(polarity, table.polarity)
            assertEquals(formula.profiles, edited.profiles)
            assertEquals(table.id, edited.profiles.single().userMetadata!!.referenceTableFilmID)
        }
    }
}
