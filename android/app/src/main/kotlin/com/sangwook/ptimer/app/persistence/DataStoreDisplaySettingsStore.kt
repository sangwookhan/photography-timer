// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.exposure.NDNotationMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking

private val Context.displaySettingsDataStore by preferencesDataStore(name = "display_settings")
private val ND_NOTATION_MODE_KEY = stringPreferencesKey("nd_notation_mode")

/**
 * DataStore-backed store for app-global display preferences (PTIMER-187).
 * Currently just the ND notation mode. Reads fail safe to the default; a
 * malformed/absent value decodes to [NDNotationMode.DEFAULT].
 */
class DataStoreDisplaySettingsStore(private val context: Context) {

    /** Reactive ND notation mode; emits the default until a value is written. */
    fun ndNotationModeFlow(): Flow<NDNotationMode> =
        context.displaySettingsDataStore.data.map { prefs ->
            NDNotationMode.fromName(prefs[ND_NOTATION_MODE_KEY])
        }

    /** Blocking initial read for seeding UI state at composition. */
    fun loadNdNotationMode(): NDNotationMode = runCatching {
        runBlocking {
            val prefs = context.displaySettingsDataStore.data.firstOrNull()
            NDNotationMode.fromName(prefs?.get(ND_NOTATION_MODE_KEY))
        }
    }.getOrDefault(NDNotationMode.DEFAULT)

    suspend fun setNdNotationMode(mode: NDNotationMode) {
        runCatching {
            context.displaySettingsDataStore.edit { it[ND_NOTATION_MODE_KEY] = mode.name }
        }
    }
}
