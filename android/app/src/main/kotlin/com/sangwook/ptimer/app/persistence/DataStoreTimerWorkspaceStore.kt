package com.sangwook.ptimer.app.persistence

import android.content.Context
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
 */
class DataStoreTimerWorkspaceStore(private val context: Context) : WorkspacePersistenceStoring {

    // Each IO call is wrapped so a DataStore read/write failure degrades safely
    // (read -> null, write/clear -> no-op) instead of crashing the caller.
    override fun loadSnapshot(): PersistentWorkspaceSnapshot? = runCatching {
        runBlocking {
            val prefs = context.timerWorkspaceDataStore.data.firstOrNull()
            val json = prefs?.get(SNAPSHOT_KEY) ?: return@runBlocking null
            WorkspaceSnapshotCodec.decode(json)
        }
    }.getOrNull()

    override fun saveSnapshot(snapshot: PersistentWorkspaceSnapshot) {
        runCatching {
            runBlocking {
                context.timerWorkspaceDataStore.edit { it[SNAPSHOT_KEY] = WorkspaceSnapshotCodec.encode(snapshot) }
            }
        }
    }

    override fun clearSnapshot() {
        runCatching {
            runBlocking { context.timerWorkspaceDataStore.edit { it.remove(SNAPSHOT_KEY) } }
        }
    }
}
