// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.FilterInventoryModel
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-221 on the rendered wheel row: the two behaviors whose proof
 * needs a real composition rather than controller state alone.
 *
 * - FILTER-STACK-005: a wheel added from the Plus control appears in its
 *   settled source group immediately, with no further interaction.
 * - FILTER-STACK-004: a settle the stack REFUSES leaves the viewport on
 *   the committed row, not on the rejected candidate (the SnapWheel
 *   re-center this suite was written to cover).
 */
class FilterStackInteractionTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private fun stops(name: String, value: Double) = FilterItem(
        name,
        FilterItemBehavior.Fixed(FilterRegisteredValue(value, FilterValueUnit.stops)),
    )

    private fun controller(inventory: FilterInventory) = CalculatorController(
        films = emptyList(),
        onStart = { _, _ -> },
        inventoryModel = FilterInventoryModel(
            initial = inventory,
            persistenceWriter = PersistenceWriter { it() },
        ),
    )

    /** Full touch cycle on one wheel, driven through the controller. */
    private fun commit(c: CalculatorController, wheelIndex: Int, selection: FilterWheelSelection) {
        val wheel = c.state.value.filterWheels[wheelIndex]
        val row = wheel.rows.indexOfFirst { it.selection == selection }
        require(row >= 0) { "row $selection is not offered by wheel $wheelIndex" }
        c.setNdWheelActive(wheel.id, true)
        c.setNdWheelValue(wheel.id, row)
        c.setNdWheelActive(wheel.id, false)
    }

    @Composable
    private fun StackRow(
        controller: CalculatorController,
        onWheelValue: (Int, Int) -> Unit = controller::setNdWheelValue,
    ) {
        val state by controller.state.collectAsState()
        PTimerTheme {
            Box(Modifier.width(320.dp)) {
                FilterStackGroup(
                    state = state,
                    onWheelActive = controller::setNdWheelActive,
                    onWheelValue = onWheelValue,
                    onAddFilterWheel = controller::addFilterWheel,
                    onAdjustFilterWheel = controller::adjustFilterWheel,
                    onOverscrollRemove = controller::removeNdWheelFromOverscroll,
                    onFilterAddUnavailability = controller::filterAddUnavailability,
                    onManageFilterSets = {},
                )
            }
        }
    }

    @Test
    fun addedWheel_appearsInItsSettledSourceGroupWithoutFurtherInteraction() {
        val threeStop = stops("Lee ND 3", 3.0)
        // The second item keeps the source addable (FILTER-PLUS-005).
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(threeStop, stops("Soft", 1.0)))
        val c = controller(FilterInventory(listOf(lee)))
        commit(c, 0, FilterWheelSelection.Standard(2.0))
        c.addFilterWheel(FilterSource.FilterSet(lee.id))
        val leeWheel = c.state.value.filterWheels.indexOfFirst { it.source is FilterSource.FilterSet }
        commit(c, leeWheel, FilterWheelSelection.Item(FilterRowSelection(threeStop.id, FilterRowChoice.Fixed)))

        composeTestRule.setContent { StackRow(c) }
        composeTestRule.onNodeWithContentDescription("Filter 1 of 2, Lee holder").assertExists()

        // One tap on the Plus control; nothing else is touched afterwards.
        composeTestRule.onNodeWithContentDescription("Add filter").performClick()
        composeTestRule.waitForIdle()

        val first = composeTestRule.onNodeWithContentDescription("Filter 1 of 3, Lee holder")
        val second = composeTestRule.onNodeWithContentDescription("Filter 2 of 3, Lee holder")
        val third = composeTestRule.onNodeWithContentDescription("Filter 3 of 3, Standard")
        first.assertExists()
        second.assertExists()
        third.assertExists()
        // Rendered left to right in that same order: the Lee group (3)
        // stays contiguous ahead of Standard (2).
        val xs = listOf(first, second, third).map { it.getUnclippedBoundsInRoot().left }
        assertTrue("Wheels render in the settled group order: $xs", xs[0] < xs[1] && xs[1] < xs[2])
    }

    @Test
    fun refusedSettle_returnsTheViewportToTheCommittedRow() {
        val onlyItem = stops("Lee ND 3", 3.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(onlyItem))
        val c = controller(FilterInventory(listOf(lee)))
        // Two Lee wheels first (while the item is still unmounted), then
        // mount the single item on one of them. The other wheel's only
        // non-Empty row is now unavailable: any settle on it is refused.
        c.addFilterWheel(FilterSource.FilterSet(lee.id))
        c.addFilterWheel(FilterSource.FilterSet(lee.id))
        val mounted = FilterWheelSelection.Item(FilterRowSelection(onlyItem.id, FilterRowChoice.Fixed))
        commit(c, c.state.value.filterWheels.indexOfFirst { it.source is FilterSource.FilterSet }, mounted)

        val before = c.state.value.filterWheels.map { it.rows[it.committedIndex].selection }
        val beforeTotal = c.state.value.filterStatus.totalStopsText
        assertEquals(
            listOf(mounted, FilterWheelSelection.Empty, FilterWheelSelection.Standard(0.0)),
            before,
        )

        // Record every centered row the wheel reports. SnapWheel emits on
        // each change of the centered row, so the trailing emission for a
        // wheel IS the row its viewport ends up parked on.
        val centered = mutableListOf<Pair<Int, Int>>()
        composeTestRule.setContent {
            StackRow(c) { id, index ->
                centered += id to index
                c.setNdWheelValue(id, index)
            }
        }

        val emptyWheelId = c.state.value.filterWheels[1].id
        composeTestRule.onNodeWithContentDescription("Filter 2 of 3, Lee holder")
            .performTouchInput { swipeUp() }
        composeTestRule.waitForIdle()

        assertTrue(
            "The gesture must actually settle on the unavailable row: $centered",
            centered.contains(emptyWheelId to 1),
        )
        assertNotNull(
            "The settle on the mounted item must be refused.",
            c.state.value.filterStatus.rejection,
        )
        assertEquals(
            "The refused settle re-centers on the committed Empty row (index 0).",
            0,
            centered.last { it.first == emptyWheelId }.second,
        )
        assertEquals("The committed selections are unchanged.", before, c.state.value.filterWheels.map { it.rows[it.committedIndex].selection })
        assertEquals("The total is unchanged.", beforeTotal, c.state.value.filterStatus.totalStopsText)
    }
}
