package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.catalog.FilmIdentity
import com.sangwook.ptimer.core.catalog.ReciprocityRule
import com.sangwook.ptimer.core.reciprocity.PowerLawFitResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormulaFitter

/**
 * PTIMER-180 "Create Formula from a saved table": seeds a SEPARATE, new
 * custom FORMULA film from a saved custom table's fitted formula, linked back
 * to the table by `referenceTableFilmID` (display-only). The table is never
 * converted; the new formula calculates solely from its own parameters.
 * Returns null when the table is ineligible or the fit would shorten exposure.
 */
object CreateFormulaFromTable {
    fun create(tableFilm: FilmIdentity, newId: String): FilmIdentity? {
        if (tableFilm.kind != "custom") return null
        val tableRule = tableFilm.profiles.firstOrNull()?.typedRules
            ?.firstNotNullOfOrNull { (it as? ReciprocityRule.Table)?.rule } ?: return null

        val fit = when (val r = ReciprocityFormulaFitter.fit(tableRule.anchors)) {
            is PowerLawFitResult.Success -> r.fit
            is PowerLawFitResult.Failure -> return null
        }

        val result = CustomFilmFactory.buildFormula(
            id = newId,
            name = "${tableFilm.canonicalStockName} Formula",
            iso = tableFilm.iso,
            coefficientSeconds = fit.coefficient,
            referenceMeteredTimeSeconds = 1.0,
            exponent = fit.exponent,
            offsetSeconds = 0.0,
            noCorrectionThroughSeconds = tableRule.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds = tableRule.sourceRangeThroughSeconds,
            referenceTableFilmId = tableFilm.id,
        )
        return (result as? CustomFilmResult.Success)?.film
    }
}
