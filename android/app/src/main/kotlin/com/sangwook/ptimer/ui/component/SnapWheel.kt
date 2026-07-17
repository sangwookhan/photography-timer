// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlin.math.abs
import kotlin.math.roundToInt

/** Fraction of an overscroll pull that moves the wheel content, so the
 *  removal gesture (PTIMER-199 §4.2.3) gives damped, elastic feedback. */
private const val OverscrollVisualDamping = 0.5f

/**
 * Reusable snap wheel (the Android analogue of the iOS picker wheel; used for
 * base shutter, ND, and target shutter).
 *
 * Hard requirement (PTIMER-64 "continuous result updates while picker is
 * spinning"): the selected index is emitted on EVERY change of the centered
 * item — during the fling/scroll, not only when motion settles — so callers
 * recompute the adjusted shutter / exposure live as the wheel spins.
 *
 * The centered item is the snapped selection; neighbors fade with distance.
 */
@Composable
fun SnapWheel(
    labels: List<String>,
    selectedIndex: Int,
    onSelectedIndexChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    visibleCount: Int = 5,
    itemHeight: Dp = 44.dp,
    edgeColor: Color = MaterialTheme.colorScheme.background,
    accessibilityLabel: String? = null,
    // PTIMER-199 (ND wheel stack) additions; every default keeps the
    // pre-stack call sites (base shutter, target shutter) unchanged.
    /** Smaller text so 3–4 side-by-side stack wheels stay legible. */
    dense: Boolean = false,
    /** Reports true while the wheel is under a finger or scrolling,
     *  false at quiescence — the stack's set-commit signal. */
    onActiveChange: ((Boolean) -> Unit)? = null,
    /** Overscroll-past-zero removal (§4.2.3): pulling the wheel down
     *  past its top (0-stop) end by at least one item height and
     *  releasing invokes [onOverscrollRemoval]. */
    overscrollRemovalEnabled: Boolean = false,
    onOverscrollRemoval: (() -> Unit)? = null,
    extraAccessibilityActions: List<CustomAccessibilityAction> = emptyList(),
) {
    require(visibleCount % 2 == 1) { "visibleCount must be odd so one item sits dead-center" }
    val halfVisible = visibleCount / 2

    val listState = rememberLazyListState(initialFirstVisibleItemIndex = selectedIndex)
    val flingBehavior = rememberSnapFlingBehavior(lazyListState = listState)

    // Index of the item whose center is nearest the viewport center. Reading
    // layoutInfo here makes this recompute every frame while the list is
    // flinging, which is what drives the live emission below.
    val centeredIndex by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            if (info.visibleItemsInfo.isEmpty()) return@derivedStateOf null
            val viewportCenter = (info.viewportStartOffset + info.viewportEndOffset) / 2f
            info.visibleItemsInfo
                .minByOrNull { abs((it.offset + it.size / 2f) - viewportCenter) }
                ?.index
        }
    }

    // The collector is keyed on (listState, labels) and outlives callback
    // changes, so read the latest callback through rememberUpdatedState rather
    // than capturing it once. Otherwise a wheel whose callback identity changes
    // after first composition — e.g. the per-slot write gate flipping from no-op
    // to active when the camera pager settles on that page — would keep invoking
    // the stale callback and silently drop the user's spins.
    val currentOnSelectedIndexChange by rememberUpdatedState(onSelectedIndexChange)
    LaunchedEffect(listState, labels) {
        snapshotFlow { centeredIndex }
            .filterNotNull()
            .distinctUntilChanged()
            .collect { currentOnSelectedIndexChange(it) }
    }

    // PTIMER-199: activity signal. Pressed is tracked from the Final pass
    // without consuming, so a resting finger — which never becomes a
    // scroll — still counts as active and keeps the caller's set commit
    // open until the finger lifts.
    var pressed by remember { mutableStateOf(false) }
    val currentOnActiveChange by rememberUpdatedState(onActiveChange)
    if (onActiveChange != null) {
        LaunchedEffect(listState) {
            snapshotFlow { pressed || listState.isScrollInProgress }
                .distinctUntilChanged()
                .collect { currentOnActiveChange?.invoke(it) }
        }
        // A wheel can leave composition mid-interaction (slot switch,
        // removal): never leave the caller thinking it is still active.
        DisposableEffect(Unit) {
            onDispose { currentOnActiveChange?.invoke(false) }
        }
    }

    // PTIMER-199: overscroll-past-zero removal. Index 0 (the 0-stop row)
    // sits at the top, so a downward drag the list cannot consume is the
    // photographer pulling the wheel past its zero end. The pull is
    // accumulated (damped visually via the offset below) and judged on
    // release; the threshold is one item height.
    var overscrollPx by remember { mutableFloatStateOf(0f) }
    val currentOnOverscrollRemoval by rememberUpdatedState(onOverscrollRemoval)
    val overscrollActive = overscrollRemovalEnabled && onOverscrollRemoval != null
    val removalThresholdPx = with(LocalDensity.current) { itemHeight.toPx() }
    val overscrollConnection = remember(removalThresholdPx) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Unwind an open pull before the list scrolls again.
                if (source == NestedScrollSource.UserInput && available.y < 0f && overscrollPx > 0f) {
                    val consumed = maxOf(available.y, -overscrollPx)
                    overscrollPx += consumed
                    return Offset(0f, consumed)
                }
                return Offset.Zero
            }

            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource,
            ): Offset {
                if (source == NestedScrollSource.UserInput && available.y > 0f) {
                    overscrollPx += available.y
                    return Offset(0f, available.y)
                }
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                val pulled = overscrollPx
                overscrollPx = 0f
                if (pulled >= removalThresholdPx) currentOnOverscrollRemoval?.invoke()
                return Velocity.Zero
            }
        }
    }

    // Re-center when the selection is set from outside the wheel (Quick/Fine
    // parking, slot switch, reset) rather than by the user's own scroll. Skipped
    // while a scroll/fling is in flight so it never fights an active spin, and
    // only when the centered row actually differs from the requested index.
    LaunchedEffect(selectedIndex) {
        if (!listState.isScrollInProgress &&
            centeredIndex != null &&
            centeredIndex != selectedIndex &&
            selectedIndex in labels.indices
        ) {
            listState.scrollToItem(selectedIndex)
        }
    }

    // PTIMER-182: expose the whole wheel as ONE adjustable accessibility
    // control. clearAndSetSemantics removes the LazyColumn/Text row nodes
    // from the accessibility tree, so TalkBack cannot focus an edge row and
    // read a neighboring value; the single wheel node carries the label,
    // the committed value, and adjustable (slider-style) semantics so
    // TalkBack announces the control's role and its own "swipe up or down
    // to adjust" usage hint — one swipe moves exactly one value (iOS
    // adjustable-picker parity). The announced value reads the externally
    // committed selectedIndex — never the transient centeredIndex, which
    // stays visual-only (fade + snap emission). All mutations route through
    // the existing onSelectedIndexChange only (the caller's state change
    // then re-centers the list via the LaunchedEffect above), so snapping,
    // scrolling, and live-emission behavior are untouched.
    val previousActionLabel = stringResource(R.string.wheel_action_previous)
    val nextActionLabel = stringResource(R.string.wheel_action_next)
    val accessibilityModifier = if (accessibilityLabel != null) {
        Modifier.clearAndSetSemantics {
            contentDescription = accessibilityLabel
            labels.getOrNull(selectedIndex)?.let { stateDescription = it }
            // Adjustable role: rangeInfo tells TalkBack this is a seek-style
            // control; setProgress receives the requested target value and
            // is collapsed to a single step in the requested direction so
            // one swipe never jumps several rows. stateDescription above
            // overrides the default percentage announcement.
            progressBarRangeInfo = ProgressBarRangeInfo(
                current = selectedIndex.toFloat(),
                range = 0f..labels.lastIndex.toFloat().coerceAtLeast(0f),
                steps = (labels.size - 2).coerceAtLeast(0),
            )
            setProgress { targetValue ->
                val direction = when {
                    targetValue > selectedIndex -> 1
                    targetValue < selectedIndex -> -1
                    else -> 0
                }
                val target = selectedIndex + direction
                if (direction != 0 && target in labels.indices) {
                    currentOnSelectedIndexChange(target)
                    true
                } else {
                    false
                }
            }
            customActions = listOf(
                CustomAccessibilityAction(previousActionLabel) {
                    val target = selectedIndex - 1
                    if (target in labels.indices) {
                        currentOnSelectedIndexChange(target)
                        true
                    } else {
                        false
                    }
                },
                CustomAccessibilityAction(nextActionLabel) {
                    val target = selectedIndex + 1
                    if (target in labels.indices) {
                        currentOnSelectedIndexChange(target)
                        true
                    } else {
                        false
                    }
                },
            ) + extraAccessibilityActions
        }
    } else {
        Modifier
    }

    // A pull left open when the gate flips (e.g. the wheel's value
    // commits to non-zero mid-gesture) must not strand a visual offset.
    LaunchedEffect(overscrollActive) {
        if (!overscrollActive) overscrollPx = 0f
    }

    val pressTrackingModifier = if (onActiveChange != null) {
        Modifier.pointerInput(Unit) {
            awaitEachGesture {
                awaitFirstDown(requireUnconsumed = false)
                pressed = true
                try {
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Final)
                        if (event.changes.none { it.pressed }) break
                    }
                } finally {
                    pressed = false
                }
            }
        }
    } else {
        Modifier
    }

    Box(
        modifier = modifier
            .height(itemHeight * visibleCount)
            .then(accessibilityModifier)
            .then(pressTrackingModifier)
            .then(if (overscrollActive) Modifier.nestedScroll(overscrollConnection) else Modifier),
    ) {
        LazyColumn(
            state = listState,
            flingBehavior = flingBehavior,
            horizontalAlignment = Alignment.CenterHorizontally,
            contentPadding = PaddingValues(vertical = itemHeight * halfVisible),
            modifier = Modifier
                .fillMaxSize()
                // Damped live push-out while the wheel is pulled past zero.
                .offset { IntOffset(0, (overscrollPx * OverscrollVisualDamping).roundToInt()) },
        ) {
            itemsIndexed(labels) { index, label ->
                val distance = abs((centeredIndex ?: selectedIndex) - index)
                val isCenter = distance == 0
                val alpha = (1f - 0.26f * distance).coerceAtLeast(0.18f)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(itemHeight),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = label,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        softWrap = false,
                        style = when {
                            isCenter && dense -> MaterialTheme.typography.bodyMedium
                            isCenter -> MaterialTheme.typography.titleMedium
                            dense -> MaterialTheme.typography.bodySmall
                            else -> MaterialTheme.typography.bodyLarge
                        },
                        color = LocalContentColor.current.copy(alpha = alpha),
                    )
                }
            }
        }

        // Dim the off-center rows into the container colour and leave the
        // center cell clear, so the centered value stays legible on any
        // background instead of relying on a low-contrast highlight band.
        // Background-only overlay — it is not hit-testable, so it never
        // intercepts the wheel's scroll/fling gestures.
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        0f to edgeColor,
                        0.38f to Color.Transparent,
                        0.62f to Color.Transparent,
                        1f to edgeColor,
                    ),
                ),
        )

        // Hairline bounds of the selection cell (iOS-style; no fill).
        val boundColor = LocalContentColor.current.copy(alpha = 0.18f)
        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .height(itemHeight),
        ) {
            HorizontalDivider(modifier = Modifier.align(Alignment.TopCenter), color = boundColor)
            HorizontalDivider(modifier = Modifier.align(Alignment.BottomCenter), color = boundColor)
        }
    }
}
