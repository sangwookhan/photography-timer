package com.sangwook.ptimer.core.reciprocity

import com.sangwook.ptimer.core.exposure.ExposureCalculator
import java.util.Locale

/** Colour intent for the status line, mapped to theme colours by the view. */
enum class ReciprocityStatusTone { success, info, warning, neutral }

/** A selectable reciprocity model (the in-Details "Official table | App formula" toggle). */
data class ReciprocityModelOption(val id: String, val label: String)

/**
 * Textual display-state for the Reciprocity Details surface, structured to
 * match the iOS Film Details sheet: subtitle, the current result (Adjusted /
 * Corrected / Status), the reciprocity model (Source + Calculation), and the
 * formula equation. The iOS formula-curve graph is added separately. No
 * summary/guidance prose walls — iOS keeps this lean. (iOS:
 * FilmModeDetailsPresenter, textual subset.)
 */
data class ReciprocityDetailsDisplayState(
    val title: String,
    val subtitle: String,
    /** Model toggle options (empty for single-model films); see iOS "Official table | App formula". */
    val modelOptions: List<ReciprocityModelOption>,
    val selectedModelId: String,
    val adjustedShutterText: String,
    val correctedExposureText: String,
    val statusText: String,
    val statusTone: ReciprocityStatusTone,
    /** Explanatory sentence under the status (iOS), shown only for beyond-range / limited / warned results. */
    val statusDetailText: String? = null,
    val sourceText: String,
    val calculationText: String,
    val equationText: String?,
    /** User-entered provenance for custom films (null/blank → row hidden). */
    val notesText: String? = null,
    val referenceUrlText: String? = null,
    /** Normalized curve-graph geometry; null for profiles with no quantified curve. */
    val graph: ReciprocityGraph?,
    /** Published "Source reference" rows (metered exposure → correction); empty when the profile has no source evidence. */
    val sourceReferenceRows: List<ReciprocityReferenceRow> = emptyList(),
    /** "Guidance boundary" rows (a metered exposure the source flags as not recommended). */
    val guidanceBoundaryRows: List<ReciprocityReferenceRow> = emptyList(),
    /** Glossary lines explaining the reference annotations (color correction / stop-signal). */
    val legendLines: List<String> = emptyList(),
    /** Source citation ("publisher · title · Version X"); null when the profile has no published source. */
    val sourceCitationText: String? = null,
    /** Source reference link/citation line (often a URL); rendered as a link under the citation. */
    val sourceCitationLink: String? = null,
)

/**
 * Pure transform from a resolved reciprocity result + its film/profile context
 * into the Details display-state. Duration formatting is injected so the
 * presenter stays Foundation-free. (iOS: FilmModeDetailsPresenter.)
 */
object ReciprocityDetailsPresenter {
    private val referenceCalculator = ExposureCalculator()

    fun make(
        film: FilmIdentity,
        profile: ReciprocityProfile,
        result: ReciprocityResult,
        adjustedShutterSeconds: Double,
        formatDuration: (Double) -> String,
    ): ReciprocityDetailsDisplayState {
        val confidence = result.confidencePresentation
        val corrected = result.calculatedCorrectedSeconds
        val basis = profile.effectiveModelBasis

        // Selectable models (the in-Details toggle) — only when the film has more
        // than one. The chip label is `selectorLabel ?: name`, matching the main
        // screen's model chips.
        val pickerOptions = film.profiles.firstOrNull()
            ?.let { AlternateReciprocityModels.modelPickerOrder(it, film.id) }
            ?: emptyList()
        val modelOptions = if (pickerOptions.size > 1) {
            pickerOptions.map { ReciprocityModelOption(it.id, it.selectorLabel ?: it.name) }
        } else {
            emptyList()
        }
        val activeModelLabel = modelOptions.firstOrNull { it.id == profile.id }?.label

        // Custom-profile provenance (iOS surfaces these in the Details sheet too).
        val meta = profile.userMetadata
        val notesText = meta?.notes?.takeIf { it.isNotEmpty() }?.joinToString("\n")
        val referenceUrlText = meta?.referenceURL?.trim()?.takeIf { it.isNotEmpty() }

        // Source reference table (metered exposure → published correction, with
        // the color filter / development note as an indented sub-line) plus the
        // guidance-boundary rows and the glossary explaining them — matching iOS
        // Film Details. The values stay tied to their metered exposure rather
        // than a context-free list.
        // The Source reference table labels metered exposures in iOS's compact
        // shutter form ("64s", "100s", "1/10s") — not the hms result formatter —
        // so feed it formatShutter (iOS passes calculator.formatShutter here too).
        val reference = ReciprocitySourceReferencePresenter.rows(profile, referenceCalculator::formatShutter)
        val legendLines = ReciprocityDetailsLegendPresenter.legendLines(profile)

        // Source citation block (iOS "Sources"): "publisher · title · Version X"
        // plus the citation line (often a URL) rendered as a link. Shown for
        // every published profile, formula or table.
        // Status detail sentence — faithful port of iOS
        // ReciprocityDetailsVocabularyPresenter.summaryDetailText: per-state
        // wording (beyond-source-range / outside-guidance / table-extrapolation /
        // limited-guidance), led by the manufacturer stop-signal when a
        // not-recommended boundary has been reached. Nothing for clean
        // within-range (no-correction / formula-derived) results.
        val statusDetailText = statusDetail(profile, confidence.category, corrected, adjustedShutterSeconds)

        val src = profile.source
        val sourceCitationText = listOfNotNull(
            src.publisher.takeIf { it.isNotBlank() },
            src.title?.takeIf { it.isNotBlank() },
            src.sourceVersion?.takeIf { it.isNotBlank() }?.let { "Version $it" },
        ).joinToString(" · ").takeIf { it.isNotEmpty() }
        val sourceCitationLink = src.citation?.trim()?.takeIf { it.isNotEmpty() }

        return ReciprocityDetailsDisplayState(
            title = "Reciprocity Details",
            subtitle = subtitle(film, activeModelLabel),
            modelOptions = modelOptions,
            selectedModelId = profile.id,
            adjustedShutterText = formatDuration(adjustedShutterSeconds),
            correctedExposureText = corrected?.let(formatDuration) ?: "No corrected value",
            statusText = confidence.shortLabel,
            statusTone = toneFor(confidence.category),
            statusDetailText = statusDetailText,
            // Prefer the user's chosen source classification for custom profiles
            // (Personal test / Community reference …); presets fall back to the
            // derived source-model label.
            sourceText = meta?.customSourceType?.displayLabel ?: sourceLabel(basis.sourceModel),
            calculationText = calculationLabel(basis),
            equationText = equation(profile),
            notesText = notesText,
            referenceUrlText = referenceUrlText,
            graph = ReciprocityGraphPresenter.make(profile, adjustedShutterSeconds),
            sourceReferenceRows = reference.sourceReference,
            guidanceBoundaryRows = reference.guidanceBoundary,
            legendLines = legendLines,
            sourceCitationText = sourceCitationText,
            sourceCitationLink = sourceCitationLink,
        )
    }

