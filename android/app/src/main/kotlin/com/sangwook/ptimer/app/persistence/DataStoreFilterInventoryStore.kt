// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.FilterInventoryCodec
import com.sangwook.ptimer.core.persistence.FilterInventoryStoring
import com.sangwook.ptimer.core.persistence.PersistenceLoadOutcome
import com.sangwook.ptimer.core.persistence.PersistentFilterInventorySnapshot
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.filterInventoryDataStore by preferencesDataStore(name = "filter_inventory")
private val INVENTORY_KEY = stringPreferencesKey("filter_inventory_json")
private val QUARANTINE_KEY = stringPreferencesKey("filter_inventory_json.quarantine")

/**
 * DataStore-backed [FilterInventoryStoring] (FILTER-PERSIST-001/002).
 * Persists the user's Filter Sets and physical items as the codec's JSON
 * string under a single Preferences key, in its own store file so an
 * inventory payload can never damage the slot session.
 *
 * Decode is per-record and fail-safe: one undecodable Filter Set is
 * dropped and the rest of the inventory survives. On any degraded outcome
 * the raw payload is copied to a sibling quarantine key BEFORE a later
 * save can overwrite it, and a signal is logged — the same recovery
 * pattern as [DataStoreCustomFilmLibraryStore]. A normal save never
 * touches the quarantine.
 *
 * Takes the [DataStore] directly so it is unit-testable with a JVM-local
 * instance; use [create] to build the production instance from a
 * [Context].
 */
class DataStoreFilterInventoryStore(
    private val dataStore: DataStore<Preferences>,
) : FilterInventoryStoring {

    // IO wrapped so a DataStore read/write failure degrades safely (read ->
    // null = empty inventory, write/clear -> no-op) instead of crashing.
    override fun loadSnapshot(): PersistentFilterInventorySnapshot? = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            val json = prefs?.get(INVENTORY_KEY) ?: return@runBlocking null
            val result = FilterInventoryCodec.decodeWithDiagnostics(json)
            if (result.indicatesFailure) {
                Log.e(
                    "ptimer.persistence",
                    "Filter inventory decode degraded: outcome=${result.outcome} " +
                        "dropped=${result.droppedRecordCount}; quarantining raw payload.",
                )
                // Best-effort: a quarantine write failure must not hide the
                // Filter Sets the codec already recovered, so it is isolated
                // from the load result.
                runCatching { dataStore.edit { it[QUARANTINE_KEY] = json } }
                    .onFailure { Log.e("ptimer.persistence", "Failed to quarantine degraded payload.", it) }
            }
            // A whole-payload failure reads as an empty inventory (null); a
            // partial failure returns the recovered Filter Sets.
            when (result.outcome) {
                PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
                else -> result.snapshot
            }
        }
    }.getOrNull()

    override fun saveSnapshot(snapshot: PersistentFilterInventorySnapshot) {
        runCatching {
            runBlocking {
                dataStore.edit { it[INVENTORY_KEY] = FilterInventoryCodec.encode(snapshot) }
            }
        }
    }

    /** Clears the live inventory AND its quarantine (a full reset). */
    override fun clearSnapshot() {
        runCatching {
            runBlocking {
                dataStore.edit {
                    it.remove(INVENTORY_KEY)
                    it.remove(QUARANTINE_KEY)
                }
            }
        }
    }

    companion object {
        fun create(context: Context): DataStoreFilterInventoryStore =
            DataStoreFilterInventoryStore(context.filterInventoryDataStore)
    }
}
