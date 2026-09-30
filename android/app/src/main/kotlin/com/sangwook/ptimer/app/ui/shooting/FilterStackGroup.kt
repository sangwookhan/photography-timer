// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.FilterPlusChoice
import com.sangwook.ptimer.app.vm.FilterRowTypeCategory
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionPresenter
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentDirection
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
import com.sangwook.ptimer.app.vm.FilterWheelRowUiState
import com.sangwook.ptimer.app.vm.FilterWheelUiState
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.ui.component.LocalWheelRenderProbe
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.ui.component.snapWheelItemHeight
import com.sangwook.ptimer.ui.theme.FilterTypePalette
import com.sangwook.ptimer.ui.theme.filterSetColor
import com.sangwook.ptimer.ui.theme.filterTypePalette
import kotlinx.coroutines.delay

/** Gap between stacked wheels (tighter than the card's 8dp rhythm so
 *  four wheels keep usable value width). */
internal val FilterWheelRowSpacing = 4.dp

/**
 * MINIMUM row height of every wheel in the card, the Base Shutter
 * column included (`snapWheelItemHeight` grows it with the font scale,
 * identically for both columns, so the shared axis holds).
 */
internal val WheelItemHeight = 34.dp
private const val WheelVisibleCount = 3

/** How long a refused change or addition holds the status region. */
private const val RejectionNoticeMillis = 2_500L

/**
 * Height of the persistent type/mode label above every wheel viewport
 * (FILTER-STACK-007). The Base Shutter column reserves the same height
 * so both pickers' viewports and selection bands share one vertical
 * axis.
 */
internal val FilterWheelLabelRowHeight = 18.dp

/**
 * Floor for the persistent label's shrink-to-fit (FILTER-STACK-007). The
 * narrowest supported column — four actual wheels, Plus hidden — has to
 * hold `GND FULL` next to its source cue; the reference `labelSmall` size
 * is the ceiling and this is how far it may step down to get there.
 */
private val FilterWheelLabelMinFontSize = 7.sp
private val FilterWheelLabelFontStep = 0.25.sp

/**
 * The width one wheel column gets when [wheelCount] wheels — and the
 * Plus control, when [plusVisible] — divide [available].
 *
 * The card resolves the row's one shared numeric size before either
 * column renders (FILTER-STACK-007), and that needs this width one
 * composable above the row that lays it out. So the arithmetic lives
 * here once rather than in two places that have to keep agreeing.
 */
internal fun filterWheelWidth(available: Dp, wheelCount: Int, plusVisible: Boolean): Dp {
    val plusSlot = if (plusVisible) FilterPlusControlWidth + FilterWheelRowSpacing else 0.dp
    return (available - plusSlot - FilterWheelRowSpacing * (wheelCount - 1)) / wheelCount
}

/** Three wheels or more render their values a style step smaller. */
internal fun isDenseFilterWheelRow(wheelCount: Int) = wheelCount >= 3

/**
 * The mixed Filter Stack wheel row (FILTER-STACK): 1–4 side-by-side
 * wheels keyed by wheel identity (a settled reorder animates each stable
 * identity directly to its new position, FILTER-STACK-005), each with
 * its persistent type/mode label, source cue, and per-row type-color
 * rail; the Plus control on the trailing edge; and the one-row status
 * region underneath.
 *
 * FILTER-STACK-008 wants that status row aligned to the mixed-stack
 * card's own content insets, not to the filter sub-column — so the
 * wheels go through the [wheelRow] slot, which the card uses to place
 * them beside Base Shutter, while this composable keeps the status
 * region directly underneath at the full content width. Inverting the
 * slot rather than hoisting the region keeps [browsing] — the only
 * state the presenter needs that the controller does not own — here
 * instead of pushing it into the screen.
 *
 * All stack STATE stays out of this layer — it renders, and times only
 * its own presentation (the status region's linger and fade) and the
 * transient Plus browsing candidate, which never leaves the view.
 */
