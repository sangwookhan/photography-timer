// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.ResolvedAuxiliaryFilter

/**
 * One mounted auxiliary filter as the Main summary shows it
 * (FILTER-AUX-002): one compact row with a short identifier and the
 * current contribution. Modes, registered densities, and other metadata
 * stay in the shooting popup. Pure value; the display layer localizes the
 * kind and mode words and owns fonts and colors.
 * (iOS: `AuxiliaryFilterSummaryItemDisplay`.)
 */
data class AuxiliaryFilterSummaryItemDisplay(
    val itemId: FilterItemId,
    /** The item's registered name (`Soft GND 3`, `CPL`, `Red 25A`). */
    val name: String,
    val kind: FilterItemKind,
    /** The GND mode for a mounted GND; `null` otherwise. */
    val gndMode: GndCalculationMode?,
    /** Current contribution in canonical stops. */
    val contributionStops: Double,
    /** Current contribution as a plain decimal (`1.5`, `0`). */
    val contributionText: String,
    /**
     * The row's identifier, longest first: the view shows the first one
     * that fits the column, never a truncated one. See
     * [AuxiliaryFilterSummaryPresenter.compactLabels].
     */
    val compactLabels: List<String>,
    /** Swatch for a Color filter's optical color; `null` otherwise. */
    val opticalColor: FilterSetColor?,
    /** The owning set's user-selected color, shown as the source cue. */
    val sourceColor: FilterSetColor,
)

/**
 * The Main summary space (FILTER-AUX-001/002): every mounted auxiliary
 * item with its identity and contribution, readable without a tap. `null`
 * while nothing is mounted, so the space is hidden.
 * (iOS: `AuxiliaryFilterSummaryDisplayState`.)
 */
data class AuxiliaryFilterSummaryDisplayState(
    /** Every mounted item, in display order. */
    val items: List<AuxiliaryFilterSummaryItemDisplay>,
) {
    /** The first three items in display order, each shown as a row. */
    val visibleItems: List<AuxiliaryFilterSummaryItemDisplay> get() = items.take(VISIBLE_ITEM_LIMIT)

    /** How many mounted items are not shown individually; 0 when all fit.
     *  The display layer renders `+ N more` for them. */
    val hiddenItemCount: Int get() = (items.size - VISIBLE_ITEM_LIMIT).coerceAtLeast(0)

    companion object {
        /** How many rows Main shows individually; the rest are counted in
         *  the `+ N more` line (FILTER-AUX-002). */
        const val VISIBLE_ITEM_LIMIT: Int = 3
    }
}

/**
 * Pure-value transform from the resolved mounted auxiliary filters into
 * the Main summary. Contributions stay in stops regardless of the ND
 * notation (ND-004): they are labeled contributions, not notation
 * displays. (iOS: `AuxiliaryFilterSummaryPresenter`.)
 */
object AuxiliaryFilterSummaryPresenter {

    fun displayState(rows: List<ResolvedAuxiliaryFilter>): AuxiliaryFilterSummaryDisplayState? {
        if (rows.isEmpty()) return null
        return AuxiliaryFilterSummaryDisplayState(rows.map { itemDisplay(it, rows) })
    }

    /**
     * The working selection as one short line for the top of Shooting
     * Filters (FILTER-FLOW-003): each item's concise identity and
     * contribution in Main's order; `null` when nothing is selected. The
     * identity is Main's first concise name without a number, so a name's
     * number never runs into the contribution (`Soft GND 0`, not
     * `Soft GND 2 0`); a name that is all number keeps its whole form.
     */
    fun selectedFiltersText(rows: List<ResolvedAuxiliaryFilter>): String? =
        displayState(rows)?.items?.joinToString(" · ") { item ->
            val label = item.compactLabels.firstOrNull { label ->
                label.split(Regex("\\s+")).none { word -> word.any { it.isDigit() } }
            } ?: item.compactLabels.firstOrNull() ?: item.name
            "$label ${item.contributionText}"
        }

    /** One row of the summary. [rows] are all mounted items, so the
     *  identifier can tell two items of the same kind apart. */
    fun itemDisplay(row: ResolvedAuxiliaryFilter, rows: List<ResolvedAuxiliaryFilter>): AuxiliaryFilterSummaryItemDisplay =
        AuxiliaryFilterSummaryItemDisplay(
            itemId = row.item.id,
            name = row.item.name,
            kind = row.item.behavior.kind,
            gndMode = (row.mount.choice as? AuxiliaryFilterChoice.Gnd)?.mode,
            contributionStops = row.contributionStops,
            contributionText = FilterWheelPresenter.decimalStopsValue(row.contributionStops),
            compactLabels = compactLabels(row, rows),
            opticalColor = row.item.behavior.opticalColor,
            sourceColor = row.filterSetColor,
        )

    /**
     * The deterministic concise-name rule for a compact Main row, longest
     * candidate first; the view shows the first that fits.
     * - A CPL is identified as `CPL` when it is the only mounted CPL; with
     *   two, by name so they stay distinct.
     * - A GND, Color, or Effect item is identified by name
     *   (FILTER-AUX-006: a GND by its distinguishing name, so equal Hard
     *   and Soft densities never read alike).
     * - A name's candidates are the whole name, then the words before the
     *   first word that contains a digit (`Soft GND 2` → `Soft GND`,
     *   `MARUMI Red 25A` → `MARUMI Red`), then the first word (`MARUMI`).
     *   A shortened candidate that another mounted item of the same kind
     *   would also show is left out, so rows never read the same.
     */
    fun compactLabels(row: ResolvedAuxiliaryFilter, rows: List<ResolvedAuxiliaryFilter>): List<String> {
        val kind = row.item.behavior.kind
        val sameKind = rows.filter { it.item.behavior.kind == kind }
        if (kind == FilterItemKind.cpl && sameKind.size == 1) return listOf("CPL")
        val others = sameKind.filter { it.item.id != row.item.id }.map { nameCandidates(it.item.name) }
        val candidates = nameCandidates(row.item.name)
        val whole = candidates.firstOrNull() ?: return listOf(row.item.name)
        val shortened = candidates.drop(1).filter { candidate -> others.none { candidate in it } }
        return listOf(whole) + shortened
    }

    private fun nameCandidates(name: String): List<String> {
        val words = name.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val first = words.firstOrNull() ?: return emptyList()
        val candidates = mutableListOf(words.joinToString(" "))
        val leading = words.takeWhile { word -> word.none { it.isDigit() } }
        if (leading.isNotEmpty() && leading.size < words.size) candidates.add(leading.joinToString(" "))
        if (words.size > 1 && candidates.last() != first) candidates.add(first)
        return candidates
    }
}
