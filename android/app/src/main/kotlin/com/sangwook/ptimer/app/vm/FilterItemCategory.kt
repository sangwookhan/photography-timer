// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSet
import java.text.Collator

/**
 * The fixed presentation order of Filter Sets and their items
 * (FILTER-SET-004, FILTER-ITEM-001/003). There is no manual reorder: a
 * Set's items read ND first, then Color, Effect, CPL, and GND, each kind
 * alphabetically by name; Available Sets read alphabetically by name.
 * Names compare the way the platform collates them for the current
 * locale. The kind order is also the type choice of the item editor,
 * where a new filter starts at ND. (iOS: `FilterSetItemOrder`.)
 */
object FilterSetItemOrder {
    val kinds: List<FilterItemKind> = listOf(
        FilterItemKind.fixed,
        FilterItemKind.color,
        FilterItemKind.effect,
        FilterItemKind.cpl,
        FilterItemKind.gnd,
    )

    /** The kind a new filter starts at. */
    val newItemKind: FilterItemKind = FilterItemKind.fixed

    /** [items] by kind, then by name; equal names keep a stable order by id. */
    fun ordered(items: List<FilterItem>): List<FilterItem> {
        val collator = Collator.getInstance()
        return items.sortedWith(
            compareBy<FilterItem> { kinds.indexOf(it.behavior.kind) }
                .thenComparator { a, b -> collator.compare(a.name, b.name) }
                .thenBy { it.id.rawValue },
        )
    }

    /** [filterSets] by name; equal names keep a stable order by id. */
    fun sortedByName(filterSets: List<FilterSet>): List<FilterSet> {
        val collator = Collator.getInstance()
        return filterSets.sortedWith(
            Comparator<FilterSet> { a, b -> collator.compare(a.name, b.name) }.thenBy { it.id.rawValue },
        )
    }
}

/**
 * The Plus ND source preferred after an Apply adds Filter Sets while Plus
 * is on Standard (FILTER-PLUS-006): among the selected Sets that hold ND
 * items, the one with the most registered ND items, an ND-only Set before
 * a mixed one on a tie, then by name; equal names keep the selection
 * order. `null` when no selected Set holds an ND item.
 * (iOS: `PreferredNDSource`.)
 */
object PreferredNdSource {
    fun winner(selected: List<FilterSet>): FilterSetId? {
        val collator = Collator.getInstance()
        return selected
            .mapIndexed { index, set -> Triple(set, set.items.count { it.behavior.kind == FilterItemKind.fixed }, index) }
            .filter { it.second > 0 }
            .sortedWith(
                compareByDescending<Triple<FilterSet, Int, Int>> { it.second }
                    .thenBy { if (it.first.auxiliaryItems.isEmpty()) 0 else 1 }
                    .thenComparator { a, b -> collator.compare(a.first.name, b.first.name) }
                    .thenBy { it.third },
            )
            .firstOrNull()?.first?.id
    }
}
