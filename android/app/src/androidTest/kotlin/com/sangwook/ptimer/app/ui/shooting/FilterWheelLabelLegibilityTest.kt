// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.FilterInventoryModel
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * PTIMER-221 FILTER-STACK-007: the persistent label above a wheel
 * viewport must communicate the GND mode — `GND` with `REC` or `FULL` —
 * and, source cue included, stay legible "without ellipsis at the
 * default and every supported standard text size", up to the
 * four-actual-wheel composition.
 *
 * `GND FULL` is the widest label the stack can produce. Before this
 * suite the label was a plain `maxLines = 1` Text with the default
 * `TextOverflow.Clip` and no font-scale discipline, so a narrow column
 * dropped the mode word silently: the header rendered `GND` with no
 * ellipsis and Record only became indistinguishable from Apply full
 * value.
 *
 * The label is deliberately outside the semantics tree
 * (FILTER-A11Y-001), and a semantics assertion would have passed
 * against the clipped rendering anyway — so what gets asserted is the
 * laid-out text: one line, complete, no visual overflow.
 *
 * [wheelColumns_areNoNarrowerThanTheHarnessWidth] and its three-wheel
 * twin pin the harness widths against the real geometry of the running
 * device, so the harness is never more generous than the app.
 */
class FilterWheelLabelLegibilityTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private companion object {
        /**
         * Widths the label harness is held at: narrower than the column
         * a three- / four-wheel stack actually gets on the phones this
         * branch is verified on, so passing here implies passing there.
         */
        val HarnessWidthAtFourWheels = 48.dp
        val HarnessWidthAtThreeWheels = 56.dp

        /**
         * The system "Font size" steps Android exposes, from the
         * smallest through the largest accessibility step.
         */
        val SupportedFontScales = listOf(0.85f, 1.0f, 1.15f, 1.3f, 1.5f, 1.8f, 2.0f)

        /** Both GND mode labels; FILTER-STACK-007 fixes the words. */
        val GndLabels = listOf("GND REC", "GND FULL")
    }

    private fun gnd(name: String, stops: Double) = FilterItem(
        name,
        FilterItemBehavior.Gnd(FilterRegisteredValue(stops, FilterValueUnit.stops)),
    )

    private fun fixed(name: String, stops: Double) = FilterItem(
        name,
        FilterItemBehavior.Fixed(FilterRegisteredValue(stops, FilterValueUnit.stops)),
    )

    /**
     * A stack of [wheelCount] actual wheels whose Filter Set wheel sits
     * on its GND row in Apply full value mode. Four wheels is the cap,
     * and hides Plus.
     */
    private fun stackWithGndFull(wheelCount: Int): CalculatorController {
        val soft = gnd("Lee soft GND", 3.0)
        val lee = FilterSet(
            "Lee holder",
            FilterSetColor.blue,
            listOf(soft, fixed("Lee ND 3", 3.0), fixed("Lee ND 6", 6.0)),
        )
        val controller = CalculatorController(
            films = emptyList(),
            onStart = { _, _ -> },
            inventoryModel = FilterInventoryModel(
                initial = FilterInventory(listOf(lee)),
                persistenceWriter = PersistenceWriter { it() },
            ),
        )
        // The stack starts with one Standard wheel.
        repeat(wheelCount - 1) { controller.addFilterWheel(FilterSource.FilterSet(lee.id)) }
        val target = FilterWheelSelection.Item(
            FilterRowSelection(soft.id, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
        )
        val wheel = controller.state.value.filterWheels
            .first { candidate -> candidate.rows.any { it.selection == target } }
        controller.setNdWheelActive(wheel.id, true)
        controller.setNdWheelValue(wheel.id, wheel.rows.indexOfFirst { it.selection == target })
        controller.setNdWheelActive(wheel.id, false)

        val committed = controller.state.value.filterWheels.first { it.id == wheel.id }
        require(committed.rows[committed.committedIndex].selection == target) {
            "the GND Apply full value row did not commit; the harness is not testing GND FULL"
        }
        require(controller.state.value.filterWheels.size == wheelCount) {
            "expected $wheelCount wheels, got ${controller.state.value.filterWheels.size}"
        }
        return controller
    }

    /**
     * The real screen at the running device's own width: the column the
     * app hands a wheel must be at least as wide as the harness width.
     */
    @Test
    fun wheelColumns_areNoNarrowerThanTheHarnessWidth() {
        assertColumnsAtLeast(wheelCount = 4, harness = HarnessWidthAtFourWheels)
    }

    @Test
    fun wheelColumnsAtThreeWheels_areNoNarrowerThanTheHarnessWidth() {
        assertColumnsAtLeast(wheelCount = 3, harness = HarnessWidthAtThreeWheels)
    }

    private fun assertColumnsAtLeast(wheelCount: Int, harness: Dp) {
        val controller = stackWithGndFull(wheelCount)
        composeTestRule.setContent {
            val state by controller.state.collectAsState()
            PTimerTheme { ShootingScreenHarness(state) }
        }

        (1..wheelCount).forEach { position ->
            val width = composeTestRule
                .onNodeWithContentDescription("Filter $position of $wheelCount", substring = true)
                .assertExists()
                .getUnclippedBoundsInRoot()
                .width
            assertTrue(
                "Wheel $position of $wheelCount is $width, narrower than the $harness " +
                    "harness; retune the harness width.",
                width >= harness,
            )
        }
    }

    /**
     * FILTER-STACK-007 proper. Both mode labels, at both narrow column
     * widths, at every supported system font scale: one line, the
     * complete text, and no visual overflow — so neither a silent clip
     * nor an ellipsis, with the source cue still beside it.
     */
    @Test
    fun gndLabels_stayCompleteAndUnclippedAtEverySupportedTextSize() {
        val layouts = mutableMapOf<String, TextLayoutResult>()
        val cases = SupportedFontScales.flatMap { scale ->
            listOf(HarnessWidthAtThreeWheels to 3, HarnessWidthAtFourWheels to 4)
                .flatMap { (width, wheels) -> GndLabels.map { Triple(scale, width, wheels) to it } }
        }
        composeTestRule.setContent {
            val base = LocalDensity.current
            PTimerTheme {
                Column {
                    cases.forEach { (case, label) ->
                        val (scale, width, wheels) = case
                        CompositionLocalProvider(
                            LocalDensity provides Density(base.density, scale),
                        ) {
                            Box(Modifier.width(width)) {
                                FilterWheelLabelRow(
                                    label = label,
                                    // A Filter Set wheel always leads with
                                    // its source cue, so the label competes
                                    // with it for the column.
                                    cueColor = Color.Blue,
                                    onLabelTextLayout = { layouts[key(label, wheels, scale)] = it },
                                )
                            }
                        }
                    }
                }
            }
        }
        composeTestRule.waitForIdle()

        cases.forEach { (case, label) ->
            val (scale, _, wheels) = case
            val key = key(label, wheels, scale)
            val result = layouts[key]
            assertNotNull("$key never laid out.", result)
            assertEquals(key, label, result!!.layoutInput.text.text)
            assertEquals("$key must stay on one line.", 1, result.lineCount)
            assertFalse(
                "$key overflows its column and is cut: the mode word disappears " +
                    "and Record only becomes indistinguishable from Apply full value.",
                result.hasVisualOverflow,
            )
        }
    }

    private fun key(label: String, wheels: Int, scale: Float) = "$label at ${wheels}w, scale $scale"

    /** Minimal wiring: only the stack's own callbacks do anything. */
    @Composable
    private fun ShootingScreenHarness(state: CalculatorUiState) {
        ShootingScreen(
            state = state,
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
}
