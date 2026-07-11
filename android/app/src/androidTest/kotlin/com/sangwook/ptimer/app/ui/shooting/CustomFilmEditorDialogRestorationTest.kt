// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-218: the Custom Film editor's field state used plain `remember`, so
 * an in-progress edit was silently dropped on configuration change or
 * process recreation, resetting the form back to [CustomFilmDraft]'s
 * `initial` value. Verifies the label input (a representative text field)
 * now survives a simulated save/restore via [StateRestorationTester].
 */
class CustomFilmEditorDialogRestorationTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun labelInput_survivesStateRestoration() {
        val restorationTester = StateRestorationTester(composeTestRule)
        restorationTester.setContent {
            PTimerTheme {
                CustomFilmEditorDialog(
                    initial = null,
                    onCreateFormula = { _, _ -> true },
                    onCreateTable = { _, _ -> true },
                    onPreviewFormula = { null },
                    onPreviewTable = { null },
                    onFormulaCheckpoints = { emptyList() },
                    onTableCheckpoints = { emptyList() },
                    onCalculationBasis = { "" },
                    onPreviewTableFit = { null },
                    onCreateFormulaFromTable = { _, _ -> true },
                    onReferencePoints = { _, _ -> emptyList() },
                    onDismiss = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Label").performClick()
        // The Label field's ValueEditPanel is composed first among the
        // simultaneously-mounted text fields (Notes/Reference URL further
        // down the same non-lazy Column also have a SetText action).
        composeTestRule.onAllNodes(hasSetTextAction()).onFirst().performTextInput("Restored Film")
        // Both the editable field and the EditorRow's read-only summary now
        // show "Restored Film" simultaneously — match either occurrence.
        composeTestRule.onAllNodesWithText("Restored Film").onFirst().assertExists()

        restorationTester.emulateSavedInstanceStateRestore()

        composeTestRule.onAllNodesWithText("Restored Film").onFirst().assertExists()
    }
}
