// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.FilterInventoryModel
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.exposure.*
import com.sangwook.ptimer.ui.component.LocalWheelRenderProbe
import com.sangwook.ptimer.ui.component.WheelRenderProbe
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Real, validated shooting fixtures: text must fit, not merely have a semantics label. */
class PhoneShootingReadabilityTest {
    @get:Rule val rule = createComposeRule()

    private fun controller(auxiliary: Boolean, longExposure: Boolean, ndCount: Int = 3): CalculatorController {
        val orange = FilterItem("Orange Filter", FilterItemBehavior.Color(FilterExposureLoss(2.0), FilterSetColor.orange))
        val set = FilterSet("Film Color Filters", FilterSetColor.orange, listOf(orange))
        val c = CalculatorController(
            films = LaunchPresetFilmCatalogV2.films,
            inventoryModel = FilterInventoryModel(initial = FilterInventory(listOf(set)), persistenceWriter = PersistenceWriter { it() }),
        )
        c.selectFilm("adox-chs-100-ii")
        c.setTargetShutter(60.0)
        if (auxiliary) assertNull(c.applyShootingFilters(listOf(set.id), listOf(
            MountedAuxiliaryFilter(set.id, orange.id, AuxiliaryFilterChoice.RegisteredLoss),
        )))
        val stops = if (longExposure) listOf(27, 1, 1, 1) else listOf(2, 2, 1)
        stops.take(if (longExposure) stops.size else ndCount).forEachIndexed { index, value ->
            if (index > 0) c.addFilterWheel(FilterSource.Standard)
            val wheel = c.state.value.filterWheels.last()
            val row = wheel.rows.indexOfFirst { it.contributionStops == value.toDouble() }
            require(row >= 0)
            c.setNdWheelValue(wheel.id, row)
        }
        c.setShutterIndex(if (longExposure) c.state.value.shutterLabels.lastIndex else c.state.value.shutterLabels.indexOf("1/3"))
        return c
    }

    @Test fun plusTouchAddsWheelInCompactShootingScreen() {
        val c = controller(auxiliary = true, longExposure = false, ndCount = 1)
        rule.setContent {
            val state by c.state.collectAsState()
            PTimerTheme {
                Box(Modifier.width(360.dp).height(586.dp)) {
                    ShootingScreenHarness(state, c::addFilterWheel)
                }
            }
        }
        rule.onNodeWithContentDescription("Add filter").performTouchInput { click() }
        rule.waitForIdle()
        assertEquals(2, c.state.value.filterWheels.size)
    }

    @Test fun maximumFilmContentFitsAbovePagerWithoutScrolling() {
        val c = controller(auxiliary = true, longExposure = false)
        rule.setContent {
            PTimerTheme {
                Box(Modifier.width(360.dp).height(602.dp)) {
                    ShootingScreenHarness(c.state.value)
                }
            }
        }
        rule.waitForIdle()
        val page = rule.onNodeWithTag("shooting-page-scroll-0", useUnmergedTree = true).fetchSemanticsNode()
        val scrollRange = page.config[SemanticsProperties.VerticalScrollAxisRange]
        assertEquals("Main content must fit without scrolling", 0f, scrollRange.maxValue(), 0f)
    }

    @Test fun narrowAuxiliaryNameAndValueAreVisible() {
        val item = controller(auxiliary = true, longExposure = false).state.value.auxiliarySummary!!.visibleItems.single()
        val compact = mutableStateOf(true)
        rule.setContent {
            PTimerTheme {
                PhoneShootingPresentation(enabled = true, extra = if (compact.value) 0.dp else 24.dp) {
                    Box(Modifier.width(if (compact.value) 46.dp else 52.dp)) {
                        AuxiliarySummaryRow(item, canStack = true)
                    }
                }
            }
        }
        for (isCompact in listOf(true, false)) {
            rule.runOnIdle { compact.value = isCompact }
            val name = rule.onNodeWithText("Orange").fetchSemanticsNode()
            val layouts = mutableListOf<TextLayoutResult>()
            name.config[SemanticsActions.GetTextLayoutResult].action!!.invoke(layouts)
            val layout = layouts.single()
            assertEquals(6, layout.getLineEnd(layout.lineCount - 1, true))
            assertFalse(layout.hasVisualOverflow)
            val value = rule.onNodeWithText("2").fetchSemanticsNode()
            assertTrue(name.boundsInRoot.bottom <= value.boundsInRoot.top)
        }
    }

