// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.catalog

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class FilmClassificationCatalogTest {
    @Test fun allFortyStocksMatchSourceEvidenceMapping() {
        val source = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
            .map { File(it, "shared/catalog/FilmClassificationSources.json") }.first { it.exists() }
        val rows = Json.parseToJsonElement(source.readText()).jsonObject.getValue("films").jsonArray
        val films = LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        assertEquals(40, rows.size)
        assertEquals(films.map { it.id }.toSet(), rows.map { it.jsonObject.getValue("filmID").jsonPrimitive.content }.toSet())
        for (film in films) {
            val row = rows.single { it.jsonObject.getValue("filmID").jsonPrimitive.content == film.id }.jsonObject
            assertEquals(row.getValue("polarity").jsonPrimitive.content, film.polarity.name)
            assertEquals(row.getValue("color").jsonPrimitive.content, film.color.name)
            assertFalse(row.getValue("sources").jsonArray.isEmpty())
        }
    }
}
