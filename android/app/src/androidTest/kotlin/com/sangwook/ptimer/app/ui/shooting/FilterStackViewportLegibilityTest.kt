// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import android.graphics.Paint
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
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.ui.MaxCappedFontScale
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.FilterInventoryModel
import com.sangwook.ptimer.app.vm.FilterRowTypeCategory
import com.sangwook.ptimer.app.vm.FilterWheelPresenter
import com.sangwook.ptimer.app.vm.FilterWheelRowUiState
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.ui.component.LocalWheelRenderProbe
import com.sangwook.ptimer.ui.component.RowRailWidth
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
 * PTIMER-221 FILTER-STACK-007 / FILTER-A11Y-002 / SHELL-030, across the
 * card's whole viewport matrix.
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
 * text size." The same contract also holds the row together: every
 * filter wheel's "picker viewport top and bottom, selected-row band,
 * selected-value baseline, and vertical touch center shall align with"
 * the Base Shutter column's, and "Base Shutter and every filter wheel in
 * the row shall use the same numeric size".
 *
 * ## The content under test is derived, not chosen
 *
 * A wheel showing `0` proves nothing about a 47dp column. So every wheel
 * is seeded to the WIDEST row it can legally hold, and the widest is
 * derived by walking the legal value domain through the shipping
 * formatters rather than by naming a value:
 *
 * - [widestStops] walks every canonical stops value a wheel can carry —
 *   the shipping ladder of `ND-001` plus the decimal registrations
 *   `FILTER-ITEM-004` admits ("finite, greater than 0, and no greater
 *   than 30 stops") — through [NDNotationFormatter], and takes the
 *   widest rendering for the case's notation. Because the decimal
 *   registrations are in the domain, the formatter's reserved
 *   mixed-fraction branch is in the ranking too, which is where its
 *   widest output actually lives in `Stops`.
 * - [widestCplLoss] does the same over the exposure-loss choices
 *   `FILTER-CPL-002` admits, through [FilterWheelPresenter.decimalStopsValue]
 *   — CPL bypasses the notation setting.
 * - The per-wheel seeding then picks, from the rows the controller
 *   itself reports AVAILABLE, the one whose value is widest. Availability
 *   matters: the 30-stop cap is what bounds the widest SIMULTANEOUS
 *   content, and a GND Record-only row is how four wheels can each
 *   display a 30-stop value while contributing almost nothing.
 *
 * [assertTheWidestContentIsOnScreen] then asserts the seeding
 * actually achieved that, so the fixture cannot quietly degrade back to
 * narrow digits.
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
 * the real screen instead of a width harness. `hasVisualOverflow` covers
 * BOTH axes: the row height follows the rendered metrics
 * (`snapWheelItemHeight`), so a line box taller than its row is a defect
 * here rather than a fact of life.
 */
@RunWith(Parameterized::class)
class FilterStackViewportLegibilityTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    /**
     * How the stack is seeded. Both fill every wheel with the widest row
     * it can legally take; they differ in which rows are eligible.
     */
    enum class Seeding {
        /**
         * The widest available row of any kind. The real worst case: it
         * finds the GND Record-only rows, which display a 30-stop value
         * on every wheel at once because they contribute zero.
         */
        widest,

        /**
         * The widest available row of the type assigned to each wheel,
         * cycling GND / Fixed / CPL / Empty, so Fixed, CPL, GND and
         * Empty are all on screen together where the wheel count allows.
         */
        typeSpread,
    }

    /** One (viewport, locale, font scale, wheel count, notation, seeding). */
    data class Case(
        val viewport: Dp,
        val locale: Locale,
        val fontScale: Float,
        val wheelCount: Int,
        val notation: NDNotationMode,
        val seeding: Seeding,
    ) {
        override fun toString() =
            "${viewport.value.toInt()}dp ${locale.toLanguageTag()} ${fontScale}x ${wheelCount}w " +
                "${notation.name.lowercase()} ${seeding.name}"
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
         * Default, the app's own cap, and the largest system "Font size"
         * step.
         *
         * [MaxCappedFontScale] is the scale the shipping app actually
         * reaches: `ShootingApp` wraps the whole shooting surface in
         * `CappedFontScale`, so however far the system slider is pushed,
         * 1.3x is the largest scale the screen renders at today. This
         * harness composes `ShootingScreen` directly rather than through
         * `ShootingApp`, so it is also the only place the uncapped
         * layout above that is visible at all.
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
        private val Scales = listOf(1.0f, MaxCappedFontScale, 2.0f)

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

        /**
         * Ranks candidate renderings with the platform's default
         * typeface. Only the ORDER is used, and the order of two strings
         * in one typeface does not depend on the size they are drawn at;
         * every assertion below measures the real laid-out text instead.
         */
        private val rankingPaint = Paint().apply { textSize = 100f }

        private fun rank(text: String): Float = rankingPaint.measureText(text)

        /**
         * Every canonical stops value a wheel can legally carry: the
         * shipping ladder (`ND-001`) and the decimal registrations
         * `FILTER-ITEM-004` admits, sampled finely enough to visit every
         * branch of the formatter — whole stop, commercial preset, and
         * the mixed-fraction path a decimal falls into.
         */
        private val legalStops: List<Double> by lazy {
            val cap = ExposureScale.MAXIMUM_WHOLE_ND_STOPS
            val sampled = (1..cap * 100).map { it / 100.0 } + listOf(6.6, 7.6, 16.6)
            sampled.filter { FilterRegisteredValue(it, FilterValueUnit.stops).canonicalStops != null }
        }

        /**
         * The canonical stops value whose rendering is widest in [mode],
         * and that rendering. Derived from the formatter over the whole
         * legal domain — never named here.
         *
         * Digits are tabular, so many renderings tie on width; ties go
         * to the LARGEST stops value, which is also the one that puts
         * the most pressure on the other legality bound, the 30-stop
         * cap.
         */
        private val widestStops: Map<NDNotationMode, Pair<Double, String>> by lazy {
            NDNotationMode.entries.associateWith { mode ->
                legalStops
                    .map { it to NDNotationFormatter.display(it, mode).value }
                    .maxWith(compareBy({ rank(it.second) }, { it.first }))
            }
        }

        /** The same, over the exposure-loss choices `FILTER-CPL-002` admits. */
        private val widestCplLoss: Pair<Double, String> by lazy {
            (1..99).map { it / 10.0 }
                .filter { CplExposureLossChoices.isValidChoice(it) }
                .map { it to FilterWheelPresenter.decimalStopsValue(it) }
                .maxWith(compareBy({ rank(it.second) }, { it.first }))
        }

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = Viewports.flatMap { viewport ->
            listOf(Locale.US, Locale.KOREA).flatMap { locale ->
                Scales.flatMap { scale ->
                    WheelCounts.flatMap { wheels ->
                        NDNotationMode.entries.flatMap { notation ->
                            // One wheel has no second type to spread
                            // onto, so the two seedings coincide there.
                            val seedings =
                                if (wheels == 1) listOf(Seeding.widest) else Seeding.entries
                            seedings.map { seeding ->
                                arrayOf<Any>(Case(viewport, locale, scale, wheels, notation, seeding))
                            }
                        }
                    }
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
        /**
         * The size the wheel last drew its centered value at, and the
         * size it last drew a neighbouring one at.
         *
         * Taken as the wheel reports each row rather than looked up in
         * [rows] afterwards. [rows] is keyed by index and keeps the last
         * layout of each, so a row that was centered before the seeding
         * moved the selection still holds its centered-size layout — and
         * picking "a row that is not the centered one" out of that map
         * reads a stale style, which is what the first version of
         * [assertOneNumericSizeAcrossTheRow] did.
         */
        var centeredSize: TextUnit? = null,
        var neighbouringSize: TextUnit? = null,
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
            val size = layout.layoutInput.style.fontSize
            if (isCenter) entry.centeredSize = size else entry.neighbouringSize = size
            if (hasRail) entry.railedRows += index else entry.railedRows -= index
        }

        override fun onLabel(wheel: String, hasSourceCue: Boolean, layout: TextLayoutResult) {
            val entry = rendered.getOrPut(wheel) { WheelRender() }
            entry.label = layout
            entry.hasSourceCue = hasSourceCue
        }
    }

    private lateinit var controller: CalculatorController

    /**
     * A Filter Set holding, for this case's notation, an item of every
     * behavior kind at its own widest legal value — four GND items, so a
     * four-wheel stack can put the widest value on every wheel at once
     * (three of them Record-only, which is how that stays under the
     * 30-stop cap).
     */
    private fun buildStack(): CalculatorController {
        val (widestValue, _) = widestStops.getValue(case.notation)
        val registered = FilterRegisteredValue(widestValue, FilterValueUnit.stops)
        val items = buildList {
            repeat(4) { add(FilterItem("Lee GND ${it + 1}", FilterItemBehavior.Gnd(registered))) }
            add(FilterItem("Lee ND", FilterItemBehavior.Fixed(registered)))
            add(
                FilterItem(
                    "Lee CPL",
                    FilterItemBehavior.Cpl(
                        CplExposureLossChoices(listOf(widestCplLoss.first, 1.0, 2.0)),
                    ),
                ),
            )
        }
        val lee = FilterSet(SetName, FilterSetColor.blue, items)
        val built = CalculatorController(
            films = emptyList(),
            onStart = { _, _ -> },
            inventoryModel = FilterInventoryModel(
                initial = FilterInventory(listOf(lee)),
                persistenceWriter = PersistenceWriter { it() },
            ),
        )
        built.setNotationMode(case.notation)
        // The widest base-shutter label sits at the head of the ladder,
        // so the column renders it rather than a three-character one.
        built.setShutterIndex(ExposureScale.oneThirdStopShutterCameraLabels.indices.maxBy {
            rank(ExposureScale.oneThirdStopShutterCameraLabels[it])
        })
        repeat(case.wheelCount - 1) { built.addFilterWheel(FilterSource.FilterSet(lee.id)) }
        require(built.state.value.filterWheels.size == case.wheelCount) {
            "expected ${case.wheelCount} wheels, got ${built.state.value.filterWheels.size}"
        }
        return built
    }

    /** The row types [Seeding.typeSpread] cycles across the wheels. */
    private val spreadTypes = listOf(
        FilterRowTypeCategory.gnd,
        FilterRowTypeCategory.nd,
        FilterRowTypeCategory.cpl,
        FilterRowTypeCategory.empty,
    )

    /**
     * Eligible rows for the wheel at [index] under this case's seeding:
     * the available ones, narrowed to the assigned type when that leaves
     * anything (the Standard wheel has only ND rows, so the filter
     * cannot be allowed to empty a wheel).
     */
    private fun eligible(rows: List<FilterWheelRowUiState>, index: Int): List<FilterWheelRowUiState> {
        val available = rows.filter { it.isAvailable }
        if (case.seeding == Seeding.widest) return available
        val assigned = spreadTypes[index % spreadTypes.size]
        return available.filter { it.typeCategory == assigned }.ifEmpty { available }
    }

    /**
     * The widest of [rows]. Ties go to a GND Apply-full-value row, then
     * to any GND row: `GND FULL` is the widest persistent label the
     * stack can produce, so when two rows render the same value the one
     * that also stresses the label wins.
     */
    private fun widest(rows: List<FilterWheelRowUiState>): FilterWheelRowUiState? = rows.maxWithOrNull(
        compareBy(
            { rank(it.compactValueText) },
            { if (it.gndMode == GndCalculationMode.applyFullValue) 2 else 0 },
            { if (it.typeCategory == FilterRowTypeCategory.gnd) 1 else 0 },
        ),
    )

    /** Wheel id to the value the seeding committed on it. */
    private val seeded = linkedMapOf<Int, String>()

    /**
     * Commits the widest eligible row on every wheel.
     *
     * Keyed by wheel ID, not by position: a settled selection can reorder
     * the stack (FILTER-STACK-005), so walking positions seeds one wheel
     * twice and skips another. Re-read between wheels on purpose —
     * committing a contribution changes what the wheels after it may
     * take, and the widest LEGAL content is the widest under that cap.
     */
    private fun seed() {
        // One UI-thread pass: the controller publishes each commit
        // synchronously, so the availability the next wheel sees is
        // already up to date without a recomposition in between.
        composeTestRule.runOnUiThread {
            controller.state.value.filterWheels.map { it.id }.forEachIndexed { index, id ->
                val wheel = controller.state.value.filterWheels.firstOrNull { it.id == id }
                    ?: return@forEachIndexed
                val target = widest(eligible(wheel.rows, index)) ?: return@forEachIndexed
                val rowIndex = wheel.rows.indexOfFirst { it.selection == target.selection }
                if (rowIndex < 0) return@forEachIndexed
                controller.setNdWheelActive(id, true)
                controller.setNdWheelValue(id, rowIndex)
                controller.setNdWheelActive(id, false)
                seeded[id] = target.compactValueText
            }
        }
        composeTestRule.waitForIdle()
    }

    private lateinit var composedDensity: Density
    private lateinit var viewportBounds: Rect

    private fun render() {
        controller = buildStack()
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
        seed()

        val root = composeTestRule.onRoot().fetchSemanticsNode().boundsInRoot
        viewportBounds = Rect(root.left, root.top, root.left + case.viewport.px(), root.bottom)
    }

    /**
     * The wheels the probe reported that are still on screen.
     *
     * A wheel's probe key is its content description, which carries its
     * position and its source name — so seeding a Filter Set row, or a
     * settle reordering the stack, renames wheels and leaves the old
     * keys behind in [rendered]. The semantics tree is the authority on
     * which of them exist now; what each one last laid out is still a
     * true measurement, since the column widths and row heights do not
     * change while the stack is seeded.
     */
    private fun liveWheels(): Map<String, WheelRender> = live ?: run {
        val onScreen = mergedNodes().flatMap { it.descriptions() }.toSet()
        rendered.filterKeys { it in onScreen }
    }.also { live = it }

    private var live: Map<String, WheelRender>? = null

    /**
     * The semantics tree as it stands after [render] has seeded the
     * stack, walked once.
     *
     * Every assertion below names the nodes it is about, and the failure
     * messages quote the whole geometry, so the tree was being fetched
     * and walked dozens of times per case for one unchanging answer —
     * about thirty seconds of a passing case. Nothing here mutates the
     * tree, so one walk is the whole truth.
     */
    private fun mergedNodes(): List<SemanticsNode> = walked ?: buildList {
        fun walk(node: SemanticsNode) {
            add(node)
            node.children.forEach(::walk)
        }
        walk(composeTestRule.onRoot().fetchSemanticsNode())
    }.also { walked = it }

    private var walked: List<SemanticsNode>? = null

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

    /** Width of the single line a wheel row lays out. */
    private fun TextLayoutResult.lineWidth(): Float = getLineRight(0) - getLineLeft(0)

    /** Height of that same line. */
    private fun TextLayoutResult.lineHeight(): Float = getLineBottom(0) - getLineTop(0)

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

    /**
     * Every failure message quotes this, and JUnit builds an assertion
     * message whether or not the assertion fails, so it is built once
     * per case — the state it describes does not change after [render].
     */
    private fun geometry(): String = described ?: buildGeometry().also { described = it }

    private var described: String? = null

    private fun buildGeometry(): String {
        val committed = controller.state.value.filterWheels.joinToString(", ") { wheel ->
            val row = wheel.rows.getOrNull(wheel.committedIndex)
            "${wheel.sourceName}:${row?.typeCategory}${row?.gndMode?.let { "/$it" } ?: ""}=" +
                "`${row?.compactValueText}`"
        }
        val wheels = liveWheels().entries.joinToString(" | ") { (name, render) ->
            val label = render.label
            val rows = render.rows.entries.joinToString(",") { (index, row) ->
                "$index:`${row.layoutInput.text.text}`" +
                    "${row.lineWidth().toInt()}w/${row.size.width}" +
                    "c${row.layoutInput.constraints.maxWidth}" +
                    "h${row.lineHeight().toInt()}/${row.size.height}px" +
                    (if (row.hasVisualOverflow) " OVERFLOW" else "") +
                    (if (index in render.railedRows) "" else " NORAIL")
            }
            "$name label=" +
                (label?.let { "`${it.layoutInput.text.text}`${if (it.hasVisualOverflow) " OVERFLOW" else ""}" }
                    ?: "<none>") +
                " cue=${render.hasSourceCue} rows[$rows]"
        }
        val bounds = mergedNodes()
            .filter { node -> liveWheels().keys.any { it in node.descriptions() } }
            .joinToString(" | ") { node ->
                val b = node.boundsInRoot
                "${node.descriptions().first()} ${b.left.toDp().value.toInt()}.." +
                    "${b.right.toDp().value.toInt()}dp (${b.width.toDp().value.toInt()}dp wide, " +
                    "y ${b.top.toDp().value.toInt()}..${b.bottom.toDp().value.toInt()}dp)"
            }
        return "Viewport ${viewportBounds.width.toDp()}. Widest legal value for " +
            "${case.notation}: `${widestStops.getValue(case.notation).second}`, widest CPL loss " +
            "`${widestCplLoss.second}`. Committed: $committed. Wheels drew: $wheels. " +
            "Wheel boxes: $bounds"
    }

    /**
     * One rendering per case, four groups of assertions against it.
     * They are one test because each case has to drive the real screen
     * and seed four wheels, and four renderings of the same state cost
     * four times as long for nothing — every failure message carries
     * the full geometry, so granularity is not lost.
     */
    @Test
    fun theStackStaysLegibleWithItsWidestContent() {
        render()
        assertTheWidestContentIsOnScreen()
        assertLabelsValuesAndCues()
        assertTheRailHasItsOwnLane()
        assertOneNumericSizeAcrossTheRow()
        assertNotationOptionsOwnFullTouchTargets()
        assertSharedBaseShutterAxis()
    }

    /**
     * FILTER-STACK-007 wants the numeric value AND the type rail legible,
     * and two marks drawn in one place are not. So the rail's leading
     * lane is reserved out of the row and the value is centered in what
     * remains.
     *
     * Asserted on the CONSTRAINT each row was measured with, not on the
     * text that came out of it: a narrow value clears the rail wherever
     * it is drawn, so only the reserved lane says the widest one will
     * too. Found by looking at a rendered capture of the worst content —
     * the rail was painted over the leading digit of `30 2/3`, and every
     * assertion in this suite was green, because a value that fills its
     * row still overflows nothing.
     */
    private fun assertTheRailHasItsOwnLane() {
        val filters = liveWheels().filterKeys { it != baseShutterTitle }
        val rooms = filters.mapValues { (_, render) ->
            render.rows.values.map { it.layoutInput.constraints.maxWidth }.distinct()
        }
        rooms.forEach { (wheel, widths) ->
            assertEquals(
                "$case: `$wheel` measured its rows against ${widths.size} different widths " +
                    "($widths), so they cannot share one numeric column. ${geometry()}",
                1,
                widths.size,
            )
        }
        val room = rooms.values.map { it.single() }.distinct()
        assertEquals(
            "$case: the wheels divide the column evenly, so every one of them should measure its " +
                "value against the same width; they used $room. ${geometry()}",
            1,
            room.size,
        )

        // The Standard wheel carries a rail and no source cue, so its
        // persistent label row IS the whole column, and the difference
        // between the two is the lane exactly. Every other wheel shares
        // that width by the assertion above.
        val standard = filters.entries.firstOrNull { !it.value.hasSourceCue } ?: return
        val label = standard.value.label ?: return
        assertEquals(
            "$case: `${standard.key}` measured its value against ${room.single()}px inside a " +
                "${label.layoutInput.constraints.maxWidth}px column, leaving the type rail no " +
                "lane of its own. The rail is drawn at the row's leading edge, so a value that " +
                "fills the row is painted under it — which a rendered capture of `30 2/3` at four " +
                "wheels showed while every other assertion here was green. ${geometry()}",
            with(composedDensity) { RowRailWidth.roundToPx() },
            label.layoutInput.constraints.maxWidth - room.single(),
        )
    }

    /**
     * FILTER-STACK-007's "Base Shutter and every filter wheel in the row
     * shall use the same numeric size", read off the size each column
     * actually laid its text out at.
     *
     * The centered row and its neighbours are deliberately different
     * sizes WITHIN a column, so they are compared separately: the clause
     * is that the columns agree with each other, not that a column is
     * uniform. Nothing else in this suite would notice them disagreeing
     * — a column that kept its own larger value would still clear its
     * own width, still share the vertical axis, and still ellipsize
     * nothing.
     */
    private fun assertOneNumericSizeAcrossTheRow() {
        val live = liveWheels()
        val sizes = listOf<Pair<String, (WheelRender) -> TextUnit?>>(
            "centered value" to { render -> render.centeredSize },
            "neighbouring value" to { render -> render.neighbouringSize },
        )
        sizes.forEach { (what, pick) ->
            val drawn = live.mapValues { (_, render) -> pick(render) }
            val distinct = drawn.values.filterNotNull().distinct()
            assertTrue(
                "$case: the row's columns drew their $what at ${distinct.size} different sizes — " +
                    drawn.entries.joinToString { "`${it.key}`=${it.value}" } +
                    ". FILTER-STACK-007 wants Base Shutter and every filter wheel in the row to " +
                    "use the same numeric size. ${geometry()}",
                distinct.size == 1,
            )
        }
    }

    /**
     * The fixture's own guard. Every wheel must be resting on the widest
     * row it was allowed to take, and the widest legal rendering for the
     * case's notation must actually be on screen once there is a Filter
     * Set wheel to hold it — otherwise the assertions below are passing
     * on digits that happened to be narrow.
     */
    private fun assertTheWidestContentIsOnScreen() {
        val wheels = controller.state.value.filterWheels
        // Not an equality: seeding a wheel to Empty can make the
        // automatic cleanup remove it (FILTER-STACK-006), which is the
        // contract working. What matters is that every wheel still
        // standing was seeded.
        assertTrue(
            "$case: ${wheels.size - wheels.count { it.id in seeded }} wheel(s) in the stack were " +
                "never seeded. ${geometry()}",
            wheels.all { it.id in seeded },
        )
        wheels.forEach { wheel ->
            val committed = wheel.rows.getOrNull(wheel.committedIndex)
            assertTrue("$case: wheel ${wheel.id} has no committed row. ${geometry()}", committed != null)
            assertEquals(
                "$case: wheel ${wheel.id} was seeded to the widest row it could take but rests " +
                    "on another value. ${geometry()}",
                seeded[wheel.id],
                committed!!.compactValueText,
            )
        }

        if (case.wheelCount > 1 && case.seeding == Seeding.widest) {
            val widestLegal = widestStops.getValue(case.notation).second
            assertTrue(
                "$case: the widest legal rendering `$widestLegal` is on no wheel, so this case " +
                    "does not exercise the widest content. ${geometry()}",
                wheels.any { it.rows.getOrNull(it.committedIndex)?.compactValueText == widestLegal },
            )
        }

        if (case.wheelCount >= 4 && case.seeding == Seeding.typeSpread) {
            val types = wheels.mapNotNull { it.rows.getOrNull(it.committedIndex)?.typeCategory }.toSet()
            assertTrue(
                "$case: four wheels seeded by type spread only reached $types; Fixed, CPL, GND " +
                    "and Empty should all be on screen. ${geometry()}",
                types.size >= 3,
            )
        }
    }

    /**
     * FILTER-STACK-007 for every real wheel, at every viewport, locale,
     * supported text size and notation, with the widest content it can
     * legally hold: the persistent label and the numeric values stay
     * whole in both axes, and the source and type cues stay drawn.
     */
    private fun assertLabelsValuesAndCues() {
        val live = liveWheels()
        val filterWheels = live.keys.filter { it != baseShutterTitle }
        assertEquals(
            "$case: expected every wheel in the stack to report. ${geometry()}",
            controller.state.value.filterWheels.size,
            filterWheels.size,
        )

        // The Base Shutter column's rows are measured too: its values are
        // the widest text in the card and its row height is the one the
        // filter wheels share.
        live.forEach { (wheel, render) ->
            // Both axes, and each named: `hasVisualOverflow` is the
            // authority, and the measured line box beside it says which
            // dimension gave way — the horizontal one is what the widest
            // content above is here to find.
            val clipped = render.rows.filterValues {
                it.hasVisualOverflow || it.lineWidth() > it.size.width + RoundingSlackPx
            }
            assertTrue(
                "$case: ${clipped.size} of `$wheel`'s numeric rows overflow their row: " +
                    clipped.values.joinToString {
                        val wide = it.lineWidth() > it.size.width + RoundingSlackPx
                        val tall = it.lineHeight() > it.size.height + RoundingSlackPx
                        "`${it.layoutInput.text.text}` needs ${it.lineWidth().toInt()}x" +
                            "${it.lineHeight().toInt()}px in ${it.size.width}x${it.size.height}px " +
                            "(" + listOfNotNull(
                            "HORIZONTAL".takeIf { _ -> wide },
                            "VERTICAL".takeIf { _ -> tall },
                        ).ifEmpty { listOf("REPORTED") }.joinToString("+") + ")"
                    } +
                    ". The rows are `maxLines = 1, softWrap = false` with no overflow, so a row " +
                    "a pixel too small cuts the value in silence. ${geometry()}",
                clipped.isEmpty(),
            )
        }

        filterWheels.forEach { wheel ->
            val render = live.getValue(wheel)
            val label = render.label
            assertTrue("$case: `$wheel` never laid its persistent label out. ${geometry()}", label != null)
            assertEquals(
                "$case: `$wheel`'s persistent label wrapped onto ${label!!.lineCount} lines. " +
                    geometry(),
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
     * SHELL-030 in both dimensions, which is the clause the header suite
     * only half-checked, carried across this suite's viewport matrix.
     */
    private fun assertNotationOptionsOwnFullTouchTargets() {
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
                            "overlap, so neither owns the $MinTouchTarget it reports. ${geometry()}",
                        a.overlaps(b).not(),
                    )
                }
            }
        }
    }

    /**
     * FILTER-STACK-007's shared vertical axis, under the same sweep:
     * every filter wheel's viewport top and bottom, and therefore its
     * selected-row band and vertical touch center, stay level with the
     * Base Shutter column's.
     */
    private fun assertSharedBaseShutterAxis() {
        val shutter = mergedNodes()
            .filter { baseShutterTitle in it.descriptions() }
            .also { assertEquals("$case: expected one base-shutter wheel. ${geometry()}", 1, it.size) }
            .single()
            .boundsInRoot

        liveWheels().keys.filter { it != baseShutterTitle }.forEach { wheel ->
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
