// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.app.LocaleManager
import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.FilterItemSaveBlockReason
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
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
 *
 * Three surfaces interpolate a camera name — deleting a Filter Set,
 * deleting a Filter Item, and a refused item save — and each is driven
 * here for real, in English and in Korean, with one default slot name
 * and one custom name in the same message.
 *
 * Every one of the three lives inside a Compose `Dialog`, which hosts
 * its own `AndroidComposeView` and re-provides `LocalContext`,
 * `LocalConfiguration` and `LocalResources` from the platform. A
 * `CompositionLocalProvider` wrapped around the content therefore does
 * not reach inside (it does reach the shooting screen, which is not a
 * dialog). The language is set at the instrumentation boundary instead,
 * on the per-app locale, and the activity that renders is launched
 * afterwards and asserted to carry it.
 */
class AffectedCameraNameTest {
    /**
     * Empty: the content goes on an activity this test launches itself,
     * after the per-app locale is in place.
     */
    @get:Rule
    val composeTestRule = createEmptyComposeRule()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val localeManager: LocaleManager =
        instrumentation.targetContext.getSystemService(LocaleManager::class.java)

    /** Whatever the device had, restored whichever way a test ends. */
    private var originalLocales: LocaleList = LocaleList.getEmptyLocaleList()
    private var scenario: ActivityScenario<ComponentActivity>? = null

    /** Resources of the activity that is rendering, in its own locale. */
    private lateinit var rendered: Resources

    /** One default slot label and one photographer-supplied name. */
    private val cameras = listOf(
        CameraSlotIdentity(CameraSlotId.camera1),
        CameraSlotIdentity(CameraSlotId.camera3, CUSTOM_CAMERA_NAME),
    )