    @Test fun fractionalNdFitsWithFourWheels() {
        val nd = FilterItem("Fractional ND", FilterItemBehavior.Fixed(FilterRegisteredValue(8.0 + 2.0 / 3.0, FilterValueUnit.stops)))
        val set = FilterSet("ND Set", FilterSetColor.blue, listOf(nd))
        val c = CalculatorController(
            films = LaunchPresetFilmCatalogV2.films,
            inventoryModel = FilterInventoryModel(initial = FilterInventory(listOf(set)), persistenceWriter = PersistenceWriter { it() }),
        )
        c.selectFilm("adox-chs-100-ii")
        c.setTargetShutter(60.0)
        c.arrangeCandidateFilterSets(listOf(set.id))
        c.addFilterWheel(FilterSource.FilterSet(set.id))
        val wheel = c.state.value.filterWheels.first { it.source is FilterSource.FilterSet }
        val index = wheel.rows.indexOfFirst { it.selection is FilterWheelSelection.Item }
        require(index >= 0)
        c.setNdWheelValue(wheel.id, index)
        repeat(2) { c.addFilterWheel(FilterSource.Standard) }
        assertEquals(4, c.state.value.filterWheels.size)
        val fixture = c.state.value
        val layouts = mutableListOf<TextLayoutResult>()
        rule.setContent {
            CompositionLocalProvider(LocalWheelRenderProbe provides object : WheelRenderProbe {
                override fun onRow(wheel: String, index: Int, isCenter: Boolean, hasRail: Boolean, layout: TextLayoutResult) {
                    if (isCenter && layout.layoutInput.text.text.contains("8 2/3")) layouts.add(layout)
                }
                override fun onLabel(wheel: String, hasSourceCue: Boolean, layout: TextLayoutResult) {}
            }) {
                PTimerTheme { Box(Modifier.width(360.dp).height(586.dp)) { ShootingScreenHarness(fixture) } }
            }
        }
        rule.waitForIdle()
        assertTrue("Fractional selected ND was not rendered", layouts.isNotEmpty())
        val layout = layouts.last()
        assertEquals(layout.layoutInput.text.length, layout.getLineEnd(0, true))
        assertFalse("Fractional ND must not clip: text=${layout.layoutInput.text}, size=${layout.size}, constraints=${layout.layoutInput.constraints}, lineRight=${layout.getLineRight(0)}, width=${layout.didOverflowWidth}, height=${layout.didOverflowHeight}", layout.hasVisualOverflow)
    }

    @Test fun busyAndLongExposureValuesFitAtDefaultAndAboveTheFontCap() {
        val initial = controller(true, false)
        val state = mutableStateOf(initial.state.value)
        val font = mutableStateOf(1f)
        val revision = mutableStateOf(0)
        val wheelLayouts = mutableMapOf<String, TextLayoutResult>()
        var runtimeDensity = 1f
        rule.setContent {
            val density = LocalDensity.current
            runtimeDensity = density.density
            val config = Configuration(LocalConfiguration.current).apply { fontScale = font.value }
            CompositionLocalProvider(
                LocalConfiguration provides config,
                LocalDensity provides Density(density.density, font.value),
                LocalWheelRenderProbe provides object : WheelRenderProbe {
                    override fun onRow(wheel: String, index: Int, isCenter: Boolean, hasRail: Boolean, layout: TextLayoutResult) {
                        if (isCenter) wheelLayouts[wheel] = layout
                    }
                    override fun onLabel(wheel: String, hasSourceCue: Boolean, layout: TextLayoutResult) {}
                },
            ) {
                PTimerTheme { Box(Modifier.width(360.dp).height(586.dp)) { key(revision.value) { ShootingScreenHarness(state.value) } } }
            }
        }
        for (aux in listOf(true, false)) for (scale in listOf(1f, 1.2f, 2f)) for (mode in NDNotationMode.entries) {
            val c = controller(aux, !aux)
            c.setNotationMode(mode)
            rule.runOnIdle { wheelLayouts.clear(); state.value = c.state.value; font.value = scale; revision.value++ }
            rule.waitForIdle()
            val description = "aux=$aux font=$scale mode=$mode"
            val nodes = rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
                .fetchSemanticsNodes()
            val required = listOf("Target Shutter", "Base Shutter", "Adjusted Shutter", "Reciprocity", "Corrected Exposure",
                c.state.value.adjustedText, c.state.value.correctedText!!)
            required.forEach { text ->
                val node = nodes.first { it.config[SemanticsProperties.Text].any { it.text == text } }
                val results = mutableListOf<TextLayoutResult>()
                node.config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results)
                val layout = results.single()
                assertEquals("$description $text", text.length, layout.getLineEnd(layout.lineCount - 1, true))
                assertFalse("$description $text is ellipsized", layout.isLineEllipsized(layout.lineCount - 1))
                assertTrue("$description $text outside page: ${node.boundsInRoot}", node.boundsInRoot.bottom <= 586 * runtimeDensity)
            }
            assertTrue("$description missing wheel probes", wheelLayouts.size >= if (aux) 4 else 5)
            wheelLayouts.forEach { (wheel, layout) ->
                assertEquals("$description $wheel ${layout.layoutInput.text}", layout.layoutInput.text.length, layout.getLineEnd(0, true))
                assertFalse("$description $wheel ${layout.layoutInput.text} exceeds ${layout.size}", layout.hasVisualOverflow)
                assertTrue("$description $wheel selected size", layout.layoutInput.style.fontSize >= 22.sp)
                assertEquals("$description $wheel selected weight", FontWeight.SemiBold, layout.layoutInput.style.fontWeight)
            }
        }
    }
}
