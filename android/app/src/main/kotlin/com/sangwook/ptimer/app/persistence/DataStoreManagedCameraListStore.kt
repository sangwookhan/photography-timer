// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.ManagedCameraListCodec
import com.sangwook.ptimer.core.persistence.ManagedCameraListLoadResult
import com.sangwook.ptimer.core.persistence.ManagedCameraListStoring
import com.sangwook.ptimer.core.persistence.PersistentManagedCameraList
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.managedCameraListDataStore by preferencesDataStore(name = "managed_camera_list")
private val MANAGED_LIST_KEY = stringPreferencesKey("managed_camera_list_json")

/**
 * DataStore-backed [ManagedCameraListStoring]: the managed camera list as the
 * codec's JSON string under its own DataStore, separate from the legacy
 * slot-session store (which stays untouched as the migration source) and from
 * the automatic-name sequence store. One Preferences edit commits the whole
 * payload, so a save lands entirely or not at all.
 *
 * A read that fails reads as [ManagedCameraListLoadResult.ReadFailed], so a
 * transient I/O failure never deletes, reseeds, or migrates over stored data.
 * Writes are issued on the shared persistence writer by the caller.
 */
class DataStoreManagedCameraListStore(
    private val dataStore: DataStore<Preferences>,
) : ManagedCameraListStoring {

    override fun load(): ManagedCameraListLoadResult = try {
        val preferences = runBlocking { dataStore.data.firstOrNull() }
        val text = preferences?.get(MANAGED_LIST_KEY)
        when {
            preferences == null -> ManagedCameraListLoadResult.ReadFailed
            text == null -> ManagedCameraListLoadResult.Absent
            else -> ManagedCameraListCodec.decode(text)
        }
    } catch (_: Exception) {
        ManagedCameraListLoadResult.ReadFailed
    }

    override fun save(payload: PersistentManagedCameraList): Boolean = runCatching {
        runBlocking { dataStore.edit { it[MANAGED_LIST_KEY] = ManagedCameraListCodec.encode(payload) } }
    }.isSuccess

    companion object {
        fun create(context: Context): DataStoreManagedCameraListStore =
            DataStoreManagedCameraListStore(context.managedCameraListDataStore)
    }
}
