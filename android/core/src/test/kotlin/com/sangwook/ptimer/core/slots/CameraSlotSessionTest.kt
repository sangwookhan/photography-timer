// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CameraSlotSessionTest {

    private val default = SlotCalculatorSnapshot(shutterIndex = 5, ndIndex = 0, selectedFilmId = null, selectedProfileId = null)

    private fun session() = CameraSlotSession(defaultSnapshot = default)

    @Test
    fun startsOnCamera1WithDefaultIdentities() {
        val s = session()
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
        assertEquals("Camera 1", s.activeIdentity.displayName)
        assertEquals(4, s.identities().size)
    }

    @Test
    fun switchCapturesOutgoingAndRestoresIncomingDefault() {
        val s = session()
        val outgoing = SlotCalculatorSnapshot(shutterIndex = 12, ndIndex = 3, selectedFilmId = "kodak", selectedProfileId = "p1")
        val incoming = s.switchActiveSlot(CameraSlotId.camera2, outgoing)
        // Incoming camera2 has no stored snapshot yet → default.
        assertEquals(default, incoming)
        assertEquals(CameraSlotId.camera2, s.activeSlotId)
        // Switching back restores camera1's captured inputs.
        val back = s.switchActiveSlot(CameraSlotId.camera1, SlotCalculatorSnapshot(0, 0, null, null))
        assertEquals(outgoing, back)
    }

    @Test
    fun sameSlotSwitchIsNoOp() {
        val s = session()
        assertNull(s.switchActiveSlot(CameraSlotId.camera1, SlotCalculatorSnapshot(9, 9, "x", "y")))
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun renameAndResetCustomName() {
        val s = session()
        s.setCustomName("Hasselblad", CameraSlotId.camera1)
        assertEquals("Hasselblad", s.activeIdentity.displayName)
        s.setCustomName("   ", CameraSlotId.camera1)
        // Blank trims to empty → clears back to the default label.
        assertEquals("Camera 1", s.activeIdentity.displayName)
        s.setCustomName("  Leica  ", CameraSlotId.camera1)
        assertEquals("Leica", s.activeIdentity.displayName)
        s.resetCustomName(CameraSlotId.camera1)
        assertEquals("Camera 1", s.activeIdentity.displayName)
    }

    @Test
    fun snapshotForActiveSlotIsNull() {
        val s = session()
        assertNull(s.snapshot(forInactiveSlot = CameraSlotId.camera1))
        assertEquals(default, s.snapshot(forInactiveSlot = CameraSlotId.camera2))
    }

    @Test
    fun shortLabelsAreSequential() {
        assertEquals("C1", CameraSlotId.camera1.shortLabel)
        assertEquals("C4", CameraSlotId.camera4.shortLabel)
    }
}
