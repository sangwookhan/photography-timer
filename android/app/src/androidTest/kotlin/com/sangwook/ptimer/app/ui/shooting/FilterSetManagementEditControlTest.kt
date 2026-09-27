// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-221 FILTER-SET-001: the management surface never presents a
 * no-op Edit control. With no Filter Sets there is nothing to reorder or
 * delete, so Close and New stay and the Edit / Finish Editing toggle is
 * absent; it appears once a set exists and disappears again when the
 * last set is deleted (which also ends edit mode).
 */
class FilterSetManagementEditControlTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private fun show(initial: FilterInventory = FilterInventory.empty) {
        composeTestRule.setContent {
            var inventory by remember { mutableStateOf(initial) }
            PTimerTheme {
                FilterSetManagementScreen(
                    inventory = inventory,
                    actions = FilterSetManagementActions(
                        suggestCreationColor = { FilterSetColor.blue },
                        createFilterSet = { name, color ->
                            inventory = FilterInventory(inventory.filterSets + FilterSet(name, color))
                        },
                        renameFilterSet = { _, _ -> },
                        recolorFilterSet = { _, _ -> },
                        moveFilterSet = { _, _ -> },
                        deleteFilterSet = { id ->
                            inventory = FilterInventory(inventory.filterSets.filterNot { it.id == id })
                        },
                        moveFilterItem = { _, _, _ -> },
                        deleteFilterItem = {},
                        saveFilterItem = { _, _ -> FilterItemSaveOutcome.Saved },
                        camerasAffectedByDeletingFilterSet = { emptyList() },
                        camerasAffectedByDeletingItem = { emptyList() },
                    ),
                    onDismiss = {},
                )
            }
        }
    }

    @Test
    fun emptyList_showsCloseAndNewButNoEditControl() {
        show()

        composeTestRule.onNodeWithContentDescription("Done").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("New Filter Set").assertIsDisplayed()
        composeTestRule.onNodeWithText("Edit").assertDoesNotExist()
        composeTestRule.onNodeWithText("Finish Editing").assertDoesNotExist()
    }

    @Test
    fun editControl_appearsWithTheFirstSetAndLeavesWithTheLastOne() {
        show()
        composeTestRule.onNodeWithText("Edit").assertDoesNotExist()

        // Create one Filter Set through the New dialog.
        composeTestRule.onNodeWithContentDescription("New Filter Set").performClick()
        composeTestRule.onNodeWithText("Name").performTextInput("Lee holder")
        composeTestRule.onNodeWithText("Save").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Edit").assertIsDisplayed()

        // Enter edit mode and delete the only set.
        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithText("Finish Editing").assertIsDisplayed()
        composeTestRule.onNodeWithContentDescription("Delete").performClick()
        composeTestRule.onNodeWithText("Delete Lee holder").performClick()
        composeTestRule.waitForIdle()

        // Edit mode ended with the list, and no no-op control remains.
        composeTestRule.onNodeWithText("Finish Editing").assertDoesNotExist()
        composeTestRule.onNodeWithText("Edit").assertDoesNotExist()
        composeTestRule.onNodeWithContentDescription("New Filter Set").assertIsDisplayed()
    }
}
