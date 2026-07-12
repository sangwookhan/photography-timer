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
import com.sangwook.ptimer.core.persistence.PersistenceLoadOutcome
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspacePersistenceStoring
import com.sangwook.ptimer.core.persistence.WorkspaceSnapshotCodec
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.timerWorkspaceDataStore by preferencesDataStore(name = "timer_workspace")
private val SNAPSHOT_KEY = stringPreferencesKey("workspace_snapshot_json")
private val QUARANTINE_KEY = stringPreferencesKey("workspace_snapshot_json.quarantine")

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
    // PTIMER-215: on a per-record decode failure the raw payload is copied to
    // a sibling quarantine key before any save can overwrite it, and a signal
    // is logged. A normal save never touches the quarantine.
    override fun loadSnapshot(): PersistentWorkspaceSnapshot? = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            val json = prefs?.get(SNAPSHOT_KEY) ?: return@runBlocking null
            val result = WorkspaceSnapshotCodec.decodeWithDiagnostics(json)
            if (result.indicatesFailure) {
                Log.e(
                    "ptimer.persistence",
                    "Timer workspace decode degraded: outcome=${result.outcome} " +
                        "dropped=${result.droppedRecordCount}; quarantining raw payload.",
                )
                // Best-effort: a quarantine write failure must not hide the
                // records the codec already recovered, so it is isolated from
                // the load result.
                runCatching { dataStore.edit { it[QUARANTINE_KEY] = json } }
                    .onFailure { Log.e("ptimer.persistence", "Failed to quarantine degraded payload.", it) }
            }
            // A whole-payload failure reads as empty (null), matching the prior
            // contract; a partial failure returns the recovered timers.
            when (result.outcome) {
                PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
                else -> result.snapshot
            }
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
        // Clears the live collection only; the quarantine is recovery state,
        // not part of the collection, so it survives (replaced only by a later
        // failed load).
        runCatching {
            runBlocking { dataStore.edit { it.remove(SNAPSHOT_KEY) } }
        }
    }

    companion object {
        fun create(context: Context): DataStoreTimerWorkspaceStore =
            DataStoreTimerWorkspaceStore(context.timerWorkspaceDataStore)
    }
}
