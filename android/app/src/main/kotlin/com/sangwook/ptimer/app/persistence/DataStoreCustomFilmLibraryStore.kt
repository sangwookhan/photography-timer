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
import com.sangwook.ptimer.core.persistence.CustomFilmLibraryCodec
import com.sangwook.ptimer.core.persistence.CustomFilmLibraryStoring
import com.sangwook.ptimer.core.persistence.PersistenceLoadOutcome
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.customFilmLibraryDataStore by preferencesDataStore(name = "custom_film_library")
private val LIBRARY_KEY = stringPreferencesKey("custom_film_library_json")
private val QUARANTINE_KEY = stringPreferencesKey("custom_film_library_json.quarantine")

/**
 * DataStore-backed [CustomFilmLibraryStoring]. Persists the custom film
 * library as the codec's JSON string under a single Preferences key. Writes
 * are infrequent (only on create/delete), so the bridged blocking write is
 * negligible; decode is fail-safe so a corrupt store reads as empty.
 *
 * Takes the [DataStore] directly (PTIMER-216) rather than a [Context] so it
 * is directly unit-testable with a JVM-local instance; use [create] to build
 * the production instance from a [Context].
 */
class DataStoreCustomFilmLibraryStore(
    private val dataStore: DataStore<Preferences>,
) : CustomFilmLibraryStoring {

    // IO wrapped so a DataStore read/write failure degrades safely (read ->
    // null = empty library, write/clear -> no-op) instead of crashing.
    // PTIMER-215: on a per-record decode failure the raw payload is copied to
    // a sibling quarantine key before any save can overwrite it, and a signal
    // is logged. A normal save never touches the quarantine.
    override fun loadSnapshot(): PersistentCustomFilmLibrarySnapshot? = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            val json = prefs?.get(LIBRARY_KEY) ?: return@runBlocking null
            val result = CustomFilmLibraryCodec.decodeWithDiagnostics(json)
            if (result.indicatesFailure) {
                dataStore.edit { it[QUARANTINE_KEY] = json }
                Log.e(
                    "ptimer.persistence",
                    "Custom film library decode degraded: outcome=${result.outcome} " +
                        "dropped=${result.droppedRecordCount}; raw payload quarantined.",
                )
            }
            // A whole-payload failure reads as an empty library (null),
            // matching the prior contract; a partial failure returns the
            // recovered films.
            when (result.outcome) {
                PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
                else -> result.snapshot
            }
        }
    }.getOrNull()

    override fun saveSnapshot(snapshot: PersistentCustomFilmLibrarySnapshot) {
        runCatching {
            runBlocking {
                dataStore.edit { it[LIBRARY_KEY] = CustomFilmLibraryCodec.encode(snapshot) }
            }
        }
    }

    override fun clearSnapshot() {
        // Clears the live collection only; the quarantine is recovery state,
        // not part of the collection, so it survives (replaced only by a later
        // failed load).
        runCatching {
            runBlocking { dataStore.edit { it.remove(LIBRARY_KEY) } }
        }
    }

    companion object {
        fun create(context: Context): DataStoreCustomFilmLibraryStore =
            DataStoreCustomFilmLibraryStore(context.customFilmLibraryDataStore)
    }
}
