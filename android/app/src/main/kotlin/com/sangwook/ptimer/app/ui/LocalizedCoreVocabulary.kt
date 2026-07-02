// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.sangwook.ptimer.R
import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType

// Display-boundary localization for canonical English vocabulary produced by
// the pure-Kotlin core (which has no Android resource access). Core keeps
// emitting locale-stable English; these resolvers map the known canonical
// values to string resources at render time and pass unknown values through
// unchanged. Semantic state, persistence, comparisons, and ordering never
// see a localized string (PTIMER-192/194 safety).

/** Resource for a canonical core vocabulary string; null → no mapping, render as-is. */
@StringRes
internal fun coreVocabularyRes(text: String): Int? = when (text) {
    // Confidence short labels (ReciprocityConfidencePresentationMapper.shortLabel)
    "Formula-derived" -> R.string.recip_value_formula_derived
    "Table-derived" -> R.string.recip_value_table_derived
    "No correction" -> R.string.recip_value_no_correction
    "No quantified prediction" -> R.string.recip_value_no_quantified_prediction
    "Outside guidance" -> R.string.recip_value_outside_guidance
    // Source / calculation model labels (ReciprocityDetailsPresenter)
    "Manufacturer formula" -> R.string.recip_value_manufacturer_formula
    "Manufacturer table" -> R.string.recip_value_manufacturer_table
    "Manufacturer range guidance" -> R.string.recip_value_manufacturer_range_guidance
    "Manufacturer limited guidance" -> R.string.recip_value_manufacturer_limited_guidance
    "Limited guidance" -> R.string.recip_value_limited_guidance
    "Guarded formula" -> R.string.recip_value_guarded_formula
    "App-derived guarded formula" -> R.string.recip_value_app_derived_guarded_formula
    "Unsupported" -> R.string.recip_value_unsupported
    "User-defined" -> R.string.recip_value_user_defined
    // Authority labels (ReciprocityDetailsPresenter subtitle)
    "Official guidance" -> R.string.recip_value_official_guidance
    "Unofficial practical" -> R.string.recip_value_unofficial_practical
    // Details values
    "Reciprocity Details" -> R.string.recip_details_title
    "No corrected value" -> R.string.shooting_no_corrected_value
    "No official quantified prediction is available beyond this range." ->
        R.string.recip_detail_no_official_beyond_range
    else -> null
}

/** Localized form of a core-produced display string; unmapped values pass through. */
@Composable
internal fun localizedCoreText(text: String): String =
    coreVocabularyRes(text)?.let { stringResource(it) } ?: text

/**
 * Details subtitle is "film name · label" where only the trailing label
 * (authority or model name) can be vocabulary; the film name never localizes.
 */
@Composable
internal fun localizedDetailsSubtitle(subtitle: String): String {
    val sep = " · "
    val idx = subtitle.lastIndexOf(sep)
    if (idx < 0) return subtitle
    val res = coreVocabularyRes(subtitle.substring(idx + sep.length)) ?: return subtitle
    return subtitle.substring(0, idx) + sep + stringResource(res)
}

// Canonical exposure-source tokens captured in TimerIdentity.subtitle
// (CalculatorController.identity). Display-only labels; the stored subtitle
// stays canonical so old and new records render alike.
private val TIMER_SOURCE_TOKENS =
    listOf("Calculated", "Adjusted Exposure", "Corrected Exposure", "Target Exposure")

/** The canonical source token a timer subtitle starts with, or null. */
internal fun timerSubtitleSource(subtitle: String): String? =
    TIMER_SOURCE_TOKENS.firstOrNull { subtitle.startsWith("$it ") }

/** Display label for a canonical timer exposure-source token; null → unmapped. */
@StringRes
internal fun timerSourceRes(source: String): Int? = when (source) {
    "Calculated" -> R.string.timer_source_calculated
    "Adjusted Exposure" -> R.string.timer_source_adjusted
    // iOS labels the corrected-exposure timer basis "Reciprocity" (PTIMER-183).
    "Corrected Exposure" -> R.string.shooting_reciprocity
    "Target Exposure" -> R.string.timer_source_target
    else -> null
}

/** Timer subtitle ("source value") with the leading source token localized. */
@Composable
internal fun localizedTimerSubtitle(subtitle: String): String {
    val source = timerSubtitleSource(subtitle) ?: return subtitle
    val res = timerSourceRes(source) ?: return subtitle
    return stringResource(res) + subtitle.removePrefix(source)
}

/** Canonical no-film cue captured in TimerIdentity (CalculatorController.identity). */
internal const val NO_FILM_SENTINEL = "No film"

/** Film cue with the canonical "No film" sentinel localized. */
@Composable
internal fun localizedFilmName(filmName: String): String =
    if (filmName == NO_FILM_SENTINEL) stringResource(R.string.no_film) else filmName

/** Timer title ("camera · film") with a trailing "No film" cue localized. */
@Composable
internal fun localizedTimerTitle(title: String): String =
    if (title.endsWith(" · $NO_FILM_SENTINEL")) {
        title.removeSuffix(NO_FILM_SENTINEL) + stringResource(R.string.no_film)
    } else {
        title
    }

/** Display label for a custom-profile source classification. */
@Composable
internal fun localizedSourceTypeLabel(type: CustomProfileSourceType): String =
    coreVocabularyRes(type.displayLabel)?.let { stringResource(it) } ?: type.displayLabel
