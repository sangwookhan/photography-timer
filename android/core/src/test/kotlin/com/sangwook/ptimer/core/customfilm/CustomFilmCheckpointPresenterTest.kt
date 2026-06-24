package com.sangwook.ptimer.core.customfilm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CustomFilmCheckpointPresenterTest {

    private fun formulaProfile() = CustomFilmBuilder.buildFormulaFilm(
        input = CustomFormulaFilmInput(
            filmLabel = "Pow", profileName = "Pow", iso = 100,
            coefficientSeconds = 1.0, referenceMeteredTimeSeconds = 1.0,
            exponent = 1.9, offsetSeconds = 0.0, noCorrectionThroughSeconds = 1.0,
        ),
        filmId = "f", profileId = "p",
    )!!.profiles.first()

    @Test
    fun checkpointsCoverTheSampleLadderWithStopDeltas() {
        val rows = CustomFilmCheckpointPresenter.rows(formulaProfile())
        assertEquals(listOf(1.0, 10.0, 60.0, 300.0, 1000.0), rows.map { it.meteredSeconds })

        // Tc = Tm^1.9: 1s stays uncorrected; 10s → ~79s ≈ +3 stops.
        val oneSecond = rows.first { it.meteredSeconds == 1.0 }
        assertNull("1s is within the no-correction range", oneSecond.stopDelta)

        val tenSeconds = rows.first { it.meteredSeconds == 10.0 }
        assertEquals(79.4, tenSeconds.correctedSeconds!!, 0.5)
        assertEquals(3.0, tenSeconds.stopDelta!!, 0.05)
    }

    @Test
    fun beyondSourceRangeRowsAreFlagged() {
        // Source range capped at 30s: the 60s+ samples read as beyond-range.
        val profile = CustomFilmBuilder.buildFormulaFilm(
            input = CustomFormulaFilmInput(
                filmLabel = "Pow", profileName = "Pow", iso = 100,
                coefficientSeconds = 1.0, referenceMeteredTimeSeconds = 1.0,
                exponent = 1.9, offsetSeconds = 0.0, noCorrectionThroughSeconds = 1.0,
                sourceRangeThroughSeconds = 30.0,
            ),
            filmId = "f", profileId = "p",
        )!!.profiles.first()
        val rows = CustomFilmCheckpointPresenter.rows(profile)
        assertTrue(rows.first { it.meteredSeconds == 60.0 }.beyondSourceRange)
        assertTrue(!rows.first { it.meteredSeconds == 10.0 }.beyondSourceRange)
    }
}
