package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.TableAnchor

/**
 * Resolves the linked reference-table anchors for a saved custom FORMULA
 * film from its persisted `UserEditableMetadata.referenceTableFilmID`
 * (PTIMER-180). Display-only: the anchors drive reference/error rendering
 * and are NEVER fed into calculation. Mirrors iOS
 * `CustomFilmReferenceTableResolver`.
 */
object CustomFilmReferenceTableResolver {

    data class Resolution(
        /** Current anchors of the linked table, or empty when unlinked or unresolvable. */
        val anchors: List<TableAnchor>,
        /** True when a link exists but no longer resolves to a custom table. */
        val isLinkedButMissing: Boolean,
    )

    /**
     * Resolves the reference table for [formulaFilm]. [lookup] maps a film id
     * to the current [FilmIdentity] in the library. An unlinked formula
     * returns an empty, not-missing resolution.
     */
    fun resolve(formulaFilm: FilmIdentity, lookup: (String) -> FilmIdentity?): Resolution {
        val tableId = formulaFilm.userMetadata?.referenceTableFilmID
            ?: return Resolution(emptyList(), isLinkedButMissing = false)
        val table = lookup(tableId) ?: return Resolution(emptyList(), isLinkedButMissing = true)
        val anchors = tableAnchors(table)
        return if (anchors.isEmpty()) {
            Resolution(emptyList(), isLinkedButMissing = true)
        } else {
            Resolution(anchors, isLinkedButMissing = false)
        }
    }

    private fun tableAnchors(film: FilmIdentity): List<TableAnchor> {
        val rules = film.profiles.firstOrNull()?.typedRules ?: return emptyList()
        return rules.firstNotNullOfOrNull { (it as? ReciprocityRule.Table)?.rule?.anchors } ?: emptyList()
    }
}
