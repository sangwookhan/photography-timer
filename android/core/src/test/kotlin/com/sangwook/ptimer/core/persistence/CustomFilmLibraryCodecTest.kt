// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.FilmProductionStatus
import com.sangwook.ptimer.core.reciprocity.FormulaFamily
import com.sangwook.ptimer.core.reciprocity.FormulaReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityConfidence
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceProvenance
import com.sangwook.ptimer.core.reciprocity.UserEditableMetadata
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-215 per-record decode behavior for the custom film library codec.
 * Unknown enum values / rule kinds injected into one record drop only that
 * record; the rest survive. Version-gate and malformed-root failures reject
 * the whole payload.
 */
class CustomFilmLibraryCodecTest {
    private fun customFilm(id: String, stock: String, iso: Int): FilmIdentity {
        val profile = ReciprocityProfile(
            id = "$id-profile",
            name = "Profile for $stock",
            source = ReciprocitySourceProvenance(
                kind = ReciprocitySourceKind.userDefined,
                authority = ReciprocityAuthority.userDefined,
                confidence = ReciprocityConfidence.unknown,
                publisher = "",
            ),
            rules = listOf(
                ReciprocityRule(
                    kind = ReciprocityRuleKind.formula,
                    formula = FormulaReciprocityRule(
                        formula = ReciprocityFormula(
                            formulaFamily = FormulaFamily.modifiedSchwarzschild,
                            exponent = 1.3,
                            noCorrectionThroughSeconds = 1.0,
                        ),
                    ),
                ),
            ),
            userMetadata = UserEditableMetadata(),
        )
        return FilmIdentity(
            id = id,
            kind = FilmIdentityKind.custom,
            canonicalStockName = stock,
            aliases = emptyList(),
            iso = iso,
            productionStatus = FilmProductionStatus.unknown,
            profiles = listOf(profile),
            userMetadata = UserEditableMetadata(),
        )
    }

    private fun twoFilms() = PersistentCustomFilmLibrarySnapshot(
        films = listOf(customFilm("cf-1", "Alpha", 100), customFilm("cf-2", "Beta", 400)),
    )

    @Test
    fun validLibraryLoadsAllRecords() {
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics(CustomFilmLibraryCodec.encode(twoFilms()))
        assertEquals(PersistenceLoadOutcome.loaded, result.outcome)
        assertEquals(listOf("cf-1", "cf-2"), result.snapshot.films.map { it.id })
    }

    @Test
    fun unknownRuleKindDropsOnlyThatFilm() {
        val corrupted = CustomFilmLibraryCodec.encode(twoFilms())
            .replaceFirst("\"kind\":\"formula\"", "\"kind\":\"quantumFlux\"")
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics(corrupted)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(1, result.droppedRecordCount)
        assertEquals(listOf("cf-2"), result.snapshot.films.map { it.id })
    }

    @Test
    fun unknownAuthorityEnumDropsOnlyThatFilm() {
        val corrupted = CustomFilmLibraryCodec.encode(twoFilms())
            .replaceFirst("\"authority\":\"userDefined\"", "\"authority\":\"martian\"")
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics(corrupted)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(listOf("cf-2"), result.snapshot.films.map { it.id })
    }

    @Test
    fun duplicateIdsCollapseFirstValidWins() {
        val dup = PersistentCustomFilmLibrarySnapshot(
            films = listOf(customFilm("dup", "First", 100), customFilm("dup", "Second", 200)),
        )
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics(CustomFilmLibraryCodec.encode(dup))
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(listOf("First"), result.snapshot.films.map { it.canonicalStockName })
    }

    @Test
    fun futureSchemaVersionRejectsWholePayload() {
        val corrupted = CustomFilmLibraryCodec.encode(twoFilms())
            .replaceFirst("\"schemaVersion\":1", "\"schemaVersion\":999")
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics(corrupted)
        assertEquals(PersistenceLoadOutcome.versionRejected, result.outcome)
        assertTrue(result.snapshot.films.isEmpty())
        assertNull(CustomFilmLibraryCodec.decode(corrupted))
    }

    @Test
    fun missingSchemaVersionAcceptedAsLegacyV1() {
        val corrupted = CustomFilmLibraryCodec.encode(twoFilms())
            .replaceFirst(",\"schemaVersion\":1", "")
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics(corrupted)
        assertEquals(PersistenceLoadOutcome.loaded, result.outcome)
        assertEquals(listOf("cf-1", "cf-2"), result.snapshot.films.map { it.id })
    }

    @Test
    fun malformedRootReportsMalformed() {
        val result = CustomFilmLibraryCodec.decodeWithDiagnostics("not json")
        assertEquals(PersistenceLoadOutcome.malformed, result.outcome)
        assertTrue(result.snapshot.films.isEmpty())
        assertNull(CustomFilmLibraryCodec.decode("not json"))
    }
}
