// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType
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
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.core.reciprocity.TableInterpolationReciprocityRule
import com.sangwook.ptimer.core.reciprocity.UserEditableMetadata
import com.sangwook.ptimer.core.reciprocity.hasValidParameters

/**
 * Validated inputs for a custom formula film. Editor labels map onto the
 * shared [ReciprocityFormula] field names verbatim (iOS:
 * CustomFilmEditorFormState.buildFilmIdentity):
 *
 *   Tm₀ (Metered point)   → referenceMeteredTimeSeconds
 *   Tc₀ (Corrected point) → coefficientSeconds
 *   p  (Curve strength)   → exponent
 *   b  (Fixed add-on)     → offsetSeconds
 *   No correction until   → noCorrectionThroughSeconds
 *   Source data through   → sourceRangeThroughSeconds (null = unlimited)
 */
data class CustomFormulaFilmInput(
    val filmLabel: String,
    val profileName: String,
    val iso: Int,
    val coefficientSeconds: Double,
    val referenceMeteredTimeSeconds: Double,
    val exponent: Double,
    val offsetSeconds: Double = 0.0,
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double? = null,
    val manufacturer: String? = null,
    val notes: String? = null,
    val sourceType: CustomProfileSourceType = CustomProfileSourceType.userDefined,
    val referenceUrl: String? = null,
    /** Display-only link to the custom table this formula was derived from. */
    val referenceTableFilmId: String? = null,
)

/**
 * Validated inputs for a custom table film: ≥2 (metered, corrected) anchor
 * pairs plus the no-correction knee. The source range is taken as the last
 * anchor's metered time. (iOS: CustomFilmEditorTableFormState.)
 */
data class CustomTableFilmInput(
    val filmLabel: String,
    val profileName: String,
    val iso: Int,
    val anchors: List<Pair<Double, Double>>,
    val noCorrectionThroughSeconds: Double,
    val manufacturer: String? = null,
    val notes: String? = null,
    val sourceType: CustomProfileSourceType = CustomProfileSourceType.userDefined,
    val referenceUrl: String? = null,
)

/**
 * Builds a well-formed custom [FilmIdentity] (kind = custom, single
 * `.userDefined`-authority formula profile) from validated formula inputs,
 * sharing the same domain shape preset films use. Returns null when the
 * inputs fail the non-shortening usable-range guard or carry an empty
 * name. (iOS: CustomFilmEditorFormState.buildFilmIdentity / assembleCustomFilm.)
 */
object CustomFilmBuilder {
    fun buildFormulaFilm(
        input: CustomFormulaFilmInput,
        filmId: String,
        profileId: String,
    ): FilmIdentity? {
        val label = input.filmLabel.trim()
        if (label.isEmpty() || input.iso <= 0) return null

        val guardOk = CustomFilmFormulaGuard.passesUsableRangeCheck(
            CustomFilmFormulaGuard.UsableRangeInput(
                exponent = input.exponent,
                referenceMeteredTimeSeconds = input.referenceMeteredTimeSeconds,
                coefficientSeconds = input.coefficientSeconds,
                offsetSeconds = input.offsetSeconds,
                noCorrectionThroughSeconds = input.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds = input.sourceRangeThroughSeconds,
            ),
        )
        if (!guardOk) return null

        val formula = ReciprocityFormula(
            formulaFamily = FormulaFamily.modifiedSchwarzschild,
            coefficientSeconds = input.coefficientSeconds,
            referenceMeteredTimeSeconds = input.referenceMeteredTimeSeconds,
            exponent = input.exponent,
            offsetSeconds = input.offsetSeconds,
            noCorrectionThroughSeconds = input.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds = input.sourceRangeThroughSeconds,
        )
        return assemble(
            filmId = filmId,
            profileId = profileId,
            profileName = input.profileName.trim().ifEmpty { label },
            rule = ReciprocityRule(kind = ReciprocityRuleKind.formula, formula = FormulaReciprocityRule(formula)),
            label = label,
            iso = input.iso,
            manufacturer = input.manufacturer,
            notes = input.notes,
            sourceType = input.sourceType,
            referenceUrl = input.referenceUrl,
            referenceTableFilmId = input.referenceTableFilmId,
        )
    }

