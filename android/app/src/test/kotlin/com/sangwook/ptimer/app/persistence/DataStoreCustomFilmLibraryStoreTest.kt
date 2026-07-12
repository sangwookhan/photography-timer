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
import kotlinx.coroutines.flow.first
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

    // MARK: - PTIMER-215 quarantine transitions

    private val quarantineKey = stringPreferencesKey("custom_film_library_json.quarantine")

    private fun DataStore<Preferences>.readQuarantine(): String? =
        runBlocking { data.first()[quarantineKey] }

    private fun DataStore<Preferences>.writeRaw(value: String) =
        runBlocking { edit { it[libraryKey] = value } }

    @Test
    fun corruptPayloadIsQuarantinedAtLoad() {
        val ds = newDataStore("library_q1.preferences_pb")
        ds.writeRaw("{not valid json")
        val store = DataStoreCustomFilmLibraryStore(ds)

        assertNull(store.loadSnapshot())
        assertEquals("{not valid json", ds.readQuarantine())
    }

    @Test
    fun secondFailureReplacesQuarantine() {
        val ds = newDataStore("library_q2.preferences_pb")
        val store = DataStoreCustomFilmLibraryStore(ds)

        ds.writeRaw("bad payload A")
        store.loadSnapshot()
        assertEquals("bad payload A", ds.readQuarantine())

        ds.writeRaw("different bad payload B")
        store.loadSnapshot()
        assertEquals("different bad payload B", ds.readQuarantine())
    }

    @Test
    fun normalSaveAfterFailureKeepsQuarantine() {
        val ds = newDataStore("library_q3.preferences_pb")
        val store = DataStoreCustomFilmLibraryStore(ds)

        ds.writeRaw("bad")
        store.loadSnapshot()

        store.saveSnapshot(PersistentCustomFilmLibrarySnapshot(films = emptyList()))
        assertEquals("bad", ds.readQuarantine())
    }

    @Test
    fun clearRemovesLiveSnapshotButKeepsQuarantine() {
        val ds = newDataStore("library_q4.preferences_pb")
        val store = DataStoreCustomFilmLibraryStore(ds)

        ds.writeRaw("bad")
        store.loadSnapshot()
        assertEquals("bad", ds.readQuarantine())

        // clearSnapshot is the "no live snapshot" operation, not a recovery
        // reset: the live key goes, the quarantine stays recoverable.
        store.clearSnapshot()
        assertNull(store.loadSnapshot())
        assertEquals("bad", ds.readQuarantine())
    }
}
