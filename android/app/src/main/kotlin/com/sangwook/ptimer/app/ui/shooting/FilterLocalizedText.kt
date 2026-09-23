// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.FilterReferenceVocabulary
import com.sangwook.ptimer.app.vm.FilterRejectionNotice
import com.sangwook.ptimer.app.vm.FilterSummaryReferencePresenter
import com.sangwook.ptimer.app.vm.FilterRowTypeCategory
import com.sangwook.ptimer.app.vm.FilterWheelPresenter
import com.sangwook.ptimer.app.vm.FilterWheelRowUiState
import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode

// Display-boundary localization for the mixed Filter Stack (FILTER-A11Y-003).
// The state layer emits structured rows and canonical English vocabulary; the
// wheel labels, the status region, and every announcement compose their text
// from string resources here, so English and Korean expose equivalent
// terminology, modes, and disabled reasons.

/** Canonical source name localized: `Standard` and the unresolved
 *  `Filter Set` fallback; a user-defined set name passes through. */
@Composable
internal fun localizedSourceName(name: String): String = when (name) {
    FilterWheelPresenter.STANDARD_SOURCE_NAME -> stringResource(R.string.filter_source_standard)
    FilterWheelPresenter.FALLBACK_FILTER_SET_NAME -> stringResource(R.string.filter_source_filter_set)
    else -> name
}

/** `N stops` / `1 stop`. */
@Composable
internal fun filterStopsText(stops: Double): String {
    val value = FilterWheelPresenter.decimalStopsValue(stops)
    return if (value == "1") {
        stringResource(R.string.filter_one_stop)
    } else {
        stringResource(R.string.filter_stops, value)
    }
}

/** The app-global notation rendering of a canonical stops value as a
 *  standalone phrase: `9 stops`, `OD 2.7`, `ND512`. */
@Composable
internal fun filterNotationText(stops: Double, mode: NDNotationMode): String {
    val value = NDNotationFormatter.display(stops, mode).value
    return when (mode) {
        NDNotationMode.STOPS -> if (value == "1") {
            stringResource(R.string.filter_one_stop)
        } else {
            stringResource(R.string.filter_stops, value)
        }
        NDNotationMode.OPTICAL_DENSITY -> stringResource(R.string.filter_value_od, value)
        NDNotationMode.FILTER_FACTOR -> stringResource(R.string.filter_value_nd, value)
    }
}

/** The registered Fixed / GND value as the user entered it. */
@Composable
internal fun filterRegisteredValueText(value: FilterRegisteredValue): String {
    val number = FilterWheelPresenter.trimmedNumber(value.value)
    return when (value.unit) {
        FilterValueUnit.stops -> filterStopsText(value.value)
        FilterValueUnit.opticalDensity -> stringResource(R.string.filter_value_od, number)
        FilterValueUnit.filterFactor -> stringResource(R.string.filter_value_nd, number)
    }
}

@Composable
internal fun localizedGndModeName(mode: GndCalculationMode): String = when (mode) {
    GndCalculationMode.recordOnly -> stringResource(R.string.filter_mode_record_only)
    GndCalculationMode.applyFullValue -> stringResource(R.string.filter_mode_apply_full_value)
}

/**
 * Persistent type / mode label above a wheel viewport (FILTER-STACK-007):
 * `ND`, `CPL`, `GND REC`, `GND FULL`, `EMPTY`. The tokens are identical
 * in every locale but still resolve through resources so a future locale
 * can adjust them.
 */
@Composable
internal fun filterTypeLabelText(row: FilterWheelRowUiState): String = when (row.typeCategory) {
    FilterRowTypeCategory.nd -> stringResource(R.string.filter_type_nd)
    FilterRowTypeCategory.cpl -> stringResource(R.string.filter_type_cpl)
    FilterRowTypeCategory.gnd -> {
        val mode = when (row.gndMode) {
            GndCalculationMode.applyFullValue -> stringResource(R.string.filter_type_gnd_full)
            else -> stringResource(R.string.filter_type_gnd_rec)
        }
        "${stringResource(R.string.filter_type_gnd)} $mode"
    }
    FilterRowTypeCategory.empty -> stringResource(R.string.filter_type_empty)
}

/**
 * The moving wheel's detail (FILTER-STACK-007/008): full item name,
 * original registered representation, calculation mode, and active
 * contribution. A Fixed item registered in stops would print its value
 * twice, so the contribution is shown once in that case.
 */
