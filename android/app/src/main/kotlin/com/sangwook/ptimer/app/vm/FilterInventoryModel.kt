// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.AppPersistenceWriter
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.persistence.FilterInventoryStoring
import com.sangwook.ptimer.core.persistence.NoOpFilterInventoryStore
import com.sangwook.ptimer.core.persistence.PersistentFilterInventorySnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Source-of-truth owner of the user's Filter Sets and physical filter
 * items (FILTER-SET / FILTER-ITEM). The model is the only writer of the
 * inventory; readers consume [inventory]. Every mutation persists the
 * whole snapshot through [store], handed to [persistenceWriter] so the
 * blocking store write never runs on the calling thread.
 *
 * Stack reconciliation — making every camera's Filter Stack follow an
 * item edit or deletion — is orchestrated by [CalculatorController],
 * the one place that reads both this inventory and the camera-slot
 * state. Pure Kotlin, no Android. (iOS: `FilterInventoryModel`.)
 */
class FilterInventoryModel(
    private val store: FilterInventoryStoring = NoOpFilterInventoryStore(),
    /**
     * Bootstrap-loaded inventory (the restored snapshot read off the main
     * thread). `null` falls back to reading [store] here, which is what
     * pure unit tests and the no-op default do.
     */
    initial: FilterInventory? = null,
    private val persistenceWriter: PersistenceWriter = AppPersistenceWriter,
) {
    private val _inventory = MutableStateFlow(
        initial ?: store.loadSnapshot()?.restoredInventory ?: FilterInventory.empty,
    )
    val inventory: StateFlow<FilterInventory> = _inventory.asStateFlow()

    /** Color suggested on the most recent creation opening — the next
     *  suggestion must differ from it (FILTER-SET-003). Session state. */
    private var lastSuggestedColor: FilterSetColor? = null

    val filterSets: List<FilterSet> get() = _inventory.value.filterSets

    fun filterSet(id: FilterSetId): FilterSet? = _inventory.value.filterSet(id)

    fun item(id: FilterItemId): Pair<FilterSet, FilterItem>? = _inventory.value.item(id)

    // MARK: Filter Sets

    /**
     * Random color for a new Filter Set that differs from the color
     * suggested on the immediately preceding creation opening.
     */
    fun suggestCreationColor(): FilterSetColor {
        val suggestion = FilterSetColor.suggestion(excluding = lastSuggestedColor)
        lastSuggestedColor = suggestion
        return suggestion
    }

    /**
     * Appends a new Filter Set to the user-defined order. Returns `null`
     * (and changes nothing) for a blank name.
     */
    fun createFilterSet(name: String, color: FilterSetColor): FilterSet? {
        val trimmed = trimmed(name) ?: return null
        val filterSet = FilterSet(name = trimmed, color = color)
        mutate { it + filterSet }
        return filterSet
    }

    fun renameFilterSet(id: FilterSetId, name: String) {
        val trimmed = trimmed(name) ?: return
        val index = indexOfSet(id) ?: return
        if (filterSets[index].name == trimmed) return
        mutate { sets -> sets.replacing(index, sets[index].copy(name = trimmed)) }
    }

    fun recolorFilterSet(id: FilterSetId, color: FilterSetColor) {
        val index = indexOfSet(id) ?: return
        if (filterSets[index].color == color) return
        mutate { sets -> sets.replacing(index, sets[index].copy(color = color)) }
    }

    /**
     * Reorders Filter Sets: the set at [fromIndex] is removed and
     * re-inserted at [toIndex] of the resulting list. Ids never change.
     */
    fun moveFilterSet(fromIndex: Int, toIndex: Int) {
        val sets = filterSets
        if (fromIndex !in sets.indices || toIndex !in sets.indices || fromIndex == toIndex) return
        mutate { it.moving(fromIndex, toIndex) }
    }

    /**
     * Removes a Filter Set and every item it holds. Stack cleanup for
     * wheels that referenced the set is the controller's responsibility.
     */
    fun deleteFilterSet(id: FilterSetId) {
        if (indexOfSet(id) == null) return
        mutate { sets -> sets.filterNot { it.id == id } }
    }

    // MARK: Items

    /**
     * Appends a well-formed item to [toSetId]. A duplicate item id
     * replaces the existing entry in place.
     */
    fun addItem(item: FilterItem, toSetId: FilterSetId) {
        if (!item.isWellFormed) return
        val index = indexOfSet(toSetId) ?: return
        mutate { sets ->
            val filterSet = sets[index]
            val existing = filterSet.items.indexOfFirst { it.id == item.id }
            val items = if (existing >= 0) {
                filterSet.items.replacing(existing, item)
            } else {
                filterSet.items + item
            }
            sets.replacing(index, filterSet.copy(items = items))
        }
    }

    /**
     * Replaces the item matching `item.id` wherever it lives. Item
     * identity and position are preserved.
     */
    fun updateItem(item: FilterItem) {
        if (!item.isWellFormed) return
        val sets = filterSets
        for (setIndex in sets.indices) {
            val itemIndex = sets[setIndex].items.indexOfFirst { it.id == item.id }
            if (itemIndex < 0) continue
            if (sets[setIndex].items[itemIndex] == item) return
            mutate { current ->
                current.replacing(
                    setIndex,
                    current[setIndex].copy(items = current[setIndex].items.replacing(itemIndex, item)),
                )
            }
            return
        }
    }

    /** Reorders one Filter Set's items; see [moveFilterSet] for the index rule. */
    fun moveItem(setId: FilterSetId, fromIndex: Int, toIndex: Int) {
        val setIndex = indexOfSet(setId) ?: return
        val items = filterSets[setIndex].items
        if (fromIndex !in items.indices || toIndex !in items.indices || fromIndex == toIndex) return
        mutate { sets ->
            sets.replacing(setIndex, sets[setIndex].copy(items = sets[setIndex].items.moving(fromIndex, toIndex)))
        }
    }

    fun deleteItem(id: FilterItemId) {
        val sets = filterSets
        for (setIndex in sets.indices) {
            if (sets[setIndex].items.none { it.id == id }) continue
            mutate { current ->
                current.replacing(
                    setIndex,
                    current[setIndex].copy(items = current[setIndex].items.filterNot { it.id == id }),
                )
            }
            return
        }
    }

    // MARK: Helpers

    private fun indexOfSet(id: FilterSetId): Int? =
        filterSets.indexOfFirst { it.id == id }.takeIf { it >= 0 }

    private fun trimmed(name: String): String? = name.trim().takeIf { it.isNotEmpty() }

    private fun mutate(transform: (List<FilterSet>) -> List<FilterSet>) {
        _inventory.value = FilterInventory(transform(_inventory.value.filterSets))
        persist()
    }

    private fun persist() {
        val snapshot = PersistentFilterInventorySnapshot.from(_inventory.value)
        persistenceWriter.submit {
            // A failing store write must not crash inventory editing.
            runCatching { store.saveSnapshot(snapshot) }
        }
    }
}

private fun <T> List<T>.replacing(index: Int, element: T): List<T> =
    toMutableList().also { it[index] = element }

private fun <T> List<T>.moving(fromIndex: Int, toIndex: Int): List<T> =
    toMutableList().also { it.add(toIndex, it.removeAt(fromIndex)) }
