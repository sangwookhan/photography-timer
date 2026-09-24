// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.FilterInventoryModel
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
import com.sangwook.ptimer.ui.component.LocalWheelRenderProbe
import com.sangwook.ptimer.ui.component.WheelRenderProbe
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.util.Locale

/**
 * PTIMER-221, the two gaps `NdHeaderLargeTextTest` reported rather than
 * closed.
 *
 * `SHELL-030`: "Primary shooting/timer action controls and ND notation
 * controls provide a comfortably tappable interactive area, independent
 * of their drawn visual size … On Android this is enforced as a minimum
 * 48dp interactive target." The three notation options were 48dp tall
 * and 14–30dp wide, so only one of the two dimensions was ever checked.
 *
 * `FILTER-STACK-007`: "For every allowed composition, including three
 * actual wheels with Plus and four actual wheels, the persistent
 * type/mode label, numeric value, source cue, and type rail shall remain
 * legible without ellipsis at the default and every supported standard
 * text size." `FILTER-STACK-008`: every filter wheel's "picker viewport
 * top and bottom, selected-row band, selected-value baseline, and
 * vertical touch center shall align with" the Base Shutter column's.
 * `FILTER-A11Y-002` carries both under the large-text rules. The
 * previous suite verified the header and the Base Shutter column at
 * 360dp and 2x, but not the wheels beside them — which is where the
 * width that the header gave up actually went.
 *
 * ## What is asserted, and why in this form
 *
 * The notation options are asserted on their LAID-OUT bounds, not on
 * `touchBoundsInRoot`. Compose pads the reported touch bounds of any
 * node carrying an `OnClick` action out to the platform minimum by
 * itself (`NodeCoordinator.touchBoundsInRoot`, via
 * `calculateMinimumTouchTargetPadding`), so `touchBoundsInRoot.width >=
 * 48dp` is true of a 14dp segment and proves nothing. A segment only
 * really owns 48dp when it is laid out at 48dp — which is also why the
 * padded bounds of adjacent options are asserted disjoint: overlapping
 * expanded targets are how a "48dp" target is paid for out of its
 * neighbour.
 *
 * The wheels are asserted through [WheelRenderProbe]. Their rows sit
 * inside the wheel's cleared semantics and the persistent label clears
 * its own (FILTER-A11Y-001), so a semantics assertion cannot see a
 * silent clip — `FilterWheelLabelLegibilityTest` already measures the
 * laid-out text for this reason, and this suite does the same against
 * the real screen instead of a width harness.
 */
