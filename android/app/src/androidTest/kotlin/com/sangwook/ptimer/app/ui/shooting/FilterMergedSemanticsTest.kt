// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-221 FILTER-SET-001 / FILTER-A11Y-002, on the MERGED semantics
 * tree that TalkBack actually consumes.
 *
 * A `uiautomator dump` of the running app suggested that every colour
 * swatch read `selected=false clickable=false`. That reading comes from
 * Compose's UNMERGED tree, which uiautomator has no way to collapse.
 * These tests are the standing proof that the merged tree — the one
 * exported to the accessibility framework — is correct.
 */
class FilterMergedSemanticsTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    // ---------------------------------------------------------------
    // The Filter Set colour swatches.
    // ---------------------------------------------------------------

    @Test
    fun colorSwatches_reportNameAndSelectedStateOnTheMergedNode() {
        composeTestRule.setContent {
            PTimerTheme {
                // The creation dialog preselects the suggested color.
                NewFilterSetDialog(suggestedColor = FilterSetColor.blue, onSave = { _, _ -> }, onDismiss = {})
            }
        }
        composeTestRule.waitForIdle()

        assertSwatch("Blue", expectedSelected = true)
        assertSwatch("Red", expectedSelected = false)
        assertSwatch("Green", expectedSelected = false)

        // Selecting another swatch moves the state, so `selected` is
        // genuinely bound and not a constant.
        composeTestRule.onNodeWithContentDescription("Red").performClick()
        composeTestRule.waitForIdle()
        assertSwatch("Red", expectedSelected = true)
        assertSwatch("Blue", expectedSelected = false)
    }

    private fun assertSwatch(name: String, expectedSelected: Boolean) {
        val swatch = composeTestRule.onNodeWithContentDescription(name).assertIsDisplayed()
        val config = swatch.fetchSemanticsNode().config
        assertTrue(
            "Swatch $name must be clickable so colour is never the only affordance.",
            config.contains(SemanticsActions.OnClick),
        )
        assertEquals(
            "Swatch $name selected state (FILTER-A11Y-002: colour redundant with state).",
            expectedSelected,
            config.getOrElse(SemanticsProperties.Selected) { false },
        )
        // Redundant text plus a reachable target.
        swatch.assertWidthIsAtLeast(32.dp)
        swatch.assertHeightIsAtLeast(32.dp)
    }
}
