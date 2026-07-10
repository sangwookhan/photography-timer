// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.persistence.SlotSessionCodec
import com.sangwook.ptimer.core.persistence.SlotSessionStoring
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.slotSessionDataStore by preferencesDataStore(name = "slot_session")
private val SESSION_KEY = stringPreferencesKey("slot_session_json")

/**
 * DataStore-backed [SlotSessionStoring]. Persists the camera-slot session as the
 * codec's JSON string under a single Preferences key. The payload is tiny (≤4
 * slot snapshots), and decode is fail-safe so a corrupt store reads as a fresh
 * session. Writes are issued off the hot wheel-tick path by the caller
 * (debounced), so the bridged blocking write is negligible.
 *
 * Takes the [DataStore] directly (PTIMER-216) rather than a [Context] so it
 * is directly unit-testable with a JVM-local instance; use [create] to build
 * the production instance from a [Context].
 */
class DataStoreSlotSessionStore(
    private val dataStore: DataStore<Preferences>,
) : SlotSessionStoring {

    // IO wrapped so a DataStore read/write failure degrades safely (read ->
    // null = fresh session, write/clear -> no-op) instead of crashing.
    override fun loadSession(): PersistentSlotSession? = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            val json = prefs?.get(SESSION_KEY) ?: return@runBlocking null
            SlotSessionCodec.decode(json)
        }
    }.getOrNull()

    override fun saveSession(session: PersistentSlotSession) {
        runCatching {
            runBlocking {
                dataStore.edit { it[SESSION_KEY] = SlotSessionCodec.encode(session) }
            }
        }
    }

    override fun clearSession() {
        runCatching {
            runBlocking { dataStore.edit { it.remove(SESSION_KEY) } }
        }
    }

    companion object {
        fun create(context: Context): DataStoreSlotSessionStore =
            DataStoreSlotSessionStore(context.slotSessionDataStore)
    }
}