    /**
     * iOS `ReciprocityDetailsVocabularyPresenter.summaryDetailText`: the
     * explanatory sentence under the Status line. Unofficial profiles lead with
     * their authority caveat; user-defined provenance lives in its own section
     * (only the table-beyond-range case adds a sentence); official profiles use
     * the per-category wording, led by the manufacturer stop-signal when a
     * not-recommended boundary is reached.
     */
    private fun statusDetail(
        profile: ReciprocityProfile,
        category: ReciprocityConfidenceCategory,
        correctedSeconds: Double?,
        adjustedShutterSeconds: Double,
    ): String? {
        if (profile.source.authority == ReciprocityAuthority.unofficial) {
            profile.notes.firstNotNullOfOrNull { it.trim().takeIf { t -> t.isNotEmpty() } }?.let { return it }
        }
        if (profile.source.authority == ReciprocityAuthority.userDefined) {
            return if (category == ReciprocityConfidenceCategory.unsupported &&
                correctedSeconds != null && usesTableInterpolation(profile)
            ) {
                tableBeyondSourceRangeDetail(profile)
            } else {
                null
            }
        }
        return when (category) {
            ReciprocityConfidenceCategory.unsupported -> {
                val generic = if (correctedSeconds != null) {
                    when {
                        usesTableInterpolation(profile) -> tableBeyondSourceRangeDetail(profile)
                        isConvertedFormulaProfile(profile) ->
                            "Current input is beyond the manufacturer source range. " +
                                "The corrected value is a formula prediction past the published reference."
                        else ->
                            "Current input is outside manufacturer guidance. " +
                                "The corrected value is a formula prediction outside the supported range."
                    }
                } else {
                    "Current input is outside the supported range and no quantified corrected point is available."
                }
                val stopSignal = ReciprocitySourceEvidenceClassifier
                    .reachedStopSignalMessages(profile, adjustedShutterSeconds)
                    .firstOrNull()
                    ?.let { "Manufacturer guidance: $it" }
                if (stopSignal != null) "$stopSignal $generic" else generic
            }
            ReciprocityConfidenceCategory.limitedGuidance ->
                "No official quantified prediction is available beyond this range."
            ReciprocityConfidenceCategory.noCorrection,
            ReciprocityConfidenceCategory.formulaDerived -> null
        }
    }

    private fun tableBeyondSourceRangeDetail(profile: ReciprocityProfile): String =
        when (profile.source.authority) {
            ReciprocityAuthority.official ->
                "Current input is beyond the published source table. " +
                    "The corrected value is extrapolated past the official anchors."
            ReciprocityAuthority.unofficial ->
                "Current input is beyond this table's source range. " +
                    "The corrected value is extrapolated past the last community table anchor."
            else ->
                "Current input is beyond this table's source range. " +
                    "The corrected value is extrapolated past the last table anchor."
        }

    private fun usesTableInterpolation(profile: ReciprocityProfile): Boolean =
        profile.rules.any { it.kind == ReciprocityRuleKind.tableInterpolation }

