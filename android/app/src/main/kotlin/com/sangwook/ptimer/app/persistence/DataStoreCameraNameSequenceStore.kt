// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sangwook.ptimer.core.persistence.CameraNameSequenceCodec
import com.sangwook.ptimer.core.persistence.CameraNameSequenceLoadResult
import com.sangwook.ptimer.core.persistence.CameraNameSequenceRange
import com.sangwook.ptimer.core.persistence.CameraNameSequenceStoring
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

private val Context.cameraNameSequenceDataStore by preferencesDataStore(name = "camera_name_sequence")
private val SEQUENCE_KEY = stringPreferencesKey("camera_name_sequence_json")

/**
 * DataStore-backed [CameraNameSequenceStoring]: the automatic `Camera N`
 * sequence under its own DataStore and key, independent of the managed camera
 * list payload (CAMERA-PERSIST-001). A stored value that cannot be decoded
 * reads as [CameraNameSequenceLoadResult.Unusable]; a failed read supplies no
 * content and reads as [CameraNameSequenceLoadResult.ReadFailed].
 */
class DataStoreCameraNameSequenceStore(
    private val dataStore: DataStore<Preferences>,
) : CameraNameSequenceStoring {

    override fun load(): CameraNameSequenceLoadResult = try {
        val preferences = runBlocking { dataStore.data.firstOrNull() }
        val text = preferences?.get(SEQUENCE_KEY)
        when {
            preferences == null -> CameraNameSequenceLoadResult.ReadFailed
            text == null -> CameraNameSequenceLoadResult.Absent
            else -> CameraNameSequenceCodec.decode(text)
        }
    } catch (_: Exception) {
        CameraNameSequenceLoadResult.ReadFailed
    }

    override fun save(nextNumber: Int): Boolean {
        if (!CameraNameSequenceRange.isUsable(nextNumber)) return false
        return runCatching {
            runBlocking { dataStore.edit { it[SEQUENCE_KEY] = CameraNameSequenceCodec.encode(nextNumber) } }
        }.isSuccess
    }

    companion object {
        fun create(context: Context): DataStoreCameraNameSequenceStore =
            DataStoreCameraNameSequenceStore(context.cameraNameSequenceDataStore)
    }
}
