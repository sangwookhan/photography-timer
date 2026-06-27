// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointPresenter
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointsPresenter
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula
import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraphPresenter
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.core.reciprocity.sortedAnchors

/**
 * Editor prefill for an existing custom film, reconstructed from the stored
 * profile so the create dialogs can reopen in edit mode. Strings mirror the
 * dialog fields; [isTable] selects the table vs formula editor.
 */
data class CustomFilmDraft(
    val filmId: String,
    val isTable: Boolean,
    val label: String,
    val manufacturer: String,
    val iso: String,
    val tc0: String = "",
    val tm0: String = "",
    val exponent: String = "",
    val offset: String = "",
    val noCorrection: String = "",
    val sourceThrough: String = "",
    val anchors: List<Pair<String, String>> = emptyList(),
    val notes: String = "",
    val sourceType: CustomProfileSourceType = CustomProfileSourceType.userDefined,
    val referenceUrl: String = "",
    /** Source table this formula was derived from (preserved on re-save). */
    val referenceTableFilmId: String? = null,
    /** The linked table's current anchors, resolved at open time for reference points. */
    val linkedTableAnchors: List<Pair<Double, Double>> = emptyList(),
)

/**
 * Pure helpers behind the custom-film editor: fit / build / preview a
 * candidate film from in-progress inputs, and reconstruct an edit draft from a
 * saved film. Stateless — the calculator controller delegates here, passing the
 * current film list and adjusted-shutter marker, so the controller stays
 * focused on live shooting state.
 */
object CustomFilmEditingPresenter {
    /**
     * App-derived (fitted) formula outcome for the in-progress table editor
     * inputs (iOS PTIMER-179). Null until the inputs form a valid table.
     */
    fun previewTableFit(input: CustomTableFilmInput): CustomTableFittedFormula.Outcome? =
        tableRule(input)?.let { CustomTableFittedFormula.outcome(it) }

    /**
     * Builds a separate formula film fitted from the in-progress table inputs
     * (iOS PTIMER-180 "Create Custom Formula"); null if the table is invalid or
     * the fit is unusable. The label gains a " (formula)" suffix.
     */
    fun buildFormulaFilmFromTableInput(
        input: CustomTableFilmInput,
        filmId: String,
        profileId: String,
        referenceTableFilmId: String? = null,
    ): FilmIdentity? {
        val rule = tableRule(input) ?: return null
        val fitted = (CustomTableFittedFormula.outcome(rule) as? CustomTableFittedFormula.Outcome.Available)?.formula
            ?: return null
        val name = "${input.filmLabel} (formula)"
        return CustomFilmBuilder.buildFormulaFilm(
            CustomFormulaFilmInput(
                filmLabel = name,
                profileName = name,
                iso = input.iso,
                coefficientSeconds = fitted.coefficientSeconds,
                referenceMeteredTimeSeconds = fitted.referenceMeteredTimeSeconds,
                exponent = fitted.exponent,
                offsetSeconds = fitted.offsetSeconds,
                noCorrectionThroughSeconds = fitted.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds = fitted.sourceRangeThroughSeconds,
                manufacturer = input.manufacturer,
                referenceTableFilmId = referenceTableFilmId,
            ),
            filmId,
            profileId,
        )
    }

    /**
     * Reference points comparing a formula against its source table's anchors
     * (iOS PTIMER-180), resolved against the table's current anchors.
     */
    fun referencePoints(
        input: CustomFormulaFilmInput,
        anchors: List<Pair<Double, Double>>,
    ): List<CustomFilmReferencePointRow> {
        val profile = CustomFilmBuilder.buildFormulaFilm(input, "ref-film", "ref-profile")
            ?.profiles?.firstOrNull() ?: return emptyList()
        return CustomFilmReferencePointsPresenter.rows(
            profile,
            anchors.map { TableAnchor(meteredSeconds = it.first, correctedSeconds = it.second) },
        )
    }

    /** Current anchors of a saved custom table film, by id; empty if unresolved. */
    fun tableAnchorsOf(films: List<FilmIdentity>, filmId: String?): List<Pair<Double, Double>> {
        if (filmId == null) return emptyList()
        val table = films.firstOrNull { it.id == filmId }
            ?.profiles?.firstOrNull()
            ?.rules?.firstNotNullOfOrNull { it.tableInterpolation } ?: return emptyList()
        return table.sortedAnchors.map { it.meteredSeconds to it.correctedSeconds }
    }

    private fun tableRule(input: CustomTableFilmInput) =
        CustomFilmBuilder.buildTableFilm(input, "fit-film", "fit-profile")
            ?.profiles?.firstOrNull()
            ?.rules?.firstNotNullOfOrNull { it.tableInterpolation }

    /**
     * Live reciprocity preview curve for the in-progress inputs; [adjustedSeconds]
     * places the current-result marker. Null until the inputs form a profile.
     */
    fun previewFormulaGraph(input: CustomFormulaFilmInput, adjustedSeconds: Double): ReciprocityGraph? =
        CustomFilmBuilder.buildFormulaFilm(input, "preview-film", "preview-profile")
            ?.profiles?.firstOrNull()
            ?.let { ReciprocityGraphPresenter.make(it, adjustedSeconds) }

