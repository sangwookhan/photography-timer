// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.persistence.CustomFilmLibraryCodec
import com.sangwook.ptimer.core.persistence.CustomFilmLibraryStoring
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CustomFilmTest {

    private fun input(
        tc: Double = 2.0,
        tm: Double = 1.0,
        exponent: Double = 1.3,
        offset: Double = 0.0,
        through: Double? = null,
    ) = CustomFormulaFilmInput(
        filmLabel = "My Film",
        profileName = "My Film",
        iso = 100,
        coefficientSeconds = tc,
        referenceMeteredTimeSeconds = tm,
        exponent = exponent,
        offsetSeconds = offset,
        noCorrectionThroughSeconds = 1.0,
        sourceRangeThroughSeconds = through,
    )

    @Test
    fun guardRejectsShorteningFormula() {
        // exponent < 1 with no source range eventually shortens → rejected.
        assertFalse(
            CustomFilmFormulaGuard.passesUsableRangeCheck(
                CustomFilmFormulaGuard.UsableRangeInput(0.5, 1.0, 2.0, 0.0, 1.0, null),
            ),
        )
    }

    @Test
    fun guardAcceptsLengtheningFormula() {
        assertTrue(
            CustomFilmFormulaGuard.passesUsableRangeCheck(
                CustomFilmFormulaGuard.UsableRangeInput(1.3, 1.0, 1.0, 0.0, 1.0, null),
            ),
        )
    }

    @Test
    fun durationParserHandlesUnitsUnlimitedAndEmpty() {
        assertEquals(CustomFilmDurationParser.ParsedDuration.Empty, CustomFilmDurationParser.parse("  "))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Unlimited, CustomFilmDurationParser.parse("Unlimited"))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Seconds(300.0), CustomFilmDurationParser.parse("5m"))
        assertEquals(CustomFilmDurationParser.ParsedDuration.Seconds(3600.0), CustomFilmDurationParser.parse("1h"))
        assertNull(CustomFilmDurationParser.parse("abc"))
    }

    @Test
    fun builderProducesWellFormedCustomFilmAndRejectsBadFormula() {
        val good = CustomFilmBuilder.buildFormulaFilm(input(), "film-1", "profile-1")
        assertNotNull(good)
        assertEquals(FilmIdentityKind.custom, good!!.kind)
        assertEquals("My Film", good.canonicalStockName)
        assertEquals(ReciprocityAuthorityUserDefined, good.profiles.first().source.authority.name)

        // A shortening formula is rejected by the guard inside the builder.
        assertNull(CustomFilmBuilder.buildFormulaFilm(input(tc = 0.5, exponent = 0.5), "film-2", "profile-2"))
    }

    @Test
    fun tableBuilderProducesWellFormedFilmAndRejectsBadAnchors() {
        val good = CustomFilmBuilder.buildTableFilm(
            CustomTableFilmInput(
                filmLabel = "Table Film",
                profileName = "Table Film",
                iso = 100,
                anchors = listOf(2.0 to 3.0, 4.0 to 8.0, 8.0 to 20.0),
                noCorrectionThroughSeconds = 1.0,
            ),
            "film-t",
            "profile-t",
        )
        assertNotNull(good)
        assertEquals(FilmIdentityKind.custom, good!!.kind)
        // The library accepts it (single table rule, knee > 0 below the first anchor).
        val library = CustomFilmLibrary()
        library.add(good)
        assertEquals(1, library.customFilms.size)

        // Fewer than two anchors → rejected.
        assertNull(
            CustomFilmBuilder.buildTableFilm(
                CustomTableFilmInput("X", "X", 100, listOf(2.0 to 3.0), 1.0),
                "f",
                "p",
            ),
        )
        // A shortening anchor (corrected < metered) → rejected by the domain contract.
        assertNull(
            CustomFilmBuilder.buildTableFilm(
                CustomTableFilmInput("X", "X", 100, listOf(2.0 to 1.0, 4.0 to 3.0), 1.0),
                "f",
                "p",
            ),
        )
    }

    @Test
    fun libraryAddsRemovesAndPersistsThroughStore() {
        val store = FakeStore()
        val library = CustomFilmLibrary(store = store)
        val film = CustomFilmBuilder.buildFormulaFilm(input(), "film-1", "profile-1")!!
        library.add(film)
        assertEquals(1, library.customFilms.size)
        assertNotNull(store.saved)

        // Reload from the persisted snapshot: the film survives sanitation.
        val reloaded = CustomFilmLibrary(store = store)
        assertEquals(1, reloaded.customFilms.size)
        assertEquals("film-1", reloaded.customFilms.first().id)

        reloaded.remove("film-1")
        assertTrue(reloaded.isEmpty)
    }

    @Test
    fun fittedFormulaRecoversAKnownPowerLawWithGoodQuality() {
        // Anchors sampled from Tc = 2 × Tm^1.5 (non-shortening), knee below first.
        val rule = com.sangwook.ptimer.core.reciprocity.TableInterpolationReciprocityRule(
            anchors = listOf(
                com.sangwook.ptimer.core.reciprocity.TableAnchor(2.0, 2.0 * Math.pow(2.0, 1.5)),
                com.sangwook.ptimer.core.reciprocity.TableAnchor(4.0, 2.0 * Math.pow(4.0, 1.5)),
                com.sangwook.ptimer.core.reciprocity.TableAnchor(8.0, 2.0 * Math.pow(8.0, 1.5)),
            ),
            noCorrectionThroughSeconds = 1.0,
            sourceRangeThroughSeconds = 8.0,
        )
        val outcome = CustomTableFittedFormula.outcome(rule)
        val available = outcome as CustomTableFittedFormula.Outcome.Available
        assertEquals(CustomTableFittedFormula.FitQuality.good, available.formula.quality)
        assertEquals(1.5, available.formula.exponent, 1e-6)
        assertEquals(2.0, available.formula.coefficientSeconds, 1e-6)
        assertEquals(3, available.formula.comparisonRows.size)
    }

    @Test
    fun fitterRejectsInsufficientAnchors() {
        val r = ReciprocityFormulaFitter.fit(
            listOf(com.sangwook.ptimer.core.reciprocity.TableAnchor(2.0, 4.0)),
        )
        assertTrue(r is ReciprocityFormulaFitter.FitResult.Failure)
    }

    @Test
    fun codecRoundTripsAndFailsSafe() {
        val film = CustomFilmBuilder.buildFormulaFilm(input(), "film-1", "profile-1")!!
        val snapshot = PersistentCustomFilmLibrarySnapshot(films = listOf(film))
        assertEquals(snapshot, CustomFilmLibraryCodec.decode(CustomFilmLibraryCodec.encode(snapshot)))
        assertNull(CustomFilmLibraryCodec.decode("{bad"))
    }

    private val ReciprocityAuthorityUserDefined = "userDefined"

    private class FakeStore : CustomFilmLibraryStoring {
        var saved: PersistentCustomFilmLibrarySnapshot? = null
        override fun loadSnapshot(): PersistentCustomFilmLibrarySnapshot? = saved
        override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) { saved = snapshot }
        override fun clearSnapshot() { saved = null }
    }
}
