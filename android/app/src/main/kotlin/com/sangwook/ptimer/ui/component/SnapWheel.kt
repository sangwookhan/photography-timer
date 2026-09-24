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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.runtime.staticCompositionLocalOf
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
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.filterNotNull
import kotlin.math.abs
import kotlin.math.roundToInt

/** Fraction of an overscroll pull that moves the wheel content, so the
 *  removal gesture (PTIMER-199 §4.2.3) gives damped, elastic feedback. */
private const val OverscrollVisualDamping = 0.5f

/** Width of the per-row type-color rail (FILTER-STACK-007). */
private val RowRailWidth = 3.dp

/** Share of the row height the rail spans, so it reads as a mark on the
 *  row rather than a divider between rows. */
private const val RowRailHeightFraction = 0.6f

/** Extra fade of a row the wheel cannot currently select. */
private const val UnavailableRowAlpha = 0.35f

/**
 * A wheel's scroll must never leak into outer surfaces. When a fling
 * runs past the ladder's end (most easily from a 0-stop wheel, whose
 * top end is one row away), the unconsumed deltas and the leftover
 * fling velocity would otherwise propagate up the nested-scroll chain
 * into ancestors — the camera pager among them, which could visibly
 * move pages seconds after the wheel gesture. This outermost
 * connection swallows everything the wheel (and the stack's own
 * overscroll accounting, which sits inside it) leaves unconsumed.
 */
private object WheelNestedScrollFence : NestedScrollConnection {
    override fun onPostScroll(
        consumed: Offset,
        available: Offset,
        source: NestedScrollSource,
    ): Offset = available

    override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity =
        available
}

/**
 * Measurement hook for the layout regression suites (PTIMER-221).
 *
 * A wheel's numeric rows, its persistent type/mode label, its Filter Set
 * source cue and its per-row type-color rail are all deliberately outside
 * the semantics tree — the wheel is one accessibility element
 * (FILTER-A11Y-001), and the label row clears its own semantics — so no
 * semantics assertion can see a row clipped in silence or a cue that
 * stopped being drawn. FILTER-STACK-007 asks for exactly those things to
 * stay legible at every supported text size, so the suites read the
 * laid-out text and the drawn cues from here instead of asserting
 * something weaker.
 *
 * `null` in production: nothing reads the probe unless a test provides one.
 */
internal interface WheelRenderProbe {
    /** One numeric row of the wheel named [wheel], as it was laid out. */
    fun onRow(wheel: String, index: Int, isCenter: Boolean, hasRail: Boolean, layout: TextLayoutResult)

    /** The persistent type/mode label above [wheel]'s viewport. */
    fun onLabel(wheel: String, hasSourceCue: Boolean, layout: TextLayoutResult)
}

/** @see WheelRenderProbe */
internal val LocalWheelRenderProbe = staticCompositionLocalOf<WheelRenderProbe?> { null }

/**
 * The row height a [SnapWheel] uses for [minimum] at the current system
 * font scale: [minimum], or the tallest line any of the wheel's row
 * styles renders if that is taller.
 *
 * The wheels' row height used to be a fixed 34dp at every font scale.
 * Every row's `Text` is measured against it, so a raised scale left the
 * line box larger than the row it was laid out in, on the Base Shutter
 * column as much as on the filter wheels. Measured at 360dp with three
 * wheels, on the selected row (which renders one style step larger than
 * its neighbours): Base Shutter's `1/30` took 111px of line in an 89px
 * row and a filter wheel's `0` took 98px in 89px, both at the 89px the
 * fixed 34dp gave them. FILTER-STACK-007 and the large-text rules in
 * `cross-cutting/presentation.md` want the numeric value legible at
 * every supported standard text size, so the row follows the metrics
 * instead and the card grows. The same case now reports 111/111px and
 * 98/98px: line box and row are equal.
 *
 * It measures EVERY style a row can take — centered or not, dense or
 * not — rather than the one this wheel will use, so a dense filter
 * wheel and the non-dense Base Shutter beside it always reserve the
 * same height. FILTER-STACK-008's shared viewport, selection band and
 * vertical touch center then hold by construction rather than by two
 * call sites agreeing on a number. Callers that size a sibling to the
 * viewport (the Plus control) resolve it through this function too.
 */
@Composable
internal fun snapWheelItemHeight(minimum: Dp): Dp {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    val styles = listOf(
        typography.titleMedium,
        typography.bodyLarge,
        typography.bodyMedium,
        typography.bodySmall,
    )
    // One line of any of them is the same height whatever digits it
    // holds, so a single probe character stands for every row.
    val tallest: Int = styles.maxOf { style ->
        measurer.measure(RowHeightProbe, style, maxLines = 1, softWrap = false).size.height
    }
    return maxOf(minimum, with(density) { tallest.toDp() })
}

