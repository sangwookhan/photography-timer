// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.preferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.persistence.FilterInventoryCodec
import com.sangwook.ptimer.core.persistence.PersistentFilterInventorySnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

/**
 * PTIMER-221: round-trip and corrupt-payload contract tests for the
 * concrete [DataStoreFilterInventoryStore] adapter — a real JVM-local
 * DataStore (backed by a temp file, no Robolectric/emulator), not just
 * the core codec (FILTER-PERSIST-001/002).
 */
class DataStoreFilterInventoryStoreTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val inventoryKey = stringPreferencesKey("filter_inventory_json")
    private val quarantineKey = stringPreferencesKey("filter_inventory_json.quarantine")

    private fun newDataStore(name: String): DataStore<Preferences> {
        val file = tempFolder.newFile(name)
        return PreferenceDataStoreFactory.create(
            scope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
            produceFile = { file },
        )
    }

    private fun DataStore<Preferences>.readQuarantine(): String? =
        runBlocking { data.first()[quarantineKey] }

    private fun DataStore<Preferences>.writeRaw(value: String) =
        runBlocking { edit { it[inventoryKey] = value } }

    private val sample = PersistentFilterInventorySnapshot.from(
        FilterInventory(
            listOf(
                FilterSet(
                    name = "Lee holder",
                    color = FilterSetColor.indigo,
                    items = listOf(
                        FilterItem(
                            "Big Stopper",
                            FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor)),
                        ),
                        FilterItem(
                            "Lee GND 0.9",
                            FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
                        ),
                        FilterItem("Lee CPL", FilterItemBehavior.Cpl(CplExposureLossChoices.defaults)),
                    ),
                ),
                FilterSet("NiSi kit", FilterSetColor.teal),
            ),
        ),
    )

    @Test
    fun roundTripsIdsNamesColorsOrderAndItems() {
        val store = DataStoreFilterInventoryStore(newDataStore("inventory_roundtrip.preferences_pb"))

        store.saveSnapshot(sample)

        val loaded = store.loadSnapshot()
        assertEquals(sample, loaded)
        assertEquals(
            listOf("Lee holder", "NiSi kit"),
            loaded!!.restoredInventory.filterSets.map { it.name },
        )
        assertEquals(sample.restoredInventory, loaded.restoredInventory)
    }

    @Test
    fun missingKeyReadsAsNullRatherThanThrowing() {
        assertNull(DataStoreFilterInventoryStore(newDataStore("inventory_empty.preferences_pb")).loadSnapshot())
    }

    /**
     * The defect this guards: a Filter Set whose ITEMS are damaged still
     * decodes as a set, so the outcome used to read `loaded`, nothing was
     * quarantined, and the very next edit wrote the reduced inventory over
     * the only copy of the user's filter records.
     */
    @Test
    fun itemLevelDamageIsQuarantinedAndSurvivesTheNextSave() {
        val ds = newDataStore("inventory_item_damage.preferences_pb")
        val original = """
            {"schemaVersion":1,"filterSets":[{"id":"s-lee","name":"Lee holder","color":"indigo","items":[
              {"id":"i-ok","name":"Big Stopper","kind":"fixed","value":1000.0,"unit":"filterFactor"},
              {"id":"i-torn","name":"Torn","kind":"fixed","value":"three","unit":"stops"},
              {"id":"i-alien","name":"Unknown kind","kind":"laser"}
            ]}]}
        """.trimIndent()
        ds.writeRaw(original)
        val store = DataStoreFilterInventoryStore(ds)

        // The set and its intact sibling survive the load.
        val loaded = store.loadSnapshot()
        assertNotNull(loaded)
        val sets = loaded!!.restoredInventory.filterSets
        assertEquals(listOf("Lee holder"), sets.map { it.name })
        assertEquals(listOf("Big Stopper"), sets.single().items.map { it.name })

        // And the two that did not are recoverable: the quarantine holds
        // the original bytes, exactly.
        assertEquals(original, ds.readQuarantine())

        // A later edit overwrites the live inventory, as it must — and
        // leaves the quarantined copy alone.
        store.saveSnapshot(sample)
        assertEquals(sample, store.loadSnapshot())
        assertEquals(
            "The user's damaged records stay recoverable after the save that replaced them.",
            original,
            ds.readQuarantine(),
        )
    }

    /**
     * The same, one level up: a record that parses and then restores to
     * nothing. The collection decoder refuses nothing here, so this is
     * invisible without the restore-time diagnostics.
     */
    @Test
    fun aFilterSetThatCannotBeRestoredIsQuarantined() {
        val ds = newDataStore("inventory_unrestorable.preferences_pb")
        val original = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s-lee","name":"Lee holder","color":"indigo","items":[]},
              {"id":"  ","name":"Blank id","color":"red","items":[]}
            ]}
        """.trimIndent()
        ds.writeRaw(original)

        val loaded = DataStoreFilterInventoryStore(ds).loadSnapshot()
        assertEquals(listOf("Lee holder"), loaded!!.restoredInventory.filterSets.map { it.name })
        assertEquals(original, ds.readQuarantine())
    }

    /**
     * The container-level half of the same recoverability defect: an
     * `items` field that is present but is not an array hid a whole
     * set's worth of filters, because it read exactly like an empty one.
     */
    @Test
    fun aNonArrayItemsFieldIsQuarantinedAndSurvivesTheNextSave() {
        val ds = newDataStore("inventory_items_container.preferences_pb")
        val original = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s-lee","name":"Lee holder","color":"indigo","items":[]},
              {"id":"s-torn","name":"Torn","color":"red","items":"damaged"}
            ]}
        """.trimIndent()
        ds.writeRaw(original)
        val store = DataStoreFilterInventoryStore(ds)

        // The intact set still loads.
        assertEquals(
            listOf("Lee holder"),
            store.loadSnapshot()!!.restoredInventory.filterSets.map { it.name },
        )
        // The damaged one is recoverable, byte for byte...
        assertEquals(original, ds.readQuarantine())

        // ...and stays so once the reduced inventory is written back.
        store.saveSnapshot(sample)
        assertEquals(sample, store.loadSnapshot())
        assertEquals(original, ds.readQuarantine())
    }

    /** An intact payload is never quarantined. */
    @Test
    fun anIntactPayloadLeavesNoQuarantineCopy() {
        val ds = newDataStore("inventory_intact.preferences_pb")
        val store = DataStoreFilterInventoryStore(ds)

        store.saveSnapshot(sample)
        assertEquals(sample, store.loadSnapshot())
        assertNull(ds.readQuarantine())
    }

    @Test
    fun corruptPayloadFailsSafeToNullAndIsQuarantined() {
        val ds = newDataStore("inventory_corrupt.preferences_pb")
        ds.writeRaw("{not valid json")
        val store = DataStoreFilterInventoryStore(ds)

        assertNull(store.loadSnapshot())
        assertEquals("{not valid json", ds.readQuarantine())
    }

    @Test
    fun secondFailureReplacesQuarantineAndANormalSaveKeepsIt() {
        val ds = newDataStore("inventory_quarantine.preferences_pb")
        val store = DataStoreFilterInventoryStore(ds)

        ds.writeRaw("bad payload A")
        store.loadSnapshot()
        assertEquals("bad payload A", ds.readQuarantine())

        ds.writeRaw("different bad payload B")
        store.loadSnapshot()
        assertEquals("different bad payload B", ds.readQuarantine())

        store.saveSnapshot(sample)
        assertEquals("different bad payload B", ds.readQuarantine())
        assertEquals(sample, store.loadSnapshot())
    }

    @Test
    fun clearRemovesTheLiveSnapshotAndItsQuarantine() {
        val ds = newDataStore("inventory_clear.preferences_pb")
        val store = DataStoreFilterInventoryStore(ds)
        ds.writeRaw("bad")
        store.loadSnapshot()
        store.saveSnapshot(sample)

        store.clearSnapshot()

        assertNull(store.loadSnapshot())
        assertNull(ds.readQuarantine())
    }

    /** Reads succeed from [prefs]; every write (updateData/edit) fails. */
    private class ReadOkWriteFailsDataStore(private val prefs: Preferences) : DataStore<Preferences> {
        override val data: Flow<Preferences> = flowOf(prefs)
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            throw IOException("simulated quarantine write failure")
    }

    @Test
    fun quarantineWriteFailureStillReturnsRecoveredFilterSets() {
        // One undecodable Filter Set ahead of the valid ones → degraded
        // decode with survivors. The quarantine write then fails; the
        // recovered sets must still be returned, not lost to a null load.
        val withBad = FilterInventoryCodec.encode(sample)
            .replaceFirst("\"filterSets\":[", "\"filterSets\":[{\"id\":\"broken\"},")
        val store = DataStoreFilterInventoryStore(
            ReadOkWriteFailsDataStore(preferencesOf(inventoryKey to withBad)),
        )

        val loaded = store.loadSnapshot()
        assertNotNull(loaded)
        assertEquals(listOf("Lee holder", "NiSi kit"), loaded!!.filterSets.map { it.name })
    }
}
