// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.timer

import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-218: the timer-card action buttons (Pause, Resume, Repeat Shot,
 * Cancel, Remove) share a compact wrapper with a 34dp visible height, below
 * Android's 48dp minimum accessible touch target. minimumInteractiveComponentSize()
 * must pad the actual touch/semantics bounds out to 48dp without growing the
 * visible pill.
 */
class CompactTimerActionTouchTargetTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun filledAction_hasAtLeast48dpTouchHeight() {
        composeTestRule.setContent {
            PTimerTheme {
                CompactFilledAction(text = "Pause") {}
            }
        }
        composeTestRule.onNodeWithText("Pause").assertTouchHeightIsEqualTo(48.dp)
    }

    @Test
    fun outlinedAction_hasAtLeast48dpTouchHeight() {
        composeTestRule.setContent {
            PTimerTheme {
                CompactOutlinedAction(text = "Cancel") {}
            }
        }
        composeTestRule.onNodeWithText("Cancel").assertTouchHeightIsEqualTo(48.dp)
    }
}
