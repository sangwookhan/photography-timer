// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pure pager rules (CAMERA-PAGER-004/007). */
class CameraPagerNavigationTest {

    @Test
    fun closingManagementFromTheUtilityPageReturnsThereWhileACameraIsDisplayed() {
        assertEquals(
            CameraPagerReturnTarget.UtilityPage,
            CameraPagerNavigation.returnTarget(CameraManagementOrigin.UtilityPage, 3),
        )
    }

    @Test
    fun closingFromTheUtilityPageAfterEveryCameraWasHiddenShowsTheEmptyState() {
        assertEquals(
            CameraPagerReturnTarget.EmptyState,
            CameraPagerNavigation.returnTarget(CameraManagementOrigin.UtilityPage, 0),
        )
    }

    @Test
    fun closingFromSettingsReturnsToTheActiveCameraOrTheEmptyState() {
        assertEquals(CameraPagerReturnTarget.ActiveCamera, CameraPagerNavigation.returnTarget(CameraManagementOrigin.Settings, 2))
        assertEquals(CameraPagerReturnTarget.EmptyState, CameraPagerNavigation.returnTarget(CameraManagementOrigin.Settings, 0))
    }

    @Test
    fun closingFromTheEmptyStateReturnsToTheActiveCameraOnceOneIsDisplayed() {
        assertEquals(CameraPagerReturnTarget.ActiveCamera, CameraPagerNavigation.returnTarget(CameraManagementOrigin.EmptyState, 1))
        assertEquals(CameraPagerReturnTarget.EmptyState, CameraPagerNavigation.returnTarget(CameraManagementOrigin.EmptyState, 0))
    }

    @Test
    fun theIndicatorCountsTheUtilityPageButCameraPositionsExcludeIt() {
        val onCamera = CameraPagerNavigation.indicator(3, 1, isUtilityPageShowing = false)!!
        assertEquals(4, onCamera.dotCount)
        assertEquals(1, onCamera.activeDot)
        assertEquals(2 to 3, onCamera.position)

        val onUtility = CameraPagerNavigation.indicator(3, 2, isUtilityPageShowing = true)!!
        assertEquals(4, onUtility.dotCount)
        assertEquals(3, onUtility.activeDot)
        assertNull(onUtility.position)
    }

    @Test
    fun thereIsNoIndicatorWhenNoCameraIsDisplayed() {
        assertNull(CameraPagerNavigation.indicator(0, 0, isUtilityPageShowing = false))
        assertEquals(0, CameraPagerNavigation.pageCount(0))
    }

    @Test
    fun theUtilityPageFollowsTheLastCameraAndIsNotACamera() {
        assertEquals(4, CameraPagerNavigation.pageCount(3))
        assertEquals(3, CameraPagerNavigation.utilityPageIndex(3))
        assertTrue(CameraPagerNavigation.isUtilityPage(3, 3))
        assertFalse(CameraPagerNavigation.isUtilityPage(2, 3))
        assertFalse(CameraPagerNavigation.isUtilityPage(0, 0))
    }

    @Test
    fun nextFromTheLastCameraRevealsTheUtilityPage() {
        assertTrue(CameraPagerNavigation.revealsUtilityPage(2, 3))
        assertFalse(CameraPagerNavigation.revealsUtilityPage(1, 3))
        assertFalse(CameraPagerNavigation.revealsUtilityPage(0, 0))
        assertNotNull(CameraPagerNavigation.indicator(1, 0, false))
    }

    // --- Announcement after a camera-list change (CAMERA-PAGER-006), shared by every Add entry point ---

    private val one = com.sangwook.ptimer.core.slots.CameraSlotId("one")
    private val two = com.sangwook.ptimer.core.slots.CameraSlotId("two")

    private fun identity(id: com.sangwook.ptimer.core.slots.CameraSlotId, name: String) =
        com.sangwook.ptimer.core.slots.CameraSlotIdentity(id, name)

    @Test
    fun aNewActiveCameraIsAnnouncedWhetherOrNotThereWasOneBefore() {
        assertEquals(
            CameraAnnouncement.ActiveCamera("Camera 5"),
            CameraPagerNavigation.announcementAfter(one, identity(two, "Camera 5"), isDeletion = false),
        )
        // The all-hidden empty state (no camera before) and the utility page share this rule.
        assertEquals(
            CameraAnnouncement.ActiveCamera("Camera 5"),
            CameraPagerNavigation.announcementAfter(null, identity(two, "Camera 5"), isDeletion = false),
        )
    }

    @Test
    fun anUnchangedActiveCameraIsNotAnnouncedUnlessACameraWasDeleted() {
        assertNull(CameraPagerNavigation.announcementAfter(one, identity(one, "Camera 1"), isDeletion = false))
        assertEquals(
            CameraAnnouncement.ActiveCamera("Camera 1"),
            CameraPagerNavigation.announcementAfter(one, identity(one, "Camera 1"), isDeletion = true),
        )
    }

    @Test
    fun noDisplayedCameraAfterTheChangeAnnouncesTheEmptyState() {
        assertEquals(CameraAnnouncement.NoCamerasShown, CameraPagerNavigation.announcementAfter(one, null, isDeletion = false))
        assertNull(CameraPagerNavigation.announcementAfter(null, null, isDeletion = false))
    }
}
