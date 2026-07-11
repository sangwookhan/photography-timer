// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.ModelOption
import com.sangwook.ptimer.app.vm.SlotTab
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.core.target.TargetShutterUnavailableReason
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-218: ShootingScreen's dialog-visibility flags (showFilmPicker,
 * showRename, showTarget, showEditor, showResetConfirm) and [editDraft] used
 * plain `remember`, so a configuration change or process recreation silently
 * closed whatever dialog was open. Exercises the Rename dialog (showRename)
 * as a representative case — all five flags share the identical
 * rememberSaveable<Boolean> fix.
 */
class ShootingScreenDialogRestorationTest {
    @get:Rule
    val composeTestRule = createComposeRule()

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

    @Test
    fun renameDialog_staysOpenAfterStateRestoration() {
        val restorationTester = StateRestorationTester(composeTestRule)
        restorationTester.setContent {
            PTimerTheme {
                ShootingScreen(
                    state = minimalState(),
                    onShutterIndex = {},
                    onNdIndex = {},
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
        }

        composeTestRule.onNodeWithText("Camera 1").performClick()
        composeTestRule.onNodeWithText("Camera name").assertExists()

        restorationTester.emulateSavedInstanceStateRestore()

        composeTestRule.onNodeWithText("Camera name").assertExists()
    }
}
