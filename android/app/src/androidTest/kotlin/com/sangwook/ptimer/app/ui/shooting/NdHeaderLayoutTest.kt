// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.FilterInventoryModel
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.util.Locale

/**
 * PTIMER-221 ND card header, as the owner approved it: one row reading
 * `Base Shutter`, the Select Filters button, then the
 * `Stops | OD | ND` selector (`ND-012`, `FILTER-FLOW-002`), with every
 * control a real 48dp target (`SHELL-030`) and every required label
 * whole (`FILTER-A11Y-002`). The shooting screen is laid out at 1.0x
 * whatever the system font setting, so that is the size rendered.
 *
 * Each case renders the real screen through [ShootingScreenHarness] at
 * one (locale, wheel count, viewport) and asserts on the MERGED semantics
 * tree — the one TalkBack consumes — that everything in the header row
 * carries a name and a usable target. The rest holds the other side of
 * the trade: the labels read whole, the caption and the button keep their
 * gap, the button and the notation keep theirs, and
 * neither the base-shutter value nor its caption is clipped to pay for
 * the header's room.
 *
 * The locale is imposed with a `LocalContext` / `LocalConfiguration`
 * provider. That does not reach into a Compose `Dialog`, which hosts
 * its own `AndroidComposeView` (see `AffectedCameraNameTest`), but the
 * shooting screen is not a dialog — [selectFilters] resolving to the
 * Korean string in the rendered tree is this suite's own proof that the
 * provider took.
 *
 * The header's need is a width in dp, so every case also renders at an
 * explicit [Case.viewport]; the 360dp cases are the narrow ones.
 * [Case.viewport] `null` renders at the running device's own width.
 */
