// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlin.math.abs

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

    Box(
        modifier = modifier.height(itemHeight * visibleCount),
    ) {
        LazyColumn(
            state = listState,
            flingBehavior = flingBehavior,
            horizontalAlignment = Alignment.CenterHorizontally,
            contentPadding = PaddingValues(vertical = itemHeight * halfVisible),
            modifier = Modifier.fillMaxSize(),
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
                        style = if (isCenter) {
                            MaterialTheme.typography.titleMedium
                        } else {
                            MaterialTheme.typography.bodyLarge
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
