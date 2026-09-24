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
import androidx.compose.ui.unit.Constraints
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
 * PTIMER-221 FILTER-A11Y-002: in the ND header, "required controls,
 * persistent labels, and type cues shall remain reachable and readable
 * under the large-text … rules".
 *
 * The header holds the `ND Filter` title, the three-option notation
 * toggle, and the persistent Filter Set management entry — on one row
 * where they fit, and with the title reflowed onto its own line above
 * the controls where they do not. The title used to be measured first
 * at its full intrinsic width in a single fixed row, so at a
 * raised system font scale it took the row and squeezed the two
 * controls out — measured on a real device in English with a single
 * wheel (the widest title against the narrowest column): at 1.15x the
 * `ND` option was 10px wide and the gear 18px, and from 1.3x up both
 * were gone from the semantics tree, leaving unlabelled hit targets and
 * an undrawn gear. Korean survived, because `ND 필터` and `스톱` are
 * narrower — so the failure is layout-width driven and the sweep has to
 * cover both languages.
 *
 * Each case renders the real screen through [ShootingScreenHarness] at
 * one (locale, font scale, wheel count, viewport) and asserts on the
 * MERGED semantics tree — the one TalkBack consumes — that everything
 * in the header band still carries a name and a usable target. The
 * rest holds the other side of the trade: every required label reads
 * whole, the two columns keep a gutter between them, and neither the
 * base-shutter value nor its caption is clipped to pay for the
 * header's room.
 *
 * The locale is imposed with a `LocalContext` / `LocalConfiguration`
 * provider. That does not reach into a Compose `Dialog`, which hosts
 * its own `AndroidComposeView` (see `AffectedCameraNameTest`), but the
 * shooting screen is not a dialog — [ndFilterTitle] resolving to the
 * Korean string in the rendered tree is this suite's own proof that the
 * provider took.
 *
 * ## Viewport sweep
 *
 * Naming a font scale is not enough. The header's need is a width in
 * dp — title plus the two controls — while the column split used to be
 * a ratio, so the same scale passes on a 411dp phone and fails on a
 * 360dp one. `SHELL-020` admits no such gap: required shooting-flow
 * controls "remain reachable and readable when the system font scale is
 * set large", with no device-width escape clause. So every case renders
 * at an explicit [Case.viewport] as well, and the 360dp cases are the
 * ones that pin the fix. [Case.viewport] `null` keeps the original
 * sweep at the running device's own width.
 */
