// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
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
private val EXACT_ALARM_WARNING_DISMISSED_KEY = booleanPreferencesKey("exact_alarm_warning_dismissed")

/**
 * DataStore-backed store for app-global display preferences (PTIMER-187).
 * Reads fail safe to the default; a malformed/absent value decodes to the
 * documented default for each preference.
 *
 * Takes the [DataStore] directly (PTIMER-216) rather than a [Context] so it
 * is directly unit-testable with a JVM-local instance; use [create] to build
 * the production instance from a [Context].
 */
class DataStoreDisplaySettingsStore(
    private val dataStore: DataStore<Preferences>,
) {

    /** Reactive ND notation mode; emits the default until a value is written. */
    fun ndNotationModeFlow(): Flow<NDNotationMode> =
        dataStore.data.map { prefs ->
            NDNotationMode.fromName(prefs[ND_NOTATION_MODE_KEY])
        }

    /** Blocking initial read for seeding UI state at composition. */
    fun loadNdNotationMode(): NDNotationMode = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            NDNotationMode.fromName(prefs?.get(ND_NOTATION_MODE_KEY))
        }
    }.getOrDefault(NDNotationMode.DEFAULT)

    suspend fun setNdNotationMode(mode: NDNotationMode) {
        runCatching {
            dataStore.edit { it[ND_NOTATION_MODE_KEY] = mode.name }
        }
    }

    /**
     * Whether the user has acknowledged the exact-alarm warning (PTIMER-219):
     * once dismissed, the banner stops reappearing on every active timer.
     */
    fun exactAlarmWarningDismissedFlow(): Flow<Boolean> =
        dataStore.data.map { prefs ->
            prefs[EXACT_ALARM_WARNING_DISMISSED_KEY] ?: false
        }

    /** Blocking initial read for seeding UI state at composition. */
    fun loadExactAlarmWarningDismissed(): Boolean = runCatching {
        runBlocking {
            val prefs = dataStore.data.firstOrNull()
            prefs?.get(EXACT_ALARM_WARNING_DISMISSED_KEY) ?: false
        }
    }.getOrDefault(false)

    suspend fun setExactAlarmWarningDismissed(dismissed: Boolean) {
        runCatching {
            dataStore.edit { it[EXACT_ALARM_WARNING_DISMISSED_KEY] = dismissed }
        }
    }

    companion object {
        fun create(context: Context): DataStoreDisplaySettingsStore =
            DataStoreDisplaySettingsStore(context.displaySettingsDataStore)
    }
}
