// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.surfaceColorAtElevation
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.espresso.Espresso
import com.sangwook.ptimer.app.ui.AccessibilityTest
import com.sangwook.ptimer.core.slots.CameraListEntry
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * Camera management modes and rows (CAMERA-PAGER-005/006/008): header and
 * bottom actions per mode, the row layout, trailing-swipe delete with
 * confirmation, drag reorder, and back dismissal blocked while editing.
 */
class CameraManagementScreenTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private val cameras = listOf(
        CameraListEntry(CameraSlotId.camera1, "Leica M6 with a very long descriptive name that has to wrap instead of truncating"),
        CameraListEntry(CameraSlotId.camera2, "Camera 2", isDisplayed = false),
        CameraListEntry(CameraSlotId.camera3, "Nikon F2"),
    )

    private fun show(
        actions: CameraManagementActions = CameraManagementActions.None,
        onDismiss: () -> Unit = {},
    ) = composeTestRule.setContent {
        PTimerTheme {
            CameraManagementScreen(
                cameras = cameras,
                activeId = CameraSlotId.camera1,
                actions = actions,
                onDismiss = onDismiss,
            )
        }
    }

    @Test
    fun normalModeHasCloseTitleAndEditAndEditModeSwapsThemForDone() {
        var dismissed = 0
        show(onDismiss = { dismissed++ })

        composeTestRule.onNodeWithContentDescription("Close").assertIsDisplayed()
        composeTestRule.onNodeWithText("Cameras").assertIsDisplayed()
        composeTestRule.onNodeWithText("Edit").assertIsDisplayed()

        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onAllNodesWithContentDescription("Close").assertCountEquals(0)
        composeTestRule.onNodeWithText("Done").assertIsDisplayed()

        composeTestRule.onNodeWithText("Done").performClick()
        composeTestRule.onNodeWithContentDescription("Close").performClick()
        assertEquals(1, dismissed)
    }

    @Test
    fun backDismissesInNormalModeButIsBlockedInEditMode() {
        var dismissed = 0
        show(onDismiss = { dismissed++ })

        composeTestRule.onNodeWithText("Edit").performClick()
        Espresso.pressBack()
        composeTestRule.waitForIdle()
        assertEquals(0, dismissed)
        composeTestRule.onNodeWithText("Done").assertIsDisplayed()

        composeTestRule.onNodeWithText("Done").performClick()
        Espresso.pressBack()
        composeTestRule.waitForIdle()
        assertEquals(1, dismissed)
    }

    @Test
    fun rowsShowNameStateAndPositionAndExposeThemAsTheirLabel() {
        show()
        val long = cameras.first().name
        composeTestRule.onNodeWithContentDescription("$long, Shown, 1 of 3").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Camera 2, Hidden, 2 of 3").assertIsDisplayed()
        // Position and state are visible text, and the long name wraps in full.
        composeTestRule.onNodeWithText("1 of 3 · Shown", useUnmergedTree = true).assertIsDisplayed()
        composeTestRule.onNodeWithText("2 of 3 · Hidden", useUnmergedTree = true).assertIsDisplayed()
        composeTestRule.onNodeWithText(long, useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun tappingTheNameOpensRenameAndTheEyeControlShowsOrHides() {
        val shown = mutableListOf<Pair<CameraSlotId, Boolean>>()
        show(actions = CameraManagementActions.None.copy(setDisplayed = { id, on -> shown += id to on }))

        composeTestRule.onNodeWithTag("camera-row-2").performClick()
        composeTestRule.onNodeWithText("Rename camera").assertIsDisplayed()
        composeTestRule.onNodeWithText("Cancel").performClick()

        composeTestRule.onNodeWithTag("camera-row-visibility-0").performClick()
        composeTestRule.onNodeWithTag("camera-row-visibility-1").performClick()
        assertEquals(listOf(CameraSlotId.camera1 to false, CameraSlotId.camera2 to true), shown)
    }

    @Test
    fun deleteIsNotPersistentlyVisibleAndNormalModeHasOneLabelledAddCameraAction() {
        show()
        composeTestRule.onAllNodesWithTag("camera-row-delete-0").assertCountEquals(0)
        composeTestRule.onAllNodesWithContentDescription("Delete camera").assertCountEquals(0)
        composeTestRule.onAllNodesWithTag("camera-management-bulk-delete").assertCountEquals(0)
        composeTestRule.onNodeWithText("Add camera").assertIsDisplayed()
        composeTestRule.onNodeWithTag("camera-management-add").assertIsDisplayed()
        composeTestRule.onNodeWithTag("camera-add-plus", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun addCameraVisibleHeightIs44To48dp() {
        show()
        val bounds = composeTestRule.onNodeWithTag("camera-management-add").getBoundsInRoot()
        assertTrue("Add camera height ${bounds.height}", bounds.height >= 44.dp && bounds.height <= 48.dp)
    }

    @Test
    fun addCameraOutlineAndLabelReachContrastAgainstTheBottomBarSurface() {
        var outline = Color.Unspecified
        var label = Color.Unspecified
        var surface = Color.Unspecified
        var plus = Color.Unspecified
        composeTestRule.setContent {
            PTimerTheme {
                outline = MaterialTheme.colorScheme.outline
                label = MaterialTheme.colorScheme.onSurface
                plus = MaterialTheme.colorScheme.primary
                surface = MaterialTheme.colorScheme.surfaceColorAtElevation(3.dp)
            }
        }
        fun ratio(a: Color, b: Color): Float {
            val hi = maxOf(a.luminance(), b.luminance())
            val lo = minOf(a.luminance(), b.luminance())
            return (hi + 0.05f) / (lo + 0.05f)
        }
        assertTrue("outline ${ratio(outline, surface)}", ratio(outline, surface) >= 3f)
        assertTrue("label ${ratio(label, surface)}", ratio(label, surface) >= 4.5f)
        assertTrue("plus ${ratio(plus, surface)}", ratio(plus, surface) >= 3f)
    }

    @Test
    fun closeEditAndDoneAreAtLeast48dpTouchTargets() {
        show()
        for (tag in listOf("camera-management-close", "camera-management-edit")) {
            val bounds = composeTestRule.onNodeWithTag(tag).getBoundsInRoot()
            assertTrue("$tag width ${bounds.width}", bounds.width >= 48.dp)
            assertTrue("$tag height ${bounds.height}", bounds.height >= 48.dp)
        }
        composeTestRule.onNodeWithTag("camera-management-edit").performClick()
        val done = composeTestRule.onNodeWithTag("camera-management-edit").getBoundsInRoot()
        assertTrue("Done ${done.width} x ${done.height}", done.width >= 48.dp && done.height >= 48.dp)
    }

    @Test
    fun aTrailingSwipeRevealsDeleteAndAsksForConfirmationBeforeRemoving() {
        var deleted: Set<CameraSlotId>? = null
        show(actions = CameraManagementActions.None.copy(delete = { deleted = it }))

        composeTestRule.onNodeWithTag("camera-row-2").performTouchInput { swipeLeft() }
        composeTestRule.onNodeWithText(
            "Deletes Nikon F2 and its calculator settings. A new camera with the same name will not reconnect them or this camera's timers. This cannot be undone.",
        ).assertIsDisplayed()
        assertEquals(null, deleted)

        composeTestRule.onNodeWithTag("camera-management-confirm-delete").performClick()
        assertEquals(setOf(CameraSlotId.camera3), deleted)
    }

    @Test
    fun cancellingTheDeleteConfirmationRemovesNothing() {
        var deleted: Set<CameraSlotId>? = null
        show(actions = CameraManagementActions.None.copy(delete = { deleted = it }))

        composeTestRule.onNodeWithTag("camera-row-1").performTouchInput { swipeLeft() }
        composeTestRule.onNodeWithText("Cancel").performClick()
        assertEquals(null, deleted)
    }

    @Test
    fun editModeShowsHandlesAndSideBySideHideAndDeleteButNoArrowButtons() {
        show()
        composeTestRule.onNodeWithText("Edit").performClick()

        (0..2).forEach { composeTestRule.onNodeWithTag("camera-row-handle-$it").assertIsDisplayed() }
        composeTestRule.onAllNodesWithTag("camera-row-up-0").assertCountEquals(0)
        composeTestRule.onAllNodesWithTag("camera-row-down-0").assertCountEquals(0)
        composeTestRule.onAllNodesWithTag("camera-management-add").assertCountEquals(0)

        val hide = composeTestRule.onNodeWithTag("camera-management-bulk-hide").getBoundsInRoot()
        val delete = composeTestRule.onNodeWithTag("camera-management-bulk-delete").getBoundsInRoot()
        assertTrue("Hide and Delete share a row", hide.top == delete.top && hide.right <= delete.left + 1.dp)
        composeTestRule.onNodeWithTag("camera-management-bulk-hide").assertIsNotEnabled()
        composeTestRule.onNodeWithTag("camera-management-bulk-delete").assertIsNotEnabled()
    }

    @Test
    fun aBulkDeleteAsksOnceWithTheCount() {
        var deleted: Set<CameraSlotId>? = null
        show(actions = CameraManagementActions.None.copy(delete = { deleted = it }))

        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithTag("camera-row-select-0").performClick()
        composeTestRule.onNodeWithTag("camera-row-select-1").performClick()
        composeTestRule.onNodeWithTag("camera-management-bulk-delete").performClick()
        composeTestRule.onNodeWithText("Deletes 2 cameras and their calculator settings. This cannot be undone.")
            .assertIsDisplayed()
        composeTestRule.onNodeWithTag("camera-management-confirm-delete").performClick()
        assertEquals(CameraSlotId.legacyOrdered.take(2).toSet(), deleted)
    }

    @Test
    fun draggingAHandleReordersOnDrop() {
        val moves = mutableListOf<Pair<CameraSlotId, Int>>()
        show(actions = CameraManagementActions.None.copy(move = { id, delta -> moves += id to delta }))

        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithTag("camera-row-handle-0").performTouchInput {
            down(center)
            // Past the touch slop first, then well beyond the second row.
            moveBy(Offset(0f, 24f))
            moveBy(Offset(0f, 200f))
            moveBy(Offset(0f, 200f))
            up()
        }
        composeTestRule.waitForIdle()
        assertEquals(1, moves.size)
        assertEquals(CameraSlotId.camera1, moves.single().first)
        assertTrue("moved down at least one place: ${moves.single().second}", moves.single().second >= 1)
    }

    @Test
    fun aShortDragThatStaysInPlaceChangesNothing() {
        val moves = mutableListOf<Pair<CameraSlotId, Int>>()
        show(actions = CameraManagementActions.None.copy(move = { id, delta -> moves += id to delta }))

        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithTag("camera-row-handle-1").performTouchInput {
            down(center)
            moveBy(Offset(0f, 30f))
            up()
        }
        composeTestRule.waitForIdle()
        assertTrue(moves.isEmpty())
    }

    @Test
    @AccessibilityTest
    fun theNonDragMoveActionsAreOnTheRowForAssistiveTechnology() {
        val moves = mutableListOf<Pair<CameraSlotId, Int>>()
        show(actions = CameraManagementActions.None.copy(move = { id, delta -> moves += id to delta }))

        composeTestRule.onNodeWithText("Edit").performClick()
        val row = composeTestRule.onNodeWithContentDescription("Camera 2, Hidden, 2 of 3").fetchSemanticsNode()
        val actions = row.config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        assertEquals(listOf("Move up", "Move down"), actions.map { it.label })
        actions.first { it.label == "Move down" }.action()
        assertEquals(listOf(CameraSlotId.camera2 to 1), moves)
    }

    /**
     * The list and active camera a real owner would publish, driven by the
     * actions under test, so focus and announcement follow the result of an
     * edit that completes later (CAMERA-PAGER-006).
     */
    private class Owner(initial: List<CameraListEntry>, active: CameraSlotId?) {
        var list by mutableStateOf(initial)
        var active by mutableStateOf(active)
        fun activeIdentity(): CameraSlotIdentity? =
            active?.let { id -> list.firstOrNull { it.id == id }?.let { CameraSlotIdentity(it.id, it.name) } }
    }

    private fun showOwned(owner: Owner, actions: CameraManagementActions) = composeTestRule.setContent {
        PTimerTheme {
            CameraManagementScreen(
                cameras = owner.list,
                activeId = owner.active,
                actions = actions,
                onDismiss = {},
            )
        }
    }

    /** Collects the accessibility announcements the screen makes (TYPE_ANNOUNCEMENT events). */
    private class Announcements {
        val texts = java.util.concurrent.CopyOnWriteArrayList<String>()

        fun record(event: android.view.accessibility.AccessibilityEvent) {
            if (event.eventType == android.view.accessibility.AccessibilityEvent.TYPE_ANNOUNCEMENT) {
                texts += event.text.joinToString(" ")
            }
        }
    }

    private fun listenForAnnouncements(): Announcements {
        val collected = Announcements()
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            .getUiAutomation(android.app.UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
            .setOnAccessibilityEventListener(collected::record)
        return collected
    }

    private fun awaitAnnouncement(collected: Announcements, text: String) {
        composeTestRule.waitUntil(5_000) { collected.texts.any { it.contains(text) } }
    }

    @Test
    @AccessibilityTest
    fun addCompletingLaterAnnouncesTheNewlyActiveCamera() {
        val announcements = listenForAnnouncements()
        val owner = Owner(cameras, CameraSlotId.camera1)
        val added = CameraSlotId("camera-added")
        val actions = CameraManagementActions.None.copy(
            // The owner reserves the number and commits later; add returns when done.
            add = {
                kotlinx.coroutines.delay(300)
                composeTestRule.runOnUiThread {
                    owner.list = owner.list + CameraListEntry(added, "Camera 4")
                    owner.active = added
                }
            },
            activeCamera = owner::activeIdentity,
        )
        showOwned(owner, actions)

        composeTestRule.onNodeWithTag("camera-management-add").performClick()
        awaitAnnouncement(announcements, "Active camera: Camera 4")
    }

    @Test
    @AccessibilityTest
    fun deletingTheActiveCameraAnnouncesTheResultingActiveCamera() {
        val announcements = listenForAnnouncements()
        val owner = Owner(cameras, CameraSlotId.camera1)
        val actions = CameraManagementActions.None.copy(
            delete = { ids ->
                owner.list = owner.list.filter { it.id !in ids }
                owner.active = owner.list.firstOrNull { it.isDisplayed }?.id
            },
            activeCamera = owner::activeIdentity,
        )
        showOwned(owner, actions)

        composeTestRule.onNodeWithTag("camera-row-0").performTouchInput { swipeLeft() }
        composeTestRule.onNodeWithTag("camera-management-confirm-delete").performClick()
        awaitAnnouncement(announcements, "Active camera: Nikon F2")
    }

    @Test
    @AccessibilityTest
    fun deletingTheLastShownCameraAnnouncesTheEmptyState() {
        val announcements = listenForAnnouncements()
        val owner = Owner(listOf(CameraListEntry(CameraSlotId.camera1, "Only")), CameraSlotId.camera1)
        val actions = CameraManagementActions.None.copy(
            delete = { ids ->
                owner.list = owner.list.filter { it.id !in ids }
                owner.active = null
            },
            activeCamera = owner::activeIdentity,
        )
        showOwned(owner, actions)

        composeTestRule.onNodeWithTag("camera-row-0").performTouchInput { swipeLeft() }
        composeTestRule.onNodeWithTag("camera-management-confirm-delete").performClick()
        awaitAnnouncement(announcements, "No cameras shown")
    }

    @Test
    fun doneClearsTheSelection() {
        show()
        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithTag("camera-row-select-0").performClick()
        composeTestRule.onNodeWithTag("camera-management-bulk-hide").assertIsEnabled()

        composeTestRule.onNodeWithText("Done").performClick()
        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithTag("camera-management-bulk-hide").assertIsNotEnabled()
        composeTestRule.onNodeWithTag("camera-management-bulk-delete").assertIsNotEnabled()
    }

    @Test
    @AccessibilityTest
    fun editModeHasOneSelectNodePerRowWithItsCheckedState() {
        show()
        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onAllNodesWithContentDescription("Select Nikon F2").assertCountEquals(0)
        val row = composeTestRule.onNodeWithContentDescription("Nikon F2, Shown, 3 of 3").fetchSemanticsNode()
        assertEquals(androidx.compose.ui.state.ToggleableState.Off, row.config[androidx.compose.ui.semantics.SemanticsProperties.ToggleableState])
        composeTestRule.onNodeWithTag("camera-row-select-2").performClick()
        val checked = composeTestRule.onNodeWithContentDescription("Nikon F2, Shown, 3 of 3").fetchSemanticsNode()
        assertEquals(androidx.compose.ui.state.ToggleableState.On, checked.config[androidx.compose.ui.semantics.SemanticsProperties.ToggleableState])
    }

    @Test
    fun aFailedStorageReadShowsTheExplanationAndDisablesEditAndAdd() {
        composeTestRule.setContent {
            PTimerTheme {
                CameraManagementScreen(
                    cameras = emptyList(),
                    activeId = null,
                    actions = CameraManagementActions.None.copy(isEditable = false),
                    onDismiss = {},
                )
            }
        }
        composeTestRule.onNodeWithText("Camera data couldn't be loaded. Restart the app.").assertIsDisplayed()
        composeTestRule.onNodeWithTag("camera-management-edit").assertIsNotEnabled()
        composeTestRule.onNodeWithTag("camera-management-add").assertIsNotEnabled()
        composeTestRule.onNodeWithContentDescription("Close").assertIsDisplayed()
    }
}
