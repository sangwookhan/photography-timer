// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The managed camera list model (CAMERA-001..007, ORDER, PAGER-001/003, STATE). */
class CameraSlotSessionTest {

    private val default = SlotCalculatorSnapshot(shutterIndex = 5, ndIndex = 0, selectedFilmId = null, selectedProfileId = null)

    private fun seeded() = CameraListSnapshot.seeded { "Camera $it" }

    private fun session(
        initial: CameraListSnapshot = seeded(),
        generate: () -> CameraSlotId = { CameraSlotId.generate() },
    ) = CameraSlotSession(initial, default, generate)

    private fun CameraSlotSession.names() = cameras.map { it.name }

    private fun id(n: Int) = CameraSlotId("camera-test-$n")

    @Test
    fun defaultListIsTheFourSeededCamerasShownInOrderWithCameraOneActive() {
        val s = session()
        assertEquals(CameraSlotId.legacyOrdered, s.cameraIds)
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), s.names())
        assertTrue(s.cameras.all { it.isDisplayed })
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
        assertEquals("Camera 1", s.activeIdentity?.displayName)
    }

    @Test
    fun addAppendsAShownActiveCameraWithTheGivenNameAndFreshDefaults() {
        val s = session()
        s.updateActiveSnapshot { it.copy(shutterIndex = 20) }
        val added = s.addCamera("Camera 5")
        assertEquals(CameraSlotId.legacyOrdered + added, s.cameraIds)
        assertEquals("Camera 5", s.identity(added)?.displayName)
        assertTrue(s.entry(added)!!.isDisplayed)
        assertEquals(added, s.activeSlotId)
        assertEquals(default, s.snapshot(added))
        assertEquals(20, s.snapshot(CameraSlotId.camera1)?.shutterIndex)
    }

    @Test
    fun addNeverReusesAFreedIdentity() {
        val s = session()
        val first = s.addCamera("A")
        s.deleteCameras(setOf(first))
        val second = s.addCamera("B")
        assertNotEquals(first, second)
        assertTrue(first in s.issuedIds)
    }

    @Test
    fun addRedrawsWhenAGeneratedIdentityWasAlreadyIssued() {
        // The first offered identity is already issued (camera2): it is skipped.
        val queue = ArrayDeque(listOf(CameraSlotId.camera2, id(1)))
        val s = session(generate = { queue.removeFirst() })
        assertEquals(id(1), s.addCamera("A"))
        // A deleted camera's identity stays issued and is skipped too.
        s.deleteCameras(setOf(id(1)))
        queue.addAll(listOf(id(1), id(2)))
        assertEquals(id(2), s.addCamera("B"))
    }

    @Test
    fun theModelNeverDerivesAnAddedCamerasNameFromTheList() {
        val s = session()
        s.renameCamera(CameraSlotId.camera1, "Camera 99")
        val added = s.addCamera("Camera 5")
        assertEquals("Camera 5", s.identity(added)?.displayName)
    }

    @Test
    fun thereIsNoNumericLimitOnTheList() {
        val s = session()
        repeat(60) { s.addCamera("Camera ${it + 5}") }
        assertEquals(64, s.cameras.size)
        assertEquals(64, s.displayedIds.size)
    }

    @Test
    fun renameTrimsAndRejectsBlankNames() {
        val s = session()
        assertTrue(s.renameCamera(CameraSlotId.camera1, "  Leica  "))
        assertEquals("Leica", s.identity(CameraSlotId.camera1)?.displayName)
        assertFalse(s.renameCamera(CameraSlotId.camera1, "   "))
        assertFalse(s.renameCamera(CameraSlotId.camera1, ""))
        assertEquals("Leica", s.identity(CameraSlotId.camera1)?.displayName)
        assertFalse(s.renameCamera(CameraSlotId("missing"), "X"))
    }

    @Test
    fun duplicateAndHistoricalNamesAreAllowedAndKeepDistinctIdentities() {
        val s = session()
        s.renameCamera(CameraSlotId.camera2, "Camera 1")
        assertEquals("Camera 1", s.identity(CameraSlotId.camera2)?.displayName)
        assertNotEquals(s.identity(CameraSlotId.camera1)?.id, s.identity(CameraSlotId.camera2)?.id)
        s.deleteCameras(setOf(CameraSlotId.camera3))
        val reused = s.addCamera("Camera 3")
        assertNotEquals(CameraSlotId.camera3, reused)
        assertNull(s.snapshot(CameraSlotId.camera3))
    }

    @Test
    fun renameDoesNotTouchCalculatorState() {
        val s = session()
        s.updateSnapshot(CameraSlotId.camera2) { it.copy(shutterIndex = 9) }
        s.renameCamera(CameraSlotId.camera2, "Hasselblad")
        assertEquals(9, s.snapshot(CameraSlotId.camera2)?.shutterIndex)
    }

    @Test
    fun hidingPreservesNamePositionAndStateAndShowingRestoresThePosition() {
        val s = session()
        s.updateSnapshot(CameraSlotId.camera3) { it.copy(shutterIndex = 7) }
        s.renameCamera(CameraSlotId.camera3, "Rollei")
        s.setDisplayed(CameraSlotId.camera3, false)
        assertEquals(listOf(CameraSlotId.camera1, CameraSlotId.camera2, CameraSlotId.camera4), s.displayedIds)
        assertEquals(CameraSlotId.legacyOrdered, s.cameraIds)
        assertEquals("Rollei", s.identity(CameraSlotId.camera3)?.displayName)
        assertEquals(7, s.snapshot(CameraSlotId.camera3)?.shutterIndex)
        s.setDisplayed(CameraSlotId.camera3, true)
        assertEquals(CameraSlotId.legacyOrdered, s.displayedIds)
    }

    @Test
    fun hidingTheActiveCameraActivatesTheNextDisplayedCamera() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera2)
        s.setDisplayed(CameraSlotId.camera2, false)
        assertEquals(CameraSlotId.camera3, s.activeSlotId)
    }

    @Test
    fun hidingTheActiveLastCameraActivatesTheFirstDisplayedCamera() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera4)
        s.setDisplayed(CameraSlotId.camera4, false)
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun hidingAnInactiveCameraKeepsTheActiveCamera() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera3)
        s.setDisplayed(CameraSlotId.camera1, false)
        assertEquals(CameraSlotId.camera3, s.activeSlotId)
    }

    @Test
    fun hidingTheLastDisplayedCameraLeavesNoActiveCamera() {
        val s = session()
        s.hideCameras(CameraSlotId.legacyOrdered.toSet())
        assertNull(s.activeSlotId)
        assertTrue(s.displayedIds.isEmpty())
        assertEquals(4, s.cameras.size)
    }

    @Test
    fun showingACameraWhileNoneIsActiveActivatesIt() {
        val s = session()
        s.hideCameras(CameraSlotId.legacyOrdered.toSet())
        s.setDisplayed(CameraSlotId.camera3, true)
        assertEquals(CameraSlotId.camera3, s.activeSlotId)
    }

    @Test
    fun showingACameraKeepsAnExistingActiveCamera() {
        val s = session()
        s.setDisplayed(CameraSlotId.camera4, false)
        s.setDisplayed(CameraSlotId.camera4, true)
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun deleteRemovesTheEntryAndItsCalculatorState() {
        val s = session()
        s.updateSnapshot(CameraSlotId.camera2) { it.copy(shutterIndex = 11) }
        s.deleteCameras(setOf(CameraSlotId.camera2))
        assertEquals(listOf(CameraSlotId.camera1, CameraSlotId.camera3, CameraSlotId.camera4), s.cameraIds)
        assertNull(s.snapshot(CameraSlotId.camera2))
        assertNull(s.export().snapshots[CameraSlotId.camera2])
        assertTrue(CameraSlotId.camera2 in s.issuedIds)
    }

    @Test
    fun deletingTheActiveCameraActivatesTheNextDisplayedCameraInTheResultingList() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera2)
        s.deleteCameras(setOf(CameraSlotId.camera2))
        assertEquals(CameraSlotId.camera3, s.activeSlotId)
    }

    @Test
    fun deletingTheActiveLastCameraActivatesTheFirstDisplayedCamera() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera4)
        s.deleteCameras(setOf(CameraSlotId.camera4))
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun bulkNextActiveIsComputedAgainstTheResultingList() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera2)
        s.deleteCameras(setOf(CameraSlotId.camera2, CameraSlotId.camera3))
        assertEquals(CameraSlotId.camera4, s.activeSlotId)
    }

    @Test
    fun bulkHideSkipsHiddenAndRemovedCamerasWhenPickingTheNextActiveCamera() {
        val s = session()
        s.setDisplayed(CameraSlotId.camera3, false)
        s.switchActiveSlot(CameraSlotId.camera2)
        s.hideCameras(setOf(CameraSlotId.camera2, CameraSlotId.camera4))
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun deletingEveryCameraLeavesAnEmptyListAndNoActiveCamera() {
        val s = session()
        s.deleteCameras(s.cameraIds.toSet())
        assertTrue(s.cameras.isEmpty())
        assertNull(s.activeSlotId)
        assertNull(s.activeIdentity)
        assertEquals(default, s.activeSnapshot)
    }

    @Test
    fun bulkActionsIgnoreIdentitiesThatNoLongerExist() {
        val s = session()
        s.deleteCameras(setOf(CameraSlotId("gone"), CameraSlotId.camera4))
        s.hideCameras(setOf(CameraSlotId("gone"), CameraSlotId.camera4))
        assertEquals(3, s.cameras.size)
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun moveByOnePositionReordersTheGlobalListWithoutChangingState() {
        val s = session()
        s.updateSnapshot(CameraSlotId.camera3) { it.copy(shutterIndex = 3) }
        s.moveCamera(CameraSlotId.camera3, -1)
        assertEquals(
            listOf(CameraSlotId.camera1, CameraSlotId.camera3, CameraSlotId.camera2, CameraSlotId.camera4),
            s.cameraIds,
        )
        assertEquals(3, s.snapshot(CameraSlotId.camera3)?.shutterIndex)
    }

    @Test
    fun moveIsClampedAtTheEnds() {
        val s = session()
        s.moveCamera(CameraSlotId.camera1, -1)
        s.moveCamera(CameraSlotId.camera4, 1)
        assertEquals(CameraSlotId.legacyOrdered, s.cameraIds)
        s.moveCamera(CameraSlotId.camera1, 10)
        assertEquals(CameraSlotId.camera1, s.cameraIds.last())
    }

    @Test
    fun hidingKeepsTheGlobalOrderAndThePagerFollowsIt() {
        val s = session()
        s.moveCamera(CameraSlotId.camera4, -3)
        s.setDisplayed(CameraSlotId.camera2, false)
        assertEquals(
            listOf(CameraSlotId.camera4, CameraSlotId.camera1, CameraSlotId.camera3),
            s.displayedIds,
        )
    }

    @Test
    fun reorderingKeepsTheActiveCameraAndItsState() {
        val s = session()
        s.switchActiveSlot(CameraSlotId.camera3)
        s.updateActiveSnapshot { it.copy(shutterIndex = 14) }
        s.moveCamera(CameraSlotId.camera3, -2)
        assertEquals(CameraSlotId.camera3, s.activeSlotId)
        assertEquals(14, s.activeSnapshot.shutterIndex)
    }

    @Test
    fun eachCameraOwnsItsSnapshotAcrossSwitches() {
        val s = session()
        s.updateActiveSnapshot { SlotCalculatorSnapshot(shutterIndex = 12, ndIndex = 3, selectedFilmId = "kodak", selectedProfileId = "p1") }
        assertTrue(s.switchActiveSlot(CameraSlotId.camera2))
        assertEquals(default, s.activeSnapshot)
        s.updateActiveSnapshot { it.copy(ndIndex = 5) }
        assertTrue(s.switchActiveSlot(CameraSlotId.camera1))
        assertEquals(SlotCalculatorSnapshot(12, 3, "kodak", "p1"), s.activeSnapshot)
        assertEquals(5, s.snapshot(CameraSlotId.camera2)?.ndIndex)
    }

    @Test
    fun switchToTheActiveHiddenOrUnknownCameraIsRejected() {
        val s = session()
        assertFalse(s.switchActiveSlot(CameraSlotId.camera1))
        s.setDisplayed(CameraSlotId.camera2, false)
        assertFalse(s.switchActiveSlot(CameraSlotId.camera2))
        assertFalse(s.switchActiveSlot(CameraSlotId("missing")))
        assertEquals(CameraSlotId.camera1, s.activeSlotId)
    }

    @Test
    fun initialStateDropsStaleReferencesAndDuplicates() {
        val orphan = SlotCalculatorSnapshot(1, 1, null, null)
        val kept = SlotCalculatorSnapshot(2, 2, null, null)
        val s = session(
            CameraListSnapshot(
                cameras = listOf(
                    CameraListEntry(id(1), "One", isDisplayed = false),
                    CameraListEntry(id(2), "Two"),
                    CameraListEntry(id(2), "Duplicate"),
                ),
                activeSlotId = id(1),
                issuedIds = setOf(id(9)),
                snapshots = mapOf(id(2) to kept, id(7) to orphan),
            ),
        )
        assertEquals(listOf("One", "Two"), s.names())
        // The stored active camera is hidden: the first displayed camera wins.
        assertEquals(id(2), s.activeSlotId)
        assertEquals(setOf(id(1), id(2), id(9)), s.issuedIds)
        assertEquals(kept, s.snapshot(id(2)))
        assertEquals(default, s.snapshot(id(1)))
        assertNull(s.snapshot(id(7)))
    }

    @Test
    fun initialStateWithNothingDisplayedHasNoActiveCamera() {
        val s = session(
            CameraListSnapshot(
                cameras = listOf(CameraListEntry(id(1), "One", isDisplayed = false)),
                activeSlotId = id(1),
                issuedIds = emptySet(),
                snapshots = emptyMap(),
            ),
        )
        assertNull(s.activeSlotId)
    }

    @Test
    fun exportRoundTripsThroughTheConstructor() {
        val s = session()
        s.addCamera("Camera 5")
        s.setDisplayed(CameraSlotId.camera2, false)
        s.updateSnapshot(CameraSlotId.camera3) { it.copy(shutterIndex = 21) }
        val exported = s.export()
        val again = session(exported)
        assertEquals(exported, again.export())
    }
}
