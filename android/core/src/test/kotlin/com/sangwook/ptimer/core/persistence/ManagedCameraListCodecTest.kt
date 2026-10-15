// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The managed-list payload codec (CAMERA-PERSIST-001/004/005, PERSIST-004). */
class ManagedCameraListCodecTest {

    private val snapshot = SlotCalculatorSnapshot(shutterIndex = 8, ndIndex = 3, selectedFilmId = "film", selectedProfileId = null)

    private fun loaded(text: String) =
        (ManagedCameraListCodec.decode(text) as ManagedCameraListLoadResult.Loaded).list

    @Test
    fun roundTripKeepsOrderInclusionActiveIdentitiesAndCalculatorState() {
        val payload = PersistentManagedCameraList(
            issuedIds = listOf("camera-a", "camera1", "camera2"),
            activeCameraId = "camera-a",
            cameras = listOf(
                PersistentManagedCamera("camera-a", "Leica M6", isDisplayed = true, calculator = snapshot),
                PersistentManagedCamera("camera1", "Camera 1", isDisplayed = false),
            ),
        )
        val decoded = loaded(ManagedCameraListCodec.encode(payload))
        assertEquals(payload.issuedIds, decoded.issuedIds)
        assertEquals("camera-a", decoded.activeCameraId)
        assertEquals(
            listOf(
                DecodedManagedCamera("camera-a", "Leica M6", true, snapshot),
                DecodedManagedCamera("camera1", "Camera 1", false, null),
            ),
            decoded.cameras,
        )
        assertEquals(0, decoded.skippedEntryCount)
    }

    @Test
    fun explicitNoActiveCameraAndEmptyListAreKept() {
        val text = ManagedCameraListCodec.encode(
            PersistentManagedCameraList(issuedIds = listOf("camera1"), activeCameraId = null, cameras = emptyList()),
        )
        val decoded = loaded(text)
        assertNull(decoded.activeCameraId)
        assertTrue(decoded.cameras.isEmpty())
        assertEquals(0, decoded.skippedEntryCount)
    }

    @Test
    fun malformedUnknownVersionAndMissingCamerasAreUndecodable() {
        assertEquals(ManagedCameraListLoadResult.Undecodable, ManagedCameraListCodec.decode("not json"))
        assertEquals(ManagedCameraListLoadResult.Undecodable, ManagedCameraListCodec.decode("[1,2]"))
        assertEquals(
            ManagedCameraListLoadResult.Undecodable,
            ManagedCameraListCodec.decode("""{"schemaVersion":2,"issuedIds":[],"activeCameraId":null,"cameras":[]}"""),
        )
        assertEquals(
            ManagedCameraListLoadResult.Undecodable,
            ManagedCameraListCodec.decode("""{"issuedIds":[],"activeCameraId":null,"cameras":[]}"""),
        )
        assertEquals(
            ManagedCameraListLoadResult.Undecodable,
            ManagedCameraListCodec.decode("""{"schemaVersion":1,"issuedIds":[],"activeCameraId":null}"""),
        )
    }

    @Test
    fun aKeyedRecordWithMissingFieldsKeepsTheMissingFieldsAbsentAndAnythingElseIsSkipped() {
        val text = """{"schemaVersion":1,"issuedIds":["a","b"],"activeCameraId":"b","cameras":[
            {"id":"a","name":"A","isDisplayed":true},
            {"isDisplayed":true},
            "garbage",
            {"id":"b","name":"B","isDisplayed":false}]}"""
        val decoded = loaded(text)
        assertEquals(listOf("a", null, "b"), decoded.cameras.map { it.id })
        assertNull(decoded.cameras[1].name)
        assertNull(decoded.cameras[0].calculator)
        assertEquals(1, decoded.skippedEntryCount)
    }

    @Test
    fun wronglyTypedFieldsReadAsMissing() {
        val text = """{"schemaVersion":1,"issuedIds":[],"activeCameraId":null,"cameras":[
            {"id":5,"name":["x"],"isDisplayed":"yes"}]}"""
        val camera = loaded(text).cameras.single()
        assertNull(camera.id)
        assertNull(camera.name)
        assertNull(camera.isDisplayed)
    }

    @Test
    fun anUndecodableCalculatorRestoresAsNoCalculatorStateNotAFailedCamera() {
        val text = """{"schemaVersion":1,"issuedIds":[],"activeCameraId":"a","cameras":[
            {"id":"a","name":"A","isDisplayed":true,"calculator":{"shutterIndex":"oops"}}]}"""
        val decoded = loaded(text)
        assertEquals(1, decoded.cameras.size)
        assertNull(decoded.cameras.single().calculator)
    }

    @Test
    fun unknownKeysAreIgnoredSoAnAdditiveFieldStaysReadable() {
        val text = """{"schemaVersion":1,"extra":1,"issuedIds":[],"activeCameraId":null,"cameras":[
            {"id":"a","name":"A","isDisplayed":true,"future":"x"}]}"""
        assertEquals(1, loaded(text).cameras.size)
    }

    @Test
    fun sequenceCodecAcceptsOnlyTheCurrentVersionAndTheAllocatableRange() {
        assertEquals(CameraNameSequenceLoadResult.Value(7), CameraNameSequenceCodec.decode(CameraNameSequenceCodec.encode(7)))
        assertEquals(CameraNameSequenceLoadResult.Unusable, CameraNameSequenceCodec.decode("garbage"))
        assertEquals(CameraNameSequenceLoadResult.Unusable, CameraNameSequenceCodec.decode("""{"schemaVersion":2,"nextNumber":7}"""))
        assertEquals(CameraNameSequenceLoadResult.Unusable, CameraNameSequenceCodec.decode("""{"schemaVersion":1,"nextNumber":0}"""))
        assertEquals(CameraNameSequenceLoadResult.Unusable, CameraNameSequenceCodec.decode("""{"schemaVersion":1}"""))
    }

    @Test
    fun sequenceCodecAcceptsFiveThroughIntMaxMinusOneAndNothingElse() {
        for (usable in listOf(5, 6, 1000, Int.MAX_VALUE - 1)) {
            assertEquals(
                CameraNameSequenceLoadResult.Value(usable),
                CameraNameSequenceCodec.decode("""{"schemaVersion":1,"nextNumber":$usable}"""),
            )
        }
        for (unusable in listOf(Int.MIN_VALUE, -1, 0, 1, 2, 3, 4, Int.MAX_VALUE)) {
            assertEquals(
                "nextNumber $unusable",
                CameraNameSequenceLoadResult.Unusable,
                CameraNameSequenceCodec.decode("""{"schemaVersion":1,"nextNumber":$unusable}"""),
            )
        }
        assertEquals(CameraNameSequenceLoadResult.Unusable, CameraNameSequenceCodec.decode("""{"schemaVersion":1,"nextNumber":5.5}"""))
        assertEquals(CameraNameSequenceLoadResult.Unusable, CameraNameSequenceCodec.decode("""{"schemaVersion":1,"nextNumber":2147483648}"""))
    }
}
