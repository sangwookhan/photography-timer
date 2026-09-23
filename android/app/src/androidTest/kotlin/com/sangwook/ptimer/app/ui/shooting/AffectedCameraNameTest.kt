// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity
import com.sangwook.ptimer.ui.theme.PTimerTheme
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.util.Locale

/**
 * FILTER-A11Y-003 on the affected-camera messages: the default slot
 * label is the app's own word and must be the user's language, while a
 * photographer-supplied camera name is the photographer's text and must
 * survive byte for byte. The state layer keeps the default label
 * locale-stable because it has no resources, so the substitution
 * happens here, at the display boundary.
 */
class AffectedCameraNameTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private val set = FilterSet("Lee holder", FilterSetColor.blue)

    private fun resourcesFor(locale: Locale) = InstrumentationRegistry.getInstrumentation()
        .targetContext
        .let { base ->
            base.createConfigurationContext(
                Configuration(base.resources.configuration).apply { setLocale(locale) },
            ).resources
        }

    private fun showDeleteConfirmation(cameras: List<CameraSlotIdentity>) {
        composeTestRule.setContent {
            PTimerTheme {
                    FilterSetManagementScreen(
                        inventory = FilterInventory(listOf(set)),
                        actions = FilterSetManagementActions(
                            suggestCreationColor = { FilterSetColor.blue },
                            createFilterSet = { _, _ -> },
                            renameFilterSet = { _, _ -> },
                            recolorFilterSet = { _, _ -> },
                            moveFilterSet = { _, _ -> },
                            deleteFilterSet = {},
                            moveFilterItem = { _, _, _ -> },
                            deleteFilterItem = {},
                            saveFilterItem = { _, _ -> FilterItemSaveOutcome.Saved },
                            camerasAffectedByDeletingFilterSet = { cameras },
                            camerasAffectedByDeletingItem = { cameras },
                        ),
                        onDismiss = {},
                    )
            }
        }
        // Enter edit mode and ask to delete the only set, which raises the
        // confirmation carrying the affected-camera message.
        composeTestRule.onNodeWithText("Edit").performClick()
        composeTestRule.onNodeWithContentDescription("Delete").performClick()
        composeTestRule.waitForIdle()
    }

    @Test
    fun theRenderedConfirmationNamesTheDefaultSlotAndKeepsACustomName() {
        showDeleteConfirmation(
            listOf(
                CameraSlotIdentity(CameraSlotId.camera1),
                CameraSlotIdentity(CameraSlotId.camera3, "Rolleiflex 2.8F"),
            ),
        )
        composeTestRule.onNodeWithText("Camera 1, Rolleiflex 2.8F", substring = true).assertIsDisplayed()
    }

    /**
     * The management surface is a `Dialog`, and a Compose `Dialog` hosts
     * its own `AndroidComposeView` which re-provides `LocalContext` and
     * `LocalConfiguration` from the platform — a provider outside it does
     * not reach inside, so the rendered test above cannot be driven in a
     * second language. The Korean half is asserted on the exact function
     * the dialog calls, with a real Korean `Resources`.
     */
    @Test
    fun theDefaultSlotLabelIsLocalizedAndACustomNameIsNot() {
        val english = resourcesFor(Locale.US)
        val korean = resourcesFor(Locale.KOREA)
        val default = listOf(CameraSlotIdentity(CameraSlotId.camera1))
        val custom = listOf(CameraSlotIdentity(CameraSlotId.camera2, "Hasselblad 500C/M"))

        assertEquals("Camera 1", localizedCameraNames(default, english))
        assertEquals("카메라 1", localizedCameraNames(default, korean))

        // A photographer's own text is not the app's word to translate.
        assertEquals("Hasselblad 500C/M", localizedCameraNames(custom, english))
        assertEquals("Hasselblad 500C/M", localizedCameraNames(custom, korean))
    }

    @Test
    fun aMixedListLocalizesOnlyTheDefaultLabel() {
        assertEquals(
            "카메라 1, Rolleiflex 2.8F",
            localizedCameraNames(
                listOf(
                    CameraSlotIdentity(CameraSlotId.camera1),
                    CameraSlotIdentity(CameraSlotId.camera3, "Rolleiflex 2.8F"),
                ),
                resourcesFor(Locale.KOREA),
            ),
        )
    }

    /** A blank or whitespace custom name falls back to the default. */
    @Test
    fun aBlankCustomNameFallsBackToTheLocalizedDefault() {
        assertEquals(
            "카메라 4",
            localizedCameraNames(
                listOf(CameraSlotIdentity(CameraSlotId.camera4, "   ")),
                resourcesFor(Locale.KOREA),
            ),
        )
    }
}
