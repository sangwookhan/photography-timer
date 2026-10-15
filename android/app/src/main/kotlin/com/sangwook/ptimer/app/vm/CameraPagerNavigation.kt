// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity

/**
 * Where camera management was opened from; decides where closing it returns to
 * (CAMERA-PAGER-007). (iOS: CameraManagementOrigin.)
 */
enum class CameraManagementOrigin {
    UtilityPage,
    Settings,
    EmptyState,
}

enum class CameraPagerReturnTarget {
    UtilityPage,
    ActiveCamera,
    EmptyState,
}

/** What a camera-list change owes the screen reader (CAMERA-PAGER-006). */
sealed interface CameraAnnouncement {
    /** The resulting active camera. */
    data class ActiveCamera(val name: String) : CameraAnnouncement

    /** No camera is displayed any more. */
    data object NoCamerasShown : CameraAnnouncement
}

/** Pure pager rules, kept out of the composables so they can be tested. (iOS: CameraPagerNavigation.) */
object CameraPagerNavigation {
    /**
     * Closing camera management: from the utility page it returns there while
     * at least one camera remains displayed (the empty state replaces it
     * otherwise); from Settings it returns to the active camera, or to the
     * empty state when no camera is displayed.
     */
    fun returnTarget(origin: CameraManagementOrigin, displayedCameraCount: Int): CameraPagerReturnTarget {
        if (displayedCameraCount <= 0) return CameraPagerReturnTarget.EmptyState
        return when (origin) {
            CameraManagementOrigin.UtilityPage -> CameraPagerReturnTarget.UtilityPage
            CameraManagementOrigin.Settings, CameraManagementOrigin.EmptyState -> CameraPagerReturnTarget.ActiveCamera
        }
    }

    /**
     * The standard page indicator includes the utility page; camera position
     * labels and camera counts exclude it.
     */
    data class Indicator(
        val dotCount: Int,
        val activeDot: Int,
        /** `n of M` over cameras only; `null` on the utility page. */
        val position: Pair<Int, Int>?,
    )

    /** `null` when no camera is displayed (the empty state has no pager). */
    fun indicator(displayedCameraCount: Int, activeCameraIndex: Int, isUtilityPageShowing: Boolean): Indicator? {
        if (displayedCameraCount <= 0) return null
        if (isUtilityPageShowing) {
            return Indicator(dotCount = displayedCameraCount + 1, activeDot = displayedCameraCount, position = null)
        }
        return Indicator(
            dotCount = displayedCameraCount + 1,
            activeDot = activeCameraIndex,
            position = (activeCameraIndex + 1) to displayedCameraCount,
        )
    }

    /** Pager page count: the displayed cameras plus the trailing utility page; none without a camera. */
    fun pageCount(displayedCameraCount: Int): Int =
        if (displayedCameraCount > 0) displayedCameraCount + 1 else 0

    /** The utility page's pager index (right after the last camera). */
    fun utilityPageIndex(displayedCameraCount: Int): Int = displayedCameraCount

    /**
     * What a settled pager page means: a camera index, or the utility page,
     * which is not a camera and changes no camera, calculator, or timer.
     */
    fun isUtilityPage(page: Int, displayedCameraCount: Int): Boolean =
        displayedCameraCount > 0 && page == displayedCameraCount

    /** The accessibility "next page" action from the last camera reveals the utility page. */
    fun revealsUtilityPage(activeCameraIndex: Int, displayedCameraCount: Int): Boolean =
        displayedCameraCount > 0 && activeCameraIndex == displayedCameraCount - 1

    /**
     * The announcement after a camera-list change, shared by every entry point
     * (camera management, the utility page, the empty state): the resulting
     * active camera or the empty state after a confirmed deletion or whenever
     * the active camera changed; `null` when nothing changed for the user.
     */
    fun announcementAfter(before: CameraSlotId?, after: CameraSlotIdentity?, isDeletion: Boolean): CameraAnnouncement? {
        if (!isDeletion && after?.id == before) return null
        return after?.let { CameraAnnouncement.ActiveCamera(it.displayName) } ?: CameraAnnouncement.NoCamerasShown
    }
}
