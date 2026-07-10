// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.core.persistence.PersistentCustomFilmLibrarySnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * PTIMER-216: round-trip and corrupt-payload contract tests for the concrete
 * [DataStoreCustomFilmLibraryStore] adapter — a real JVM-local DataStore
 * (backed by a temp file, no Robolectric/emulator), not just the core codec.
 */
class DataStoreCustomFilmLibraryStoreTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val libraryKey = stringPreferencesKey("custom_film_library_json")

    private fun newDataStore(name: String): DataStore<Preferences> {
        val file = tempFolder.newFile(name)
        return PreferenceDataStoreFactory.create(
            scope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
            produceFile = { file },
        )
    }

    @Test
    fun roundTripsAnEncodedLibrarySnapshot() {
        val store = DataStoreCustomFilmLibraryStore(newDataStore("library_roundtrip.preferences_pb"))
        val snapshot = PersistentCustomFilmLibrarySnapshot(films = emptyList())

        store.saveSnapshot(snapshot)

        assertEquals(snapshot, store.loadSnapshot())
    }

    @Test
    fun clearRemovesThePersistedSnapshotEntirely() {
        val store = DataStoreCustomFilmLibraryStore(newDataStore("library_clear.preferences_pb"))
        store.saveSnapshot(PersistentCustomFilmLibrarySnapshot(films = emptyList()))

        store.clearSnapshot()

        assertNull(store.loadSnapshot())
    }

    @Test
    fun corruptPayloadFailsSafeToNullInsteadOfThrowing() {
        val dataStore = newDataStore("library_corrupt.preferences_pb")
        runBlocking { dataStore.edit { it[libraryKey] = "{not valid json" } }
        val store = DataStoreCustomFilmLibraryStore(dataStore)

        assertNull(store.loadSnapshot())
    }

    @Test
    fun missingKeyReadsAsNullRatherThanThrowing() {
        val store = DataStoreCustomFilmLibraryStore(newDataStore("library_empty.preferences_pb"))

        assertNull(store.loadSnapshot())
    }
}
