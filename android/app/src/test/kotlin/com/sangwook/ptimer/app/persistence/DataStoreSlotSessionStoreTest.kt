// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
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
 * [DataStoreSlotSessionStore] adapter — a real JVM-local DataStore (backed by
 * a temp file, no Robolectric/emulator), not just the core codec.
 */
class DataStoreSlotSessionStoreTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val sessionKey = stringPreferencesKey("slot_session_json")

    private fun newDataStore(name: String): DataStore<Preferences> {
        val file = tempFolder.newFile(name)
        return PreferenceDataStoreFactory.create(
            scope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
            produceFile = { file },
        )
    }

    private val sample = PersistentSlotSession(
        activeSlotId = CameraSlotId.camera2,
        snapshots = mapOf(
            CameraSlotId.camera1 to SlotCalculatorSnapshot(3, 1, "kodak", "p1", 30.0),
            CameraSlotId.camera2 to SlotCalculatorSnapshot(7, 0, null, null, null),
        ),
        customNames = mapOf(CameraSlotId.camera1 to "Leica"),
    )

    @Test
    fun roundTripsActiveSlotSnapshotsAndCustomNames() {
        val store = DataStoreSlotSessionStore(newDataStore("slot_roundtrip.preferences_pb"))

        store.saveSession(sample)

        assertEquals(sample, store.loadSession())
    }

    @Test
    fun clearRemovesThePersistedSessionEntirely() {
        val store = DataStoreSlotSessionStore(newDataStore("slot_clear.preferences_pb"))
        store.saveSession(sample)

        store.clearSession()

        assertNull(store.loadSession())
    }

    @Test
    fun corruptPayloadFailsSafeToNullInsteadOfThrowing() {
        val dataStore = newDataStore("slot_corrupt.preferences_pb")
        runBlocking { dataStore.edit { it[sessionKey] = "not json at all" } }
        val store = DataStoreSlotSessionStore(dataStore)

        assertNull(store.loadSession())
    }

    @Test
    fun missingKeyReadsAsNullRatherThanThrowing() {
        val store = DataStoreSlotSessionStore(newDataStore("slot_empty.preferences_pb"))

        assertNull(store.loadSession())
    }
}