@RunWith(Parameterized::class)
class NdHeaderLayoutTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    /**
     * One (locale, wheel count, viewport) rendering of the header. A
     * `null` [viewport] renders at the running device's own width.
     */
    data class Case(
        val locale: Locale,
        val wheelCount: Int,
        val viewport: Dp? = null,
    ) {
        override fun toString() =
            "${locale.toLanguageTag()} ${wheelCount}w " +
                (viewport?.let { "${it.value.toInt()}dp" } ?: "device")
    }

    companion object {
        /** Android's minimum touch target. */
        private val MinTouchTarget = 48.dp

        /**
         * The two phone widths pinned: 411dp (1080px at 420dpi) and the
         * common narrow 360dp phone, the owner's Samsung SM-G981N.
         */
        private val Viewports = listOf(360.dp, 411.dp)

        /**
         * The visible gap the header keeps between the `Base Shutter`
         * caption and the Select Filters button (FILTER-FLOW-002).
         */
        private val MinHeaderGutter = 12.dp

        /** The gap between the Select Filters button and the notation. */
        private val MinButtonNotationGap = 8.dp

        /** Items of one row share a vertical centre, within rounding. */
        private val RowCentreSlack = 2.dp

        /**
         * A measured width may miss the laid-out one by a rounding
         * step: [TextMeasurer] and the composition round the same
         * float independently. One pixel of slack, not enough to hide
         * a clipped glyph.
         */
        private const val RoundingSlackPx = 1f

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> =
            listOf(Locale.US, Locale.KOREA).flatMap { locale ->
                (listOf(null) + Viewports).flatMap { viewport ->
                    listOf(1, 3, 4).map { wheels -> arrayOf<Any>(Case(locale, wheels, viewport)) }
                }
            }
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun resources(locale: Locale) = instrumentation.targetContext.let { base ->
        base.createConfigurationContext(
            Configuration(base.resources.configuration).apply { setLocale(locale) },
        ).resources
    }

    private val strings = resources(case.locale)
    private val selectFilters: String = strings.getString(R.string.filter_aux_header_title)
    private val baseShutterTitle: String = strings.getString(R.string.shooting_base_shutter)

    /** Stops / OD / ND — every option the notation toggle offers. */
    private val notationOptions: List<String> = listOf(
        strings.getString(R.string.notation_stops),
        "OD",
        "ND",
    )

    /** A stack of [wheelCount] wheels, the first of which ships by default. */
    private fun stack(wheelCount: Int): CalculatorController {
        val controller = CalculatorController(
            films = emptyList(),
            onStart = { _, _ -> },
            inventoryModel = FilterInventoryModel(
                initial = FilterInventory.empty,
                persistenceWriter = PersistenceWriter { it() },
            ),
        )
        repeat(wheelCount - 1) { controller.addFilterWheel(FilterSource.Standard) }
        require(controller.state.value.filterWheels.size == wheelCount) {
            "expected $wheelCount wheels, got ${controller.state.value.filterWheels.size}"
        }
        return controller
    }

    // What the composition used, captured so the title's own intrinsic
    // width can be re-measured outside it.
    private lateinit var composedDensity: Density
    private lateinit var titleStyle: TextStyle
    private lateinit var wheelStyle: TextStyle
    private lateinit var fontResolver: FontFamily.Resolver
    private lateinit var layoutDirection: LayoutDirection

    private fun measurer() = TextMeasurer(fontResolver, composedDensity, layoutDirection)

    private fun widthOf(text: String, style: TextStyle) =
        measurer().measure(text, style, maxLines = 1, softWrap = false).size.width

    /**
     * The viewport the case renders into: the constrained box, or the
     * whole root when the case takes the device's own width.
     */
    private lateinit var viewportBounds: Rect

    private fun render() {
        val controller = stack(case.wheelCount)
        val base = instrumentation.targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(case.locale)
            fontScale = 1f
        }
        val localized = base.createConfigurationContext(configuration)
        composeTestRule.setContent {
            val state by controller.state.collectAsState()
            val platformDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides localized,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(platformDensity.density, 1f),
            ) {
                PTimerTheme {
                    composedDensity = LocalDensity.current
                    titleStyle = LocalTextStyle.current.merge(MaterialTheme.typography.labelMedium)
                    // The centered row of a non-dense SnapWheel; the
                    // widest text the base-shutter column has to fit.
                    wheelStyle = LocalTextStyle.current.merge(MaterialTheme.typography.titleMedium)
                    fontResolver = LocalFontFamilyResolver.current
                    layoutDirection = LocalLayoutDirection.current
                    // A narrower phone is imposed as a width, not by
                    // resizing the device: the screen reads its width
                    // from the constraints it is measured with, so a
                    // constrained box reproduces the 360dp layout
                    // exactly while the suite keeps the device's own
                    // density and stays runnable on any emulator.
                    val viewport = case.viewport
                    if (viewport == null) {
                        ShootingScreenHarness(state)
                    } else {
                        Box(Modifier.width(viewport).fillMaxHeight()) {
                            ShootingScreenHarness(state)
                        }
                    }
                }
            }
        }
        composeTestRule.waitForIdle()

        val root = composeTestRule.onRoot().fetchSemanticsNode().boundsInRoot
        viewportBounds = case.viewport?.let { Rect(root.left, root.top, root.left + it.px(), root.bottom) }
            ?: root
    }

    /**
     * The header band: the vertical slice both columns reserve above
     * their pickers.
     *
     * Its floor is exact and independent of everything under test —
     * the base-shutter picker's own top, less the persistent
     * label-row height both columns reserve below the header
     * (FILTER-STACK-007). Its ceiling is the higher of the two
     * captions that sit in the band.
     */
    private fun headerBand(): ClosedFloatingPointRange<Float> {
        val captions = mergedNodes().filter { baseShutterTitle in it.texts() }
        assertEquals(
            "Expected exactly one `$baseShutterTitle` caption to anchor the header band.",
            1,
            captions.size,
        )
        val titles = mergedNodes().filter { selectFilters in it.texts() }
        assertEquals("$case: no `$selectFilters` button to anchor the header band.", 1, titles.size)
        val top = minOf(captions.single().boundsInRoot.top, titles.single().boundsInRoot.top)
        return top..(baseShutterWheel().boundsInRoot.top - FilterWheelLabelRowHeight.px())
    }

    /** The base-shutter picker, the one node below the whole band. */
    private fun baseShutterWheel(): SemanticsNode {
        val wheels = mergedNodes().filter { baseShutterTitle in it.descriptions() }
        assertEquals("$case: expected one base-shutter wheel node.", 1, wheels.size)
        return wheels.single()
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

    @Test
    fun theNdHeaderKeepsItsControlsNamedAndReachable() {
        render()

        val band = headerBand()
        val inHeader = mergedNodes().filter { it.boundsInRoot.center.y in band }
        val visible = inHeader.joinToString(" | ") { node ->
            val name = node.names().joinToString("/").ifEmpty { "<unnamed>" }
            val b = node.boundsInRoot
            "$name ${b.left.toDp().value.toInt()}..${b.right.toDp().value.toInt()}dp " +
                "${b.width.toDp().value.toInt()}x${b.height.toDp().value.toInt()}dp"
        }
        val geometry = "Viewport ${viewportBounds.width.toDp()}, header band " +
            "${(band.endInclusive - band.start).toDp()} tall. Header nodes were: $visible"

        // (a) The Select Filters button: one named, clickable node with a
        //     touch target a finger can actually hit; its title and
        //     chevron are that one node.
        val entries = inHeader.filter { selectFilters in it.texts() }
        assertEquals(
            "$case: the `$selectFilters` button is not in the ND header's merged " +
                "semantics tree. $geometry",
            1,
            entries.size,
        )
        val entry = entries.single()
        assertTrue(
            "$case: the `$selectFilters` node carries no click action.",
            entry.config.contains(SemanticsActions.OnClick),
        )
        val touch = entry.touchBoundsInRoot
        assertTrue(
            "$case: the `$selectFilters` touch target is " +
                "${touch.width.toDp()} x ${touch.height.toDp()}, under $MinTouchTarget.",
            touch.width.toDp() >= MinTouchTarget && touch.height.toDp() >= MinTouchTarget,
        )

        // (b) Every notation option, still named, still selectable, and
        //     laid out on a full 48dp target in BOTH dimensions
        //     (SHELL-030). Nothing here may shrink one to buy the title
        //     room. The laid-out box is what is asserted, not
        //     `touchBoundsInRoot`: Compose pads that out to the platform
        //     minimum by itself for any node with a click action, so it
        //     reads 48dp of a 14dp segment.
        val optionNodes = notationOptions.map { option ->
            val matches = inHeader.filter { option in it.names() }
            assertEquals(
                "$case: the `$option` notation option is not in the ND header's merged " +
                    "semantics tree. $geometry",
                1,
                matches.size,
            )
            val laidOut = matches.single().boundsInRoot
            assertTrue(
                "$case: the `$option` option is laid out " +
                    "${laidOut.width.toDp()} x ${laidOut.height.toDp()}, under $MinTouchTarget. " +
                    geometry,
                laidOut.width.toDp() >= MinTouchTarget && laidOut.height.toDp() >= MinTouchTarget,
            )
            option to matches.single()
        }

        // (b2) …and none of those targets is paid for out of a
        //      neighbour's. Compose's padding is what makes the naive
        //      form of (b) vacuous, so the padded bounds of the three
        //      options and the management entry are asserted disjoint:
        //      overlapping expanded targets are exactly how a control
        //      can report 48dp it does not own.
        val targets = optionNodes + (selectFilters to entry)
        targets.indices.forEach { i ->
            (i + 1 until targets.size).forEach { j ->
                val (leftName, leftNode) = targets[i]
                val (rightName, rightNode) = targets[j]
                val a = leftNode.touchBoundsInRoot
                val b = rightNode.touchBoundsInRoot
                assertTrue(
                    "$case: the touch targets of `$leftName` ($a) and `$rightName` ($b) " +
                        "overlap, so neither owns the $MinTouchTarget it reports. $geometry",
                    a.overlaps(b).not(),
                )
            }
        }

        // (c) Nothing tappable in the header is left anonymous. This is
        //     what the device dump caught: `NAF=true` nodes with neither
        //     text nor a content description where the controls used to
        //     be.
        val anonymous = inHeader.filter {
            it.config.contains(SemanticsActions.OnClick) && it.names().all(String::isEmpty)
        }
        assertTrue(
            "$case: ${anonymous.size} clickable header node(s) have no text and no content " +
                "description: ${anonymous.map { it.boundsInRoot }}. $geometry",
            anonymous.isEmpty(),
        )

        // (e) The button's title is a required label, so it reads whole
        //     at every width and wheel count.
        val title = entry
        val intrinsic = widthOf(selectFilters, titleStyle)
        assertTrue(
            "$case: the button only gets ${title.size.width}px but its title needs " +
                "${intrinsic}px, so `$selectFilters` renders ellipsized. $geometry",
            title.size.width >= intrinsic,
        )

        // (f) Paying for the ND column out of the base-shutter column is
        //     only free while the shutter wheel still fits its widest
        //     value. Its rows are `maxLines = 1, softWrap = false` with no
        //     overflow, so a column one pixel too narrow clips them in
        //     silence; and `clearAndSetSemantics` hides the rows, so the
        //     wheel's own node is what gets measured.
        val wheel = baseShutterWheel()
        val column = wheel.size.width
        val widest = ExposureScale.oneThirdStopShutterCameraLabels
            .maxBy { widthOf(it, wheelStyle) }
        assertTrue(
            "$case: the base-shutter column is ${column}px wide but its " +
                "widest value `$widest` needs ${widthOf(widest, wheelStyle)}px — the ND " +
                "column has taken too much of the row and the wheel clips its values. " +
                geometry,
            column >= widthOf(widest, wheelStyle),
        )

        // (g) The `Base Shutter` caption is a required label on the same
        //     one-line row. Laying the text out on one line says what it
        //     needs; the node's own box says what it got.
        val captions = inHeader.filter { baseShutterTitle in it.texts() }
        assertEquals("$case: no `$baseShutterTitle` caption in the header. $geometry", 1, captions.size)
        val caption = captions.single().boundsInRoot
        val captionNeeds = measurer().measure(
            baseShutterTitle,
            titleStyle,
            maxLines = 1,
            softWrap = false,
        ).size
        assertTrue(
            "$case: the `$baseShutterTitle` caption is laid out " +
                "${caption.width}x${caption.height}px, but one line of it needs " +
                "${captionNeeds.width}x${captionNeeds.height}px. It is clipped. $geometry",
            caption.width >= captionNeeds.width - RoundingSlackPx &&
                caption.height >= captionNeeds.height - RoundingSlackPx,
        )

        // (g2) …with at least the visible central gap before the button
        //      (FILTER-FLOW-002)…
        assertTrue(
            "$case: `$baseShutterTitle` ends at ${caption.right}px and `$selectFilters` " +
                "starts at ${title.boundsInRoot.left}px, under $MinHeaderGutter apart. " +
                geometry,
            title.boundsInRoot.left - caption.right >= MinHeaderGutter.px() - RoundingSlackPx,
        )

        // (g3) …and the button stays apart from the notation, which is last.
        val firstOption = optionNodes.minOf { it.second.boundsInRoot.left }
        assertTrue(
            "$case: `$selectFilters` ends at ${title.boundsInRoot.right}px and the notation " +
                "starts at ${firstOption}px, under $MinButtonNotationGap apart. $geometry",
            firstOption - title.boundsInRoot.right >= MinButtonNotationGap.px() - RoundingSlackPx,
        )

        // (h) Nothing in the header may be laid out outside the
        //     viewport. A child that overflows its parent still reports
        //     bounds and still answers a semantics query, so (a)-(c)
        //     alone would pass on a control pushed off the screen edge.
        val escaped = inHeader.filter {
            val b = it.boundsInRoot
            b.width > 0f && (b.left < viewportBounds.left - RoundingSlackPx ||
                b.right > viewportBounds.right + RoundingSlackPx)
        }
        assertTrue(
            "$case: ${escaped.size} header node(s) are laid out outside the viewport " +
                "(${viewportBounds.left}..${viewportBounds.right}px): " +
                escaped.joinToString { "${it.names().joinToString("/")}@${it.boundsInRoot}" } +
                ". $geometry",
            escaped.isEmpty(),
        )

        // (i) And the controls never take the caption's or the value's
        //     room, which is the other way the header can "fit" while
        //     making one of them unreadable: a control may sit above the
        //     base-shutter wheel, never on it or on the caption.
        val controls = entries + notationOptions.mapNotNull { option ->
            inHeader.firstOrNull { option in it.names() }
        }
        listOf("caption" to caption, "wheel" to wheel.boundsInRoot).forEach { (what, area) ->
            val overlapping = controls.filter { it.boundsInRoot.overlaps(area.deflate(RoundingSlackPx)) }
            assertTrue(
                "$case: ${overlapping.size} ND-header control(s) overlap the base-shutter " +
                    "$what at $area: " +
                    overlapping.joinToString { "${it.names().joinToString("/")}@${it.boundsInRoot}" } +
                    ". $geometry",
                overlapping.isEmpty(),
            )
        }

        // (j) One row: the caption, the button and every
        //     notation option share one vertical centre, so nothing has
        //     wrapped onto a second line of the header.
        val rowItems = listOf(
            baseShutterTitle to caption,
            selectFilters to entry.boundsInRoot,
        ) + optionNodes.map { (name, node) -> name to node.boundsInRoot }
        val centres = rowItems.map { (name, bounds) -> name to bounds.center.y }
        val spread = centres.maxOf { it.second } - centres.minOf { it.second }
        assertTrue(
            "$case: the header items are not on one row; their vertical centres are " +
                centres.joinToString { (name, y) -> "$name@${y.toDp()}" } + ". $geometry",
            spread.toDp() <= RowCentreSlack,
        )
    }
}