    /** iOS `ReciprocityProfile.isConvertedFormulaProfile`. */
    private fun isConvertedFormulaProfile(profile: ReciprocityProfile): Boolean {
        val hasFormula = profile.rules.any { it.kind == ReciprocityRuleKind.formula }
        return hasFormula &&
            profile.sourceEvidence.isNotEmpty() &&
            profile.source.authority == ReciprocityAuthority.official &&
            (
                profile.source.kind == ReciprocitySourceKind.manufacturerPublished ||
                    profile.source.kind == ReciprocitySourceKind.manufacturerArchive
                )
    }

    private fun subtitle(film: FilmIdentity, activeModelLabel: String?): String {
        val name = film.canonicalStockName.trim()
        // Multi-model films show the active model name (matching iOS, where the
        // model toggle lives in this sheet); single-model films show the
        // authority label ("Official guidance").
        val label = activeModelLabel ?: authorityLabel(film.profiles.firstOrNull()?.source?.authority ?: ReciprocityAuthority.unknown)
        return if (label.isBlank()) name else "$name · $label"
    }

    private fun authorityLabel(authority: ReciprocityAuthority): String = when (authority) {
        ReciprocityAuthority.official -> "Official guidance"
        ReciprocityAuthority.unofficial -> "Unofficial practical"
        ReciprocityAuthority.userDefined -> "User-supplied"
        ReciprocityAuthority.unknown -> ""
    }

    private fun toneFor(category: ReciprocityConfidenceCategory): ReciprocityStatusTone = when (category) {
        ReciprocityConfidenceCategory.noCorrection -> ReciprocityStatusTone.success
        ReciprocityConfidenceCategory.formulaDerived -> ReciprocityStatusTone.info
        ReciprocityConfidenceCategory.limitedGuidance -> ReciprocityStatusTone.warning
        ReciprocityConfidenceCategory.unsupported -> ReciprocityStatusTone.warning
    }

    private fun sourceLabel(model: ReciprocitySourceModel): String = when (model) {
        ReciprocitySourceModel.manufacturerFormula -> "Manufacturer formula"
        ReciprocitySourceModel.manufacturerTable -> "Manufacturer table"
        ReciprocitySourceModel.manufacturerGraphTable -> "Manufacturer graph"
        ReciprocitySourceModel.manufacturerRangeGuidance -> "Manufacturer range guidance"
        ReciprocitySourceModel.manufacturerLimitedGuidance -> "Manufacturer limited guidance"
        ReciprocitySourceModel.practicalCommunityGuidance -> "Community guidance"
        ReciprocitySourceModel.userDefined -> "User-defined"
        ReciprocitySourceModel.unknown -> "Unknown"
    }

    /**
     * Calculation method label. A guarded formula derived from a manufacturer
     * TABLE / GRAPH source is app-derived ("App-derived guarded formula"); a
     * guard of a published manufacturer formula stays "Guarded formula". Mirrors
     * iOS ReciprocityModelMetadataPresenter.calculationMethodLabel.
     */
    private fun calculationLabel(basis: ReciprocityProfileModelBasis): String = when (basis.calculationModel) {
        ReciprocityCalculationModel.guardedFormula -> when (basis.sourceModel) {
            ReciprocitySourceModel.manufacturerTable,
            ReciprocitySourceModel.manufacturerGraphTable -> "App-derived guarded formula"
            else -> "Guarded formula"
        }
        ReciprocityCalculationModel.limitedGuidance -> "Limited guidance"
        ReciprocityCalculationModel.unsupported -> "Unsupported"
        ReciprocityCalculationModel.tableLookup -> "Table lookup"
        ReciprocityCalculationModel.tableLogLogInterpolation -> "Log-log table interpolation"
    }

    /**
     * Modified-Schwarzschild equation for a formula profile. The common
     * `a = 1, t_ref = 1 s, b = 0` case collapses to the clean `Tc = Tm^p`
     * iOS shows; otherwise the fuller form is rendered. Null for non-formula
     * profiles.
     */
    private fun equation(profile: ReciprocityProfile): String? {
        val f = profile.rules.firstNotNullOfOrNull { it.formula }?.formula ?: return null
        val simple = f.coefficientSeconds == 1.0 && f.referenceMeteredTimeSeconds == 1.0 && f.offsetSeconds == 0.0
        if (simple) return "Tc = Tm^${trimNumber(f.exponent)}"
        val base = "Tc = ${trimNumber(f.coefficientSeconds)}·(Tm / ${trimNumber(f.referenceMeteredTimeSeconds)} s)^${trimNumber(f.exponent)}"
        return if (f.offsetSeconds != 0.0) "$base + ${trimNumber(f.offsetSeconds)} s" else base
    }

    private fun trimNumber(value: Double): String {
        if (value == value.toLong().toDouble()) return value.toLong().toString()
        return String.format(Locale.ROOT, "%.4g", value).trimEnd('0').trimEnd('.')
    }
}