@Composable
internal fun FilterStackGroup(
    state: CalculatorUiState,
    onWheelActive: (Int, Boolean) -> Unit,
    onWheelValue: (Int, Int) -> Unit,
    onAddFilterWheel: (FilterSource) -> Unit,
    onAdjustFilterWheel: (Int, FilterWheelAdjustmentDirection) -> FilterWheelAdjustmentOutcome,
    onOverscrollRemove: (Int) -> Unit,
    onManageFilterSets: () -> Unit,
    onOpenShootingFilters: () -> Unit,
    modifier: Modifier = Modifier,
    wheelRow: @Composable (wheels: @Composable () -> Unit) -> Unit = { it() },
) {
    val wheels = state.filterWheels
    val palette = filterTypePalette()
    val totalText = filterTotalText(
        state.filterStatus.totalStopsText,
        state.filterStatus.totalIsMaximum,
    )

    // The Plus browsing candidate is pure presentation: it exists only
    // between touch-down and release and never reaches the controller.
    var browsing by remember { mutableStateOf<FilterPlusChoice?>(null) }
    val auxiliaryTitle = stringResource(R.string.filter_auxiliary_title)

    // A refusal holds the status region for a fixed time and then yields
    // (FILTER-STACK-004). The controller keeps it only as "the current
    // refusal" until its context changes; the timing lives here.
    val rejection = state.filterStatus.rejection
    var expiredRejection by rememberSaveable { mutableStateOf<Int?>(null) }
    LaunchedEffect(rejection?.sequence) {
        if (rejection != null) {
            delay(RejectionNoticeMillis)
            expiredRejection = rejection.sequence
        }
    }
    val shownRejection = rejection?.takeIf { it.sequence != expiredRejection }

    Column(modifier = modifier.fillMaxWidth()) {
        wheelRow {
            BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                val spaces = state.occupiedFilterSpaces
                val wheelWidth = filterWheelWidth(maxWidth, spaces, state.plus.isVisible)
                val viewportHeight = snapWheelItemHeight(WheelItemHeight) * WheelVisibleCount

                LazyRow(
                    userScrollEnabled = false,
                    horizontalArrangement = Arrangement.spacedBy(FilterWheelRowSpacing),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    // The auxiliary summary stays immediately after Base
                    // Shutter (FILTER-AUX-001, FILTER-STACK-005).
                    state.auxiliarySummary?.let { summary ->
                        item(key = "auxiliary-summary") {
                            AuxiliaryFilterSummaryColumn(
                                summary = summary,
                                viewportHeight = viewportHeight,
                                enabled = true,
                                onOpen = onOpenShootingFilters,
                                modifier = Modifier.width(wheelWidth).animateItem(),
                            )
                        }
                    }
                    itemsIndexed(wheels, key = { _, wheel -> wheel.id }) { index, wheel ->
                        FilterWheelColumn(
                            wheel = wheel,
                            position = index + 1,
                            wheelCount = wheels.size,
                            palette = palette,
                            dense = isDenseFilterWheelRow(spaces),
                            totalText = totalText,
                            onActiveChange = { onWheelActive(wheel.id, it) },
                            onSelectedIndexChange = { onWheelValue(wheel.id, it) },
                            onOverscrollRemove = { onOverscrollRemove(wheel.id) },
                            onAdjust = { direction -> onAdjustFilterWheel(wheel.id, direction) },
                            modifier = Modifier.width(wheelWidth).animateItem(),
                        )
                    }
                    if (state.plus.isVisible) {
                        item(key = "filter-plus") {
                            Column(modifier = Modifier.animateItem()) {
                                Spacer(Modifier.height(FilterWheelLabelRowHeight))
                                FilterSourcePlusControl(
                                    plus = state.plus,
                                    // Through the same resolver as the wheels,
                                    // so a raised font scale does not leave the
                                    // Plus control short of the viewport.
                                    height = viewportHeight,
                                    onAdd = onAddFilterWheel,
                                    onManage = onManageFilterSets,
                                    onOpenAuxiliaryFilters = onOpenShootingFilters,
                                    browsing = browsing,
                                    onBrowsingChanged = { browsing = it },
                                )
                            }
                        }
                    }
                }
            }
        }

        FilterStatusRegion(
            content = FilterStatusRegionPresenter.content(
                moving = state.movingFilterWheel?.let { wheel ->
                    wheel.rows.getOrNull(wheel.selectedIndex)?.let { row ->
                        FilterStatusLeading.MovingRow(row = row, sourceName = wheel.sourceName)
                    }
                },
                browsing = when (val choice = browsing) {
                    is FilterPlusChoice.Source -> FilterStatusLeading.BrowsingSource(choice.option.name, choice.option.color)
                    FilterPlusChoice.AuxiliaryFilters -> FilterStatusLeading.BrowsingSource(auxiliaryTitle, null)
                    null -> null
                },
                rejection = shownRejection,
                totalText = totalText,
                idleSourceSummary = state.filterStatus.idleSourceSummary,
                // A Standard-only stack keeps the existing ND behavior:
                // the total appears on change from two wheels up.
                isStandardTotalVisible = state.ndTotalStopsText != null,
            ),
            wheelCount = wheels.size,
            notationMode = state.ndNotationMode,
            totalValueText = state.filterStatus.totalStopsText,
            // The centered ND value style of the same row (SnapWheel).
            totalValueStyle = if (isDenseFilterWheelRow(state.occupiedFilterSpaces)) {
                MaterialTheme.typography.bodyMedium
            } else {
                MaterialTheme.typography.titleMedium
            },
        )
    }
}

