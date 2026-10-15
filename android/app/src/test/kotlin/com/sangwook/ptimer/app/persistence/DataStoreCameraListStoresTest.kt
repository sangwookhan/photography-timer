// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.core.persistence.CameraListPersistenceController
import com.sangwook.ptimer.core.persistence.CameraNameSequenceLoadResult
import com.sangwook.ptimer.core.persistence.ManagedCameraListLoadResult
import com.sangwook.ptimer.core.persistence.PersistentManagedCamera
import com.sangwook.ptimer.core.persistence.SlotSessionLoadResult
import com.sangwook.ptimer.core.persistence.PersistentManagedCameraList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Round-trip and corrupt-payload contract tests for the concrete managed
 * camera list and automatic-name sequence stores, over a real JVM-local
 * DataStore (a temp file, no Robolectric or emulator).
 */
class DataStoreCameraListStoresTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun newDataStore(name: String): DataStore<Preferences> {
        val file = tempFolder.newFile(name)
        return PreferenceDataStoreFactory.create(
            scope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
            produceFile = { file },
        )
    }

    /** A DataStore whose reads fail without supplying content and whose writes fail too. */
    private class FailingDataStore : DataStore<Preferences> {
        var updates = 0
        override val data: Flow<Preferences> = flow { throw IOException("read failed") }
        override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences {
            updates++
            throw IOException("write failed")
        }
    }

    private fun DataStore<Preferences>.put(key: String, value: String) =
        runBlocking { edit { it[stringPreferencesKey(key)] = value } }

    private val payload = PersistentManagedCameraList(
        issuedIds = listOf("camera1", "camera-x"),
        activeCameraId = "camera-x",
        cameras = listOf(
            PersistentManagedCamera("camera-x", "Leica M6", isDisplayed = true),
            PersistentManagedCamera("camera1", "Camera 1", isDisplayed = false),
        ),
    )

    @Test
    fun managedListIsAbsentUntilSavedThenRoundTrips() {
        val store = DataStoreManagedCameraListStore(newDataStore("managed.preferences_pb"))
        assertEquals(ManagedCameraListLoadResult.Absent, store.load())

        assertTrue(store.save(payload))

        val loaded = (store.load() as ManagedCameraListLoadResult.Loaded).list
        assertEquals(payload.cameras.map { it.id to it.name }, loaded.cameras.map { it.id to it.name })
        assertEquals("camera-x", loaded.activeCameraId)
        assertEquals(payload.issuedIds, loaded.issuedIds)
    }

    @Test
    fun aCorruptOrUnsupportedManagedPayloadReadsAsUndecodableAndIsNotOverwrittenByLoad() {
        val ds = newDataStore("managed_bad.preferences_pb")
        val store = DataStoreManagedCameraListStore(ds)
        ds.put("managed_camera_list_json", "{not json")
        assertEquals(ManagedCameraListLoadResult.Undecodable, store.load())
        ds.put("managed_camera_list_json", """{"schemaVersion":99,"cameras":[]}""")
        assertEquals(ManagedCameraListLoadResult.Undecodable, store.load())
        // Loading never rewrote the stored text.
        assertEquals(ManagedCameraListLoadResult.Undecodable, store.load())
    }

    @Test
    fun sequenceIsAbsentUntilSavedThenRoundTrips() {
        val store = DataStoreCameraNameSequenceStore(newDataStore("sequence.preferences_pb"))
        assertEquals(CameraNameSequenceLoadResult.Absent, store.load())

        assertTrue(store.save(5))
        assertEquals(CameraNameSequenceLoadResult.Value(5), store.load())
        assertTrue(store.save(6))
        assertEquals(CameraNameSequenceLoadResult.Value(6), store.load())
    }

    @Test
    fun aCorruptUnsupportedOrOutOfRangeSequenceReadsAsUnusable() {
        val ds = newDataStore("sequence_bad.preferences_pb")
        val store = DataStoreCameraNameSequenceStore(ds)
        val outOfRange = listOf(-1, 0, 1, 2, 3, 4, Int.MAX_VALUE).map { """{"schemaVersion":1,"nextNumber":$it}""" }
        for (bad in listOf("garbage", """{"schemaVersion":2,"nextNumber":7}""") + outOfRange) {
            ds.put("camera_name_sequence_json", bad)
            assertEquals(CameraNameSequenceLoadResult.Unusable, store.load())
        }
    }

    @Test
    fun theSequenceRefusesNumbersOutsideTheAllocatableRange() {
        val store = DataStoreCameraNameSequenceStore(newDataStore("sequence_range.preferences_pb"))
        for (bad in listOf(Int.MIN_VALUE, -1, 0, 1, 4, Int.MAX_VALUE)) {
            assertFalse("save $bad", store.save(bad))
            assertEquals(CameraNameSequenceLoadResult.Absent, store.load())
        }
        assertTrue(store.save(5))
        assertTrue(store.save(Int.MAX_VALUE - 1))
    }

    @Test
    fun theTwoStoresLiveInSeparateDataStores() {
        val managedDs = newDataStore("managed_sep.preferences_pb")
        val sequenceDs = newDataStore("sequence_sep.preferences_pb")
        DataStoreManagedCameraListStore(managedDs).save(payload)
        assertEquals(CameraNameSequenceLoadResult.Absent, DataStoreCameraNameSequenceStore(sequenceDs).load())
    }

    @Test
    fun aFailedReadSuppliesNoContentAndIsDistinctFromAbsentAndUndecodable() {
        val failing = FailingDataStore()
        assertEquals(ManagedCameraListLoadResult.ReadFailed, DataStoreManagedCameraListStore(failing).load())
        assertEquals(CameraNameSequenceLoadResult.ReadFailed, DataStoreCameraNameSequenceStore(failing).load())
        assertEquals(SlotSessionLoadResult.ReadFailed, DataStoreSlotSessionStore(failing).load())
        // Reading never deletes or writes.
        assertEquals(0, failing.updates)
    }

    @Test
    fun theLegacyStoreDistinguishesAbsentLoadedAndUnsupportedContent() {
        val ds = newDataStore("legacy.preferences_pb")
        val store = DataStoreSlotSessionStore(ds)
        assertEquals(SlotSessionLoadResult.Absent, store.load())
        ds.put("slot_session_json", "{not json")
        assertEquals(SlotSessionLoadResult.Unsupported, store.load())
    }

    private fun managedWithOneCamera(name: String): DataStore<Preferences> {
        val ds = newDataStore(name)
        DataStoreManagedCameraListStore(ds).save(payload)
        return ds
    }

    @Test
    fun aDecodableButInvalidSequenceStartsTheAllocatorAtFiveAndStoresSix() {
        val sequenceDs = newDataStore("sequence_invalid.preferences_pb")
        sequenceDs.put("camera_name_sequence_json", """{"schemaVersion":2,"nextNumber":9}""")
        val controller = CameraListPersistenceController(
            DataStoreManagedCameraListStore(managedWithOneCamera("managed_for_invalid_seq.preferences_pb")),
            sequenceStore = DataStoreCameraNameSequenceStore(sequenceDs),
        )
        controller.restore()

        assertFalse(controller.isReadFailed)
        assertEquals(5, controller.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Value(6), DataStoreCameraNameSequenceStore(sequenceDs).load())
    }

    @Test
    fun anActualSequenceReadFailureUsesTheFallbackAndStoresSixWithoutBlockingCameraState() {
        val underlying = newDataStore("sequence_read_fails.preferences_pb")
        val readFails = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = flow { throw IOException("read failed") }
            override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences) =
                underlying.updateData(transform)
        }
        val controller = CameraListPersistenceController(
            DataStoreManagedCameraListStore(managedWithOneCamera("managed_for_failed_seq.preferences_pb")),
            sequenceStore = DataStoreCameraNameSequenceStore(readFails),
        )
        controller.restore()

        assertFalse(controller.isReadFailed)
        assertEquals(5, controller.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Value(6), DataStoreCameraNameSequenceStore(underlying).load())
    }

    @Test
    fun aSequenceReadFailureWithAFailingWriteCreatesNoCamera() {
        val failing = FailingDataStore()
        val controller = CameraListPersistenceController(
            DataStoreManagedCameraListStore(managedWithOneCamera("managed_for_failed_seq_write.preferences_pb")),
            sequenceStore = DataStoreCameraNameSequenceStore(failing),
        )
        controller.restore()

        assertEquals(null, controller.reserveNextCameraNumber())
    }

    @Test
    fun anOutOfRangeStoredSequenceStoresSixThroughTheRealStoreBeforeCameraFive() {
        listOf(1, 2, 3, 4, Int.MAX_VALUE).forEach { stored ->
            val sequenceDs = newDataStore("sequence_out_of_range_$stored.preferences_pb")
            sequenceDs.put("camera_name_sequence_json", """{"schemaVersion":1,"nextNumber":$stored}""")
            val controller = CameraListPersistenceController(
                DataStoreManagedCameraListStore(managedWithOneCamera("managed_for_out_of_range_$stored.preferences_pb")),
                sequenceStore = DataStoreCameraNameSequenceStore(sequenceDs),
            )
            controller.restore()

            assertFalse(controller.isReadFailed)
            assertEquals("stored $stored", 5, controller.reserveNextCameraNumber())
            // Six is durable by the time the caller can commit Camera 5.
            assertEquals(CameraNameSequenceLoadResult.Value(6), DataStoreCameraNameSequenceStore(sequenceDs).load())
        }
    }

    @Test
    fun anOutOfRangeStoredSequenceWithAFailingWriteReservesNothing() {
        val underlying = newDataStore("sequence_out_of_range_write_fails.preferences_pb")
        underlying.put("camera_name_sequence_json", """{"schemaVersion":1,"nextNumber":3}""")
        val writeFails = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = underlying.data
            override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
                throw IOException("write failed")
        }
        val controller = CameraListPersistenceController(
            DataStoreManagedCameraListStore(managedWithOneCamera("managed_for_out_of_range_write.preferences_pb")),
            sequenceStore = DataStoreCameraNameSequenceStore(writeFails),
        )
        controller.restore()

        assertEquals(null, controller.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Unusable, DataStoreCameraNameSequenceStore(underlying).load())
    }
}
