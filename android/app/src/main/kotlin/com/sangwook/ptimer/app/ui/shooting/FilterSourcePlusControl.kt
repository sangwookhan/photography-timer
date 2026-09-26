// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.FilterPlusUiState
import com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiter
import com.sangwook.ptimer.app.vm.FilterSourceUiOption
import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.ui.theme.filterSetColor
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Slim trailing-edge Plus control width (iOS uses a 26 pt ghost column). */
internal val FilterPlusControlWidth = 26.dp

/**
 * The Plus wheel (FILTER-PLUS): the trailing-edge control of the wheel
 * row while fewer than four actual wheels exist. It is NOT an actual
 * filter wheel — it selects the Filter Source the next wheel is created
 * from:
 *
 * - a tap adds a Standard 0 or Filter Set Empty wheel for the displayed
 *   source, exactly once (FILTER-PLUS-003);
 * - a vertical drag browses Standard / Filter Sets in selection order,
 *   reporting the candidate so the status region can show it; releasing
 *   on a different source adds exactly one wheel from that final source,
 *   while a return to the starting source adds nothing;
 * - a stationary long press opens Filter Set management; movement past
 *   the stationary tolerance cancels it, and once the drag threshold is
 *   crossed browsing has won for the rest of the touch (FILTER-PLUS-001).
 *
 * At rest the compact control shows the candidate source's color as a
 * secondary cue. TalkBack sees ONE focusable element (FILTER-A11Y-001,
 * FILTER-PLUS-004): its adjustable value steps a transient displayed
 * candidate through the sources without adding or touching the camera's
 * remembered source, Manage Filter Sets is always a named action, and
 * Add — activation and the named action — exists only while the
 * DISPLAYED source can add right now; otherwise the state description
 * carries the reason and the element stays adjustable so the user can
 * browse away.
 */