/**
 * One wheel column: the persistent type/mode label with its Filter Set
 * source cue above the viewport, and the wheel itself as one adjustable
 * accessibility element (FILTER-A11Y-001/005).
 */
@Composable
private fun FilterWheelColumn(
    wheel: FilterWheelUiState,
    position: Int,
    wheelCount: Int,
    palette: FilterTypePalette,
    dense: Boolean,
    totalText: String,
    onActiveChange: (Boolean) -> Unit,
    onSelectedIndexChange: (Int) -> Unit,
    onOverscrollRemove: () -> Unit,
    onAdjust: (FilterWheelAdjustmentDirection) -> FilterWheelAdjustmentOutcome,
    modifier: Modifier = Modifier,
) {
    val displayed = wheel.rows.getOrNull(wheel.selectedIndex)
    val committed = wheel.rows.getOrNull(wheel.committedIndex)
    val view = LocalView.current
    val rejectionTexts = filterRejectionTexts()
    val boundaryText = stringResource(R.string.filter_boundary)

    // A Filter Set wheel scans its rows for the next AVAILABLE one and
    // announces a refusal or a boundary itself (FILTER-A11Y-004/005); a
    // Standard wheel keeps the plain one-row step.
    val onAccessibilityAdjust: ((Boolean) -> Boolean)? =
        if (wheel.source !is FilterSource.FilterSet) {
            null
        } else {
            { forward ->
                val direction = if (forward) {
                    FilterWheelAdjustmentDirection.increment
                } else {
                    FilterWheelAdjustmentDirection.decrement
                }
                when (val outcome = onAdjust(direction)) {
                    // The committed value updates; the changed
                    // accessibility value is the announcement.
                    is FilterWheelAdjustmentOutcome.Selection -> true

                    is FilterWheelAdjustmentOutcome.Unavailable -> {
                        view.announceForAccessibility(rejectionTexts[outcome.rejection])
                        false
                    }

                    FilterWheelAdjustmentOutcome.Boundary -> {
                        view.announceForAccessibility(boundaryText)
                        false
                    }
                }
            }
        }

    // Also the wheel's key in the render probe, so a suite can match a
    // label report to the numeric rows under it.
    val wheelDescription = stringResource(
        R.string.filter_wheel_cd,
        position,
        wheelCount,
        localizedSourceName(wheel.sourceName),
    )
    val cueColor = wheel.sourceColor?.let { filterSetColor(it) }
    val renderProbe = LocalWheelRenderProbe.current

    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        FilterWheelLabelRow(
            label = displayed?.let { filterTypeLabelText(it) }.orEmpty(),
            cueColor = cueColor,
            onLabelTextLayout = { renderProbe?.onLabel(wheelDescription, cueColor != null, it) },
        )
        SnapWheel(
            labels = wheel.rows.map { it.compactValueText },
            selectedIndex = wheel.selectedIndex,
            onSelectedIndexChange = onSelectedIndexChange,
            modifier = Modifier.fillMaxWidth(),
            visibleCount = WheelVisibleCount,
            itemHeight = WheelItemHeight,
            accessibilityLabel = wheelDescription,
            dense = dense,
            onActiveChange = onActiveChange,
            // Visual gate only — the controller re-validates the removal
            // (cleanable committed row, last-wheel rule, quiet others).
            overscrollRemovalEnabled = displayed?.isCleanable == true && wheelCount > 1,
            onOverscrollRemoval = onOverscrollRemove,
            rowRailColor = { index -> wheel.rows.getOrNull(index)?.typeCategory?.railColor(palette) },
            rowEnabled = { index -> wheel.rows.getOrNull(index)?.isAvailable ?: true },
            onAccessibilityAdjust = onAccessibilityAdjust,
            accessibilityValue = committed?.let { filterRowAccessibilityValue(it, totalText) },
        )
    }
}

