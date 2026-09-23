// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.assertTouchWidthIsEqualTo
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
import com.sangwook.ptimer.app.vm.ModelOption
import com.sangwook.ptimer.app.vm.SlotTab
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.core.target.TargetShutterUnavailableReason
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-221 FILTER-SET-001 / FILTER-A11Y-002, on the MERGED semantics
 * tree that TalkBack actually consumes.
 *
 * A `uiautomator dump` of the running app suggested two defects: the
 * Filter Set management entry looked like a 48dp clickable node with an
 * empty content description plus a 16dp described child, and every
 * colour swatch looked like `selected=false clickable=false`. Both
 * readings come from Compose's UNMERGED tree, which uiautomator has no
 * way to collapse. These tests are the standing proof that the merged
 * tree — the one exported to the accessibility framework — is correct.
 */
class FilterMergedSemanticsTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    // ---------------------------------------------------------------
    // (a) The persistent Filter Set management entry in the ND header.
    // ---------------------------------------------------------------

    @Test
    fun managementEntry_isOneClickableNodeCarryingItsDescription() {
        composeTestRule.setContent { PTimerTheme { ShootingScreenHarness() } }

        // Exactly one node in the merged tree, not a described child
        // next to a separate clickable ancestor.
        val matches = composeTestRule
            .onAllNodesWithContentDescription("Manage Filter Sets")
            .fetchSemanticsNodes()
        assertEquals("Expected one merged management node.", 1, matches.size)

        val entry: SemanticsNodeInteraction = composeTestRule
            .onNodeWithContentDescription("Manage Filter Sets")
            .assertIsDisplayed()
        assertTrue(
            "The described node must itself carry the click action.",
            entry.fetchSemanticsNode().config.contains(SemanticsActions.OnClick),
        )
        // The visible glyph is 26dp; the touch/semantics target is the
        // one that has to reach 48dp.
        entry.assertTouchHeightIsEqualTo(48.dp)
        entry.assertTouchWidthIsEqualTo(48.dp)
    }

    // ---------------------------------------------------------------
    // (b) The Filter Set colour swatches.
    // ---------------------------------------------------------------

    @Test
    fun colorSwatches_reportNameAndSelectedStateOnTheMergedNode() {
        composeTestRule.setContent {
            var inventory by remember { mutableStateOf(FilterInventory.empty) }
            PTimerTheme {
                FilterSetManagementScreen(
                    inventory = inventory,
                    actions = managementActions(
                        onCreate = { name, color ->
                            inventory = FilterInventory(inventory.filterSets + FilterSet(name, color))
                        },
                    ),
                    onDismiss = {},
                )
            }
        }

        // The creation dialog preselects Blue (the stubbed suggestion).
        composeTestRule.onNodeWithContentDescription("New Filter Set").performClick()
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

    private fun managementActions(onCreate: (String, FilterSetColor) -> Unit) =
        FilterSetManagementActions(
            suggestCreationColor = { FilterSetColor.blue },
            createFilterSet = onCreate,
            renameFilterSet = { _, _ -> },
            recolorFilterSet = { _, _ -> },
            moveFilterSet = { _, _ -> },
            deleteFilterSet = {},
            moveFilterItem = { _, _, _ -> },
            deleteFilterItem = {},
            saveFilterItem = { _, _ -> FilterItemSaveOutcome.Saved },
            camerasAffectedByDeletingFilterSet = { emptyList() },
            camerasAffectedByDeletingItem = { emptyList() },
        )

    @Composable
    private fun ShootingScreenHarness() {
        ShootingScreen(
            state = minimalState(),
            onShutterIndex = {},
            onNdWheelActive = { _, _ -> },
            onNdWheelValue = { _, _ -> },
            onAddFilterWheel = {},
            onAdjustFilterWheel = { _, _ -> FilterWheelAdjustmentOutcome.Boundary },
            onFilterAddUnavailability = { null },
            onRemoveNdWheelOverscroll = {},
            onManageFilterSets = {},
            onSelectNotation = {},
            onSelectFilm = {},
            onSelectProfile = {},
            onSelectSlot = {},
            onRenameSlot = {},
            onSetTarget = {},
            onStartTarget = {},
            onStartAdjusted = {},
            onStartCorrected = {},
            onOpenDetails = {},
            onResetSettings = {},
            onResetSettingsAndName = {},
            onCreateCustomFilm = { _, _ -> true },
            onCreateCustomTableFilm = { _, _ -> true },
            onEditCustomFilm = { null },
            onDeleteCustomFilm = {},
            onPreviewCustomFilm = { null },
            onPreviewCustomTableFilm = { null },
            onFormulaCheckpoints = { emptyList() },
            onTableCheckpoints = { emptyList() },
            onCalculationBasis = { "" },
            onPreviewTableFit = { null },
            onCreateFormulaFromTable = { _, _ -> true },
            onReferencePoints = { _, _ -> emptyList() },
            onOpenAbout = {},
            showExactAlarmSettingsAction = false,
            onOpenExactAlarmSettings = {},
        )
    }

    private fun minimalState() = CalculatorUiState(
        slots = listOf(SlotTab(CameraSlotId.camera1, "Camera 1", isActive = true)),
        activeSlotName = "Camera 1",
        shutterLabels = listOf("1/125"),
        shutterIndex = 0,
        ndLabels = listOf("0"),
        ndIndex = 0,
        filmOptions = emptyList(),
        selectedFilmId = null,
        selectedFilmName = "No film",
        modelOptions = emptyList<ModelOption>(),
        selectedProfileId = null,
        hasFilm = false,
        canReset = false,
        ndNotationMode = NDNotationMode.DEFAULT,
        adjustedText = "1/125",
        adjustedSecondsText = null,
        adjustedStartEnabled = true,
        correctedText = null,
        correctedSecondsText = null,
        correctedStartEnabled = false,
        confidenceLabel = null,
        startEnabled = true,
        hint = null,
        targetDisplay = TargetShutterDisplayState.Unavailable(TargetShutterUnavailableReason.inactive),
    )
}
