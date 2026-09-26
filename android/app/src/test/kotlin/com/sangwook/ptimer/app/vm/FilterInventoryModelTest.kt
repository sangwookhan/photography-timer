// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.persistence.FilterInventoryStoring
import com.sangwook.ptimer.core.persistence.PersistentFilterInventorySnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-221: the inventory owner (FILTER-SET-001..005, FILTER-ITEM-001/
 * 002/003). Mirrors the iOS FilterInventoryModelTests at Android level:
 * every command's effect on the ordered inventory and the fact that each
 * one persists exactly one snapshot.
 */
class FilterInventoryModelTest {

    private class RecordingStore(var toLoad: PersistentFilterInventorySnapshot? = null) :
        FilterInventoryStoring {
        val saved = mutableListOf<PersistentFilterInventorySnapshot>()
        var cleared = 0
            private set

        override fun loadSnapshot(): PersistentFilterInventorySnapshot? = toLoad
        override fun saveSnapshot(snapshot: PersistentFilterInventorySnapshot) { saved += snapshot }
        override fun clearSnapshot() { cleared++ }
    }

    /** Runs the store write inline so assertions need no scheduler. */
    private val inlineWriter = PersistenceWriter { it() }

    private fun model(store: RecordingStore = RecordingStore(), initial: FilterInventory? = null) =
        FilterInventoryModel(store = store, initial = initial, persistenceWriter = inlineWriter)

    private fun fixed(name: String, stops: Double) = FilterItem(
        name = name,
        behavior = FilterItemBehavior.Fixed(FilterRegisteredValue(stops, FilterValueUnit.stops)),
    )

    // MARK: construction

    @Test
    fun readsTheStoreOnlyWhenNoBootstrapInventoryIsSupplied() {
        val stored = PersistentFilterInventorySnapshot.from(
            FilterInventory(listOf(FilterSet("Stored", FilterSetColor.teal))),
        )
        assertEquals("Stored", model(RecordingStore(stored)).filterSets.single().name)

        val bootstrap = FilterInventory(listOf(FilterSet("Bootstrap", FilterSetColor.pink)))
        assertEquals(
            "Bootstrap",
            model(RecordingStore(stored), initial = bootstrap).filterSets.single().name,
        )
        assertTrue(model().filterSets.isEmpty())
    }

    // MARK: Filter Sets

    @Test
    fun creationAppendsToTheUserDefinedOrderAndRejectsABlankName() {
        val store = RecordingStore()
        val sut = model(store)

        assertNull(sut.createFilterSet("   ", FilterSetColor.red))
        assertTrue(sut.filterSets.isEmpty())
        assertTrue("A refused creation persists nothing.", store.saved.isEmpty())

        val first = sut.createFilterSet("  NiSi kit  ", FilterSetColor.red)
        val second = sut.createFilterSet("Lee holder", FilterSetColor.blue)
        assertNotNull(first)
        assertEquals(listOf("NiSi kit", "Lee holder"), sut.filterSets.map { it.name })
        assertEquals(2, store.saved.size)
        assertEquals(listOf("NiSi kit", "Lee holder"), store.saved.last().filterSets.map { it.name })
        assertEquals(second!!.id, sut.filterSets[1].id)
    }

    @Test
    fun renameAndRecolorKeepTheStableIdAndSkipNoOps() {
        val store = RecordingStore()
        val sut = model(store)
        val set = sut.createFilterSet("NiSi", FilterSetColor.red)!!
        store.saved.clear()

        sut.renameFilterSet(set.id, "  NiSi kit  ")
        sut.recolorFilterSet(set.id, FilterSetColor.mint)
        assertEquals("NiSi kit", sut.filterSet(set.id)?.name)
        assertEquals(FilterSetColor.mint, sut.filterSet(set.id)?.color)
        assertEquals(set.id, sut.filterSets.single().id)
        assertEquals(2, store.saved.size)

        // Unchanged values and a blank rename write nothing.
        sut.renameFilterSet(set.id, "NiSi kit")
        sut.renameFilterSet(set.id, "  ")
        sut.recolorFilterSet(set.id, FilterSetColor.mint)
        assertEquals(2, store.saved.size)
    }

    @Test
    fun moveReordersWithoutChangingIds() {
        val sut = model()
        val a = sut.createFilterSet("A", FilterSetColor.red)!!
        val b = sut.createFilterSet("B", FilterSetColor.blue)!!
        val c = sut.createFilterSet("C", FilterSetColor.green)!!

        sut.moveFilterSet(fromIndex = 2, toIndex = 0)
        assertEquals(listOf("C", "A", "B"), sut.filterSets.map { it.name })
        assertEquals(listOf(c.id, a.id, b.id), sut.filterSets.map { it.id })

        // Out-of-range and no-op moves change nothing.
        sut.moveFilterSet(0, 0)
        sut.moveFilterSet(0, 9)
        assertEquals(listOf("C", "A", "B"), sut.filterSets.map { it.name })
    }