@Composable
internal fun filterRowDetailText(row: FilterWheelRowUiState, mode: NDNotationMode): String {
    when (row.selection) {
        is FilterWheelSelection.Standard -> return listOf(
            stringResource(R.string.filter_source_standard),
            filterNotationText(row.selection.stops, mode),
        ).joinToString(DetailSeparator)

        is FilterWheelSelection.Empty -> return stringResource(R.string.filter_empty_detail)

        is FilterWheelSelection.Item -> Unit
    }
    val name = row.itemName ?: stringResource(R.string.filter_item_fallback)
    val contribution = filterStopsText(row.contributionStops)
    val registered = row.cplLossStops
        ?.let { stringResource(R.string.filter_value_cpl, FilterWheelPresenter.decimalStopsValue(it)) }
        ?: row.registeredValue?.let { filterRegisteredValueText(it) }
        ?: filterStopsText(row.registeredStops)
    val modeName = row.gndMode?.let { localizedGndModeName(it) }
    val segments = buildList {
        add(name)
        add(registered)
        if (modeName != null) add(modeName)
        if (registered != contribution || modeName != null) add(contribution)
    }
    return segments.joinToString(DetailSeparator)
}

/**
 * The wheel element's dynamic TalkBack value (FILTER-A11Y-005): the
 * committed row's concise identity — item or Empty, type or calculation
 * mode, canonical contribution — followed by the current complete Total.
 */
@Composable
internal fun filterRowAccessibilityValue(row: FilterWheelRowUiState, totalText: String): String {
    val segments = when (row.selection) {
        is FilterWheelSelection.Standard -> listOf(
            stringResource(R.string.filter_source_standard),
            stringResource(R.string.filter_type_nd),
            filterStopsText(row.contributionStops),
        )

        is FilterWheelSelection.Empty -> listOf(
            stringResource(R.string.filter_empty),
            filterStopsText(0.0),
        )

        is FilterWheelSelection.Item -> {
            val semanticType = when (row.typeCategory) {
                FilterRowTypeCategory.cpl -> stringResource(R.string.filter_type_cpl)
                FilterRowTypeCategory.gnd -> "${stringResource(R.string.filter_type_gnd)}, " +
                    localizedGndModeName(row.gndMode ?: GndCalculationMode.recordOnly)
                else -> stringResource(R.string.filter_kind_fixed)
            }
            listOf(
                row.itemName ?: stringResource(R.string.filter_item_fallback),
                semanticType,
                filterStopsText(row.contributionStops),
            )
        }
    }
    val unavailability = row.unavailability?.let { filterRejectionText(it) }
    return (segments + listOfNotNull(unavailability) + totalText).joinToString(", ")
}

/** Localized total for the status region and the wheel value. */
@Composable
internal fun filterTotalText(totalStopsText: String, isMaximum: Boolean): String =
    if (isMaximum) {
        stringResource(R.string.nd_total_stops_maximum, totalStopsText)
    } else {
        stringResource(R.string.nd_total_stops, totalStopsText)
    }

@Composable
internal fun filterRejectionText(rejection: FilterStackRejection): String = when (rejection) {
    FilterStackRejection.exceedsTotalLimit -> stringResource(R.string.filter_reject_exceeds_limit)
    FilterStackRejection.itemAlreadyMounted -> stringResource(R.string.filter_reject_already_mounted)
    FilterStackRejection.unresolvedSelection -> stringResource(R.string.filter_reject_unavailable)
}

/** Every refusal reason resolved at once, so a gesture or an assistive
 *  adjustment can announce one without a composable lookup. */
@Composable
internal fun filterRejectionTexts(): Map<FilterStackRejection, String> = mapOf(
    FilterStackRejection.exceedsTotalLimit to stringResource(R.string.filter_reject_exceeds_limit),
    FilterStackRejection.itemAlreadyMounted to stringResource(R.string.filter_reject_already_mounted),
    FilterStackRejection.unresolvedSelection to stringResource(R.string.filter_reject_unavailable),
)

@Composable
internal fun filterAddUnavailabilityText(reason: FilterAddUnavailability): String = when (reason) {
    FilterAddUnavailability.stackFull -> stringResource(R.string.filter_add_stack_full)
    FilterAddUnavailability.noSelectableValue -> stringResource(R.string.filter_add_no_standard_value)
    FilterAddUnavailability.unknownFilterSet -> stringResource(R.string.filter_add_unknown_set)
    FilterAddUnavailability.filterSetHasNoItems -> stringResource(R.string.filter_add_set_has_no_items)
    FilterAddUnavailability.allItemsMounted -> stringResource(R.string.filter_add_all_items_mounted)
    FilterAddUnavailability.exceedsTotalLimit -> stringResource(R.string.filter_reject_exceeds_limit)
}