@RunWith(Parameterized::class)
class FilterStackViewportLegibilityTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    /** One (viewport, locale, font scale, wheel count) rendering. */
    data class Case(
        val viewport: Dp,
        val locale: Locale,
        val fontScale: Float,
        val wheelCount: Int,
    ) {
        override fun toString() =
            "${viewport.value.toInt()}dp ${locale.toLanguageTag()} ${fontScale}x ${wheelCount}w"
    }

    companion object {
        /** Android's minimum touch target. */
        private val MinTouchTarget = 48.dp

        /**
         * The two phone widths this branch is held to: 411dp is the
         * reference device, 360dp the common narrow phone that
         * `SHELL-020` gives no licence to exclude.
         */
        private val Viewports = listOf(360.dp, 411.dp)

        /**
         * The system "Font size" steps these cases render at.
         *
         * KNOWN AND UNRESOLVED: the shipping app never renders above
         * `MaxCappedFontScale` (1.3x) — `ShootingApp` wraps the whole
         * shooting surface in `CappedFontScale`. This harness composes
         * `ShootingScreen` directly rather than through `ShootingApp`,
         * so anything above 1.3x here is a scale the app cannot reach.
         * Those cases are kept because they are the only place the
         * uncapped layout is visible at all, and because whether
         * "every supported standard text size" means the OS's 2.0x or
         * the app's effective 1.3x is with the spec owner: SHELL-020
         * allows a cap on non-primary chrome but not on "primary
         * readable content", which the wheel values are. Do not read a
         * pass above 1.3x as proof about the shipping app, or a failure
         * there as a shipping defect, until that is settled.
         */
        private val Scales = listOf(1.0f, 2.0f)

        /** One wheel, the three-wheel composition with Plus, and the cap. */
        private val WheelCounts = listOf(1, 3, 4)

        /** A measured float against a laid-out one: one pixel of slack. */
        private const val RoundingSlackPx = 1f

        /**
         * The Filter Set every wheel past the first is mounted from. Set
         * names are user data, so this one word identifies the wheels
         * that must carry a source cue in either language.
         */
        private const val SetName = "Lee holder"

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = Viewports.flatMap { viewport ->
            listOf(Locale.US, Locale.KOREA).flatMap { locale ->
                Scales.flatMap { scale ->
                    WheelCounts.map { wheels -> arrayOf<Any>(Case(viewport, locale, scale, wheels)) }
                }
            }
        }
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private val strings = instrumentation.targetContext.let { base ->
        base.createConfigurationContext(
            Configuration(base.resources.configuration).apply { setLocale(case.locale) },
        ).resources
    }

    private val baseShutterTitle: String = strings.getString(R.string.shooting_base_shutter)
    private val manageFilterSets: String = strings.getString(R.string.filter_manage_sets)

    /** Stops / OD / ND — every option the notation toggle offers. */
    private val notationOptions: List<String> = listOf(
        strings.getString(R.string.notation_stops),
        "OD",
        "ND",
    )

    /** What one wheel reported about the text and cues it drew. */
    private data class WheelRender(
        var label: TextLayoutResult? = null,
        var hasSourceCue: Boolean = false,
        val rows: MutableMap<Int, TextLayoutResult> = linkedMapOf(),
        val railedRows: MutableSet<Int> = linkedSetOf(),
    )

    private val rendered = linkedMapOf<String, WheelRender>()

    private val probe = object : WheelRenderProbe {
        override fun onRow(
            wheel: String,
            index: Int,
            isCenter: Boolean,
            hasRail: Boolean,
            layout: TextLayoutResult,
        ) {
            val entry = rendered.getOrPut(wheel) { WheelRender() }
            entry.rows[index] = layout
            if (hasRail) entry.railedRows += index else entry.railedRows -= index
        }

        override fun onLabel(wheel: String, hasSourceCue: Boolean, layout: TextLayoutResult) {
            val entry = rendered.getOrPut(wheel) { WheelRender() }
            entry.label = layout
            entry.hasSourceCue = hasSourceCue
        }
    }

    /**
     * A stack of [wheelCount] actual wheels. Every wheel past the first
     * comes from a Filter Set, so it carries a source cue, and one of
     * them sits on its GND row in Apply full value mode — `GND FULL` is
     * the widest persistent label the stack can produce.
     */
    private fun stack(wheelCount: Int): CalculatorController {
        val soft = FilterItem(
            "Lee soft GND",
            FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops)),
        )
        val lee = FilterSet(
            SetName,
            FilterSetColor.blue,
            listOf(
                soft,
                FilterItem("Lee ND 3", FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops))),
                FilterItem("Lee ND 6", FilterItemBehavior.Fixed(FilterRegisteredValue(6.0, FilterValueUnit.stops))),
            ),
        )
        val controller = CalculatorController(
            films = emptyList(),
            onStart = { _, _ -> },
            inventoryModel = FilterInventoryModel(
                initial = FilterInventory(listOf(lee)),
                persistenceWriter = PersistenceWriter { it() },
            ),
        )
        repeat(wheelCount - 1) { controller.addFilterWheel(FilterSource.FilterSet(lee.id)) }
        if (wheelCount > 1) {
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
                "the GND Apply full value row did not commit; `GND FULL` is not under test"
            }
        }
        require(controller.state.value.filterWheels.size == wheelCount) {
            "expected $wheelCount wheels, got ${controller.state.value.filterWheels.size}"
        }
        return controller
    }

    private lateinit var composedDensity: Density
    private lateinit var viewportBounds: Rect

    private fun render() {
        val controller = stack(case.wheelCount)
        val base = instrumentation.targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(case.locale)
            fontScale = case.fontScale
        }
        val localized = base.createConfigurationContext(configuration)
        composeTestRule.setContent {
            val state by controller.state.collectAsState()
            val platformDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides localized,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(platformDensity.density, case.fontScale),
                LocalWheelRenderProbe provides probe,
            ) {
                PTimerTheme {
                    composedDensity = LocalDensity.current
                    // The narrow phone is imposed as a width, not by
                    // resizing the device, so the suite runs on any
                    // emulator at its own density.
                    Box(Modifier.width(case.viewport).fillMaxHeight()) {
                        ShootingScreenHarness(state)
                    }
                }
            }
        }
        composeTestRule.waitForIdle()

        val root = composeTestRule.onRoot().fetchSemanticsNode().boundsInRoot
        viewportBounds = Rect(root.left, root.top, root.left + case.viewport.px(), root.bottom)
    }

    private fun mergedNodes(): List<SemanticsNode> {
        val out = mutableListOf<SemanticsNode>()
        fun walk(node: SemanticsNode) {
            out += node
            node.children.forEach(::walk)
        }
        walk(composeTestRule.onRoot().fetchSemanticsNode())
        return out
    }

    private fun SemanticsNode.texts(): List<String> =
        if (config.contains(SemanticsProperties.Text)) {
            config[SemanticsProperties.Text].map { it.text }
        } else {
            emptyList()
        }

    private fun SemanticsNode.descriptions(): List<String> =
        if (config.contains(SemanticsProperties.ContentDescription)) {
            config[SemanticsProperties.ContentDescription]
        } else {
            emptyList()
        }

    private fun SemanticsNode.names(): List<String> = texts() + descriptions()

    private fun Float.toDp() = (this / composedDensity.density).dp

    private fun Dp.px() = value * composedDensity.density

    /** The one node that carries [name] and can be tapped. */
    private fun control(name: String): SemanticsNode {
        val matches = mergedNodes().filter {
            name in it.names() && it.config.contains(SemanticsActions.OnClick)
        }
        assertEquals("$case: expected exactly one tappable `$name`. ${geometry()}", 1, matches.size)
        return matches.single()
    }

    private fun geometry(): String {
        val wheels = rendered.entries.joinToString(" | ") { (name, render) ->
            val label = render.label
            val rows = render.rows.entries.joinToString(",") { (index, row) ->
                "$index:`${row.layoutInput.text.text}`" +
                    "${(row.getLineRight(0) - row.getLineLeft(0)).toInt()}/${row.size.width}px" +
                    "h${(row.getLineBottom(0) - row.getLineTop(0)).toInt()}/${row.size.height}px" +
                    (if (index in render.railedRows) "" else " NORAIL")
            }
            "$name label=" +
                (label?.let { "`${it.layoutInput.text.text}`${if (it.hasVisualOverflow) " OVERFLOW" else ""}" }
                    ?: "<none>") +
                " cue=${render.hasSourceCue} rows[$rows]"
        }
        val bounds = mergedNodes()
            .filter { node -> rendered.keys.any { it in node.descriptions() } }
            .joinToString(" | ") { node ->
                val b = node.boundsInRoot
                "${node.descriptions().first()} ${b.left.toDp().value.toInt()}.." +
                    "${b.right.toDp().value.toInt()}dp (${b.width.toDp().value.toInt()}dp wide, " +
                    "y ${b.top.toDp().value.toInt()}..${b.bottom.toDp().value.toInt()}dp)"
            }
        return "Viewport ${viewportBounds.width.toDp()}. Wheels drew: $wheels. Wheel boxes: $bounds"
    }

    /**
     * SHELL-030 in both dimensions, which is the clause the previous
     * suite only half-checked.
     */
    @Test
    fun everyNotationOptionOwnsAFullTouchTarget() {
        render()

        val options = notationOptions.associateWith { control(it) }
        options.forEach { (label, node) ->
            // The CLIPPED bounds, deliberately: a clipping ancestor
            // clips pointer input too, so a segment measured 48dp
            // inside a 26dp clipped track can still only be touched
            // over 26dp of it.
            val laidOut = node.boundsInRoot
            assertTrue(
                "$case: the `$label` notation option is laid out " +
                    "${laidOut.width.toDp()} x ${laidOut.height.toDp()} " +
                    "(unclipped ${node.size.width.toFloat().toDp()} x " +
                    "${node.size.height.toFloat().toDp()}), under $MinTouchTarget. " +
                    "Compose pads `touchBoundsInRoot` out to the platform minimum on its own, so " +
                    "only the laid-out box says whether the option really owns a 48dp target. " +
                    geometry(),
                laidOut.width.toDp() >= MinTouchTarget && laidOut.height.toDp() >= MinTouchTarget,
            )
            assertTrue(
                "$case: the `$label` option is laid out at ${laidOut.left}..${laidOut.right}px, " +
                    "outside the ${viewportBounds.left}..${viewportBounds.right}px viewport. " +
                    geometry(),
                laidOut.left >= viewportBounds.left - RoundingSlackPx &&
                    laidOut.right <= viewportBounds.right + RoundingSlackPx,
            )
        }

        // And no option's target is paid for out of a neighbour's: the
        // padded bounds of the three options and the management entry
        // stay disjoint.
        val targets = options + (manageFilterSets to control(manageFilterSets))
        targets.entries.toList().let { entries ->
            entries.indices.forEach { i ->
                (i + 1 until entries.size).forEach { j ->
                    val (leftName, leftNode) = entries[i]
                    val (rightName, rightNode) = entries[j]
                    val a = leftNode.touchBoundsInRoot
                    val b = rightNode.touchBoundsInRoot
                    assertTrue(
                        "$case: the touch targets of `$leftName` ($a) and `$rightName` ($b) " +
                            "overlap, so neither owns the ${MinTouchTarget} it reports. ${geometry()}",
                        a.overlaps(b).not(),
                    )
                }
            }
        }
    }

    /**
     * FILTER-STACK-007 for every real wheel, at every viewport, locale
     * and supported text size: the persistent label and the numeric
     * values stay whole in BOTH axes, and the source and type cues stay
     * drawn.
     *
     * The rows are asserted with `hasVisualOverflow` entire. That is
     * only meaningful because the row height follows the rendered text
     * metrics (`snapWheelItemHeight`); while it was a fixed 34dp, every
     * wheel's line box outgrew its row at a raised font scale and the
     * assertion had to be narrowed to width to say anything at all.
     */
    @Test
    fun everyWheelKeepsItsLabelValueAndCues() {
        render()

        val filterWheels = rendered.keys.filter { it != baseShutterTitle }
        assertEquals(
            "$case: expected ${case.wheelCount} filter wheels to report. ${geometry()}",
            case.wheelCount,
            filterWheels.size,
        )

        // The Base Shutter column is measured with them: its row height
        // is the one the filter wheels share (FILTER-STACK-008), so a
        // row too short for its line shows up there first — its values
        // are the widest text in the card.
        rendered.forEach { (wheel, render) ->
            val clipped = render.rows.filterValues { it.hasVisualOverflow }
            assertTrue(
                "$case: ${clipped.size} of `$wheel`'s numeric rows overflow their row: " +
                    clipped.values.joinToString {
                        "`${it.layoutInput.text.text}` needs " +
                            "${(it.getLineRight(0) - it.getLineLeft(0)).toInt()}x" +
                            "${(it.getLineBottom(0) - it.getLineTop(0)).toInt()}px in " +
                            "${it.size.width}x${it.size.height}px"
                    } +
                    ". The rows are `maxLines = 1, softWrap = false` with no overflow, so a row " +
                    "a pixel too small cuts the value in silence. ${geometry()}",
                clipped.isEmpty(),
            )
        }

        filterWheels.forEach { wheel ->
            val render = rendered.getValue(wheel)
            val label = render.label
            assertTrue("$case: `$wheel` never laid its persistent label out. ${geometry()}", label != null)
            assertEquals(
                "$case: `$wheel`'s persistent label wrapped onto " +
                    "${label!!.lineCount} lines. ${geometry()}",
                1,
                label.lineCount,
            )
            assertTrue(
                "$case: `$wheel`'s persistent label `${label.layoutInput.text.text}` overflows its " +
                    "column and is cut — the mode word disappears and Record only becomes " +
                    "indistinguishable from Apply full value. ${geometry()}",
                label.hasVisualOverflow.not(),
            )

            val unrailed = render.rows.keys - render.railedRows
            assertTrue(
                "$case: ${unrailed.size} of `$wheel`'s rows drew no type rail. ${geometry()}",
                unrailed.isEmpty(),
            )

            // A Filter Set wheel leads its label with the set's source
            // cue; the Standard wheel the stack starts with has none.
            assertEquals(
                "$case: `$wheel` drew ${if (render.hasSourceCue) "a" else "no"} source cue. " +
                    geometry(),
                SetName in wheel,
                render.hasSourceCue,
            )
        }
    }

    /**
     * FILTER-STACK-008's shared vertical axis, under the same sweep:
     * every filter wheel's viewport top and bottom, and therefore its
     * selected-row band and vertical touch center, stay level with the
     * Base Shutter column's.
     */
    @Test
    fun everyWheelSharesTheBaseShutterAxis() {
        render()

        val shutter = mergedNodes()
            .filter { baseShutterTitle in it.descriptions() }
            .also { assertEquals("$case: expected one base-shutter wheel. ${geometry()}", 1, it.size) }
            .single()
            .boundsInRoot

        rendered.keys.filter { it != baseShutterTitle }.forEach { wheel ->
            val node = mergedNodes()
                .filter { wheel in it.descriptions() }
                .also { assertEquals("$case: expected one `$wheel` node. ${geometry()}", 1, it.size) }
                .single()
                .boundsInRoot
            listOf(
                Triple("viewport top", shutter.top, node.top),
                Triple("viewport bottom", shutter.bottom, node.bottom),
                Triple("vertical touch center", shutter.center.y, node.center.y),
            ).forEach { (what, expected, actual) ->
                assertEquals(
                    "$case: `$wheel` does not share the Base Shutter $what. ${geometry()}",
                    expected.toDouble(),
                    actual.toDouble(),
                    RoundingSlackPx.toDouble(),
                )
            }
        }
    }
}