/**
 * The persistent type/mode label for the candidate at the touch center,
 * with the Filter Set's source cue leading it. Excluded from the
 * accessibility tree: the wheel is one element and its dynamic value
 * already carries the type and mode (FILTER-A11Y-001).
 *
 * FILTER-STACK-007 requires the label — cue included — to stay legible
 * "without ellipsis at the default and every supported standard text
 * size", for every allowed composition up to four actual wheels. The
 * widest label, `GND FULL`, does not fit the reference size once the
 * column narrows, so two things keep it whole:
 *
 * - Its height is fixed ([FilterWheelLabelRowHeight] is shared with
 *   the Base Shutter column's spacer and anchors the wheels' vertical
 *   axis, FILTER-STACK-007). The shooting screen is laid out at 1x, so
 *   the label does not grow with the system font scale.
 * - Within that fixed budget the text shrinks to fit the column instead
 *   of truncating. Ellipsis stays as the floor's last resort only, so a
 *   truncation could never again be silent.
 *
 * [onLabelTextLayout] is a measurement hook: the label is deliberately
 * outside the semantics tree, so the regression test reads its layout
 * (complete text, one line, no visual overflow) from here.
 */
@Composable
internal fun FilterWheelLabelRow(
    label: String,
    cueColor: Color?,
    onLabelTextLayout: (TextLayoutResult) -> Unit = {},
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(FilterWheelLabelRowHeight)
            .clearAndSetSemantics { },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (cueColor != null) {
            SourceCue(cueColor)
            Spacer(Modifier.width(3.dp))
        }
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            autoSize = TextAutoSize.StepBased(
                minFontSize = FilterWheelLabelMinFontSize,
                maxFontSize = MaterialTheme.typography.labelSmall.fontSize,
                stepSize = FilterWheelLabelFontStep,
            ),
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = onLabelTextLayout,
        )
    }
}

/** The row's fixed type-color rail (FILTER-STACK-007). */
private fun FilterRowTypeCategory.railColor(palette: FilterTypePalette): Color = when (this) {
    FilterRowTypeCategory.nd -> palette.nd
    FilterRowTypeCategory.cpl -> palette.cpl
    FilterRowTypeCategory.gnd -> palette.gnd
    FilterRowTypeCategory.empty -> palette.empty
}
