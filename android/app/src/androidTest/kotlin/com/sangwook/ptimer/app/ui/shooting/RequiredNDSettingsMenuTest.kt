// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.util.Locale

@RunWith(Parameterized::class)
class RequiredNDSettingsMenuTest(private val locale: Locale, private val fontScale: Float) {
    @get:Rule val rule = createComposeRule()

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0} fontScale={1}")
        fun cases() = listOf(Locale.US, Locale.KOREA).flatMap { locale ->
            listOf(1f, 1.3f, 2f).map { arrayOf<Any>(locale, it) }
        }
    }

    @Test fun typographyAndFullRowTogglePreserveGuidanceContract() {
        val controller = CalculatorController(emptyList())
        controller.setShutterIndex(ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 })
        controller.setTargetShutter(1024.0)
        controller.beginBaseInteraction()
        assertTrue(controller.state.value.showRequiredND)
        assertNotNull(controller.state.value.requiredND.result)
        val before = controller.exportCameraList()
        val calls = mutableListOf<Boolean>()
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(locale)
            this.fontScale = this@RequiredNDSettingsMenuTest.fontScale
        }
        val context = base.createConfigurationContext(configuration)
        rule.setContent {
            val state by controller.state.collectAsState()
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, fontScale),
            ) {
                PTimerTheme {
                    PhoneShootingPresentation(enabled = true) {
                        Box(Modifier.width(360.dp)) {
                            ShootingScreenHarness(state, onShowRequiredND = {
                                calls += it
                                controller.setShowRequiredND(it)
                            })
                        }
                    }
                }
            }
        }
        rule.onNodeWithTag("shooting-settings-menu").performClick()
        val row = rule.onNodeWithTag("show-required-nd-setting")
        row.assertIsDisplayed().assertHasClickAction().assertIsToggleable().assertIsOn()
        row.assertHeightIsAtLeast(72.dp)
        val title = layout(context.getString(R.string.required_nd_setting))
        val description = layout(context.getString(R.string.required_nd_setting_body))
        val neighbor = layout(context.getString(R.string.action_manage_cameras))
        assertEquals(neighbor.layoutInput.style.fontSize, title.layoutInput.style.fontSize)
        assertTrue(description.layoutInput.style.fontSize.value < title.layoutInput.style.fontSize.value)
        assertFalse("Keep the full explanation visible", description.hasVisualOverflow)
        for ((index, x) in listOf(0.1f, 0.5f, 0.9f).withIndex()) {
            row.performTouchInput { click(Offset(width * x, height / 2f)) }
            if (index % 2 == 0) row.assertIsOff() else row.assertIsOn()
            assertEquals(index + 1, calls.size)
            row.assertIsDisplayed()
            assertEquals(before, controller.exportCameraList())
        }
        assertEquals(listOf(false, true, false), calls)
        assertNull("Disabling restores ordinary status immediately", controller.state.value.requiredND.result)
        rule.runOnIdle {
            controller.selectSlot(controller.state.value.slots[1].id)
            assertFalse(controller.state.value.showRequiredND)
            controller.beginBaseInteraction()
            assertNull(controller.state.value.requiredND.result)
        }
    }

    private fun layout(text: String): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        rule.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single()
    }
}
