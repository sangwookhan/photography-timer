// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** Camera identity and naming rules (CAMERA-004, CAMERA-NAME-001, CAMERA-TIMER-003). */
class CameraIdentityTest {

    @Test
    fun legacyIdentitiesKeepTheirRawValuesVerbatim() {
        assertEquals(listOf("camera1", "camera2", "camera3", "camera4"), CameraSlotId.legacyOrdered.map { it.raw })
        assertEquals(1, CameraSlotId.camera1.legacyNumber)
        assertEquals(4, CameraSlotId.camera4.legacyNumber)
        assertNull(CameraSlotId("camera5").legacyNumber)
    }

    @Test
    fun blankRawIdentityIsRejected() {
        assertThrows(IllegalArgumentException::class.java) { CameraSlotId("") }
        assertThrows(IllegalArgumentException::class.java) { CameraSlotId("  ") }
    }

    @Test
    fun identityRoundTripsAsAPlainString() {
        val json = Json
        assertEquals("\"camera2\"", json.encodeToString(CameraSlotId.serializer(), CameraSlotId.camera2))
        assertEquals(CameraSlotId("camera-x"), json.decodeFromString(CameraSlotId.serializer(), "\"camera-x\""))
        assertThrows(SerializationException::class.java) { json.decodeFromString(CameraSlotId.serializer(), "\"\"") }
    }

    @Test
    fun generatedIdentitiesAreUniqueAndNeverALegacyIdentity() {
        val ids = List(200) { CameraSlotId.generate() }
        assertEquals(200, ids.toSet().size)
        assertFalse(ids.any { it in CameraSlotId.legacyOrdered })
        assertFalse(ids.any { it.raw.matches(Regex("camera\\d+")) })
    }

    @Test
    fun trimmedNameRejectsBlankInput() {
        assertEquals("Leica", CameraNaming.trimmedName("  Leica "))
        assertNull(CameraNaming.trimmedName("   "))
        assertNull(CameraNaming.trimmedName(null))
    }

    @Test
    fun identityWithoutAStoredNameFallsBackToTheLegacyLabelOrTheRawId() {
        assertEquals("Camera 3", CameraSlotIdentity(CameraSlotId.camera3).displayName)
        assertEquals("camera-abc", CameraSlotIdentity(CameraSlotId("camera-abc")).displayName)
    }

    @Test
    fun compactLabelKeepsLegacyBadgesAndDerivesOthersFromTheCapturedName() {
        assertEquals("C2", CameraNaming.compactLabel(CameraSlotId.camera2, "Renamed"))
        val other = CameraSlotId("camera-x")
        assertEquals("C5", CameraNaming.compactLabel(other, "Camera 5"))
        assertEquals("L6", CameraNaming.compactLabel(other, "Leica M6"))
        assertEquals("C23", CameraNaming.compactLabel(other, "Camera 123"))
        assertEquals("35", CameraNaming.compactLabel(other, "35"))
        assertEquals("7", CameraNaming.compactLabel(other, "7"))
        assertEquals("HA", CameraNaming.compactLabel(other, "Hasselblad"))
    }
}
