package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ReciprocityNoCorrectionBoundary
import com.sangwook.ptimer.core.reciprocity.TableEvaluationResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Validates the bundled catalog against its actual shape: 37 films, the
 * real manufacturer counts, and the three real profile shapes (20 formula /
 * 11 tableInterpolation / 6 threshold+limitedGuidance). The older two-shape
 * fixture rule is intentionally not enforced. Table-film goldens are derived
 * from the catalog's own anchors.
 */
class CatalogLoaderTest {

    private val films = LaunchPresetFilmCatalogLoader.loadBundledCatalog()

    @Test
    fun loadsExactly37Films() {
        assertEquals(37, films.size)
    }

    @Test
    fun manufacturerCountsMatch() {
        val counts = films.groupingBy { it.manufacturer }.eachCount()
        assertEquals(12, counts["ILFORD / HARMAN"])
        assertEquals(9, counts["Kodak"])
        assertEquals(4, counts["Fujifilm"])
        assertEquals(3, counts["FOMA BOHEMIA"])
        assertEquals(7, counts["Rollei"])
        assertEquals(2, counts["ADOX"])
    }

    @Test
    fun profileShapeDistributionMatchesCatalog() {
        val shapes = films.groupingBy { LaunchPresetFilmCatalogLoader.shapeOf(it) }.eachCount()
        assertEquals(20, shapes["formula"])
        assertEquals(11, shapes["tableInterpolation"])
        assertEquals(6, shapes["threshold+limitedGuidance"])
    }

    @Test
    fun idsAreUniqueAndKnownEntriesPresent() {
        assertEquals(films.size, films.map { it.id }.toSet().size)
        assertTrue(films.any { it.id == "ilford-pan-f-plus-50" })
        assertTrue(films.any { it.canonicalStockName == "Fomapan 100 Classic" })
    }

    @Test
    fun malformedCatalogFailsClearly() {
        assertThrows(CatalogLoadException::class.java) {
            LaunchPresetFilmCatalogLoader.loadCatalog("{ not valid json")
        }
        assertThrows(CatalogLoadException::class.java) {
            LaunchPresetFilmCatalogLoader.loadCatalog("[]")
        }
    }

    @Test
    fun tableFilmsReproduceTheirAnchorsExactly() {
        val tableFilms = films.filter { LaunchPresetFilmCatalogLoader.shapeOf(it) == "tableInterpolation" }
        assertEquals(11, tableFilms.size)
        for (film in tableFilms) {
            val rule = (film.profiles.first().typedRules.first()
                as com.sangwook.ptimer.core.catalog.ReciprocityRule.Table).rule
            for (anchor in rule.anchors) {
                // Anchors above the no-correction band must reproduce exactly.
                if (!ReciprocityNoCorrectionBoundary.isWithinNoCorrection(anchor.meteredSeconds, rule.noCorrectionThroughSeconds)) {
                    val result = rule.evaluate(anchor.meteredSeconds)
                    val value = when (result) {
                        is TableEvaluationResult.WithinSourceRange -> result.correctedExposureSeconds
                        is TableEvaluationResult.BeyondSourceRange -> result.correctedExposureSeconds
                        else -> error("${film.id}: anchor ${anchor.meteredSeconds} did not evaluate to a value ($result)")
                    }
                    assertEquals(
                        "${film.id} anchor ${anchor.meteredSeconds}s",
                        anchor.correctedSeconds, value, anchor.correctedSeconds * 1e-9 + 1e-9,
                    )
                }
            }
        }
    }
}
