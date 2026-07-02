// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.ui.draw.clip
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.core.target.TargetShutterStopDifferenceKind
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.ui.theme.StatusSuccess
import com.sangwook.ptimer.ui.theme.StatusWarning
import androidx.compose.ui.res.stringResource
import com.sangwook.ptimer.R

// Target Shutter UI (main-screen row + Quick/Fine input sheet) extracted
// from ShootingScreen. Same package; ShootingScreen calls TargetShutterRow
// and TargetShutterSheet directly.

private val targetClock = ExposureCalculator()

@Composable
internal fun TargetShutterRow(
    display: TargetShutterDisplayState,
    onEdit: () -> Unit,
    onStartTarget: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable { onEdit() },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                stringResource(R.string.target_shutter_label),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when (display) {
                is TargetShutterDisplayState.Unavailable -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.common_off), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                is TargetShutterDisplayState.Available -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Stop-difference first so the variable-width arrow + text
                        // floats on the LEFT; the target value stays pinned next to
                        // ▶ on the right and no longer slides as the stops change.
                        display.state.stopDifference?.let { diff ->
                            // Arrow shows which way to turn the ND wheel to reach
                            // the target: ↑ = add stops (longer), ↓ = remove stops.
                            // Coloured by direction like iOS — calm accent for
                            // "longer", amber for "shorter", green for a match —
                            // at a quiet weight so the cue informs without shouting.
                            val arrow = when (diff.kind) {
                                TargetShutterStopDifferenceKind.longerThanComparison -> "↑"
                                TargetShutterStopDifferenceKind.shorterThanComparison -> "↓"
                                TargetShutterStopDifferenceKind.match -> "="
                            }
                            val tint = when (diff.kind) {
                                TargetShutterStopDifferenceKind.longerThanComparison -> MaterialTheme.colorScheme.primary
                                TargetShutterStopDifferenceKind.shorterThanComparison -> StatusWarning
                                TargetShutterStopDifferenceKind.match -> StatusSuccess
                            }
                            Text(
                                arrow,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = tint,
                            )
                            Text(
                                // Localized unit around the core's signed
                                // magnitude; values constructed without the
                                // decomposition fall back to the canonical
                                // English text.
                                if (diff.signedMagnitudeText.isEmpty()) {
                                    diff.formattedText
                                } else {
                                    stringResource(
                                        if (diff.isPluralStops) R.string.target_stops_format else R.string.target_stop_format,
                                        diff.signedMagnitudeText,
                                    )
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                color = tint,
                            )
                        }
                        Text(
                            targetClock.formatCoarse(display.state.targetSeconds),
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        StartButton(onClick = onStartTarget, enabled = true)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TargetShutterSheet(
    initialSeconds: Double?,
    onConfirm: (Double?) -> Unit,
    onDismiss: () -> Unit,
) {
    // Default the toggle ON (a fresh slot seeds to 1 minute) so opening the
    // sheet lands on an active, editable target instead of a confusing "Off".
    val initial = (initialSeconds ?: 60.0).toLong()
    var useTarget by remember { mutableStateOf(true) }
    var hours by remember { mutableStateOf((initial / 3600).toInt().coerceIn(0, 12)) }
    var minutes by remember { mutableStateOf(((initial % 3600) / 60).toInt()) }
    var seconds by remember { mutableStateOf((initial % 60).toInt()) }
    val total = hours * 3600 + minutes * 60 + seconds

    val hourLabels = remember { (0..12).map { it.toString() } }
    val minuteLabels = remember { (0..59).map { it.toString() } }
    val secondLabels = remember { (0..59).map { it.toString() } }

    // Quick mode: a single wheel of photographer-friendly presets (iOS Quick
    // page). Fine mode keeps the h/m/s wheels. Both edit the same total; Quick
    // parks on the nearest preset to the current value.
    val quickPresets = remember {
        listOf(1, 2, 4, 8, 15, 30, 60, 120, 240, 480, 900, 1800, 3600, 7200, 14_400, 28_800)
    }
    val quickLabels = remember { quickPresets.map { formatHms(it) } }
    val quickIndex = quickPresets.indices.minByOrNull { kotlin.math.abs(quickPresets[it] - total) } ?: 0
    fun applyPreset(sec: Int) {
        hours = sec / 3600; minutes = (sec % 3600) / 60; seconds = sec % 60
    }
    val pagerScope = rememberCoroutineScope()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.target_use), style = MaterialTheme.typography.titleMedium)
                Switch(checked = useTarget, onCheckedChange = { useTarget = it })
            }

            Spacer(Modifier.height(12.dp))
            Text(
                if (useTarget) formatHms(total) else stringResource(R.string.common_off),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(12.dp))

            if (useTarget) {
                // Quick and Fine are swipeable pages (iOS Quick/Fine pages) with a
                // fixed height so the sheet doesn't jump between them. The mode
                // label sits above; page dots below. Quick parks on the nearest
                // preset; both pages edit the same value.
                val modePager = rememberPagerState(
                    initialPage = if (quickPresets.contains(initial.toInt())) 0 else 1,
                ) { 2 }
                Text(
                    stringResource(if (modePager.currentPage == 0) R.string.target_mode_quick else R.string.target_mode_fine),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(8.dp))
                HorizontalPager(state = modePager, modifier = Modifier.fillMaxWidth().height(150.dp)) { page ->
                    Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                        if (page == 0) {
                            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                                SnapWheel(
                                    quickLabels,
                                    quickIndex,
                                    { applyPreset(quickPresets[it]) },
                                    modifier = Modifier.fillMaxWidth(),
                                    visibleCount = 3,
                                    itemHeight = 44.dp,
                                )
                            }
                            // Right-edge cue: Fine lives one swipe away (iOS teaser).
                            ModeTeaser(stringResource(R.string.target_mode_fine), chevronLeading = false) {
                                pagerScope.launch { modePager.animateScrollToPage(1) }
                            }
                        } else {
                            // Left-edge cue: Quick lives one swipe away.
                            ModeTeaser(stringResource(R.string.target_mode_quick), chevronLeading = true) {
                                pagerScope.launch { modePager.animateScrollToPage(0) }
                            }
                            Box(Modifier.weight(1f)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                                    HmsWheel("Hours", hourLabels, hours) { hours = it }
                                    HmsWheel("Min", minuteLabels, minutes) { minutes = it }
                                    HmsWheel("Sec", secondLabels, seconds) { seconds = it }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                PagerDots(count = 2, current = modePager.currentPage)
                Spacer(Modifier.height(12.dp))
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.action_cancel)) }
                Button(
                    onClick = { onConfirm(if (useTarget && total > 0) total.toDouble() else null) },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.action_confirm)) }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

/**
 * Edge cue inside the Quick/Fine pager that another page is one swipe away
 * (iOS TargetShutterModeTeaser): a thin-outlined tall box with a chevron toward
 * the other page and its label; tapping it animates to that page.
 */
@Composable
private fun ModeTeaser(label: String, chevronLeading: Boolean, onTap: () -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .width(52.dp)
            .padding(vertical = 12.dp)
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f), shape)
            .clickable { onTap() },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            if (chevronLeading) Icons.AutoMirrored.Filled.KeyboardArrowLeft else Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.HmsWheel(
    label: String,
    labels: List<String>,
    value: Int,
    onChange: (Int) -> Unit,
) {
    Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        SnapWheel(labels, value.coerceIn(labels.indices), onChange, visibleCount = 3, itemHeight = 40.dp)
    }
}

/** Compact h/m/s rendering: drops zero parts; "0s" when empty. */
private fun formatHms(total: Int): String {
    if (total <= 0) return "0s"
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return buildString {
        if (h > 0) append("${h}h ")
        if (m > 0) append("${m}m ")
        if (s > 0) append("${s}s")
    }.trim()
}