/** A refused wheel change or a refused addition, whichever the notice carries. */
@Composable
internal fun filterRejectionNoticeText(notice: FilterRejectionNotice): String =
    notice.rejection?.let { filterRejectionText(it) }
        ?: notice.addUnavailability?.let { filterAddUnavailabilityText(it) }
        ?: stringResource(R.string.filter_reject_unavailable)

/** Localized color name — color is never the only identifying cue. */
@Composable
internal fun filterColorName(token: FilterSetColor): String = stringResource(
    when (token) {
        FilterSetColor.red -> R.string.filter_color_red
        FilterSetColor.orange -> R.string.filter_color_orange
        FilterSetColor.yellow -> R.string.filter_color_yellow
        FilterSetColor.green -> R.string.filter_color_green
        FilterSetColor.mint -> R.string.filter_color_mint
        FilterSetColor.teal -> R.string.filter_color_teal
        FilterSetColor.cyan -> R.string.filter_color_cyan
        FilterSetColor.blue -> R.string.filter_color_blue
        FilterSetColor.indigo -> R.string.filter_color_indigo
        FilterSetColor.purple -> R.string.filter_color_purple
        FilterSetColor.pink -> R.string.filter_color_pink
        FilterSetColor.brown -> R.string.filter_color_brown
    },
)

/** Behavior kind as the editor's segmented control and the inventory
 *  rows name it (FILTER-ITEM-003). */
@Composable
internal fun localizedFilterKindName(kind: FilterItemKind): String = stringResource(
    when (kind) {
        FilterItemKind.fixed -> R.string.filter_kind_fixed
        FilterItemKind.cpl -> R.string.filter_kind_cpl
        FilterItemKind.gnd -> R.string.filter_kind_gnd
    },
)

/**
 * Inventory-row detail for one physical filter: kind, registered
 * representation, and — when the registered unit is not stops — the
 * canonical conversion. `Fixed · OD 0.9 · 3 stops`, `GND · ND8 ·
 * 3 stops`, `CPL · 1 / 1.5 / 2 stops`.
 */
@Composable
internal fun filterItemDetailText(item: FilterItem): String {
    val kind = localizedFilterKindName(item.behavior.kind)
    val detail = when (val behavior = item.behavior) {
        is FilterItemBehavior.Fixed -> registeredWithConversionText(behavior.value)
        is FilterItemBehavior.Gnd -> registeredWithConversionText(behavior.value)
        is FilterItemBehavior.Cpl -> {
            val list = behavior.choices.shootingChoices
                .joinToString(" / ") { FilterWheelPresenter.decimalStopsValue(it) }
            stringResource(R.string.filter_stops, list)
        }
    }
    return "$kind$DetailSeparator$detail"
}

/** `OD 0.9 · 3 stops`; a value registered in stops reads once. */
@Composable
private fun registeredWithConversionText(value: FilterRegisteredValue): String {
    val original = filterRegisteredValueText(value)
    val stops = value.canonicalStops
    if (value.unit == FilterValueUnit.stops || stops == null) return original
    return original + DetailSeparator + filterStopsText(stops)
}

/**
 * The words the timer's start-time reference string is written in
 * (FILTER-PERSIST-003), resolved from resources so the capture lands in
 * the user's language. Read outside Compose at timer start; the Timer
 * list's legacy fallback reads the same words through [LocalContext].
 */
internal fun filterReferenceVocabulary(resources: Resources) = FilterReferenceVocabulary(
    standardSource = resources.getString(R.string.filter_source_standard),
    fallbackFilterSet = resources.getString(R.string.filter_source_filter_set),
    fallbackItem = resources.getString(R.string.filter_item_fallback),
    oneStop = resources.getString(R.string.filter_one_stop),
    stopsFormat = resources.getString(R.string.filter_stops),
    opticalDensityFormat = resources.getString(R.string.filter_value_od),
    filterFactorFormat = resources.getString(R.string.filter_value_nd),
    recordOnlyMode = resources.getString(R.string.filter_mode_record_only),
    applyFullValueMode = resources.getString(R.string.filter_mode_apply_full_value),
)

/**
 * Composes the Timer list's Filter Set reference from the IMMUTABLE
 * captured summary. This is the FALLBACK path only: a timer started by
 * this build carries the string it captured at start, and the Timer
 * list shows that. A payload written before the string existed — or one
 * whose string did not survive — still gets a line here, from the same
 * algorithm and the current language, and never from the live inventory.
 */
@Composable
internal fun localizedFilterReferenceText(summary: List<FilterSummaryEntry>): String? =
    FilterSummaryReferencePresenter.referenceText(
        summary,
        filterReferenceVocabulary(LocalContext.current.resources),
    )

/** Separator between the segments of one status detail. */
internal const val DetailSeparator: String = " · "
