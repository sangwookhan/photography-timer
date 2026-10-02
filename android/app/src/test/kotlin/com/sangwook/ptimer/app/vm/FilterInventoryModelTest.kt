// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterExposureLoss
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
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

        var loads = 0
            private set

        override fun loadSnapshot(): PersistentFilterInventorySnapshot? { loads++; return toLoad }
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
        assertEquals(listOf("Stored"), model(RecordingStore(stored)).filterSets.map { it.name })

        val bootstrap = FilterInventory(listOf(FilterSet("Bootstrap", FilterSetColor.pink)))
        assertEquals(
            "Bootstrap",
            model(RecordingStore(stored), initial = bootstrap).filterSets[0].name,
        )
        assertTrue("No built-in Set (FILTER-SET-002 retired).", model().filterSets.isEmpty())
    }

    /** FILTER-SET-008: a fresh installation starts with the first-launch
     *  inventory, written at once, so it is offered only once: an edited
     *  Sample is kept, deleted Samples stay deleted, and a saved empty
     *  inventory stays empty. */
    @Test
    fun aFreshInstallSeedsTheFirstLaunchInventoryOnce() {
        val store = RecordingStore()
        val samples = FilterInventorySamples.inventory("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set")
        val sut = FilterInventoryModel(store = store, persistenceWriter = PersistenceWriter { it() }, firstLaunchInventory = samples)
        assertEquals(samples, sut.inventory.value)
        assertEquals("The seed is written at once.", samples, store.saved.single().restoredInventory)

        store.toLoad = store.saved.last()
        val first = samples.filterSets.first()
        sut.renameFilterSet(first.id, "My ND")
        store.toLoad = store.saved.last()
        val again = FilterInventoryModel(store = store, persistenceWriter = PersistenceWriter { it() }, firstLaunchInventory = samples)
        assertEquals("An edited Sample is not overwritten.", "My ND", again.inventory.value.filterSet(first.id)?.name)

        samples.filterSets.forEach { again.deleteFilterSet(it.id) }
        store.toLoad = store.saved.last()
        val afterDelete = FilterInventoryModel(store = store, persistenceWriter = PersistenceWriter { it() }, firstLaunchInventory = samples)
        assertTrue("Deleted Samples are not seeded again.", afterDelete.filterSets.isEmpty())
    }

    /** The bootstrap already read the store and found nothing saved: the
     *  model takes that as a fresh installation without a second read. */
    @Test
    fun aBootstrapReadThatFoundNothingSeedsWithoutReadingAgain() {
        val store = RecordingStore()
        val samples = FilterInventorySamples.inventory("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set")
        val sut = FilterInventoryModel(
            store = store,
            initial = null,
            initialIsStoreRead = true,
            persistenceWriter = inlineWriter,
            firstLaunchInventory = samples,
        )
        assertEquals("No second store read.", 0, store.loads)
        assertEquals(samples, sut.inventory.value)
        assertEquals("The seed is written once.", samples, store.saved.single().restoredInventory)
    }

    /** FILTER-SET-008: an upgrade that never saved an inventory gets the
     *  Samples once, like a fresh installation; a saved empty inventory
     *  counts as saved and gets none (an unreadable or failed read reads as
     *  a saved empty inventory, DataStoreFilterInventoryStoreTest). */
    @Test
    fun samplesAreSeededOnlyWhenNoInventoryWasEverSaved() {
        val samples = FilterInventorySamples.inventory("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set")
        val neverSaved = RecordingStore()
        assertEquals("Upgrade with nothing saved: Samples.", samples, FilterInventoryModel(store = neverSaved, persistenceWriter = inlineWriter, firstLaunchInventory = samples).inventory.value)

        val savedEmpty = RecordingStore(PersistentFilterInventorySnapshot.from(FilterInventory()))
        val model = FilterInventoryModel(store = savedEmpty, persistenceWriter = inlineWriter, firstLaunchInventory = samples)
        assertTrue("A saved empty inventory stays empty.", model.filterSets.isEmpty())
        assertTrue("Nothing is written over it.", savedEmpty.saved.isEmpty())
    }

    /** FILTER-SET-009: an upgrade keeps the saved inventory: no Samples,
     *  and a former Default Set is ordinary inventory that can be deleted. */
    @Test
    fun anUpgradeKeepsAFormerDefaultAsAnOrdinarySet() {
        val formerDefault = FilterSet("Default", FilterSetColor.blue, emptyList(), FilterSetId("default"))
        val lee = FilterSet("Lee", FilterSetColor.red)
        val store = RecordingStore(PersistentFilterInventorySnapshot.from(FilterInventory(listOf(formerDefault, lee))))
        val samples = FilterInventorySamples.inventory("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set")
        val sut = FilterInventoryModel(store = store, persistenceWriter = PersistenceWriter { it() }, firstLaunchInventory = samples)
        assertEquals("No Samples on upgrade.", listOf(formerDefault.id, lee.id), sut.filterSets.map { it.id })
        assertEquals(formerDefault, sut.inventory.value.filterSet(formerDefault.id))
        assertTrue("Nothing is written by restoring.", store.saved.isEmpty())

        sut.deleteFilterSet(formerDefault.id)
        assertEquals("A former Default can be deleted.", listOf(lee.id), sut.filterSets.map { it.id })
    }

    /** FILTER-SET-008: the Samples and their registered values; the
     *  Extended items convert through the shared ND-factor mapping
     *  (ND-011), ND400 by log2 without snapping. */
    @Test
    fun theSamplesHoldTheApprovedItems() {
        val samples = FilterInventorySamples.inventory("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set")
        assertEquals(listOf("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set"), samples.filterSets.map { it.name })
        assertTrue(samples.filterSets.all { set -> set.items.all { it.isWellFormed } })
        assertEquals(3, samples.filterSets.map { it.id }.toSet().size)
        assertEquals(listOf("ND8", "ND64", "ND1000"), samples.filterSets[0].items.map { it.name })
        assertEquals(listOf(3.0, 6.0, 10.0), samples.filterSets[0].items.map { (it.behavior as FilterItemBehavior.Fixed).value.value })
        val extended = samples.filterSets[1].items
        assertEquals(listOf("ND100", "ND200", "ND400", "ND100k"), extended.map { it.name })
        val stops = extended.map { (it.behavior as FilterItemBehavior.Fixed).value.canonicalStops!! }
        assertEquals(6.6, stops[0], 1e-9)
        assertEquals(7.6, stops[1], 1e-9)
        assertEquals(kotlin.math.log2(400.0), stops[2], 1e-9)
        assertEquals(16.6, stops[3], 1e-9)
        val aux = samples.filterSets[2].items
        assertEquals(listOf("CPL", "B+W 091 Red Dark", "B+W 040 Orange", "B+W 022 Yellow", "GND 2 stops"), aux.map { it.name })
        assertEquals(FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))), aux[0].behavior)
        assertEquals(FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red), aux[1].behavior)
        assertEquals(FilterItemBehavior.Color(FilterExposureLoss(2.0), FilterSetColor.orange), aux[2].behavior)
        assertEquals(FilterItemBehavior.Color(FilterExposureLoss(1.0), FilterSetColor.yellow), aux[3].behavior)
        assertEquals(FilterItemBehavior.Gnd(FilterRegisteredValue(2.0, FilterValueUnit.stops)), aux[4].behavior)
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

    /** FILTER-ITEM-009: a proposed New Filter Set and its filter are made
     *  in one change with one saved snapshot, so no Set-only state is
     *  published or saved; a refused save changes and writes nothing. */
    @Test
    fun aProposedFilterSetIsCreatedTogetherWithItsFilter() {
        val store = RecordingStore()
        val sut = model(store)
        val nd8 = fixed("ND8", 3.0)

        assertNull("A blank name creates nothing.", sut.createFilterSet("  ", FilterSetColor.teal, nd8))
        assertNull("An invalid filter creates nothing.", sut.createFilterSet("New Filter Set", FilterSetColor.teal, fixed(" ", 3.0)))
        assertTrue(sut.filterSets.isEmpty())
        assertTrue("A refused save writes nothing.", store.saved.isEmpty())

        val created = sut.createFilterSet(" New Filter Set ", FilterSetColor.teal, nd8)!!
        assertEquals("New Filter Set", created.name)
        assertEquals(listOf(nd8), created.items)
        assertEquals(listOf(created), sut.filterSets)
        assertEquals("One saved snapshot, never a Set without its filter.", 1, store.saved.size)
        assertEquals(listOf(listOf(nd8.id)), store.saved.single().restoredInventory.filterSets.map { set -> set.items.map { it.id } })

        assertNull("An item id already in use creates nothing.", sut.createFilterSet("Other", FilterSetColor.red, nd8))
        assertEquals(1, store.saved.size)
        assertEquals(1, sut.filterSets.size)
    }

    @Test
    fun renameAndRecolorKeepTheStableIdAndSkipNoOps() {
        val store = RecordingStore()
        val sut = model(store)
        val set = sut.createFilterSet("NiSi", FilterSetColor.red)!!
        store.saved.clear()

        sut.renameFilterSet(set.id, "  NiSi kit  ")
        sut.recolorFilterSet(set.id, FilterSetColor.teal)
        assertEquals("NiSi kit", sut.inventory.value.filterSet(set.id)?.name)
        assertEquals(FilterSetColor.teal, sut.inventory.value.filterSet(set.id)?.color)
        assertEquals(listOf(set.id), sut.filterSets.map { it.id })
        assertEquals(2, store.saved.size)

        // Unchanged values and a blank rename write nothing.
        sut.renameFilterSet(set.id, "NiSi kit")
        sut.renameFilterSet(set.id, "  ")
        sut.recolorFilterSet(set.id, FilterSetColor.teal)
        assertEquals(2, store.saved.size)
    }

    @Test
    fun createdSetsAreListedByName() {
        val sut = model()
        val c = sut.createFilterSet("c holder", FilterSetColor.green)!!
        val a = sut.createFilterSet("A", FilterSetColor.red)!!
        val b = sut.createFilterSet("B 10", FilterSetColor.blue)!!
        val b9 = sut.createFilterSet("B 9", FilterSetColor.blue)!!

        assertEquals(listOf(c.id, a.id, b.id, b9.id), sut.filterSets.map { it.id })
        assertEquals(
            "No manual order: sets read by name (FILTER-SET-004).",
            listOf(a.id, b.id, b9.id, c.id),
            FilterSetItemOrder.sortedByName(sut.filterSets).map { it.id },
        )
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
        assertEquals(listOf("ND8", "CPL"), sut.inventory.value.filterSet(set.id)?.items?.map { it.name })

        sut.addItem(first.copy(name = "Big Stopper"), set.id)
        assertEquals(
            "A duplicate id replaces in place; position and count are preserved.",
            listOf("Big Stopper", "CPL"),
            sut.inventory.value.filterSet(set.id)?.items?.map { it.name },
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
        assertTrue(sut.inventory.value.filterSet(set.id)!!.items.isEmpty())
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
        assertEquals(edited, sut.inventory.value.item(item.id)?.second)
        assertEquals(lee.id, sut.inventory.value.item(item.id)?.first?.id)
        assertEquals(1, store.saved.size)

        sut.updateItem(edited)
        assertEquals("An identical update writes nothing.", 1, store.saved.size)
    }

    @Test
    fun relocateItemAndDeleteItemKeepTheItemID() {
        val sut = model()
        val nisi = sut.createFilterSet("NiSi", FilterSetColor.red)!!
        val lee = sut.createFilterSet("Lee", FilterSetColor.blue)!!
        val a = fixed("A", 1.0)
        val b = fixed("B", 2.0)
        sut.addItem(a, lee.id)
        sut.addItem(b, lee.id)
        sut.addItem(fixed("Keep", 4.0), nisi.id)

        // FILTER-ITEM-009: an existing item moves to another set with its
        // id and edits, in one change.
        val renamed = a.copy(name = "A2")
        sut.relocateItem(renamed, nisi.id)
        assertEquals(listOf("B"), sut.inventory.value.filterSet(lee.id)?.items?.map { it.name })
        assertEquals(listOf("Keep", "A2"), sut.inventory.value.filterSet(nisi.id)?.items?.map { it.name })
        assertEquals(nisi.id, sut.inventory.value.item(a.id)?.first?.id)
        sut.relocateItem(renamed, nisi.id)
        assertEquals("Moving into its own set changes nothing.", 2, sut.inventory.value.filterSet(nisi.id)?.items?.size)
        sut.relocateItem(renamed, lee.id)
        assertEquals(listOf("B", "A2"), sut.inventory.value.filterSet(lee.id)?.items?.map { it.name })

        sut.deleteItem(b.id)
        assertEquals(listOf("A2"), sut.inventory.value.filterSet(lee.id)?.items?.map { it.name })
        assertNull(sut.inventory.value.item(b.id))
    }

    @Test
    fun everyMutationRoundTripsThroughThePersistedSnapshot() {
        val store = RecordingStore()
        val sut = model(store)
        val set = sut.createFilterSet("Lee holder", FilterSetColor.blue)!!
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
        assertEquals(FilterSetColor.blue, restored.filterSet(set.id)!!.color)
        assertEquals(10.0, restored.item(sut.inventory.value.filterSet(set.id)!!.items[0].id)!!.second.behavior.registeredValue!!.canonicalStops!!, 1e-9)
    }
}