@RunWith(Parameterized::class)
class NdHeaderLargeTextTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    /**
     * One (locale, font scale, wheel count, viewport) rendering of the
     * header. A `null` [viewport] renders at the running device's own
     * width.
     */
    data class Case(
        val locale: Locale,
        val fontScale: Float,
        val wheelCount: Int,
        val viewport: Dp? = null,
    ) {
        override fun toString() =
            "${locale.toLanguageTag()} ${fontScale}x ${wheelCount}w " +
                (viewport?.let { "${it.value.toInt()}dp" } ?: "device")
    }

    companion object {
        /**
         * The system "Font size" steps the defect was measured across.
         * 1.15 is where the controls started shrinking and 1.3 is where
         * they disappeared.
         *
         * KNOWN AND UNRESOLVED: the shipping app never renders above
         * `MaxCappedFontScale` (1.3x) — `ShootingApp` wraps the whole
         * shooting surface in `CappedFontScale`, and this harness
         * composes `ShootingScreen` directly rather than through it. The
         * 1.5x and 2.0x cases are therefore scales the app cannot reach
         * today.
         *
         * SETTLED by the accepted [SPEC-CONFLICT] of 2026-09-24:
         * SHELL-020 allows a font-scale cap on non-primary chrome but
         * not on primary readable content, which the wheel values, the
         * Base Shutter value and the persistent labels are. So 2.0x is
         * REQUIRED uncapped component coverage for primary content, and
         * a failure at 2.0x blocks PR #67.
         *
         * A pass at 2.0x is component evidence only. It is not
         * shipping-path evidence, because this harness composes
         * `ShootingScreen` directly while `ShootingApp` wraps the whole
         * shooting surface in `CappedFontScale` (`MaxCappedFontScale`,
         * 1.3x). Correcting that cap is a separate Android Code PR,
         * linked to #67 as a merge dependency; shipping-path evidence
         * only exists once the two are verified combined.
         */
        private val Scales = listOf(1.0f, 1.15f, 1.3f, 1.5f, 2.0f)

        /** Android's minimum touch target. */
        private val MinTouchTarget = 48.dp

        /**
         * The header `Row` leaves a constant ~2dp between each child —
         * present before this fix too, and not something the title can
         * claim. Assertion (d) allows for it rather than chasing it.
         */
        private val RowChildGapSlack = 3.dp

        /**
         * The two phone widths the sweep pins. 411dp is the reference
         * device this branch is verified on (1080px at 420dpi); 360dp
         * is the common narrow Android phone the ratio-based split
         * failed on and which `SHELL-020` gives no licence to exclude.
         */
        private val Viewports = listOf(360.dp, 411.dp)

        /** Android's largest system "Font size" step. */
        private const val MaxSupportedFontScale = 2.0f

        /**
         * The gutter the card keeps between its two columns, so the
         * `Base Shutter` caption and the `ND Filter` title never abut.
         */
        private val MinColumnGutter = 8.dp

        /**
         * A measured width may miss the laid-out one by a rounding
         * step: [TextMeasurer] and the composition round the same
         * float independently. One pixel of slack, not enough to hide
         * a clipped glyph.
         */
        private const val RoundingSlackPx = 1f

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> {
            val locales = listOf(Locale.US, Locale.KOREA)
            // The worst case: one wheel, so the ND column is at its
            // narrowest and the header has the least room to give.
            val largeText = locales.flatMap { locale ->
                Scales.map { scale -> Case(locale, scale, wheelCount = 1) }
            }
            // And the stacked compositions, where the ND column is
            // already wider and the base-shutter column is at its
            // narrowest — the side that pays for the header's room.
            val stacked = locales.flatMap { locale ->
                listOf(3, 4).flatMap { wheels ->
                    listOf(1.0f, 2.0f).map { scale -> Case(locale, scale, wheelCount = wheels) }
                }
            }
            // The width sweep the header's dp-sized need actually
            // lives or dies on, at the default and the maximum
            // supported font scale, in both languages.
            val viewports = Viewports.flatMap { viewport ->
                locales.flatMap { locale ->
                    listOf(1.0f, MaxSupportedFontScale).flatMap { scale ->
                        listOf(1, 3, 4).map { wheels -> Case(locale, scale, wheels, viewport) }
                    }
                }
            }
            return (largeText + stacked + viewports).map { arrayOf<Any>(it) }
        }
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun resources(locale: Locale) = instrumentation.targetContext.let { base ->
        base.createConfigurationContext(
            Configuration(base.resources.configuration).apply { setLocale(locale) },
        ).resources
    }

    private val strings = resources(case.locale)
    private val ndFilterTitle: String = strings.getString(R.string.shooting_nd_filter)
    private val baseShutterTitle: String = strings.getString(R.string.shooting_base_shutter)
    private val manageFilterSets: String = strings.getString(R.string.filter_manage_sets)

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
            ) {
                PTimerTheme {
                    composedDensity = LocalDensity.current
                    titleStyle = LocalTextStyle.current.merge(MaterialTheme.typography.labelLarge)
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
     * captions that sit in the band, which is the band's own top
     * whenever either of them is top-aligned in it.
     *
     * Anchoring the ceiling on the `Base Shutter` caption alone — as
     * this did while the header was one fixed 30dp row — stops working
     * the moment the header may reflow: a one-line caption centred in
     * a two-row header marks a thin slice in the middle of the band
     * and drops the controls row out of it.
     */
    private fun headerBand(): ClosedFloatingPointRange<Float> {
        val captions = mergedNodes().filter { baseShutterTitle in it.texts() }
        assertEquals(
            "Expected exactly one `$baseShutterTitle` caption to anchor the header band.",
            1,
            captions.size,
        )
        val titles = mergedNodes().filter { ndFilterTitle in it.texts() }
        assertEquals("$case: no `$ndFilterTitle` title to anchor the header band.", 1, titles.size)
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

        // (a) The management entry: one named, clickable node with a
        //     touch target a finger can actually hit.
        val entries = inHeader.filter { manageFilterSets in it.descriptions() }
        assertEquals(
            "$case: the `$manageFilterSets` entry is not in the ND header's merged " +
                "semantics tree. $geometry",
            1,
            entries.size,
        )
        val entry = entries.single()
        assertTrue(
            "$case: the `$manageFilterSets` node carries no click action.",
            entry.config.contains(SemanticsActions.OnClick),
        )
        val touch = entry.touchBoundsInRoot
        assertTrue(
            "$case: the `$manageFilterSets` touch target is " +
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
        val targets = optionNodes + (manageFilterSets to entry)
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

        // (d) The title yields — but only as far as it must. It has to
        //     keep every pixel the controls do not need, so it is never
        //     ellipsized while the row still has slack. Sharing the
        //     remainder with a weighted Spacer, for instance, halves it.
        val titles = inHeader.filter { ndFilterTitle in it.texts() }
        assertEquals("$case: no `$ndFilterTitle` title in the header.", 1, titles.size)
        val title = titles.single()
        val titleLeft = title.positionInRoot.x
        // Everything the header places after the title: the toggle track,
        // its options, and the management entry. The nearest one marks
        // where the title's share of the row ends.
        val available = inHeader
            .filter { it !== title && it.positionInRoot.x > titleLeft }
            .minOf { it.positionInRoot.x } - titleLeft
        val intrinsic = widthOf(ndFilterTitle, titleStyle)
        val deserved = minOf(intrinsic.toFloat(), available)
        assertTrue(
            "$case: the title is laid out ${title.size.width}px wide; the row leaves " +
                "${available}px before the first control and the text needs ${intrinsic}px, " +
                "so it should have had ${deserved}px. It is ellipsized harder than the " +
                "layout requires. $geometry",
            title.size.width >= deserved - RowChildGapSlack.px(),
        )

        // (e) The other half of the contract, and the reviewer's
        //     "complete required labels": the heading is a required
        //     label, so it reads whole at EVERY supported width, scale
        //     and wheel count — not only at the default text size it
        //     used to be checked at. If the header cannot fit the title
        //     beside the controls it has to reflow and give the title
        //     its own line, not ellipsize it.
        assertTrue(
            "$case: the title only gets ${title.size.width}px but needs ${intrinsic}px, so " +
                "`$ndFilterTitle` renders ellipsized. The ND column is too narrow for its " +
                "own header and the header did not reflow. $geometry",
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

        // (g) The caption over that wheel has no `maxLines` and no
        //     overflow, so it clips in silence in BOTH directions: too
        //     narrow a column cuts it at the trailing edge, and a
        //     header row too short for the line it then needs cuts it
        //     from below. Laying the text out against the column the
        //     app actually gave it says what the caption needs; the
        //     node's own box says what it got.
        val captions = inHeader.filter { baseShutterTitle in it.texts() }
        assertEquals("$case: no `$baseShutterTitle` caption in the header. $geometry", 1, captions.size)
        val caption = captions.single().boundsInRoot
        val captionNeeds = measurer().measure(
            baseShutterTitle,
            titleStyle,
            constraints = Constraints(maxWidth = column),
        ).size
        assertTrue(
            "$case: the `$baseShutterTitle` caption is laid out " +
                "${caption.width}x${caption.height}px, but in the ${column}px column the " +
                "app gave it the text needs ${captionNeeds.width}x${captionNeeds.height}px. " +
                "It is clipped. $geometry",
            caption.width >= captionNeeds.width - RoundingSlackPx &&
                caption.height >= captionNeeds.height - RoundingSlackPx,
        )

        // (g2) …and it stays a separate word from the ND title. When
        //      the shutter column gets exactly the width its caption
        //      needs — a narrow screen at a raised font scale — the two
        //      run together with no gap at all, which reads as one
        //      string: `Base ShutterND Filter`, seen on the device at
        //      360dp before the columns were given a gutter.
        assertTrue(
            "$case: `$baseShutterTitle` ends at ${caption.right}px and `$ndFilterTitle` " +
                "starts at ${title.boundsInRoot.left}px — the two captions run together. " +
                geometry,
            title.boundsInRoot.left - caption.right >= MinColumnGutter.px() - RoundingSlackPx,
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
        //     making one of them unreadable.
        //
        //     This used to be stated as a horizontal one: no control's
        //     left edge before the base-shutter wheel's right edge. That
        //     was the right guard while the controls sat inside the ND
        //     column, and the wrong one now that they have their own row
        //     across the card — spanning the card is the whole reason
        //     each option can own 48dp at 360dp. So the guard is the
        //     rectangle it always meant: a control may sit ABOVE the
        //     base-shutter column, never ON it.
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
    }
}
