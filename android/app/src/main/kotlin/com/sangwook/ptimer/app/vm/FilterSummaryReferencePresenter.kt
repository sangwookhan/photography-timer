// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.GndCalculationMode

/**
 * Builds the human-readable, start-time reference string a timer keeps
 * beside its calculation record (FILTER-PERSIST-003): Filter Set and
 * Filter Item names, registered representations, and calculation modes
 * as they stood when the timer started. Descriptive only — generated
 * once from the captured summary, stored with the timer, and never
 * re-derived from the live inventory, so a later rename or deletion
 * cannot rewrite it.
 *
 * Example: `Standard 2 stops · Lee holder: Big Stopper ND1000 +
 * Lee GND 0.9 OD 0.9 (Record only) · NiSi kit: NiSi CPL 1.5 stops`
 * (iOS: `FilterSummaryReferencePresenter`.)
 */
object FilterSummaryReferencePresenter {

    fun referenceText(summary: List<FilterSummaryEntry>): String? {
        val segments = ArrayList<String>()
        var currentSetName: String? = null
        val currentItems = ArrayList<String>()

        fun flushSet() {
            val setName = currentSetName
            if (setName != null && currentItems.isNotEmpty()) {
                segments.add("$setName: ${currentItems.joinToString(" + ")}")
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
                            "${FilterWheelPresenter.STANDARD_SOURCE_NAME} " +
                                FilterWheelPresenter.stopsText(entry.contributedStops),
                        )
                    }
                }

                FilterSummaryEntry.SourceKind.filterSet -> {
                    val setName = entry.filterSetName ?: FilterWheelPresenter.FALLBACK_FILTER_SET_NAME
                    if (currentSetName != setName) {
                        flushSet()
                        currentSetName = setName
                    }
                    currentItems.add(itemText(entry))
                }
            }
        }
        flushSet()
        return segments.joinToString(" · ").takeIf { it.isNotEmpty() }
    }

    /**
     * `Big Stopper ND1000`, `Lee GND 0.9 OD 0.9 (Record only)`,
     * `Lee CPL 1.5 stops` — name, registered representation, mode.
     */
    internal fun itemText(entry: FilterSummaryEntry): String {
        val name = entry.itemName ?: FilterWheelPresenter.FALLBACK_ITEM_NAME
        val builder = StringBuilder(name)
        val value = entry.originalValue
        val unit = entry.originalUnit
        when (entry.calculationMode) {
            FilterSummaryEntry.CalculationMode.cplLoss ->
                entry.canonicalStops?.let { builder.append(" ").append(FilterWheelPresenter.stopsText(it)) }

            else -> if (value != null && unit != null) {
                builder.append(" ")
                    .append(FilterWheelPresenter.registeredValueText(FilterRegisteredValue(value, unit)))
            } else {
                entry.canonicalStops?.let { builder.append(" ").append(FilterWheelPresenter.stopsText(it)) }
            }
        }
        when (entry.calculationMode) {
            FilterSummaryEntry.CalculationMode.gndRecordOnly ->
                builder.append(" (").append(FilterWheelPresenter.gndModeName(GndCalculationMode.recordOnly)).append(")")

            FilterSummaryEntry.CalculationMode.gndApplyFullValue ->
                builder.append(" (")
                    .append(FilterWheelPresenter.gndModeName(GndCalculationMode.applyFullValue))
                    .append(")")

            else -> Unit
        }
        return builder.toString()
    }
}
