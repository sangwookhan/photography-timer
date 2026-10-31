// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.semantics.getOrNull
import androidx.compose.foundation.layout.width
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.assertIsSelected
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
    fun compactSegmentsRemainIndependentlyClickable() {
        val mode = androidx.compose.runtime.mutableStateOf(NDNotationMode.STOPS)
        val selected = mutableListOf<NDNotationMode>()
        composeTestRule.setContent {
            PTimerTheme {
                androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.width(128.dp)) {
                    NotationToggle(mode = mode.value, enabled = true, onSelect = { mode.value = it; selected += it })
                }
            }
        }
        for ((label, expected) in listOf("ND" to NDNotationMode.FILTER_FACTOR, "OD" to NDNotationMode.OPTICAL_DENSITY, "Stops" to NDNotationMode.STOPS)) {
            composeTestRule.onNodeWithText(label).performClick().assertIsSelected()
            org.junit.Assert.assertEquals(expected, selected.last())
        }
        org.junit.Assert.assertEquals(3, selected.size)
    }

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

/** SHELL-030 explicitly preserves the compact Main notation selector's
 * accepted sub-48dp widths. Check actual text layout and the full 48dp
 * height, rather than claiming that expanded synthetic touch bounds prove
 * a 48dp-wide segment. Other controls retain their 48dp requirement. */
internal fun assertCompactNotationTarget(node: androidx.compose.ui.semantics.SemanticsNode, context: String) {
    val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
    val action = node.config.getOrNull(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult)?.action
    org.junit.Assert.assertTrue("$context: notation exposes its actual text layout", action?.invoke(layouts) == true)
    org.junit.Assert.assertTrue("$context: complete one-line notation text: ${layouts.map { "${it.layoutInput.text.text} size=${it.size} lines=${it.lineCount} widthOverflow=${it.didOverflowWidth} heightOverflow=${it.didOverflowHeight} ellipsis=${it.isLineEllipsized(0)}" }}", layouts.isNotEmpty() && layouts.all {
        it.lineCount == 1 && !it.isLineEllipsized(0) && !it.didOverflowHeight &&
            it.getLineRight(0) - it.getLineLeft(0) <= node.boundsInRoot.width
    })
    org.junit.Assert.assertTrue("$context: compact target has positive width and 48dp height",
        node.boundsInRoot.width > 0 && node.boundsInRoot.height >= 48 * node.layoutInfo.density.density)
}
