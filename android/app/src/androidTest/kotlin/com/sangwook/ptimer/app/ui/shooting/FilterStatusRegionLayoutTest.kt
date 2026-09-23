// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.FilterInventoryModel
import com.sangwook.ptimer.app.vm.FilterRejectionNotice
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
import com.sangwook.ptimer.app.vm.FilterRowTypeCategory
import com.sangwook.ptimer.app.vm.FilterSourceSummaryItem
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionContent
import com.sangwook.ptimer.app.vm.FilterWheelRowUiState
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterValueUnit
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

    // ------------------------------------------------------------------
    // FILTER-STACK-008 in the card, not just in the region: the one
    // status row belongs to the WHOLE mixed-stack card, so its leading
    // content starts at the card's leading content inset and its Total
    // ends at the trailing one. Before this suite the region was nested
    // inside the filter sub-column, so the summary, the moving detail,
    // and the rejection reason all began near the middle of the card
    // and truncated far earlier than iOS.
    // ------------------------------------------------------------------

    /** Mirrors ShootingScreen's card content inset (`CardRowPadding`). */
    private val cardPadding = 8.dp
    private val cardWidth = 400.dp
    private val leadingInset = cardPadding
    private val trailingInset = cardWidth - cardPadding

    private fun twoWheelState(): CalculatorUiState {
        val lee = FilterSet(
            "Lee holder",
            FilterSetColor.blue,
            listOf(
                FilterItem(
                    "Lee ND 3",
                    FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops)),
                ),
                FilterItem(
                    "Lee ND 6",
                    FilterItemBehavior.Fixed(FilterRegisteredValue(6.0, FilterValueUnit.stops)),
                ),
            ),
        )
        val controller = CalculatorController(
            films = emptyList(),
            onStart = { _, _ -> },
            inventoryModel = FilterInventoryModel(
                initial = FilterInventory(listOf(lee)),
                persistenceWriter = PersistenceWriter { it() },
            ),
        )
        controller.addFilterWheel(FilterSource.FilterSet(lee.id))
        return controller.state.value
    }

    /**
     * The card: the stack owns the content column, the wheels come back
     * through the slot next to a stand-in for the Base Shutter column,
     * and the status region spans the content width underneath.
     */
    private fun showCard(state: CalculatorUiState) {
        composeTestRule.setContent {
            PTimerTheme {
                Box(Modifier.width(cardWidth)) {
                    FilterStackGroup(
                        state = state,
                        onWheelActive = { _, _ -> },
                        onWheelValue = { _, _ -> },
                        onAddFilterWheel = {},
                        onAdjustFilterWheel = { _, _ -> FilterWheelAdjustmentOutcome.Boundary },
                        onOverscrollRemove = {},
                        onFilterAddUnavailability = { null },
                        onManageFilterSets = {},
                        modifier = Modifier.padding(cardPadding),
                    ) { wheels ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                        ) {
                            // Stands in for the Base Shutter column: the
                            // status row must clear it, not start after it.
                            Column(modifier = Modifier.weight(1f)) { Spacer(Modifier.width(1.dp)) }
                            Column(modifier = Modifier.weight(1.6f)) { wheels() }
                        }
                    }
                }
            }
        }
    }

    /**
     * The status region's leading text is the only described element in
     * the card that is not a picker: wheels and the Plus control both
     * carry [SemanticsProperties.ProgressBarRangeInfo].
     */
    private fun leadingBounds(): DpRect = composeTestRule
        .onNode(
            SemanticsMatcher.keyIsDefined(SemanticsProperties.ContentDescription)
                .and(SemanticsMatcher.keyNotDefined(SemanticsProperties.ProgressBarRangeInfo)),
        )
        .assertExists()
        .getUnclippedBoundsInRoot()

    /**
     * The trailing Total: the only text node in the card that carries
     * no content description (the leading detail exposes its complete,
     * untruncated form there) and is not a picker.
     */
    private fun totalBounds(): DpRect = composeTestRule
        .onNode(
            SemanticsMatcher.keyIsDefined(SemanticsProperties.Text)
                .and(SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription))
                .and(SemanticsMatcher.keyNotDefined(SemanticsProperties.ProgressBarRangeInfo)),
        )
        .assertIsDisplayed()
        .getUnclippedBoundsInRoot()

    private fun wheelBounds(): List<DpRect> = (1..2).map { position ->
        composeTestRule
            .onNodeWithContentDescription("Filter $position of 2", substring = true)
            .assertExists()
            .getUnclippedBoundsInRoot()
    }

    private fun assertSpansContentInsets(stateName: String) {
        val leading = leadingBounds()
        val totalRect = totalBounds()
        assertEquals(
            "$stateName leading content must start at the card's leading inset.",
            leadingInset.value.toDouble(),
            leading.left.value.toDouble(),
            1.0,
        )
        assertEquals(
            "$stateName Total must end at the card's trailing inset.",
            trailingInset.value.toDouble(),
            totalRect.right.value.toDouble(),
            1.0,
        )
        assertTrue(
            "$stateName leading ${leading.left} must precede the total ${totalRect.left}.",
            leading.left < totalRect.left,
        )
    }

    @Test
    fun statusRow_spansTheCardContentInsetsInEveryState() {
        val idleState = twoWheelState()
        val movingWheel = idleState.filterWheels.first()
        val movingState = idleState.copy(
            filterStatus = idleState.filterStatus.copy(
                movingWheelId = movingWheel.id,
                movingRow = movingWheel.rows[movingWheel.selectedIndex],
            ),
        )
        val rejectionState = idleState.copy(
            filterStatus = idleState.filterStatus.copy(
                rejection = FilterRejectionNotice(
                    sequence = 1,
                    rejection = FilterStackRejection.itemAlreadyMounted,
                ),
            ),
        )
        val shown = mutableStateOf(idleState)
        composeTestRule.setContent {
            PTimerTheme {
                Box(Modifier.width(cardWidth)) {
                    FilterStackGroup(
                        state = shown.value,
                        onWheelActive = { _, _ -> },
                        onWheelValue = { _, _ -> },
                        onAddFilterWheel = {},
                        onAdjustFilterWheel = { _, _ -> FilterWheelAdjustmentOutcome.Boundary },
                        onOverscrollRemove = {},
                        onFilterAddUnavailability = { null },
                        onManageFilterSets = {},
                        modifier = Modifier.padding(cardPadding),
                    ) { wheels ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                        ) {
                            Column(modifier = Modifier.weight(1f)) { Spacer(Modifier.width(1.dp)) }
                            Column(modifier = Modifier.weight(1.6f)) { wheels() }
                        }
                    }
                }
            }
        }

        assertSpansContentInsets("Idle")
        val idleWheels = wheelBounds()

        composeTestRule.runOnUiThread { shown.value = movingState }
        composeTestRule.waitForIdle()
        assertSpansContentInsets("Moving")
        assertEquals("Moving must not move a wheel.", idleWheels, wheelBounds())

        composeTestRule.runOnUiThread { shown.value = rejectionState }
        composeTestRule.waitForIdle()
        assertSpansContentInsets("Rejection")
        assertEquals("A rejection must not move a wheel.", idleWheels, wheelBounds())
    }

    /** The status row is outside the filter sub-column, so it starts
     *  well before the first wheel rather than on its leading edge. */
    @Test
    fun statusRow_startsBeforeTheFirstFilterWheel() {
        showCard(twoWheelState())

        val leading = leadingBounds()
        val firstWheel = wheelBounds().first()
        assertTrue(
            "Leading ${leading.left} must start before the first wheel ${firstWheel.left}, " +
                "not inside the filter sub-column.",
            leading.left < firstWheel.left - 8.dp,
        )
    }
}
