// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterValueUnit

/**
 * The words the reference string is built from, supplied by the caller
 * so the same algorithm serves the localized start-time capture and the
 * canonical-English default that unit tests read. The format entries
 * carry a single `%1$s` placeholder for the already-trimmed number.
 */
data class FilterReferenceVocabulary(
    val standardSource: String,
    val fallbackFilterSet: String,
    val fallbackItem: String,
    val oneStop: String,
    val stopsFormat: String,
    val opticalDensityFormat: String,
    val filterFactorFormat: String,
    val recordOnlyMode: String,
    val applyFullValueMode: String,
) {
    companion object {
        /** The state layer's canonical vocabulary; the display boundary
         *  supplies the user's language in production. */
        val canonicalEnglish = FilterReferenceVocabulary(
            standardSource = "Standard",
            fallbackFilterSet = "Filter Set",
            fallbackItem = "Filter",
            oneStop = "1 stop",
            stopsFormat = "%1\$s stops",
            opticalDensityFormat = "OD %1\$s",
            filterFactorFormat = "ND%1\$s",
            recordOnlyMode = "Record only",
            applyFullValueMode = "Apply full value",
        )
    }
}

/**
 * Builds the human-readable reference string a timer keeps beside its
 * calculation record (FILTER-PERSIST-003): Filter Set and Filter Item
 * names, registered representations, and calculation modes as they
 * stood when the timer started. Descriptive only — generated once at
 * start from the captured summary, stored with the timer, and never
 * re-derived from the live inventory, so a later rename, reorder, edit
 * or deletion cannot rewrite an already captured Timer list entry.
 *
 * The one algorithm. The start path passes the user's language; the
 * Timer list's legacy fallback, for a payload written before the field
 * existed or one whose string is missing, passes the same vocabulary
 * resolved from resources.
 *
 * Example: `Standard 2 stops · Lee holder: Big Stopper ND1000 +
 * Lee GND 0.9 OD 0.9 (Record only) · NiSi kit: NiSi CPL 1.5 stops`
 * (iOS: `FilterSummaryReferencePresenter`.)
 */
object FilterSummaryReferencePresenter {

    private const val SEGMENT_SEPARATOR = " · "
    private const val ITEM_SEPARATOR = " + "

    fun referenceText(
        summary: List<FilterSummaryEntry>,
        vocabulary: FilterReferenceVocabulary = FilterReferenceVocabulary.canonicalEnglish,
    ): String? {
        val segments = ArrayList<String>()
        var currentSetName: String? = null
        val currentItems = ArrayList<String>()

        fun flushSet() {
            val setName = currentSetName
            if (setName != null && currentItems.isNotEmpty()) {
                segments.add("$setName: ${currentItems.joinToString(ITEM_SEPARATOR)}")
            }
            currentSetName = null
            currentItems.clear()
        }

        for (entry in summary) {
            when (entry.sourceKind) {
                FilterSummaryEntry.SourceKind.standard -> {
                    flushSet()
                    if (entry.contributedStops > 0) {
                        segments.add(
                            "${vocabulary.standardSource} ${stopsText(entry.contributedStops, vocabulary)}",
                        )
                    }
                }

                FilterSummaryEntry.SourceKind.filterSet -> {
                    val setName = entry.filterSetName ?: vocabulary.fallbackFilterSet
                    if (currentSetName != setName) {
                        flushSet()
                        currentSetName = setName
                    }
                    currentItems.add(itemText(entry, vocabulary))
                }
            }
        }
        flushSet()
        return segments.joinToString(SEGMENT_SEPARATOR).takeIf { it.isNotEmpty() }
    }

    /**
     * `Big Stopper ND1000`, `Lee GND 0.9 OD 0.9 (Record only)`,
     * `Lee CPL 1.5 stops` — name, registered representation, mode.
     */
    private fun itemText(entry: FilterSummaryEntry, vocabulary: FilterReferenceVocabulary): String {
        val value = entry.originalValue
        val unit = entry.originalUnit
        val registered = when (entry.calculationMode) {
            FilterSummaryEntry.CalculationMode.cplLoss ->
                entry.canonicalStops?.let { stopsText(it, vocabulary) }

            else -> if (value != null && unit != null) {
                registeredValueText(FilterRegisteredValue(value, unit), vocabulary)
            } else {
                entry.canonicalStops?.let { stopsText(it, vocabulary) }
            }
        }
        val mode = when (entry.calculationMode) {
            FilterSummaryEntry.CalculationMode.gndRecordOnly -> vocabulary.recordOnlyMode
            FilterSummaryEntry.CalculationMode.gndApplyFullValue -> vocabulary.applyFullValueMode
            else -> null
        }
        return buildString {
            append(entry.itemName ?: vocabulary.fallbackItem)
            if (registered != null) append(" ").append(registered)
            if (mode != null) append(" (").append(mode).append(")")
        }
    }

    /** `N stops` / `1 stop`. */
    private fun stopsText(stops: Double, vocabulary: FilterReferenceVocabulary): String {
        val value = FilterWheelPresenter.decimalStopsValue(stops)
        return if (value == "1") vocabulary.oneStop else vocabulary.stopsFormat.format(value)
    }

    /** The registered Fixed / GND value as the user entered it. */
    private fun registeredValueText(
        value: FilterRegisteredValue,
        vocabulary: FilterReferenceVocabulary,
    ): String {
        val number = FilterWheelPresenter.trimmedNumber(value.value)
        return when (value.unit) {
            FilterValueUnit.stops -> stopsText(value.value, vocabulary)
            FilterValueUnit.opticalDensity -> vocabulary.opticalDensityFormat.format(number)
            FilterValueUnit.filterFactor -> vocabulary.filterFactorFormat.format(number)
        }
    }
}
