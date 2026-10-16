// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/**
 * FILTER-ITEM-011 on the rendered Filter Set editor: the Filters-heading
 * Edit/Done path and the row swipe both reach one confirmation per item,
 * nothing leaves the list before the user confirms, and deleting the last
 * item ends Edit mode.
 */
class FilterItemDeletionScreenTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private val resources = InstrumentationRegistry.getInstrumentation().targetContext.resources
    private val nd = FilterItem("ND400", FilterItemBehavior.Fixed(FilterRegisteredValue(400.0, FilterValueUnit.filterFactor)))
    private val gnd = FilterItem("Soft GND", FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops)))

    private var inventory by mutableStateOf(FilterInventory())
    private val deleted = mutableListOf<FilterItemId>()

    private fun render(items: List<FilterItem>) {
        val set = FilterSet("Lee holder", FilterSetColor.blue, items)
        inventory = FilterInventory(listOf(set))
        val actions = FilterSetManagementActions(
            suggestCreationColor = { FilterSetColor.blue },
            createFilterSet = { _, _ -> null },
            createFilterSetHolding = { _, _, _ -> null },
            renameFilterSet = { _, _ -> },
            recolorFilterSet = { _, _ -> },
            deleteFilterSet = {},
            deleteFilterItem = { id ->
                deleted += id
                inventory = FilterInventory(inventory.filterSets.map { s -> s.copy(items = s.items.filter { it.id != id }) })
            },
            saveFilterItem = { item, setId ->
                inventory = FilterInventory(
                    inventory.filterSets.map { s -> if (s.id == setId) s.copy(items = s.items + item) else s },
                )
                FilterItemSaveOutcome.Saved
            },
            camerasAffectedByDeletingFilterSet = { emptyList() },
            camerasAffectedByDeletingItem = { emptyList() },
        )
        composeTestRule.setContent {
            PTimerTheme {
                FilterSetManagementScreen(inventory = inventory, filterSetId = set.id, actions = actions, onDismiss = {})
            }
        }
    }

    private fun text(id: Int, vararg args: Any) = resources.getString(id, *args)

    private fun edit() = composeTestRule.onNodeWithTag("filter-set-edit-filters")

    private fun row(item: FilterItem) = composeTestRule.onNodeWithTag("filter-item-row-${item.id.rawValue}")

    private fun rowDelete(item: FilterItem) = composeTestRule.onNodeWithTag("filter-item-delete-${item.id.rawValue}")

    @Test
    fun editShowsEveryRowDeleteControlAndDoneHidesThem() {
        render(listOf(nd, gnd))
        edit().assertTextEquals(text(R.string.action_edit))
        rowDelete(nd).assertDoesNotExist()

        edit().performClick()
        edit().assertTextEquals(text(R.string.action_done))
        rowDelete(nd).assertIsDisplayed()
        rowDelete(gnd).assertIsDisplayed()

        edit().performClick()
        edit().assertTextEquals(text(R.string.action_edit))
        rowDelete(nd).assertDoesNotExist()
    }

    @Test
    fun editIsHiddenWhileTheSetHasNoItems() {
        render(emptyList())
        edit().assertDoesNotExist()
    }

    @Test
    fun aRowDeleteControlAsksAndCancelKeepsTheItem() {
        render(listOf(nd, gnd))
        edit().performClick()
        rowDelete(nd).performClick()

        composeTestRule.onNodeWithText(text(R.string.filter_item_delete_title)).assertIsDisplayed()
        composeTestRule.onNodeWithText(text(R.string.filter_delete_named, nd.name)).assertIsDisplayed()
        row(nd).assertIsDisplayed()
        composeTestRule.onNodeWithText(text(R.string.action_cancel)).performClick()

        assertEquals(emptyList<FilterItemId>(), deleted)
        row(nd).assertIsDisplayed()
    }

    @Test
    fun theSwipeOnlyRevealsDeleteAndDeleteOpensTheSameConfirmation() {
        render(listOf(nd, gnd))
        val reveal = composeTestRule.onNodeWithTag("filter-item-swipe-delete-${nd.id.rawValue}")
        reveal.assertDoesNotExist() // hidden from taps and screen readers while closed

        row(nd).performTouchInput { swipeLeft() }
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText(text(R.string.filter_item_delete_title)).assertDoesNotExist()
        reveal.assertHasClickAction()

        reveal.performClick()
        composeTestRule.onNodeWithText(text(R.string.filter_item_delete_title)).assertIsDisplayed()
        row(nd).assertIsDisplayed()
        composeTestRule.onNodeWithText(text(R.string.filter_delete_named, nd.name)).performClick()

        assertEquals(listOf(nd.id), deleted)
        row(nd).assertDoesNotExist()
        row(gnd).assertIsDisplayed()
    }

    @Test
    fun deletingTheLastItemEndsEditModeAndALaterItemStartsOutsideIt() {
        render(listOf(nd))
        edit().performClick()
        rowDelete(nd).performClick()
        composeTestRule.onNodeWithText(text(R.string.filter_delete_named, nd.name)).performClick()
        edit().assertDoesNotExist()

        // Add Filter's save path, without driving the editor dialog.
        composeTestRule.runOnIdle {
            inventory = FilterInventory(inventory.filterSets.map { it.copy(items = listOf(gnd)) })
        }
        edit().assertTextEquals(text(R.string.action_edit))
        rowDelete(gnd).assertDoesNotExist()
    }
}
