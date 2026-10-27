// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.app.vm.TargetNDSettingsModel
import com.sangwook.ptimer.core.exposure.TargetNDAllowance
import com.sangwook.ptimer.core.exposure.TargetNDSettings
import com.sangwook.ptimer.core.persistence.PersistentTargetNDSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DataStoreTargetNDSettingsStoreTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun globalSettingsRoundTripKeepsOtherPreferencesAndIndependentChoices() {
        val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
        try {
            val data = PreferenceDataStoreFactory.create(scope = scope, produceFile = { temporary.newFile("settings.preferences_pb") })
            val sentinel = stringPreferencesKey("camera-sentinel")
            runBlocking { data.edit { it[sentinel] = "unchanged" } }
            val store = DataStoreTargetNDSettingsStore(data)
            assertNull(store.loadSettings())
            val initial = TargetNDSettings()
            val model = TargetNDSettingsModel(initial, store, PersistenceWriter { it() })
            val chosen = initial.copy(isEnabled = false, negative = TargetNDAllowance.extended, digital = TargetNDAllowance.extended)
            model.update(chosen)
            assertEquals(chosen, store.loadSettings()?.restored)
            assertEquals(TargetNDAllowance.standard, model.settings.value.positive)
            assertEquals("unchanged", runBlocking { data.data.first()[sentinel] })
            val recreated = TargetNDSettingsModel(requireNotNull(store.loadSettings()).restored, store, PersistenceWriter { it() })
            assertEquals(chosen, recreated.settings.value)
        } finally { scope.cancel() }
    }

    @Test fun missingUnknownAndMalformedSettingsFailSafePerField() {
        val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
        try {
            val data = PreferenceDataStoreFactory.create(scope = scope, produceFile = { temporary.newFile("legacy.preferences_pb") })
            val key = stringPreferencesKey("snapshot")
            val store = DataStoreTargetNDSettingsStore(data)
            runBlocking { data.edit { it[key] = "{}" } }
            assertEquals(TargetNDSettings(), store.loadSettings()?.restored)
            runBlocking { data.edit { it[key] = "{\"isEnabled\":false,\"negativeRaw\":\"extended\",\"positiveRaw\":\"future\"}" } }
            val restored = requireNotNull(store.loadSettings()).restored
            assertFalse(restored.isEnabled)
            assertEquals(TargetNDAllowance.extended, restored.negative)
            assertEquals(TargetNDAllowance.standard, restored.positive)
            assertEquals(TargetNDAllowance.standard, restored.digital)
            runBlocking { data.edit { it[key] = "malformed" } }
            assertNull(store.loadSettings())
        } finally { scope.cancel() }
    }
}
