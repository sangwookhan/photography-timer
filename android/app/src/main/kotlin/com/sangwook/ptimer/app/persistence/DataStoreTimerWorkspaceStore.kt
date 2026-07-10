// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.persistence.WorkspaceSnapshotCodec
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.timerWorkspaceDataStore by preferencesDataStore(name = "timer_workspace")
private val SNAPSHOT_KEY = stringPreferencesKey("workspace_snapshot_json")

/**
 * DataStore-backed [WorkspacePersistenceStoring]. Persists the workspace
 * snapshot as the codec's JSON string under a single Preferences key. Reads/
 * writes are bridged synchronously to satisfy the store interface; the payload
 * is small (a handful of timers) so blocking is negligible, and decode is
 * fail-safe so a corrupt store reads as empty.
 *
 * Takes the [DataStore] directly (PTIMER-216) rather than a [Context] so it
 * is directly unit-testable with a JVM-local instance; use [create] to build
 * the production instance from a [Context].
 */
class DataStoreTimerWorkspaceStore(
    private val dataStore: DataStore<Preferences>,
) : WorkspacePersistenceStoring {

    // Each IO call is wrapped so a DataStore read/write failure degrades safely
    // (read -> null, write/clear -> no-op) instead of crashing the caller.
    override fun loadSnapshot(): PersistentWorkspaceSnapshot? = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            val json = prefs?.get(SNAPSHOT_KEY) ?: return@runBlocking null
            WorkspaceSnapshotCodec.decode(json)
        }
    }.getOrNull()

    override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) {
        runCatching {
            runBlocking {
                dataStore.edit { it[SNAPSHOT_KEY] = WorkspaceSnapshotCodec.encode(snapshot) }
            }
        }
    }

    override fun clearSnapshot() {
        runCatching {
            runBlocking { dataStore.edit { it.remove(SNAPSHOT_KEY) } }
        }
    }

    companion object {
        fun create(context: Context): DataStoreTimerWorkspaceStore =
            DataStoreTimerWorkspaceStore(context.timerWorkspaceDataStore)
    }
}