private const val RowHeightProbe = "0"

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
    /** MINIMUM row height: [snapWheelItemHeight] grows it when the
     *  system font scale makes a row's line taller than this. */
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
    // PTIMER-221 (mixed Filter Stack) additions; every default keeps the
    // pre-Filter-Set call sites (base shutter, target shutter) unchanged.
    /** Type-color rail of each row (FILTER-STACK-007): a narrow vertical
     *  mark at the row's leading edge, inside the row's own bounds, so it
     *  never moves the centered value or changes the wheel's width.
     *  `null` (or a `null` result) draws no rail. */
    rowRailColor: ((index: Int) -> Color?)? = null,
    /** Availability of each row: an unavailable row renders faded. */
    rowEnabled: ((index: Int) -> Boolean)? = null,
    /** Replaces the default one-row step for assistive adjustment
     *  (FILTER-A11Y-004): receives the direction and reports whether the
     *  adjustment was applied. The caller announces refusals itself. */
    onAccessibilityAdjust: ((forward: Boolean) -> Boolean)? = null,
    /** Overrides the default `labels[selectedIndex]` state description
     *  (FILTER-A11Y-005). */
    accessibilityValue: String? = null,
) {
    require(visibleCount % 2 == 1) { "visibleCount must be odd so one item sits dead-center" }
    val halfVisible = visibleCount / 2
    val renderProbe = LocalWheelRenderProbe.current
    // Every measurement below uses the RESOLVED height, so a raised
    // font scale grows the viewport, the rows, the rails, the snap
    // grid and the overscroll threshold together.
    val rowHeight = snapWheelItemHeight(itemHeight)

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
    val removalThresholdPx = with(LocalDensity.current) { rowHeight.toPx() }
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

    // At rest the viewport must show the CALLER's selection, never whichever
    // row the gesture last passed over. The effect above fires only when
    // [selectedIndex] changes, so a settle the caller REFUSES leaves nothing to
    // re-trigger it: the commit barrier rejects the candidate, the committed
    // index is unchanged, and the wheel would stay parked on the rejected row
    // indefinitely — showing a value the stack does not hold (PTIMER-221
    // FILTER-STACK-004: an unavailable row never commits and the previous
    // selection remains). Re-checking on every transition to quiescence closes
    // that gap, and also covers a commit that lands while the settle animation
    // is still finishing (which the guard above drops). A wheel whose selection
    // did follow the gesture finds centered == selected here and does nothing,
    // so the base-shutter and Standard ladders are unaffected.
    val currentSelectedIndex by rememberUpdatedState(selectedIndex)
    val currentLabelCount by rememberUpdatedState(labels.size)
    LaunchedEffect(listState) {
        snapshotFlow { listState.isScrollInProgress }
            .filter { !it }
            .collect {
                val target = currentSelectedIndex
                if (centeredIndex != null && centeredIndex != target && target < currentLabelCount && target >= 0) {
                    listState.scrollToItem(target)
                }
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
    // A Filter Set wheel scans its own rows for the next AVAILABLE one
    // (FILTER-A11Y-004), so the index-stepping default is replaced rather
    // than extended; the caller reports a refusal or a boundary itself.
    val currentOnAccessibilityAdjust by rememberUpdatedState(onAccessibilityAdjust)
    val adjust: (Boolean) -> Boolean = { forward ->
        val override = currentOnAccessibilityAdjust
        if (override != null) {
            override(forward)
        } else {
            val target = selectedIndex + if (forward) 1 else -1
            if (target in labels.indices) {
                currentOnSelectedIndexChange(target)
                true
            } else {
                false
            }
        }
    }
    val accessibilityModifier = if (accessibilityLabel != null) {
        Modifier.clearAndSetSemantics {
            contentDescription = accessibilityLabel
            (accessibilityValue ?: labels.getOrNull(selectedIndex))?.let { stateDescription = it }
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
                when {
                    targetValue > selectedIndex -> adjust(true)
                    targetValue < selectedIndex -> adjust(false)
                    else -> false
                }
            }
            customActions = listOf(
                CustomAccessibilityAction(previousActionLabel) { adjust(false) },
                CustomAccessibilityAction(nextActionLabel) { adjust(true) },
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
            .height(rowHeight * visibleCount)
            .then(accessibilityModifier)
            .then(pressTrackingModifier)
            // Fence OUTSIDE the overscroll connection: the removal
            // accounting gets first crack at unconsumed deltas, the
            // fence swallows whatever remains so nothing reaches the
            // pager or the bottom sheet.
            .nestedScroll(WheelNestedScrollFence)
            .then(if (overscrollActive) Modifier.nestedScroll(overscrollConnection) else Modifier),
    ) {
        LazyColumn(
            state = listState,
            flingBehavior = flingBehavior,
            horizontalAlignment = Alignment.CenterHorizontally,
            contentPadding = PaddingValues(vertical = rowHeight * halfVisible),
            modifier = Modifier
                .fillMaxSize()
                // Damped live push-out while the wheel is pulled past zero.
                .offset { IntOffset(0, (overscrollPx * OverscrollVisualDamping).roundToInt()) },
        ) {
            itemsIndexed(labels) { index, label ->
                val distance = abs((centeredIndex ?: selectedIndex) - index)
                val isCenter = distance == 0
                val available = rowEnabled?.invoke(index) ?: true
                val alpha = (1f - 0.26f * distance).coerceAtLeast(0.18f) *
                    (if (available) 1f else UnavailableRowAlpha)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(rowHeight),
                    contentAlignment = Alignment.Center,
                ) {
                    // Type-color rail inside the row's own bounds
                    // (FILTER-STACK-007): it rides the leading edge, fades
                    // with the same distance alpha as the value, and leaves
                    // the centered numeric column untouched.
                    val railColor = rowRailColor?.invoke(index)
                    if (railColor != null) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.CenterStart)
                                .width(RowRailWidth)
                                .height(rowHeight * RowRailHeightFraction)
                                .background(
                                    color = railColor.copy(alpha = railColor.alpha * alpha),
                                    shape = RoundedCornerShape(RowRailWidth / 2),
                                ),
                        )
                    }
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
                        // The rows are inside the wheel's cleared semantics,
                        // so only the laid-out text can show a silent clip.
                        onTextLayout = { layout ->
                            if (accessibilityLabel != null) {
                                renderProbe?.onRow(accessibilityLabel, index, isCenter, railColor != null, layout)
                            }
                        },
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
                .height(rowHeight),
        ) {
            HorizontalDivider(modifier = Modifier.align(Alignment.TopCenter), color = boundColor)
            HorizontalDivider(modifier = Modifier.align(Alignment.BottomCenter), color = boundColor)
        }
    }
}