    /**
     * Builds a well-formed custom table film from anchor pairs. Returns null
     * when the inputs fail the domain's table contract (≥2 strictly-increasing
     * non-shortening anchors, 0 < no-correction knee < first anchor).
     */
    fun buildTableFilm(
        input: CustomTableFilmInput,
        filmId: String,
        profileId: String,
    ): FilmIdentity? {
        val label = input.filmLabel.trim()
        if (label.isEmpty() || input.iso <= 0) return null
        if (input.anchors.size < 2) return null

        val anchors = input.anchors.map { TableAnchor(meteredSeconds = it.first, correctedSeconds = it.second) }
        val sourceRange = anchors.maxOf { it.meteredSeconds }
        val rule = TableInterpolationReciprocityRule(
            anchors = anchors,
            noCorrectionThroughSeconds = input.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds = sourceRange,
        )
        if (!rule.hasValidParameters || rule.noCorrectionThroughSeconds <= 0) return null

        return assemble(
            filmId = filmId,
            profileId = profileId,
            profileName = input.profileName.trim().ifEmpty { label },
            rule = ReciprocityRule(kind = ReciprocityRuleKind.tableInterpolation, tableInterpolation = rule),
            label = label,
            iso = input.iso,
            manufacturer = input.manufacturer,
            notes = input.notes,
            sourceType = input.sourceType,
            referenceUrl = input.referenceUrl,
        )
    }

    /** Shared assembly: wraps a validated rule into a custom `.userDefined` film. */
    private fun assemble(
        filmId: String,
        profileId: String,
        profileName: String,
        rule: ReciprocityRule,
        label: String,
        iso: Int,
        manufacturer: String?,
        notes: String?,
        sourceType: CustomProfileSourceType,
        referenceUrl: String?,
        referenceTableFilmId: String? = null,
    ): FilmIdentity {
        val trimmedManufacturer = manufacturer?.trim()?.takeIf { it.isNotEmpty() }
        val noteList = notes?.trim()?.takeIf { it.isNotEmpty() }?.let { listOf(it) } ?: emptyList()
        val profile = ReciprocityProfile(
            id = profileId,
            name = profileName,
            source = customSourceProvenance(),
            rules = listOf(rule),
            userMetadata = UserEditableMetadata(
                notes = noteList,
                customSourceType = sourceType,
                customManufacturer = trimmedManufacturer,
                referenceURL = referenceUrl?.trim()?.takeIf { it.isNotEmpty() },
                referenceTableFilmID = referenceTableFilmId?.trim()?.takeIf { it.isNotEmpty() },
            ),
        )
        // Compose the canonical name from manufacturer + label so every
        // downstream surface reads the full film name; the top-level
        // manufacturer stays null so the picker keeps custom rows separate.
        val canonical = trimmedManufacturer?.let { "$it $label" } ?: label
        return FilmIdentity(
            id = filmId,
            kind = FilmIdentityKind.custom,
            canonicalStockName = canonical,
            aliases = emptyList(),
            iso = iso,
            productionStatus = FilmProductionStatus.unknown,
            profiles = listOf(profile),
            userMetadata = UserEditableMetadata(
                customSourceType = CustomProfileSourceType.userDefined,
                customManufacturer = trimmedManufacturer,
            ),
        )
    }

    private fun customSourceProvenance(): ReciprocitySourceProvenance = ReciprocitySourceProvenance(
        kind = ReciprocitySourceKind.userDefined,
        authority = ReciprocityAuthority.userDefined,
        confidence = ReciprocityConfidence.unknown,
        publisher = "",
    )
}
