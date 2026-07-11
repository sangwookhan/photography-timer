// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    fun eachSlotOwnsItsSnapshotAcrossSwitches() {
        val s = session()
        // Mutate camera1's owned snapshot in place, then switch away.
        s.updateActiveSnapshot { SlotCalculatorSnapshot(shutterIndex = 12, ndIndex = 3, selectedFilmId = "kodak", selectedProfileId = "p1") }
        assertTrue(s.switchActiveSlot(CameraSlotId.camera2))
        assertEquals(CameraSlotId.camera2, s.activeSlotId)
        // camera2 keeps its own default; camera1's snapshot is untouched.
        assertEquals(default, s.activeSnapshot)
        s.updateActiveSnapshot { it.copy(ndIndex = 5) }

        // Switching back exposes camera1's snapshot exactly as left; camera2 kept its own.
        assertTrue(s.switchActiveSlot(CameraSlotId.camera1))
        assertEquals(SlotCalculatorSnapshot(12, 3, "kodak", "p1"), s.activeSnapshot)
        assertEquals(5, s.snapshot(CameraSlotId.camera2)?.ndIndex)
    }

    @Test
    fun sameSlotSwitchIsNoOp() {
        val s = session()
        assertFalse(s.switchActiveSlot(CameraSlotId.camera1))
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
    fun everyAvailableSlotHasAnOwnedSnapshot() {
        val s = session()
        // Both the active and inactive slots expose their own snapshot (default until mutated).
        assertEquals(default, s.snapshot(CameraSlotId.camera1))
        assertEquals(default, s.snapshot(CameraSlotId.camera2))
        assertEquals(s.activeSnapshot, s.snapshot(s.activeSlotId))
    }

    @Test
    fun restoresInitialSnapshotsPerSlot() {
        val camera2Snapshot = SlotCalculatorSnapshot(shutterIndex = 8, ndIndex = 2, selectedFilmId = "ilford", selectedProfileId = null)
        val s = CameraSlotSession(
            defaultSnapshot = default,
            initialSnapshots = mapOf(CameraSlotId.camera2 to camera2Snapshot),
        )
        assertEquals(default, s.snapshot(CameraSlotId.camera1))
        assertEquals(camera2Snapshot, s.snapshot(CameraSlotId.camera2))
    }

    @Test
    fun shortLabelsAreSequential() {
        assertEquals("C1", CameraSlotId.camera1.shortLabel)
        assertEquals("C4", CameraSlotId.camera4.shortLabel)
    }
}
