package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.catalog.FilmIdentity
import com.sangwook.ptimer.core.catalog.ReciprocityRule
import com.sangwook.ptimer.core.reciprocity.CustomFilmFormulaGuard

/**
 * In-memory custom-film library with upsert-by-id, removal, and sanitation.
 * Only well-formed custom films (kind=custom, exactly one profile, exactly one
 * valid formula XOR table rule) are accepted/retained. Mirrors iOS
 * `CustomFilmLibrary`.
 */
class CustomFilmLibrary(initial: List<FilmIdentity> = emptyList()) {
    private val films = LinkedHashMap<String, FilmIdentity>()

    init { initial.filter { isWellFormed(it) }.forEach { films[it.id] = it } }

    val all: List<FilmIdentity> get() = films.values.toList()

    fun film(id: String): FilmIdentity? = films[id]

    /** Upsert by id; rejects non-well-formed films. Returns true if accepted. */
    fun upsert(film: FilmIdentity): Boolean {
        if (!isWellFormed(film)) return false
        films[film.id] = film
        return true
    }

    fun remove(id: String) { films.remove(id) }

    companion object {
        fun isWellFormed(film: FilmIdentity): Boolean {
            if (film.kind != "custom") return false
            val profile = film.profiles.singleOrNull() ?: return false
            val rule = profile.typedRules.singleOrNull() ?: return false
            return when (rule) {
                is ReciprocityRule.Formula -> rule.formula.hasValidParameters &&
                    CustomFilmFormulaGuard.passesUsableRangeCheck(
                        CustomFilmFormulaGuard.UsableRangeInput(
                            exponent = rule.formula.exponent,
                            referenceMeteredTimeSeconds = rule.formula.referenceMeteredTimeSeconds,
                            coefficientSeconds = rule.formula.coefficientSeconds,
                            offsetSeconds = rule.formula.offsetSeconds,
                            noCorrectionThroughSeconds = rule.formula.noCorrectionThroughSeconds,
                            sourceRangeThroughSeconds = rule.formula.sourceRangeThroughSeconds,
                        ),
                    )
                is ReciprocityRule.Table -> rule.rule.hasValidParameters
                else -> false
            }
        }
    }
}
