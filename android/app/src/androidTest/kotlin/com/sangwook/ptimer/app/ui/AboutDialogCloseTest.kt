// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/**
 * The About screen closes through an X icon named `Close`; the text `Done`
 * action is gone.
 */
class AboutDialogCloseTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun closeIconDismissesAndNoDoneTextAction() {
        var dismissals = 0
        composeTestRule.setContent {
            PTimerTheme {
                PTimerAboutDialog(versionName = "1.0", buildCode = "1", onDismiss = { dismissals++ })
            }
        }

        composeTestRule.onAllNodesWithText("Done").assertCountEquals(0)
        composeTestRule.onNodeWithContentDescription("Close").performClick()
        assertEquals(1, dismissals)
    }
}
