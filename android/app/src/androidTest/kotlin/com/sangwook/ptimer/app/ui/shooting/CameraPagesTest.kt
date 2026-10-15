// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * The two pages that carry the camera actions: the pager's utility page and
 * the all-hidden empty state (CAMERA-PAGER-004/007). Both show the same camera
 * icon, their literal copy, and `Manage cameras` before `Add camera`.
 */
class CameraPagesTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun theUtilityPageShowsItsCopyAndOffersManageThenAdd() {
        var manage = 0
        var add = 0
        composeTestRule.setContent {
            PTimerTheme {
                CameraManagementUtilityPage(isEditable = true, onManageCameras = { manage++ }, onAddCamera = { add++ })
            }
        }
        composeTestRule.onNodeWithTag("camera-utility-page").assertIsDisplayed()
        composeTestRule.onNodeWithText("Camera management").assertIsDisplayed()
        composeTestRule.onNodeWithText("Manage existing cameras or add a new one.").assertIsDisplayed()
        assertManageBeforeAdd("utility-page")
        composeTestRule.onNodeWithText("Manage cameras").performClick()
        composeTestRule.onNodeWithText("Add camera").performClick()
        assertEquals(1, manage)
        assertEquals(1, add)
    }

    @Test
    fun theEmptyStateShowsItsCopyAndOffersManageThenAdd() {
        composeTestRule.setContent {
            PTimerTheme { EmptyCameraPager(isEditable = true, onManageCameras = {}, onAddCamera = {}) }
        }
        composeTestRule.onNodeWithText("No cameras shown").assertIsDisplayed()
        composeTestRule.onNodeWithText(
            "Show or add a camera to calculate exposures. Running timers are not affected.",
        ).assertIsDisplayed()
        assertManageBeforeAdd("empty-pager")
    }

    @Test
    fun aFailedStorageReadShowsTheExplanationAndDisablesEveryCameraAction() {
        composeTestRule.setContent {
            PTimerTheme { EmptyCameraPager(isEditable = false, onManageCameras = {}, onAddCamera = {}) }
        }
        composeTestRule.onNodeWithText("Camera data couldn't be loaded. Restart the app.").assertIsDisplayed()
        composeTestRule.onAllNodesWithText("No cameras shown").assertCountEquals(0)
        composeTestRule.onNodeWithTag("empty-pager-manage-cameras").assertIsNotEnabled()
        composeTestRule.onNodeWithTag("empty-pager-add-camera").assertIsNotEnabled()
    }

    @Test
    fun theUsualEmptyStateKeepsBothActionsEnabled() {
        composeTestRule.setContent {
            PTimerTheme { EmptyCameraPager(isEditable = true, onManageCameras = {}, onAddCamera = {}) }
        }
        composeTestRule.onNodeWithTag("empty-pager-manage-cameras").assertIsEnabled()
        composeTestRule.onNodeWithTag("empty-pager-add-camera").assertIsEnabled()
    }

    private fun assertManageBeforeAdd(prefix: String) {
        val manage = composeTestRule.onNodeWithTag("$prefix-manage-cameras").getBoundsInRoot()
        val add = composeTestRule.onNodeWithTag("$prefix-add-camera").getBoundsInRoot()
        assertTrue("Manage cameras comes first", manage.left < add.left)
        assertTrue(manage.right <= add.left + 1.dp)
    }
}
