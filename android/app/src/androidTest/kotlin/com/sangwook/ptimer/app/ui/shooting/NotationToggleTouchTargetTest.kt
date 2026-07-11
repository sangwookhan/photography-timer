// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-218: the ND notation segmented toggle's visible track is ~26dp
 * tall, well under Android's 48dp minimum accessible touch target. Each
 * segment must still expose a >=48dp touch/semantics height without
 * widening the segment (that would overflow the row it shares with the
 * "ND Filter" title — see [ShootingScreen]'s `expandedTouchHeight`).
 */
class NotationToggleTouchTargetTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun everySegment_hasAtLeast48dpTouchHeight() {
        composeTestRule.setContent {
            PTimerTheme {
                NotationToggle(mode = NDNotationMode.STOPS, enabled = true, onSelect = {})
            }
        }

        composeTestRule.onNodeWithText("Stops").assertTouchHeightIsEqualTo(48.dp)
        composeTestRule.onNodeWithText("OD").assertTouchHeightIsEqualTo(48.dp)
        composeTestRule.onNodeWithText("ND").assertTouchHeightIsEqualTo(48.dp)
    }
}
