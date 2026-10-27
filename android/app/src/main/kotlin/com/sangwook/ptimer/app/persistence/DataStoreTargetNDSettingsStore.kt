// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.PersistentTargetNDSettings
import com.sangwook.ptimer.core.persistence.TargetNDSettingsStoring
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import com.sangwook.ptimer.core.persistence.TargetNDSettingsCodec

private val Context.targetNDSettingsDataStore by preferencesDataStore(name = "target_nd_settings")
private val TARGET_ND_SNAPSHOT = stringPreferencesKey("snapshot")

/** Synchronous adapter, invoked by bootstrap/ordered writer off the UI thread. */
class DataStoreTargetNDSettingsStore(private val dataStore: DataStore<Preferences>) : TargetNDSettingsStoring {
    override fun loadSettings(): PersistentTargetNDSettings? = runCatching {
        runBlocking {
            dataStore.data.first()[TARGET_ND_SNAPSHOT]?.let { TargetNDSettingsCodec.decode(it) }
        }
    }.getOrNull()
    override fun saveSettings(settings: PersistentTargetNDSettings) {
        runCatching { runBlocking { dataStore.edit { it[TARGET_ND_SNAPSHOT] = TargetNDSettingsCodec.encode(settings) } } }
    }
    companion object {
        fun create(context: Context) = DataStoreTargetNDSettingsStore(context.targetNDSettingsDataStore)
    }
}