    private val item = FilterItem(
        name = "Big Stopper",
        behavior = FilterItemBehavior.Fixed(FilterRegisteredValue(10.0, FilterValueUnit.stops)),
    )
    private val set = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))

    private val actions = FilterSetManagementActions(
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
    )

    @Before
    fun rememberTheDeviceLocale() {
        originalLocales = localeManager.applicationLocales
    }

    @After
    fun restoreTheDeviceLocale() {
        scenario?.close()
        scenario = null
        applyAppLocale(originalLocales)
    }

    // ---- the three rendered call paths -------------------------------

    @Test
    fun theFilterSetDeleteConfirmationNamesTheCamerasInEnglish() {
        openFilterSetDeleteConfirmation(ENGLISH)
        assertCamerasRendered(R.string.filter_set_delete_message_cameras, ENGLISH_CAMERAS)
    }

    @Test
    fun theFilterSetDeleteConfirmationNamesTheCamerasInKorean() {
        openFilterSetDeleteConfirmation(KOREAN)
        assertCamerasRendered(R.string.filter_set_delete_message_cameras, KOREAN_CAMERAS)
    }

    @Test
    fun theFilterItemDeleteConfirmationNamesTheCamerasInEnglish() {
        openFilterItemDeleteConfirmation(ENGLISH)
        assertCamerasRendered(R.string.filter_item_delete_message_cameras, ENGLISH_CAMERAS)
    }

    @Test
    fun theFilterItemDeleteConfirmationNamesTheCamerasInKorean() {
        openFilterItemDeleteConfirmation(KOREAN)
        assertCamerasRendered(R.string.filter_item_delete_message_cameras, KOREAN_CAMERAS)
    }

    @Test
    fun theBlockedSaveNamesTheCamerasInEnglish() {
        openBlockedSave(ENGLISH)
        assertCamerasRendered(R.string.filter_item_save_blocked_choice, ENGLISH_CAMERAS)
    }

    @Test
    fun theBlockedSaveNamesTheCamerasInKorean() {
        openBlockedSave(KOREAN)
        assertCamerasRendered(R.string.filter_item_save_blocked_choice, KOREAN_CAMERAS)
    }

    // ---- the formatter, directly -------------------------------------

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

    // ---- navigation --------------------------------------------------

    /** Edit mode on the list level, then delete the only Filter Set. */
    private fun openFilterSetDeleteConfirmation(language: String) {
        renderManagementScreen(language)
        clickText(R.string.action_edit)
        clickDescription(R.string.action_delete)
    }

    /** Open the only Filter Set, then delete its only Filter Item. */
    private fun openFilterItemDeleteConfirmation(language: String) {
        renderManagementScreen(language)
        // The row reads out as "name, color, count"; the name is enough.
        composeTestRule.onNodeWithContentDescription(set.name, substring = true).performClick()
        composeTestRule.waitForIdle()
        clickText(R.string.action_edit)
        clickDescription(R.string.action_delete)
    }

    /** Save an existing item against a controller that refuses it. */
    private fun openBlockedSave(language: String) {
        render(language) {
            FilterItemEditorDialog(
                target = FilterItemEditorTarget.Existing(item),
                onSave = {
                    FilterItemSaveOutcome.Blocked(cameras, FilterItemSaveBlockReason.removesSelectedChoice)
                },
                onSaved = {},
                onDismiss = {},
            )
        }
        clickText(R.string.action_save)
    }

    private fun renderManagementScreen(language: String) {
        render(language) {
            FilterSetManagementScreen(
                inventory = FilterInventory(listOf(set)),
                actions = actions,
                onDismiss = {},
            )
        }
    }

    // ---- assertions --------------------------------------------------

    /**
     * The whole message as the surface renders it: the sentence comes
     * from the rendering activity's own resources, so only the camera
     * names are stated here.
     */
    private fun assertCamerasRendered(@StringRes message: Int, cameraNames: String) {
        composeTestRule.onNodeWithText(rendered.getString(message, cameraNames)).assertIsDisplayed()
    }

    private fun clickText(@StringRes label: Int) {
        composeTestRule.onNodeWithText(rendered.getString(label)).performClick()
        composeTestRule.waitForIdle()
    }

    private fun clickDescription(@StringRes label: Int) {
        composeTestRule.onNodeWithContentDescription(rendered.getString(label)).performClick()
        composeTestRule.waitForIdle()
    }

    // ---- the language boundary ---------------------------------------

    /**
     * Put the app in [language], then launch the activity that renders
     * [content] and confirm it really came up in that language — a
     * silent fall back to the device locale would otherwise let the
     * second language pass by asserting the first one twice.
     */
    private fun render(language: String, content: @Composable () -> Unit) {
        applyAppLocale(LocaleList.forLanguageTags(language))
        // The process is told about the new configuration asynchronously.
        // The activity below is what has to carry it, and is asserted, so
        // this is only a settling wait.
        await { currentLanguageOf(instrumentation.targetContext.resources) == language }

        val launched = ActivityScenario.launch(ComponentActivity::class.java)
        scenario = launched
        var launchedLanguage = ""
        launched.onActivity { activity ->
            launchedLanguage = currentLanguageOf(activity.resources)
            rendered = activity.resources
            activity.setContent { PTimerTheme { content() } }
        }
        assertEquals(
            "The rendering activity did not come up in the per-app locale",
            language,
            launchedLanguage,
        )
        composeTestRule.waitForIdle()
    }

    private fun applyAppLocale(locales: LocaleList) {
        instrumentation.runOnMainSync { localeManager.applicationLocales = locales }
        await { localeManager.applicationLocales.toLanguageTags() == locales.toLanguageTags() }
        assertEquals(
            "The platform did not take the per-app locale",
            locales.toLanguageTags(),
            localeManager.applicationLocales.toLanguageTags(),
        )
    }

    private fun currentLanguageOf(resources: Resources) =
        resources.configuration.locales[0].toLanguageTag()

    private fun await(condition: () -> Boolean): Boolean {
        val deadline = SystemClock.uptimeMillis() + LOCALE_TIMEOUT_MILLIS
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return true
            Thread.sleep(LOCALE_POLL_MILLIS)
        }
        return condition()
    }

    private fun resourcesFor(locale: Locale) = instrumentation.targetContext.let { base ->
        base.createConfigurationContext(
            Configuration(base.resources.configuration).apply { setLocale(locale) },
        ).resources
    }
}

private const val ENGLISH = "en-US"
private const val KOREAN = "ko-KR"
private const val CUSTOM_CAMERA_NAME = "Rolleiflex 2.8F"
private const val ENGLISH_CAMERAS = "Camera 1, $CUSTOM_CAMERA_NAME"
private const val KOREAN_CAMERAS = "카메라 1, $CUSTOM_CAMERA_NAME"
private const val LOCALE_TIMEOUT_MILLIS = 5_000L
private const val LOCALE_POLL_MILLIS = 50L
