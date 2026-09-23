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
