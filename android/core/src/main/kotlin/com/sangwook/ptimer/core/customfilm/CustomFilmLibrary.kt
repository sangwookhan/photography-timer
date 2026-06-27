// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.persistence.CustomFilmLibraryStoring
import com.sangwook.ptimer.core.persistence.NoOpCustomFilmLibraryStore
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.FormulaReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.TableInterpolationReciprocityRule
import com.sangwook.ptimer.core.reciprocity.hasValidParameters

/**
 * Source-of-truth model for photographer-authored custom film reciprocity
 * profiles. Holds an ordered list of custom [FilmIdentity] entries whose
 * single profile carries `.userDefined` authority. Loads the persisted
 * snapshot at init and writes back on every mutation; insertion order is
 * preserved so newly created entries appear at the bottom of the picker.
 * (iOS: CustomFilmLibrary.)
 */
class CustomFilmLibrary(
    private val store: CustomFilmLibraryStoring = NoOpCustomFilmLibraryStore(),
    initial: List<FilmIdentity> = emptyList(),
) {
    private val films: MutableList<FilmIdentity> =
        sanitized(store.loadSnapshot()?.films ?: initial).toMutableList()

    val customFilms: List<FilmIdentity> get() = films.toList()
    val isEmpty: Boolean get() = films.isEmpty()

    /** Appends a custom film; a duplicate id replaces in place (edit path). */
    fun add(film: FilmIdentity) {
        if (film.kind != FilmIdentityKind.custom) return
        if (!isWellFormedCustomFilm(film)) return
        val index = films.indexOfFirst { it.id == film.id }
        if (index >= 0) films[index] = film else films.add(film)
        persist()
    }

    /** Removes the entry matching [id]; no-op when none matches. */
    fun remove(id: String) {
        if (films.removeAll { it.id == id }) persist()
    }

    fun film(withId: String): FilmIdentity? = films.firstOrNull { it.id == withId }

    private fun persist() {
        store.saveSnapshot(PersistentCustomFilmLibrarySnapshot(films = films.toList()))
    }

    private companion object {
        fun sanitized(films: List<FilmIdentity>): List<FilmIdentity> = films.filter(::isWellFormedCustomFilm)

        fun isWellFormedCustomFilm(film: FilmIdentity): Boolean {
            if (!hasWellFormedFilmIdentity(film)) return false
            val profile = film.profiles.firstOrNull() ?: return false
            if (!hasWellFormedProfileIdentity(profile)) return false

            // Exactly one calculation path: formula XOR table interpolation.
            val formulaRules = profile.rules.mapNotNull { it.formula }
            val tableRules = profile.rules.mapNotNull { it.tableInterpolation }
            if (profile.rules.size != 1 || formulaRules.size + tableRules.size != 1) return false

            formulaRules.firstOrNull()?.let { return isWellFormedFormula(it) }
            tableRules.firstOrNull()?.let { return it.hasValidParameters && it.noCorrectionThroughSeconds > 0 }
            return false
        }

        fun hasWellFormedFilmIdentity(film: FilmIdentity): Boolean =
            film.kind == FilmIdentityKind.custom &&
                film.iso > 0 &&
                film.id.trim().isNotEmpty() &&
                film.canonicalStockName.trim().isNotEmpty()

        fun hasWellFormedProfileIdentity(profile: ReciprocityProfile): Boolean =
            profile.source.authority == ReciprocityAuthority.userDefined &&
                profile.id.trim().isNotEmpty() &&
                profile.name.trim().isNotEmpty()

        fun isWellFormedFormula(rule: FormulaReciprocityRule): Boolean {
            val f = rule.formula
            if (!f.hasValidParameters) return false
            if (!(f.noCorrectionThroughSeconds.isFinite() && f.noCorrectionThroughSeconds >= 0)) return false
            f.sourceRangeThroughSeconds?.let {
                if (!(it.isFinite() && it > f.noCorrectionThroughSeconds)) return false
            }
            return CustomFilmFormulaGuard.passesUsableRangeCheck(
                CustomFilmFormulaGuard.UsableRangeInput(
                    exponent = f.exponent,
                    referenceMeteredTimeSeconds = f.referenceMeteredTimeSeconds,
                    coefficientSeconds = f.coefficientSeconds,
                    offsetSeconds = f.offsetSeconds,
                    noCorrectionThroughSeconds = f.noCorrectionThroughSeconds,
                    sourceRangeThroughSeconds = f.sourceRangeThroughSeconds,
                ),
            )
        }
    }
}
