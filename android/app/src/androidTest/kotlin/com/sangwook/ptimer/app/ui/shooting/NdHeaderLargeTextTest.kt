// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
 * PTIMER-221 FILTER-A11Y-002: in the ND header, "required controls,
 * persistent labels, and type cues shall remain reachable and readable
 * under the large-text … rules".
 *
 * The header is one `Row`: the `ND Filter` title, the three-option
 * notation toggle, and the persistent Filter Set management entry. The
 * title used to be measured first at its full intrinsic width, so at a
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
 * one (locale, font scale, wheel count) and asserts on the MERGED
 * semantics tree — the one TalkBack consumes — that everything in the
 * header band still carries a name and a usable target. A last
 * assertion holds the other side of the trade: the title may shorten
 * only as far as the controls force it to, so the ordinary rendering at
 * one, three and four wheels keeps a heading that is not needlessly
 * ellipsized.
 *
 * The locale is imposed with a `LocalContext` / `LocalConfiguration`
 * provider. That does not reach into a Compose `Dialog`, which hosts
 * its own `AndroidComposeView` (see `AffectedCameraNameTest`), but the
 * shooting screen is not a dialog — [ndFilterTitle] resolving to the
 * Korean string in the rendered tree is this suite's own proof that the
 * provider took.
 */
@RunWith(Parameterized::class)
class NdHeaderLargeTextTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    /** One (locale, font scale, wheel count) rendering of the header. */
    data class Case(
        val locale: Locale,
        val fontScale: Float,
        val wheelCount: Int,
    ) {
        override fun toString() = "${locale.toLanguageTag()} ${fontScale}x ${wheelCount}w"
    }

    companion object {
        /**
         * The system "Font size" steps the defect was measured across.
         * 1.15 is where the controls started shrinking and 1.3 is where
         * they disappeared.
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
            return (largeText + stacked).map { arrayOf<Any>(it) }
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
                    ShootingScreenHarness(state)
                }
            }
        }
        composeTestRule.waitForIdle()
    }

    /**
     * The header band: the vertical slice the `Base Shutter` caption
     * occupies. It is the ND header row's sibling in the same `Row` and
     * shares its height, so it locates the band without depending on
     * any of the nodes under test.
     */
    private fun headerBand(): ClosedFloatingPointRange<Float> {
        val captions = mergedNodes().filter { baseShutterTitle in it.texts() }
        assertEquals(
            "Expected exactly one `$baseShutterTitle` caption to anchor the header band.",
            1,
            captions.size,
        )
        val bounds = captions.single().boundsInRoot
        return bounds.top..bounds.bottom
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
            "$name ${b.width.toDp().value.toInt()}x${b.height.toDp().value.toInt()}dp"
        }

        // (a) The management entry: one named, clickable node with a
        //     touch target a finger can actually hit.
        val entries = inHeader.filter { manageFilterSets in it.descriptions() }
        assertEquals(
            "$case: the `$manageFilterSets` entry is not in the ND header's merged " +
                "semantics tree. Header nodes were: $visible",
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

        // (b) Every notation option, still named.
        notationOptions.forEach { option ->
            val matches = inHeader.filter { option in it.names() }
            assertEquals(
                "$case: the `$option` notation option is not in the ND header's merged " +
                    "semantics tree. Header nodes were: $visible",
                1,
                matches.size,
            )
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
                "description: ${anonymous.map { it.boundsInRoot }}. Header nodes were: $visible",
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
                "layout requires. Header nodes were: $visible",
            title.size.width >= deserved - RowChildGapSlack.px(),
        )

        // (e) The other half of the contract. At the DEFAULT text size the
        //     heading does not yield at all: an ordinary user, who never
        //     touches the font-size setting, must read `ND Filter` whole at
        //     every wheel count. Only a raised scale may shorten it — and
        //     even then (a)-(c) keep the controls intact.
        if (case.fontScale == 1.0f) {
            assertTrue(
                "$case: at the default text size the title only gets " +
                    "${title.size.width}px but needs ${intrinsic}px, so it renders " +
                    "ellipsized on first launch. The ND column is too narrow for its " +
                    "own header. Header nodes were: $visible",
                title.size.width >= intrinsic,
            )
        }

        // (f) Paying for the ND column out of the base-shutter column is
        //     only free while the shutter wheel still fits its widest
        //     value. Its rows are `maxLines = 1, softWrap = false` with no
        //     overflow, so a column one pixel too narrow clips them in
        //     silence; and `clearAndSetSemantics` hides the rows, so the
        //     wheel's own node is what gets measured.
        val wheels = mergedNodes().filter { baseShutterTitle in it.descriptions() }
        assertEquals("$case: expected one base-shutter wheel node.", 1, wheels.size)
        val widest = ExposureScale.oneThirdStopShutterCameraLabels
            .maxBy { widthOf(it, wheelStyle) }
        assertTrue(
            "$case: the base-shutter column is ${wheels.single().size.width}px wide but its " +
                "widest value `$widest` needs ${widthOf(widest, wheelStyle)}px — the ND " +
                "column has taken too much of the row and the wheel clips its values.",
            wheels.single().size.width >= widthOf(widest, wheelStyle),
        )
        // The caption over that wheel has no `maxLines` and no overflow,
        // so it too clips in silence. It does not survive every scale
        // even today, and repairing that is a separate ticket — but at
        // the default text size it must read whole at every wheel count,
        // whatever the ND column takes.
        if (case.fontScale == 1.0f) {
            assertTrue(
                "$case: the base-shutter column is ${wheels.single().size.width}px wide but " +
                    "its caption `$baseShutterTitle` needs " +
                    "${widthOf(baseShutterTitle, titleStyle)}px at the default text size.",
                wheels.single().size.width >= widthOf(baseShutterTitle, titleStyle),
            )
        }
    }
}
