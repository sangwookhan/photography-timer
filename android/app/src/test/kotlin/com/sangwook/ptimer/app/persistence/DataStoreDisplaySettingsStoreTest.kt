// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.core.exposure.NDNotationMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * PTIMER-216: round-trip and corrupt-payload contract tests for the concrete
 * [DataStoreDisplaySettingsStore] adapter — a real JVM-local DataStore
 * (backed by a temp file, no Robolectric/emulator).
 */
class DataStoreDisplaySettingsStoreTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val ndNotationModeKey = stringPreferencesKey("nd_notation_mode")

    private fun newDataStore(name: String): DataStore<Preferences> {
        val file = tempFolder.newFile(name)
        return PreferenceDataStoreFactory.create(
            scope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
            produceFile = { file },
        )
    }

    @Test
    fun roundTripsNdNotationModeAndExactAlarmWarningDismissed() {
        val store = DataStoreDisplaySettingsStore(newDataStore("settings_roundtrip.preferences_pb"))
        val nonDefaultMode = NDNotationMode.entries.first { it != NDNotationMode.DEFAULT }

        runBlocking {
            store.setNdNotationMode(nonDefaultMode)
            store.setExactAlarmWarningDismissed(true)
        }

        assertEquals(nonDefaultMode, store.loadNdNotationMode())
        assertTrue(store.loadExactAlarmWarningDismissed())
    }

    @Test
    fun absentValuesReadAsTheDocumentedDefaults() {
        val store = DataStoreDisplaySettingsStore(newDataStore("settings_empty.preferences_pb"))

        assertEquals(NDNotationMode.DEFAULT, store.loadNdNotationMode())
        assertFalse(store.loadExactAlarmWarningDismissed())
    }

    @Test
    fun corruptNdNotationModeValueFailsSafeToTheDefaultInsteadOfThrowing() {
        val dataStore = newDataStore("settings_corrupt.preferences_pb")
        runBlocking { dataStore.edit { it[ndNotationModeKey] = "NOT_A_REAL_MODE" } }
        val store = DataStoreDisplaySettingsStore(dataStore)

        assertEquals(NDNotationMode.DEFAULT, store.loadNdNotationMode())
    }
}