    fun previewTableGraph(input: CustomTableFilmInput, adjustedSeconds: Double): ReciprocityGraph? =
        CustomFilmBuilder.buildTableFilm(input, "preview-film", "preview-profile")
            ?.profiles?.firstOrNull()
            ?.let { ReciprocityGraphPresenter.make(it, adjustedSeconds) }

    /** Checkpoint table rows (metered → corrected → Δstop) for the editor preview. */
    fun previewFormulaCheckpoints(input: CustomFormulaFilmInput): List<CustomFilmCheckpointRow> =
        CustomFilmBuilder.buildFormulaFilm(input, "preview-film", "preview-profile")
            ?.profiles?.firstOrNull()
            ?.let { CustomFilmCheckpointPresenter.rows(it) } ?: emptyList()

    fun previewTableCheckpoints(input: CustomTableFilmInput): List<CustomFilmCheckpointRow> =
        CustomFilmBuilder.buildTableFilm(input, "preview-film", "preview-profile")
            ?.profiles?.firstOrNull()
            ?.let { CustomFilmCheckpointPresenter.rows(it) } ?: emptyList()

    /**
     * Human-readable calculation basis for a formula film (iOS "Calculation
     * basis"): `Tc = a × Tm^p + b`, dropping the neutral a=1 / b=0 terms.
     */
    fun calculationBasis(input: CustomFormulaFilmInput): String {
        val a = input.coefficientSeconds
        val b = input.offsetSeconds
        val coefficient = if (a == 1.0) "" else "${num(a)} × "
        val offset = if (b == 0.0) "" else " + ${num(b)}s"
        return "Tc = ${coefficient}Tm^${num(input.exponent)}$offset"
    }

    /** Reconstructs the editor prefill for an existing custom film; null if not custom/known. */
    fun customFilmDraft(films: List<FilmIdentity>, filmId: String): CustomFilmDraft? {
        val film = films.firstOrNull { it.id == filmId && it.kind == FilmIdentityKind.custom } ?: return null
        val profile = film.profiles.firstOrNull() ?: return null
        val manufacturer = profile.userMetadata?.customManufacturer.orEmpty()
        val label = if (manufacturer.isNotEmpty() && film.canonicalStockName.startsWith("$manufacturer ")) {
            film.canonicalStockName.removePrefix("$manufacturer ")
        } else {
            film.canonicalStockName
        }
        val iso = film.iso.toString()
        val notes = profile.userMetadata?.notes?.joinToString("\n").orEmpty()
        val sourceType = profile.userMetadata?.customSourceType ?: CustomProfileSourceType.userDefined
        val referenceUrl = profile.userMetadata?.referenceURL.orEmpty()
        val referenceTableFilmId = profile.userMetadata?.referenceTableFilmID
        val linkedTableAnchors = tableAnchorsOf(films, referenceTableFilmId)
        val table = profile.rules.firstNotNullOfOrNull { it.tableInterpolation }
        val formula = profile.rules.firstNotNullOfOrNull { it.formula }?.formula
        return when {
            table != null -> CustomFilmDraft(
                filmId = filmId, isTable = true, label = label, manufacturer = manufacturer, iso = iso,
                noCorrection = num(table.noCorrectionThroughSeconds),
                anchors = table.anchors.map { num(it.meteredSeconds) to num(it.correctedSeconds) },
                notes = notes, sourceType = sourceType, referenceUrl = referenceUrl,
            )
            formula != null -> CustomFilmDraft(
                filmId = filmId, isTable = false, label = label, manufacturer = manufacturer, iso = iso,
                tc0 = num(formula.coefficientSeconds),
                tm0 = num(formula.referenceMeteredTimeSeconds),
                exponent = num(formula.exponent),
                offset = num(formula.offsetSeconds),
                noCorrection = num(formula.noCorrectionThroughSeconds),
                sourceThrough = formula.sourceRangeThroughSeconds?.let { num(it) } ?: "unlimited",
                notes = notes, sourceType = sourceType, referenceUrl = referenceUrl,
                referenceTableFilmId = referenceTableFilmId, linkedTableAnchors = linkedTableAnchors,
            )
            else -> null
        }
    }

    /** Existing profile id for a custom film, so an edit preserves it; null if unknown. */
    fun customFilmProfileId(films: List<FilmIdentity>, filmId: String): String? =
        films.firstOrNull { it.id == filmId }?.profiles?.firstOrNull()?.id

    private fun num(value: Double): String {
        if (value == value.toLong().toDouble()) return value.toLong().toString()
        // Round to 4 decimals (trimming trailing zeros) so app-derived fitted
        // values — which carry full double precision (1.269048482140576) — read
        // cleanly in the editor chips and the calculation basis.
        return java.math.BigDecimal(value)
            .setScale(4, java.math.RoundingMode.HALF_UP)
            .stripTrailingZeros()
            .toPlainString()
    }
}
