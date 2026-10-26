// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.persistence.CustomFilmLibraryCodec
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import com.sangwook.ptimer.core.persistence.PersistenceLoadOutcome
import com.sangwook.ptimer.core.reciprocity.FilmColor
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmPolarity
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class FilmClassificationTest {
    @Test fun fourCombinationsRoundTripWithoutChangingOtherData() {
        for (table in listOf(false, true)) {
            for (polarity in FilmPolarity.entries) for (color in FilmColor.entries) {
                val film = film(table).copy(polarity = polarity, color = color)
                val encoded = CustomFilmLibraryCodec.encode(PersistentCustomFilmLibrarySnapshot(listOf(film)))
                assertEquals(listOf(film), CustomFilmLibraryCodec.decode(encoded)!!.films)
                assertEquals(color, film.copy(polarity = FilmPolarity.negative).color)
                assertEquals(polarity, film.copy(color = FilmColor.blackAndWhite).polarity)
            }
        }
    }

    @Test fun legacyFallbacksAreIndependentAndPreserveTheEntireRecord() {
        for (table in listOf(false, true)) {
            val film = film(table).copy(polarity = FilmPolarity.positive, color = FilmColor.color)
            val encoded = CustomFilmLibraryCodec.encode(PersistentCustomFilmLibrarySnapshot(listOf(film)))
            val root = Json.parseToJsonElement(encoded).jsonObject
            val record = root.getValue("films").jsonArray.single().jsonObject
            for (missing in listOf(setOf("polarity"), setOf("color"), setOf("polarity", "color"))) {
                val legacy = JsonObject(root + ("films" to JsonArray(listOf(JsonObject(record - missing)))))
                val result = CustomFilmLibraryCodec.decodeWithDiagnostics(legacy.toString())
                assertEquals(PersistenceLoadOutcome.loaded, result.outcome)
                val expected = film.copy(
                    polarity = if ("polarity" in missing) FilmPolarity.negative else FilmPolarity.positive,
                    color = if ("color" in missing) FilmColor.blackAndWhite else FilmColor.color,
                )
                assertEquals(listOf(expected), result.snapshot.films)
                assertEquals(result.snapshot, CustomFilmLibraryCodec.decode(CustomFilmLibraryCodec.encode(result.snapshot)))
            }
        }
    }

    @Test fun unknownOrNullClassificationIsIsolatedRatherThanDefaulted() {
        val good = film(false)
        val root = Json.parseToJsonElement(CustomFilmLibraryCodec.encode(PersistentCustomFilmLibrarySnapshot(listOf(good)))).jsonObject
        val record = root.getValue("films").jsonArray.single().jsonObject
        for (key in listOf("polarity", "color")) for (bad in listOf(JsonPrimitive("future"), JsonNull)) {
            val corrupt = JsonObject(record + ("id" to JsonPrimitive("bad")) + (key to bad))
            val result = CustomFilmLibraryCodec.decodeWithDiagnostics(
                JsonObject(root + ("films" to JsonArray(listOf(corrupt, record)))).toString(),
            )
            assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
            assertEquals(1, result.droppedRecordCount)
            assertEquals(listOf(good), result.snapshot.films)
        }
    }

    @Test fun formulaAndTableBuildersUseChosenValuesAndCustomDefaults() {
        for (table in listOf(false, true)) {
            val default = film(table)
            assertEquals(FilmPolarity.negative, default.polarity)
            assertEquals(FilmColor.blackAndWhite, default.color)
        }
        val input = CustomFormulaFilmInput("Film", "Profile", 100, 1.0, 1.0, 1.3,
            noCorrectionThroughSeconds = 1.0, polarity = FilmPolarity.positive, color = FilmColor.color)
        val saved = CustomFilmBuilder.buildFormulaFilm(input, "id", "profile")!!
        assertEquals(FilmPolarity.positive, saved.polarity)
        assertEquals(FilmColor.color, saved.color)
        val table = CustomTableFilmInput("Film", "Profile", 100, listOf(1.0 to 2.0, 10.0 to 40.0), 0.5,
            polarity = FilmPolarity.positive, color = FilmColor.color)
        val savedTable = CustomFilmBuilder.buildTableFilm(table, "id", "profile")!!
        assertEquals(FilmPolarity.positive, savedTable.polarity)
        assertEquals(FilmColor.color, savedTable.color)
    }

    private fun film(table: Boolean): FilmIdentity = if (table) {
        CustomFilmBuilder.buildTableFilm(CustomTableFilmInput(
            "Film", "Profile", 100, listOf(1.0 to 2.0, 10.0 to 40.0), 0.5,
            manufacturer = "Acme", notes = "Keep notes", referenceUrl = "https://example.com/source",
        ), "film", "profile")!!
    } else {
        CustomFilmBuilder.buildFormulaFilm(CustomFormulaFilmInput(
            "Film", "Profile", 100, 1.0, 1.0, 1.3, noCorrectionThroughSeconds = 1.0,
            manufacturer = "Acme", notes = "Keep notes", referenceUrl = "https://example.com/source",
            referenceTableFilmId = "reference",
        ), "film", "profile")!!
    }
}
