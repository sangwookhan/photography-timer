// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.vm.FilterRejectionNotice
import com.sangwook.ptimer.app.vm.FilterRowTypeCategory
import com.sangwook.ptimer.app.vm.FilterSourceSummaryItem
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionContent
import com.sangwook.ptimer.app.vm.FilterWheelRowUiState
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-221 FILTER-STACK-008, measured rather than eyeballed: the
 * status region is one visual row whose source summary is aligned to the
 * leading side and whose localized total is aligned to the trailing
 * side, with the total never truncated and the leading text yielding
 * space first.
 */
class FilterStatusRegionLayoutTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private val regionWidth = 220.dp
    private val total = "12 stops"

    private fun idle(vararg names: String) = FilterStatusRegionContent(
        leading = FilterStatusLeading.IdleSummary(
            names.mapIndexed { index, name ->
                FilterSourceSummaryItem(
                    source = FilterSource.Standard,
                    name = name,
                    count = 1,
                    color = if (index == 0) null else FilterSetColor.blue,
                )
            },
        ),
        total = total,
        isHeld = true,
        isSecondaryEmphasis = true,
    )

    private fun moving() = FilterStatusRegionContent(
        leading = FilterStatusLeading.MovingRow(
            row = FilterWheelRowUiState(
                selection = FilterWheelSelection.Standard(6.0),
                compactValueText = "6",
                typeCategory = FilterRowTypeCategory.nd,
                contributionStops = 6.0,
                registeredStops = 6.0,
            ),
            sourceName = "Lee holder",
        ),
        total = total,
        isHeld = true,
    )

    private fun rejection() = FilterStatusRegionContent(
        leading = FilterStatusLeading.Rejection(
            FilterRejectionNotice(sequence = 1, rejection = FilterStackRejection.itemAlreadyMounted),
        ),
        total = total,
        isWarning = true,
        isHeld = true,
    )

    private fun ComposeContentTestRule.showRegion(content: FilterStatusRegionContent) {
        setContent {
            PTimerTheme {
                Box(Modifier.width(regionWidth)) {
                    FilterStatusRegion(
                        content = content,
                        wheelCount = 2,
                        notationMode = NDNotationMode.STOPS,
                    )
                }
            }
        }
    }

    /** Leading before the Total, Total whole and inside the region. */
    private fun assertLeadingPrecedesWholeTotal(): Dp {
        val leading = composeTestRule
            .onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.ContentDescription))
            .assertExists()
        val totalNode = composeTestRule.onNodeWithText(total).assertIsDisplayed()
        val leadingBounds = leading.getUnclippedBoundsInRoot()
        val totalBounds = totalNode.getUnclippedBoundsInRoot()
        val root = composeTestRule.onRoot().getUnclippedBoundsInRoot()
        assertTrue(
            "Leading ${leadingBounds.left} must start before the total ${totalBounds.left}.",
            leadingBounds.left < totalBounds.left,
        )
        assertTrue(
            "The total must end inside the region: ${totalBounds.right} vs ${root.right}.",
            totalBounds.right <= root.right + 1.dp,
        )
        return totalBounds.right - totalBounds.left
    }

    @Test
    fun idleContent_putsTheSummaryLeadingAndTheTotalTrailing() {
        composeTestRule.showRegion(idle("Standard", "Lee holder"))
        assertLeadingPrecedesWholeTotal()
    }

    @Test
    fun movingContent_putsTheRowDetailLeadingAndTheTotalTrailing() {
        composeTestRule.showRegion(moving())
        assertLeadingPrecedesWholeTotal()
    }

    @Test
    fun rejectionContent_putsTheReasonLeadingAndTheTotalTrailing() {
        composeTestRule.showRegion(rejection())
        assertLeadingPrecedesWholeTotal()
    }

    @Test
    fun anOverflowingSummaryYieldsSpaceWhileTheTotalKeepsItsFullWidth() {
        val shown = mutableStateOf(idle("Standard"))
        composeTestRule.setContent {
            PTimerTheme {
                Box(Modifier.width(regionWidth)) {
                    FilterStatusRegion(
                        content = shown.value,
                        wheelCount = 2,
                        notationMode = NDNotationMode.STOPS,
                    )
                }
            }
        }
        val narrowTotal = assertLeadingPrecedesWholeTotal()

        composeTestRule.runOnUiThread {
            shown.value = idle(
                "A very long Filter Set name that cannot possibly fit",
                "Another very long Filter Set name",
                "And a third one as well",
            )
        }
        composeTestRule.waitForIdle()
        val crowdedTotal = assertLeadingPrecedesWholeTotal()

        assertEquals(
            "The leading summary truncates; the total keeps its full width.",
            narrowTotal.value.toDouble(),
            crowdedTotal.value.toDouble(),
            0.5,
        )
    }
}
