// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.WorkspaceTimer
import com.sangwook.ptimer.core.timer.plusSecondsDouble
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Instant
import java.util.UUID

/**
 * PTIMER-216: round-trip and corrupt-payload contract tests for the concrete
 * [DataStoreTimerWorkspaceStore] adapter — a real JVM-local DataStore (backed
 * by a temp file, no Robolectric/emulator), not just the core codec.
 */
class DataStoreTimerWorkspaceStoreTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val snapshotKey = stringPreferencesKey("workspace_snapshot_json")
    private val t0: Instant = Instant.parse("2026-06-20T00:00:00Z")

    private fun newDataStore(name: String): DataStore<Preferences> {
        val file = tempFolder.newFile(name)
        return PreferenceDataStoreFactory.create(
            scope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
            produceFile = { file },
        )
    }

    private val sample = PersistentWorkspaceSnapshot.from(
        listOf(
            WorkspaceTimer(
                state = TimerState.Running(
                    UUID.fromString("00000000-0000-0000-0000-000000000001"),
                    100.0, t0, t0.plusSecondsDouble(100.0),
                ),
                identity = TimerIdentity(title = "Camera 1 · No film", slotLabel = "C1"),
            ),
        ),
    )

    @Test
    fun roundTripsAnEncodedWorkspaceSnapshot() {
        val store = DataStoreTimerWorkspaceStore(newDataStore("workspace_roundtrip.preferences_pb"))

        store.saveSnapshot(sample)

        assertEquals(sample, store.loadSnapshot())
    }

    @Test
    fun clearRemovesThePersistedSnapshotEntirely() {
        val store = DataStoreTimerWorkspaceStore(newDataStore("workspace_clear.preferences_pb"))
        store.saveSnapshot(sample)

        store.clearSnapshot()

        assertNull(store.loadSnapshot())
    }

    @Test
    fun corruptPayloadFailsSafeToNullInsteadOfThrowing() {
        val dataStore = newDataStore("workspace_corrupt.preferences_pb")
        runBlocking { dataStore.edit { it[snapshotKey] = "{\"timers\":" } }
        val store = DataStoreTimerWorkspaceStore(dataStore)

        assertNull(store.loadSnapshot())
    }

    @Test
    fun missingKeyReadsAsNullRatherThanThrowing() {
        val store = DataStoreTimerWorkspaceStore(newDataStore("workspace_empty.preferences_pb"))

        assertNull(store.loadSnapshot())
    }
}
