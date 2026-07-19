// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.ui.component.SnapWheel
import kotlinx.coroutines.delay

/** Slim trailing-edge Add control width (iOS uses a 26 pt ghost column). */
private val AddControlWidth = 26.dp

/** Gap between stacked wheels (tighter than the card's 8dp rhythm so
 *  four wheels keep usable label width). */
private val WheelSpacing = 4.dp

private val NdWheelItemHeight = 34.dp
private const val NdWheelVisibleCount = 3

/**
 * The ND wheel stack group (PTIMER-199 M3): 1–4 side-by-side SnapWheels
 * keyed by wheel identity (a commit sort animates as movement), the slim
 * Add control on the trailing edge (presence = C1 on committed values,
 * enabled = quiet machine), the transient Total overlay, and the
 * Add/Remove TalkBack custom actions. All stack STATE — including the
 * 4-second self-cleaning timer, which lives in the ViewModel-owned
 * controller scope (PTIMER-223) — stays out of this layer; it renders,
 * and times only its own presentation (the badge fade).
 */
@Composable
internal fun NdFilterStackGroup(
    state: CalculatorUiState,
    onWheelActive: (Int, Boolean) -> Unit,
    onWheelValue: (Int, Int) -> Unit,
    onAddWheel: () -> Unit,
    onOverscrollRemove: (Int) -> Unit,
    onCleanupEmptyWheels: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val wheels = state.ndWheels
    val addLabel = stringResource(R.string.nd_add_filter)
    val removeLabel = stringResource(R.string.nd_remove_empty_filter)
    // Registered conditionally so TalkBack never surfaces a dead command:
    // both actions use the quiet-gated availability flags (not the
    // structural presence flags), so a command that would no-op while a
    // wheel is moving is simply absent. Attached to every wheel node —
    // the wheels are the group's focusable elements.
    val stackActions = buildList {
        if (state.canAddNdWheel) add(CustomAccessibilityAction(addLabel) { onAddWheel(); true })
        if (state.canCleanupEmptyNdWheels) {
            add(CustomAccessibilityAction(removeLabel) { onCleanupEmptyWheels(); true })
        }
    }

    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val addSlot = if (state.showsAddNdWheel) AddControlWidth + WheelSpacing else 0.dp
        val wheelWidth = (maxWidth - addSlot - WheelSpacing * (wheels.size - 1)) / wheels.size

        LazyRow(
            userScrollEnabled = false,
            horizontalArrangement = Arrangement.spacedBy(WheelSpacing),
            modifier = Modifier.fillMaxWidth(),
        ) {
            itemsIndexed(wheels, key = { _, wheel -> wheel.id }) { index, wheel ->
                SnapWheel(
                    labels = wheel.labels,
                    selectedIndex = wheel.selectedIndex,
                    onSelectedIndexChange = { onWheelValue(wheel.id, it) },
                    modifier = Modifier.width(wheelWidth).animateItem(),
                    visibleCount = NdWheelVisibleCount,
                    itemHeight = NdWheelItemHeight,
                    accessibilityLabel = stringResource(
                        R.string.nd_wheel_cd, index + 1, wheels.size,
                    ),
                    dense = wheels.size >= 3,
                    onActiveChange = { onWheelActive(wheel.id, it) },
                    // Visual gate only — the controller re-validates the
                    // removal (zero wheel, last-wheel rule, quiet others).
                    overscrollRemovalEnabled = wheel.selectedIndex == 0 && wheels.size > 1,
                    onOverscrollRemoval = { onOverscrollRemove(wheel.id) },
                    extraAccessibilityActions = stackActions,
                )
            }
            if (state.showsAddNdWheel) {
                item(key = "nd-add-control") {
                    AddNdWheelControl(
                        enabled = state.canAddNdWheel,
                        onClick = onAddWheel,
                        height = NdWheelItemHeight * NdWheelVisibleCount,
                        modifier = Modifier.animateItem(),
                    )
                }
            }
        }

        // Transient Total overlay (§4.6): non-clickable, so touches pass
        // through to the wheels beneath; ≥ 2 wheels gate comes from the
        // controller (null text below two wheels).
        NdStackTotalBadge(
            text = state.ndTotalStopsText,
            isMaximum = state.ndTotalIsMaximum,
            wheelCount = wheels.size,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 2.dp),
        )
    }
}

/**
 * The trailing-edge Add affordance: a dim ghost column with a plus glyph,
 * hint-width so it never competes with the wheels for row space. Present
 * while C1 allows a new wheel on committed values; dims (stays in layout,
 * so wheels never resize under a moving finger) while the machine is busy.
 */
@Composable
private fun AddNdWheelControl(
    enabled: Boolean,
    onClick: () -> Unit,
    height: Dp,
    modifier: Modifier = Modifier,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(
            alpha = if (enabled) 0.6f else 0.25f,
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = modifier.width(AddControlWidth).height(height),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                Icons.Filled.Add,
                contentDescription = stringResource(R.string.nd_add_filter),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                    alpha = if (enabled) 1f else 0.4f,
                ),
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

/**
 * Transient Total badge over the wheel row: the effective sum, always in
 * stops, plus a Maximum marker at the 30-stop cap. Re-shows on any
 * effective change while stacked, then fades after a short idle — slightly
 * longer right after a wheel was added so the add is acknowledged.
 */
@Composable
private fun NdStackTotalBadge(
    text: String?,
    isMaximum: Boolean,
    wheelCount: Int,
    modifier: Modifier = Modifier,
) {
    var visible by remember { mutableStateOf(false) }
    var lastWheelCount by remember { mutableIntStateOf(wheelCount) }
    // The text is remembered past its own null-out so the fade-out never
    // renders an empty capsule.
    var badgeText by remember { mutableStateOf("") }
    if (text != null) badgeText = text

    LaunchedEffect(text, isMaximum, wheelCount) {
        val added = wheelCount > lastWheelCount
        lastWheelCount = wheelCount
        if (text == null) {
            visible = false
            return@LaunchedEffect
        }
        visible = true
        delay(if (added) 2_500L else 1_500L)
        visible = false
    }

    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = fadeIn(tween(150)),
        exit = fadeOut(tween(400)),
    ) {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            border = BorderStroke(Dp.Hairline, MaterialTheme.colorScheme.outlineVariant),
            shadowElevation = 4.dp,
        ) {
            Text(
                text = if (isMaximum) {
                    stringResource(R.string.nd_total_stops_maximum, badgeText)
                } else {
                    stringResource(R.string.nd_total_stops, badgeText)
                },
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            )
        }
    }
}
