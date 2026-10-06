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
import com.sangwook.ptimer.core.exposure.FilterInventory
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
 * "Degraded" includes losses that only surface when the records are
 * restored — a Filter Set that parses but cannot be restored, and items
 * dropped inside a set that survives. Those are the user's own filter
 * records, and the next edit writes the reduced inventory over the
 * original bytes, so the copy has to be taken on the load that noticed.
 *
 * Takes the [DataStore] directly so it is unit-testable with a JVM-local
 * instance; use [create] to build the production instance from a
 * [Context].
 */
class DataStoreFilterInventoryStore(
    private val dataStore: DataStore<Preferences>,
) : FilterInventoryStoring {

    // IO wrapped so a DataStore read/write failure degrades safely (read ->
    // null only when nothing is saved, an unreadable payload or a failed
    // read -> a saved empty inventory; write/clear -> no-op) instead of
    // crashing.
    override fun loadSnapshot(): PersistentFilterInventorySnapshot? = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            val json = prefs?.get(INVENTORY_KEY) ?: return@runBlocking null
            val result = FilterInventoryCodec.decodeWithDiagnostics(json)
            if (result.indicatesFailure) {
                Log.e(
                    "ptimer.persistence",
                    "Filter inventory decode degraded: outcome=${result.outcome} " +
                        "droppedSets=${result.droppedRecordCount} " +
                        "lostOnRestore=${result.droppedOnRestoreCount}; quarantining raw payload.",
                )
                // Best-effort: a quarantine write failure must not hide the
                // Filter Sets the codec already recovered, so it is isolated
                // from the load result.
                runCatching { dataStore.edit { it[QUARANTINE_KEY] = json } }
                    .onFailure { Log.e("ptimer.persistence", "Failed to quarantine degraded payload.", it) }
            }
            // A whole-payload failure reads as a saved, empty inventory —
            // never as "nothing saved", which would seed the Samples over
            // the user's data (FILTER-SET-008); a partial failure returns
            // the recovered Filter Sets.
            when (result.outcome) {
                PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> unreadable
                else -> result.snapshot
            }
        }
    }.getOrElse {
        // A failed read is not a fresh installation either.
        Log.e("ptimer.persistence", "Filter inventory read failed; keeping the saved data untouched.", it)
        readFailed = true
        unreadable
    }

    /** Set when a read failed, so the stored bytes were never seen; the
     *  next save copies them to the quarantine key before writing over
     *  them (PERSIST-QUARANTINE-003, filter-inventory exception). */
    @Volatile private var readFailed = false

    private val unreadable: PersistentFilterInventorySnapshot
        get() = PersistentFilterInventorySnapshot.from(FilterInventory())

    override fun saveSnapshot(snapshot: PersistentFilterInventorySnapshot) {
        runCatching {
            runBlocking {
                dataStore.edit { prefs ->
                    if (readFailed) prefs[INVENTORY_KEY]?.let { prefs[QUARANTINE_KEY] = it }
                    prefs[INVENTORY_KEY] = FilterInventoryCodec.encode(snapshot)
                }
                readFailed = false
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
