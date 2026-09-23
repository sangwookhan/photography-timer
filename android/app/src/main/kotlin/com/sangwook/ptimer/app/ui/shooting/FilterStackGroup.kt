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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.rememberTouchExplorationEnabled
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.FilterRowTypeCategory
import com.sangwook.ptimer.app.vm.FilterSourceUiOption
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionPresenter
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentDirection
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
import com.sangwook.ptimer.app.vm.FilterWheelRowUiState
import com.sangwook.ptimer.app.vm.FilterWheelUiState
import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.ui.theme.FilterTypePalette
import com.sangwook.ptimer.ui.theme.filterSetColor
import com.sangwook.ptimer.ui.theme.filterTypePalette

/** Gap between stacked wheels (tighter than the card's 8dp rhythm so
 *  four wheels keep usable value width). */
private val WheelSpacing = 4.dp

private val WheelItemHeight = 34.dp
private const val WheelVisibleCount = 3

/**
 * Height of the persistent type/mode label above every wheel viewport
 * (FILTER-STACK-007). The Base Shutter column reserves the same height
 * so both pickers' viewports and selection bands share one vertical
 * axis.
 */
internal val FilterWheelLabelRowHeight = 18.dp

/**
 * The mixed Filter Stack wheel row (FILTER-STACK): 1–4 side-by-side
 * wheels keyed by wheel identity (a settled reorder animates each stable
 * identity directly to its new position, FILTER-STACK-005), each with
 * its persistent type/mode label, source cue, and per-row type-color
 * rail; the Plus control on the trailing edge; and the one-row status
 * region underneath.
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
    onFilterAddUnavailability: (FilterSource) -> FilterAddUnavailability?,
    onManageFilterSets: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val wheels = state.filterWheels
    val palette = filterTypePalette()
    val totalText = filterTotalText(
        state.filterStatus.totalStopsText,
        state.filterStatus.totalIsMaximum,
    )

    // The Plus browsing candidate is pure presentation: it exists only
    // between touch-down and release and never reaches the controller.
    var browsing by remember { mutableStateOf<FilterSourceUiOption?>(null) }

    AnnounceEmptyWheelRemoval(state)

    Column(modifier = modifier.fillMaxWidth()) {
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val plusSlot = if (state.plus.isVisible) FilterPlusControlWidth + WheelSpacing else 0.dp
            val wheelWidth = (maxWidth - plusSlot - WheelSpacing * (wheels.size - 1)) / wheels.size

            LazyRow(
                userScrollEnabled = false,
                horizontalArrangement = Arrangement.spacedBy(WheelSpacing),
                modifier = Modifier.fillMaxWidth(),
            ) {
                itemsIndexed(wheels, key = { _, wheel -> wheel.id }) { index, wheel ->
                    FilterWheelColumn(
                        wheel = wheel,
                        position = index + 1,
                        wheelCount = wheels.size,
                        palette = palette,
                        dense = wheels.size >= 3,
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
                                height = WheelItemHeight * WheelVisibleCount,
                                onAdd = onAddFilterWheel,
                                onManage = onManageFilterSets,
                                onBrowsingChanged = { browsing = it },
                                onAddUnavailability = onFilterAddUnavailability,
                            )
                        }
                    }
                }
            }
        }

        FilterStatusRegion(
            content = FilterStatusRegionPresenter.content(
                moving = state.filterStatus.movingRow?.let { row ->
                    FilterStatusLeading.MovingRow(
                        row = row,
                        sourceName = wheels
                            .firstOrNull { it.id == state.filterStatus.movingWheelId }
                            ?.sourceName
                            .orEmpty(),
                    )
                },
                browsing = browsing?.let { FilterStatusLeading.BrowsingSource(it.name, it.color) },
                rejection = state.filterStatus.rejection,
                totalText = totalText,
                idleSourceSummary = state.filterStatus.idleSourceSummary,
                // A Standard-only stack keeps the existing ND behavior:
                // the total appears on change from two wheels up.
                isStandardTotalVisible = state.ndTotalStopsText != null,
            ),
            wheelCount = wheels.size,
            notationMode = state.ndNotationMode,
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

    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        FilterWheelLabelRow(
            label = displayed?.let { filterTypeLabelText(it) }.orEmpty(),
            cueColor = wheel.sourceColor?.let { filterSetColor(it) },
        )
        SnapWheel(
            labels = wheel.rows.map { it.compactValueText },
            selectedIndex = wheel.selectedIndex,
            onSelectedIndexChange = onSelectedIndexChange,
            modifier = Modifier.fillMaxWidth(),
            visibleCount = WheelVisibleCount,
            itemHeight = WheelItemHeight,
            accessibilityLabel = stringResource(
                R.string.filter_wheel_cd,
                position,
                wheelCount,
                localizedSourceName(wheel.sourceName),
            ),
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
 */
@Composable
private fun FilterWheelLabelRow(label: String, cueColor: Color?) {
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
            maxLines = 1,
        )
    }
}

/**
 * FILTER-STACK-006 / ND-A11Y-002: an automatic cleanup that ACTUALLY
 * removed wheels is announced exactly once while a screen reader is
 * active. A removal already recorded when this row first composes is not
 * re-announced.
 */
@Composable
private fun AnnounceEmptyWheelRemoval(state: CalculatorUiState) {
    val removal = state.emptyWheelRemoval
    val view = LocalView.current
    val touchExplorationEnabled = rememberTouchExplorationEnabled()
    val text = removal?.let {
        if (it.removedCount <= 1) {
            stringResource(R.string.filter_empty_wheel_removed)
        } else {
            stringResource(R.string.filter_empty_wheels_removed, it.removedCount)
        }
    }
    var lastAnnounced by remember { mutableStateOf(removal?.sequence) }
    LaunchedEffect(removal?.sequence) {
        val sequence = removal?.sequence
        if (sequence != null && sequence != lastAnnounced && touchExplorationEnabled && text != null) {
            view.announceForAccessibility(text)
        }
        lastAnnounced = sequence
    }
}

/** The row's fixed type-color rail (FILTER-STACK-007). */
private fun FilterRowTypeCategory.railColor(palette: FilterTypePalette): Color = when (this) {
    FilterRowTypeCategory.nd -> palette.nd
    FilterRowTypeCategory.cpl -> palette.cpl
    FilterRowTypeCategory.gnd -> palette.gnd
    FilterRowTypeCategory.empty -> palette.empty
}
