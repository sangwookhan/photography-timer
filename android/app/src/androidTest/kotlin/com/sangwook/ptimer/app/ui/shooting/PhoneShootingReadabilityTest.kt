// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
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

    private fun controller(auxiliary: Boolean, longExposure: Boolean): CalculatorController {
        val orange = FilterItem("Orange Filter", FilterItemBehavior.Color(FilterExposureLoss(2.0), FilterSetColor.orange))
        val set = FilterSet("Film Color Filters", FilterSetColor.orange, listOf(orange))
        val c = CalculatorController(
            films = LaunchPresetFilmCatalogV2.films,
            inventoryModel = FilterInventoryModel(FilterInventory(listOf(set)), persistenceWriter = PersistenceWriter { it() }),
        )
        c.selectFilm("adox-chs-100-ii")
        c.setTargetShutter(60.0)
        if (auxiliary) assertNull(c.applyShootingFilters(listOf(set.id), listOf(
            MountedAuxiliaryFilter(set.id, orange.id, AuxiliaryFilterChoice.RegisteredLoss),
        )))
        val stops = if (longExposure) listOf(27, 1, 1, 1) else listOf(2, 2, 1)
        stops.forEachIndexed { index, value ->
            if (index > 0) c.addFilterWheel(FilterSource.Standard)
            val wheel = c.state.value.filterWheels.last()
            val row = wheel.rows.indexOfFirst { it.contributionStops == value.toDouble() }
            require(row >= 0)
            c.setNdWheelValue(wheel.id, row)
        }
        c.setShutterIndex(if (longExposure) c.state.value.shutterLabels.lastIndex else c.state.value.shutterLabels.indexOf("1/3"))
        return c
    }

    @Test fun busyAndLongExposureValuesFitAtDefaultAndAboveTheFontCap() {
        val initial = controller(true, false)
        val state = mutableStateOf(initial.state.value)
        val font = mutableStateOf(1f)
        val wheelLayouts = mutableMapOf<String, TextLayoutResult>()
        rule.setContent {
            val density = LocalDensity.current
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
                PTimerTheme { Box(Modifier.width(411.43.dp).height(794.dp)) { ShootingScreenHarness(state.value) } }
            }
        }
        for (aux in listOf(true, false)) for (scale in listOf(1f, 1.2f, 2f)) for (mode in NDNotationMode.entries) {
            val c = controller(aux, !aux)
            c.setNotationMode(mode)
            rule.runOnIdle { wheelLayouts.clear(); state.value = c.state.value; font.value = scale }
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
                assertEquals("$description $text", text.length, layout.getLineEnd(0, true))
                assertTrue("$description $text outside page: ${node.boundsInRoot}", node.boundsInRoot.bottom <= 794 * 2.625f)
            }
            assertTrue("$description missing wheel probes", wheelLayouts.size >= if (aux) 4 else 5)
            wheelLayouts.forEach { (wheel, layout) ->
                assertEquals("$description $wheel ${layout.layoutInput.text}", layout.layoutInput.text.length, layout.getLineEnd(0, true))
            }
            val root = rule.onRoot(useUnmergedTree = true).fetchSemanticsNode()
            fun verifyScroll(node: androidx.compose.ui.semantics.SemanticsNode) {
                node.config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)?.let {
                    if (node.boundsInRoot.top < 794 * 2.625f) assertEquals("$description Main scroll", 0f, it.maxValue(), 0f)
                }
                node.children.forEach(::verifyScroll)
            }
            verifyScroll(root)
        }
    }
}
