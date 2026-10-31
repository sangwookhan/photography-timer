// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.*
import com.sangwook.ptimer.core.exposure.*
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import java.util.Locale

/** Real shooting card, including three ND wheels and mounted Aux. Checks
 * exported semantics and rendered bounds; does not claim a TalkBack trial. */
@RunWith(Parameterized::class)
class RequiredNDContractTest(private val locale: Locale, private val dark: Boolean, private val fontScale: Float) {
    @get:Rule val compose = createComposeRule()

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0} dark={1} systemFont={2}")
        fun cases() = listOf(Locale.US, Locale.KOREA).flatMap { locale ->
            listOf(false, true).flatMap { dark -> listOf(1f, 1.3f, 2f).map { arrayOf<Any>(locale, dark, it) } }
        }
    }

    @Test fun guidanceRetainsActualTotalAndReasonWithoutDuplicateFocusOrGeometryChanges() {
        val effect = FilterItem("Two-stop auxiliary", FilterItemBehavior.Effect(FilterExposureLoss(2.0)))
        val kit = FilterSet("A very long source name for narrow-screen truncation", FilterSetColor.blue, listOf(effect))
        val c = CalculatorController(emptyList(), inventoryModel = FilterInventoryModel(
            initial = FilterInventory(listOf(kit)), persistenceWriter = PersistenceWriter { it() }))
        c.arrangeCandidateFilterSets(listOf(kit.id))
        repeat(2) { c.addFilterWheel(FilterSource.Standard) }
        c.state.value.filterWheels.forEach { wheel ->
            val row = wheel.rows.indexOfFirst { it.selection == FilterWheelSelection.Standard(2.0) }
            c.setNdWheelActive(wheel.id, true); c.setNdWheelValue(wheel.id, row); c.setNdWheelActive(wheel.id, false)
        }
        val mount = MountedAuxiliaryFilter(kit.id, effect.id, MountedAuxiliaryFilter.initialChoice(effect)!!)
        assertNull(c.applyShootingFilters(listOf(kit.id), listOf(mount)))
        assertEquals(4, c.state.value.occupiedFilterSpaces)
        c.setShutterIndex(ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 })
        c.setTargetShutter(1024.0)
        val shown = mutableStateOf(c.state.value)
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val config = Configuration(base.resources.configuration).apply { setLocale(this@RequiredNDContractTest.locale); this.fontScale = this@RequiredNDContractTest.fontScale }
        val context = base.createConfigurationContext(config)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalContext provides context, LocalConfiguration provides config,
                LocalDensity provides Density(density.density, fontScale)) {
                PTimerTheme(darkTheme = dark, dynamicColor = false) {
                    Box(Modifier.width(360.dp)) { ShootingScreenHarness(shown.value) }
                }
            }
        }
        compose.waitForIdle()
        fun wheels() = compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo))
            .fetchSemanticsNodes().associate { it.config[SemanticsProperties.ContentDescription].joinToString() to it.boundsInRoot }
        val before = wheels()
        assertTrue("The real Base/ND wheels must be rendered", before.size >= 4)
        val label = if (locale == Locale.KOREA) "필요 ND" else "Required ND"
        val outcomes = listOf(
            "numeric" to RequiredNDResult.Value(10.0, false),
            "source-warning" to RequiredNDResult.Value(10.3, true),
            "multiple" to RequiredNDResult.Unavailable(RequiredNDResult.Reason.MultipleSolutions),
            "unavailable" to RequiredNDResult.Unavailable(RequiredNDResult.Reason.NoQuantifiedInverse),
            "negative" to RequiredNDResult.Unavailable(RequiredNDResult.Reason.NegativeAttenuation),
        )
        for ((name, result) in outcomes) {
            compose.runOnIdle {
                val guidance = RequiredNDGuidanceState(result, RequiredNDGuidanceState.Phase.Tracking, shown.value.requiredND.generation + 1)
                val current = c.state.value
                shown.value = current.copy(requiredND = guidance, slotStates = current.slotStates.mapIndexed { index, page ->
                    if (current.slots[index].isActive) page.copy(requiredND = guidance) else page
                })
            }
            val guidance = compose.onNodeWithContentDescription(label, substring = true).assertIsDisplayed()
            val description = guidance.fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()
            assertTrue(description, description.contains(label))
            assertTrue("Actual total remains named separately: $description", description.contains("8"))
            val nodes = compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ContentDescription)).fetchSemanticsNodes()
            assertEquals("One guidance focus, no duplicate ordinary row", 1, nodes.count { it.config[SemanticsProperties.ContentDescription].any { text -> text.contains(label) } })
            assertFalse("No colon in required label", description.contains("$label:"))
            val ordinaryTotal = if (locale == Locale.KOREA) "합계 8 스톱" else "Total 8 stops"
            assertTrue(description, description.contains(ordinaryTotal))
            compose.onAllNodesWithText(ordinaryTotal).assertCountEquals(0)
            if (result is RequiredNDResult.Unavailable) assertTrue(description, description.contains("—"))
            if (name != "numeric") assertFalse("The complete reason is present", description.startsWith(label))
            assertEquals("Guidance cannot move Base or filter wheels", before, wheels())
            val image = compose.onRoot().captureToImage().asAndroidBitmap()
            val directory = File(context.externalCacheDir, "required-nd-contract").apply { mkdirs() }
            File(directory, "${locale.language}-$dark-$fontScale-$name.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        compose.runOnIdle { shown.value = c.state.value }
        compose.onAllNodesWithContentDescription(label, substring = true).assertCountEquals(0)
        assertEquals(before, wheels())
    }
}