@Composable
internal fun FilterSourcePlusControl(
    plus: FilterPlusUiState,
    height: Dp,
    onAdd: (FilterSource) -> Unit,
    onManage: () -> Unit,
    onBrowsingChanged: (FilterSourceUiOption?) -> Unit,
    onAddUnavailability: (FilterSource) -> FilterAddUnavailability?,
    modifier: Modifier = Modifier,
) {
    val sources = plus.sources
    val settledIndex = plus.selectedIndex.coerceIn(0, (sources.size - 1).coerceAtLeast(0))

    // The source an assistive increment / decrement is browsing —
    // displayed and announced, never persisted. Cleared when the
    // camera's settled source changes (a successful add) so the element
    // follows the remembered source again.
    var assistiveCandidate by remember { mutableStateOf<FilterSourceUiOption?>(null) }
    LaunchedEffect(settledIndex, sources) { assistiveCandidate = null }

    // The source a touch is currently browsing; drives the tint only.
    var browsingIndex by remember { mutableStateOf<Int?>(null) }

    val displayed = assistiveCandidate ?: sources.getOrNull(settledIndex)
    val candidate = browsingIndex?.let { sources.getOrNull(it) } ?: displayed
    val unavailability = if (assistiveCandidate == null) {
        plus.addUnavailability
    } else {
        displayed?.source?.let { onAddUnavailability(it) }
    }
    val isAddEnabled = if (assistiveCandidate == null) plus.canAdd else unavailability == null

    val tint = candidate?.color?.let { filterSetColor(it) } ?: MaterialTheme.colorScheme.onSurfaceVariant
    val isBrowsing = browsingIndex != null

    val addLabel = stringResource(R.string.nd_add_filter)
    val manageLabel = stringResource(R.string.filter_manage_sets)
    val displayedName = displayed?.name?.let { localizedSourceName(it) }.orEmpty()
    val unavailabilityText = unavailability?.let { filterAddUnavailabilityText(it) }

    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val currentOnAdd by rememberUpdatedState(onAdd)
    val currentOnManage by rememberUpdatedState(onManage)
    val currentOnBrowsingChanged by rememberUpdatedState(onBrowsingChanged)

    Box(
        modifier = modifier
            .width(FilterPlusControlWidth)
            .height(height)
            .clip(RoundedCornerShape(10.dp))
            .background(tint.copy(alpha = if (isBrowsing) 0.22f else 0.12f))
            .border(1.5.dp, tint.copy(alpha = if (isBrowsing) 0.9f else 0.55f), RoundedCornerShape(10.dp))
            // One gesture decides tap / long press / browse from the
            // touch's travel and duration, so the three never compete.
            .pointerInput(sources, settledIndex) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val arbiter = FilterSourcePlusGestureArbiter(settledIndex, sources.size)
                    var longPress: Job? = scope.launch {
                        delay(FilterSourcePlusGestureArbiter.LONG_PRESS_MILLIS)
                        if (arbiter.deadlineElapsed()) currentOnManage()
                    }
                    try {
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) {
                                change.consume()
                                break
                            }
                            val dx = (change.position.x - down.position.x).toDp().value
                            val dy = (change.position.y - down.position.y).toDp().value
                            val moved = arbiter.moved(dx, dy)
                            if (arbiter.phase != FilterSourcePlusGestureArbiter.Phase.pressing) {
                                longPress?.cancel()
                                longPress = null
                            }
                            if (moved) {
                                browsingIndex = arbiter.candidateIndex
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                currentOnBrowsingChanged(arbiter.candidateIndex?.let { sources.getOrNull(it) })
                            }
                            change.consume()
                        }
                    } finally {
                        longPress?.cancel()
                    }
                    val outcome = arbiter.released()
                    browsingIndex = null
                    currentOnBrowsingChanged(null)
                    when (outcome) {
                        // The controller refuses and reports when the
                        // source cannot add, so the view never gates it.
                        is FilterSourcePlusGestureArbiter.ReleaseOutcome.AddBrowsed ->
                            sources.getOrNull(outcome.index)?.let { currentOnAdd(it.source) }

                        FilterSourcePlusGestureArbiter.ReleaseOutcome.Add ->
                            displayed?.let { currentOnAdd(it.source) }

                        FilterSourcePlusGestureArbiter.ReleaseOutcome.Managed,
                        FilterSourcePlusGestureArbiter.ReleaseOutcome.None,
                        -> Unit
                    }
                }
            }
            .clearAndSetSemantics {
                contentDescription = addLabel
                stateDescription = unavailabilityText
                    ?.let { "$displayedName, $it" }
                    ?: displayedName
                // Adjustable: stepping browses a transient displayed
                // candidate; nothing is added and the camera's remembered
                // source does not change until an add succeeds.
                progressBarRangeInfo = ProgressBarRangeInfo(
                    current = sources.indexOf(displayed).coerceAtLeast(0).toFloat(),
                    range = 0f..(sources.size - 1).coerceAtLeast(0).toFloat(),
                    steps = (sources.size - 2).coerceAtLeast(0),
                )
                setProgress { target ->
                    val current = sources.indexOf(displayed).coerceAtLeast(0)
                    val next = when {
                        target > current -> current + 1
                        target < current -> current - 1
                        else -> return@setProgress false
                    }
                    val option = sources.getOrNull(next) ?: return@setProgress false
                    assistiveCandidate = option
                    true
                }
                onClick(addLabel) {
                    val source = displayed?.source
                    if (!isAddEnabled || source == null) {
                        false
                    } else {
                        onAdd(source)
                        true
                    }
                }
                customActions = buildList {
                    if (isAddEnabled && displayed != null) {
                        add(CustomAccessibilityAction(addLabel) { onAdd(displayed.source); true })
                    }
                    add(CustomAccessibilityAction(manageLabel) { onManage(); true })
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            ChevronGlyph(Icons.Filled.KeyboardArrowUp, tint)
            Icon(
                Icons.Filled.Add,
                contentDescription = null,
                tint = if (plus.canAdd) tint else tint.copy(alpha = 0.35f),
                modifier = Modifier.size(14.dp),
            )
            ChevronGlyph(Icons.Filled.KeyboardArrowDown, tint)
        }
    }
}

@Composable
private fun ChevronGlyph(icon: ImageVector, tint: Color) {
    Icon(
        icon,
        contentDescription = null,
        tint = tint.copy(alpha = 0.7f),
        modifier = Modifier.size(10.dp),
    )
}