    @Test
    fun deleteRemovesTheSetAndItsItems() {
        val store = RecordingStore()
        val sut = model(store)
        val set = sut.createFilterSet("NiSi", FilterSetColor.red)!!
        sut.addItem(fixed("ND1000", 10.0), set.id)
        store.saved.clear()

        sut.deleteFilterSet(set.id)
        assertTrue(sut.filterSets.isEmpty())
        assertEquals(1, store.saved.size)

        // A second delete of the same id writes nothing.
        sut.deleteFilterSet(set.id)
        assertEquals(1, store.saved.size)
    }

    @Test
    fun consecutiveColorSuggestionsDiffer() {
        val sut = model()
        var previous = sut.suggestCreationColor()
        repeat(40) {
            val next = sut.suggestCreationColor()
            assertFalse(
                "A suggestion must differ from the immediately preceding one.",
                next == previous,
            )
            previous = next
        }
    }

    // MARK: Items

    @Test
    fun addAppendsAndADuplicateIdReplacesInPlace() {
        val sut = model()
        val set = sut.createFilterSet("Lee", FilterSetColor.blue)!!
        val first = fixed("ND8", 3.0)
        sut.addItem(first, set.id)
        sut.addItem(fixed("CPL", 1.0), set.id)
        assertEquals(listOf("ND8", "CPL"), sut.filterSet(set.id)?.items?.map { it.name })

        sut.addItem(first.copy(name = "Big Stopper"), set.id)
        assertEquals(
            "A duplicate id replaces in place; position and count are preserved.",
            listOf("Big Stopper", "CPL"),
            sut.filterSet(set.id)?.items?.map { it.name },
        )
    }

    @Test
    fun addAndUpdateRejectAMalformedItem() {
        val store = RecordingStore()
        val sut = model(store)
        val set = sut.createFilterSet("Lee", FilterSetColor.blue)!!
        store.saved.clear()

        sut.addItem(fixed("  ", 3.0), set.id)
        sut.addItem(fixed("Over cap", 31.0), set.id)
        sut.addItem(
            FilterItem("No choice", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(null, null, null)))),
            set.id,
        )
        assertTrue(sut.filterSet(set.id)!!.items.isEmpty())
        assertTrue(store.saved.isEmpty())
    }

    @Test
    fun updateReplacesWhereverTheItemLivesAndSkipsAnUnchangedSave() {
        val store = RecordingStore()
        val sut = model(store)
        sut.createFilterSet("NiSi", FilterSetColor.red)
        val lee = sut.createFilterSet("Lee", FilterSetColor.blue)!!
        val item = fixed("ND8", 3.0)
        sut.addItem(item, lee.id)
        store.saved.clear()

        val edited = item.copy(
            behavior = FilterItemBehavior.Fixed(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
        )
        sut.updateItem(edited)
        assertEquals(edited, sut.item(item.id)?.second)
        assertEquals(lee.id, sut.item(item.id)?.first?.id)
        assertEquals(1, store.saved.size)

        sut.updateItem(edited)
        assertEquals("An identical update writes nothing.", 1, store.saved.size)
    }

    @Test
    fun moveItemAndDeleteItemActOnTheOwningSetOnly() {
        val sut = model()
        val nisi = sut.createFilterSet("NiSi", FilterSetColor.red)!!
        val lee = sut.createFilterSet("Lee", FilterSetColor.blue)!!
        val a = fixed("A", 1.0)
        val b = fixed("B", 2.0)
        sut.addItem(a, lee.id)
        sut.addItem(b, lee.id)
        sut.addItem(fixed("Keep", 4.0), nisi.id)

        sut.moveItem(lee.id, fromIndex = 1, toIndex = 0)
        assertEquals(listOf("B", "A"), sut.filterSet(lee.id)?.items?.map { it.name })
        assertEquals(listOf("Keep"), sut.filterSet(nisi.id)?.items?.map { it.name })

        sut.deleteItem(b.id)
        assertEquals(listOf("A"), sut.filterSet(lee.id)?.items?.map { it.name })
        assertNull(sut.item(b.id))
    }

    @Test
    fun everyMutationRoundTripsThroughThePersistedSnapshot() {
        val store = RecordingStore()
        val sut = model(store)
        val set = sut.createFilterSet("Lee holder", FilterSetColor.indigo)!!
        sut.addItem(
            FilterItem("Big Stopper", FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor))),
            set.id,
        )
        sut.addItem(
            FilterItem("Lee CPL", FilterItemBehavior.Cpl(CplExposureLossChoices.defaults)),
            set.id,
        )

        val restored = store.saved.last().restoredInventory
        assertEquals(sut.inventory.value, restored)
        assertEquals(FilterSetColor.indigo, restored.filterSets.single().color)
        assertEquals(10.0, restored.item(sut.filterSet(set.id)!!.items[0].id)!!.second.behavior.registeredValue!!.canonicalStops!!, 1e-9)
    }
}
