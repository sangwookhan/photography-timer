// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.timer

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingUiState
import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.timer.TimerBasisPresenter
import com.sangwook.ptimer.core.timer.TimerStatus
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

private val calc = ExposureCalculator()
private val endFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault())

/** Fixed peek-bar height: tall enough to show one mini card without clipping. */
val MiniTimerBarHeight = 128.dp

/** The compact dock shows the top few timers across all statuses (iOS parity). */
private const val MiniDockLimit = 3

/**
 * Peek-state content: a headerless, horizontally scrollable row of compact
 * portrait timer cards across ALL statuses — active first, then most-recent
 * history — newest first (left), capped with a "+N / View all" overflow tile.
 * Showing terminal timers too means a just-finished or very short timer stays
 * briefly visible instead of vanishing the instant it leaves the active set
 * (matches the iOS compact dock). Cards are display-only; tapping one (or the
 * overflow) expands the sheet to the full list, where the controls live.
 */
@Composable
fun MiniTimerBar(
    state: ShootingUiState,
    onOpen: (UUID?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val dock = state.active.asReversed() + state.history
    if (dock.isEmpty()) {
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(MiniTimerBarHeight)
                .clickable { onOpen(null) },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "No timers yet",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    val shown = dock.take(MiniDockLimit)
    val overflow = dock.size - shown.size
    // Terminal mini cards show relative completion time; refresh it from a
    // UI-local clock so it advances while the dock stays visible.
    val now = rememberPresentationNow(fallback = state.now, enabled = state.history.isNotEmpty())
    // Auto-scroll to the newest (leftmost) when the lead timer changes.
    val rowState = rememberLazyListState()
    LaunchedEffect(dock.firstOrNull()?.id) { rowState.animateScrollToItem(0) }
    LazyRow(
        state = rowState,
        modifier = modifier
            .fillMaxWidth()
            .height(MiniTimerBarHeight),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(shown, key = { it.id }) { card ->
            // Tapping a mini card expands the sheet and focuses this timer.
            MiniTimerCard(card, now) { onOpen(card.id) }
        }
        if (overflow > 0) {
            item { MiniOverflowTile(overflow) { onOpen(null) } }
        }
    }
}

/**
 * Expanded-state content: full Active and History sections with the complete
 * card controls and a Close action. Shown only when the sheet is expanded.
 */
@Composable
fun FullTimerList(
    state: ShootingUiState,
    onEvent: (ShootingIntent) -> Unit,
    onCollapse: () -> Unit,
    focusId: UUID?,
    ndNotationMode: NDNotationMode = NDNotationMode.DEFAULT,
    modifier: Modifier = Modifier,
) {
    val activeReversed = state.active.asReversed()
    val listState = rememberLazyListState()
    // History rows show relative completion/cancellation time; refresh it from
    // a UI-local clock so it advances while the list stays open.
    val now = rememberPresentationNow(fallback = state.now, enabled = state.history.isNotEmpty())
    // Pending Clone/Cancel/Remove confirmation; null when no dialog is shown.
    var confirm by remember { mutableStateOf<ConfirmRequest?>(null) }
    // Bring the focused card into view and highlight it: a mini-card tap focuses
    // an active timer; a tapped completion notification focuses a finished timer
    // in History. (Row at index 0 is the header; for the first active card, anchor
    // on the header so the close X stays visible.)
    LaunchedEffect(focusId, activeReversed.size, state.history.size) {
        if (focusId == null) return@LaunchedEffect
        val activePos = activeReversed.indexOfFirst { it.id == focusId }
        if (activePos >= 0) {
            listState.animateScrollToItem(if (activePos == 0) 0 else activePos + 1)
            return@LaunchedEffect
        }
        val historyPos = state.history.indexOfFirst { it.id == focusId }
        if (historyPos < 0) return@LaunchedEffect
        // header(1) + active cards + History header(1) + the card's position.
        listState.animateScrollToItem(1 + activeReversed.size + 1 + historyPos)
    }
    LazyColumn(
        state = listState,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Header with a leading close (X) that collapses the sheet to the peek.
        // Material places the dismiss control top-left; the trailing side is for
        // actions (History's Clear) only.
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onCollapse) {
                    Icon(Icons.Filled.Close, contentDescription = "Close")
                }
                SectionHeader("Timers")
            }
        }
        if (state.active.isEmpty() && state.history.isEmpty()) {
            item { EmptyState() }
        }
        // Active timers as full cards, newest first to match the peek order.
        if (state.active.isNotEmpty()) {
            items(activeReversed, key = { it.id }) { card ->
                TimerCard(card, now, ndNotationMode, onEvent, onConfirm = { confirm = it }, highlighted = card.id == focusId)
            }
        }
        if (state.history.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionHeader("History")
                    // Clear removes completed records only; canceled history is
                    // preserved (iOS clearCompletedTimers, label kept "Clear").
                    // Routed through the confirmation dialog like the card actions.
                    TextButton(onClick = { confirm = clearCompletedConfirm() }) { Text("Clear") }
                }
            }
            items(state.history, key = { it.id }) { card ->
                TimerCard(card, now, ndNotationMode, onEvent, onConfirm = { confirm = it }, highlighted = card.id == focusId)
            }
        }
    }

    confirm?.let { req ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text(req.title) },
            text = { Text(req.message) },
            confirmButton = {
                TextButton(onClick = {
                    onEvent(req.intent)
                    confirm = null
                }) {
                    Text(
                        req.confirmLabel,
                        color = if (req.destructive) MaterialTheme.colorScheme.error else Color.Unspecified,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirm = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp),
    )
}

@Composable
private fun EmptyState() {
    Box(modifier = Modifier.fillMaxWidth().padding(top = 64.dp), contentAlignment = Alignment.Center) {
        Text("No timers yet", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * Two-bar pause glyph for the mini timer's paused state. A tiny inline vector
 * so the one missing icon needs no material-icons-extended dependency; tinted
 * by the caller like any [Icons] vector.
 */
private val miniPauseIcon: ImageVector by lazy {
    ImageVector.Builder(
        name = "MiniPause",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        path(fill = SolidColor(Color.Black)) {
            moveTo(6.5f, 5f); horizontalLineTo(9.5f); verticalLineTo(19f); horizontalLineTo(6.5f); close()
            moveTo(14.5f, 5f); horizontalLineTo(17.5f); verticalLineTo(19f); horizontalLineTo(14.5f); close()
        }
    }.build()
}

/**
 * Compact, display-only card for an active timer in the bottom-sheet peek row:
 * title + slot, the remaining countdown, and a paused hint. Tapping it expands
 * the sheet to [FullTimerList], where Pause/Resume/Cancel live.
 */
@Composable
private fun MiniTimerCard(card: TimerCardState, now: Instant, onClick: () -> Unit) {
    val terminal = card.status == TimerStatus.completed || card.status == TimerStatus.canceled
    val active = card.status == TimerStatus.running || card.status == TimerStatus.paused
    // Tall portrait card mirroring the iOS compact dock, top→bottom:
    // [status dot+label · compact total cue] / big remaining (or relative
    // terminal) value / film cue / layered progress + slot badge at the foot.
    Card(
        modifier = Modifier.width(96.dp).height(116.dp).clickable { onClick() },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            // Top row: status dot + label (left), compact total/reference time
            // (right) — the iOS `secondaryTotalText`, a quiet identity cue that
            // does not compete with the big remaining value.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // State cue: a small meaningful icon (play = running, bars =
                // paused, check = done, close = canceled), tinted by state, so
                // the mini matches the iOS icon cue's intent. contentDescription
                // keeps it accessible (not color-only); kept compact so it does
                // not crowd the total cue.
                Icon(
                    imageVector = when (card.status) {
                        TimerStatus.running -> Icons.Filled.PlayArrow
                        TimerStatus.paused -> miniPauseIcon
                        TimerStatus.completed -> Icons.Filled.Check
                        TimerStatus.canceled -> Icons.Filled.Close
                    },
                    contentDescription = when (card.status) {
                        TimerStatus.running -> "Running"
                        TimerStatus.paused -> "Paused"
                        TimerStatus.completed -> "Done"
                        TimerStatus.canceled -> "Canceled"
                    },
                    tint = when (card.status) {
                        TimerStatus.running -> MaterialTheme.colorScheme.primary
                        TimerStatus.paused -> MaterialTheme.colorScheme.secondary
                        TimerStatus.canceled -> MaterialTheme.colorScheme.error
                        TimerStatus.completed -> MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    modifier = Modifier.size(14.dp),
                )
                Spacer(Modifier.weight(1f))
                if (card.durationSeconds > 0.0) {
                    Text(
                        calc.formatCoarse(card.durationSeconds),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            }
            // Centre, matching the iOS mini: active shows the big remaining
            // countdown with the film cue below; terminal shows the explicit
            // Done/Canceled state with the relative completion time below.
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    when (card.status) {
                        TimerStatus.completed -> "Done"
                        TimerStatus.canceled -> "Canceled"
                        else -> calc.formatExtendedClock(card.remainingSeconds)
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontFamily = if (terminal) FontFamily.Default else FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    if (terminal) relativeTime(card.endDate, now)
                    else card.identity.filmName?.takeIf { it.isNotBlank() } ?: "No film",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            // Foot: layered progress (active only) then the slot badge, matching
            // the iOS mini's lower zone.
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (active) {
                    MiniProgressStack(
                        durationSeconds = card.durationSeconds,
                        remainingSeconds = card.remainingSeconds,
                        status = card.status,
                    )
                }
                Row(modifier = Modifier.fillMaxWidth()) {
                    Spacer(Modifier.weight(1f))
                    Text(
                        card.identity.slotLabel,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
    }
}

/**
 * iOS-parity layered progress for the mini timer: 1–3 thin repeating-fraction
 * bars chosen by duration — sub-minute → 1 (60s), sub-hour → 2 (60m + 60s),
 * longer → 3 (whole-duration + 60m + 60s) — most-significant on top, the
 * 60-second bar at the foot, so a running mini shows progress at multiple time
 * scales like the iOS compact dock rather than one flat bar. Fractions mirror
 * iOS `repeatingRemainingFraction` / `compactLayerCount`; display only.
 */
@Composable
private fun MiniProgressStack(durationSeconds: Double, remainingSeconds: Double, status: TimerStatus) {
    fun repeating(unit: Double): Float {
        if (remainingSeconds <= 0.0) return 0f
        val r = remainingSeconds % unit
        return (if (r == 0.0) 1.0 else r / unit).toFloat().coerceIn(0f, 1f)
    }
    // Per-layer palette ported from the iOS mini (warm 60-second → cooler
    // 60-minute → calm whole-duration), so the multi-scale progress reads the
    // same on both platforms. Paused shifts to the iOS amber/yellow/green set.
    val running = status == TimerStatus.running
    val secColor = if (running) Color(0xFFFF3B30) else Color(0xFFFF9500)
    val secFill = secColor.copy(alpha = if (running) 0.92f else 0.88f)
    val secTrack = secColor.copy(alpha = if (running) 0.18f else 0.16f)
    val minColor = if (running) Color(0xFFFF9500) else Color(0xFFFFCC00)
    val minFill = minColor.copy(alpha = if (running) 0.74f else 0.72f)
    val minTrack = minColor.copy(alpha = if (running) 0.12f else 0.11f)
    val origColor = if (running) Color(0xFF30B0C7) else Color(0xFF34C759)
    val origFill = origColor.copy(alpha = if (running) 0.46f else 0.48f)
    val origTrack = origColor.copy(alpha = 0.08f)
    // Most-significant layer on top, the 60-second layer at the foot (iOS order).
    val layers = buildList {
        if (durationSeconds >= 3600.0) {
            add(Triple((remainingSeconds / 86_400.0).toFloat().coerceIn(0f, 1f), origFill, origTrack))
        }
        if (durationSeconds >= 60.0) add(Triple(repeating(3600.0), minFill, minTrack))
        add(Triple(repeating(60.0), secFill, secTrack))
    }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        layers.forEach { (fraction, fill, track) ->
            CompactBar(fraction = fraction, fill = fill, track = track)
        }
    }
}

/** A single thin (1.5dp) capsule progress hairline — matches the calm iOS
 *  CompactProgressBar look (custom-drawn so it can be thinner than a Material
 *  LinearProgressIndicator). */
@Composable
private fun CompactBar(fraction: Float, fill: Color, track: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.5.dp)
            .clip(CircleShape)
            .background(track),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .fillMaxHeight()
                .clip(CircleShape)
                .background(fill),
        )
    }
}

/** Trailing "+N / View all" tile shown when the dock holds more than it lists. */
@Composable
private fun MiniOverflowTile(count: Int, onClick: () -> Unit) {
    Card(
        modifier = Modifier.width(86.dp).height(116.dp).clickable { onClick() },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(12.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("+$count", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(
                "View all",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Formats a basis shutter value for the timer card: the camera-dial label
 * (`1/30`) for on-ladder base shutters, falling back to the coarse clock for
 * off-ladder values like the reciprocity-adjusted shutter (`8s`).
 */
private fun basisShutterLabel(seconds: Double): String =
    ExposureScale.oneThirdStopShutterCameraLabel(seconds) ?: calc.formatCoarse(seconds)

@Composable
private fun TimerCard(
    card: TimerCardState,
    now: Instant,
    ndNotationMode: NDNotationMode,
    onEvent: (ShootingIntent) -> Unit,
    onConfirm: (ConfirmRequest) -> Unit,
    highlighted: Boolean = false,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        border = if (highlighted) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null,
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(card.identity.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                StatusBadge(card.status)
            }
            if (card.identity.subtitle.isNotEmpty()) {
                Text(
                    card.identity.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(Modifier.size(8.dp))

            // Primary line: remaining-time countdown for active timers (with a
            // `left` qualifier so it reads as remaining time, not the final
            // exposure value on the second line), terminal label for history.
            // Right-aligned to match the iOS timer card (PTIMER-187).
            // Canceled shows just "Canceled" as the primary state value; the
            // remaining-at-cancel moves to the meta line so a stopped timer is
            // not presented as one dominant "Canceled · N left" string
            // (PTIMER-198). headlineSmall (was headlineMedium) keeps long
            // values like "16:09:49.829 left" readable without dominating.
            when (card.status) {
                TimerStatus.running, TimerStatus.paused ->
                    // The countdown number is the star; "left" is a quieter,
                    // smaller qualifier so the two don't compete (PTIMER-198).
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Text(
                            calc.formatExtendedClock(card.remainingSeconds),
                            style = MaterialTheme.typography.headlineSmall,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            "left",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = 2.dp),
                        )
                    }
                TimerStatus.completed, TimerStatus.canceled ->
                    // Terminal state is clear but calmer — not the heavy mono
                    // headline used for a live countdown (PTIMER-198).
                    Text(
                        if (card.status == TimerStatus.completed) "Done" else "Canceled",
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.End,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
            }

            val secondary = when (card.status) {
                TimerStatus.running -> "Ends ${endFormatter.format(card.endDate)}"
                TimerStatus.paused -> "Paused"
                TimerStatus.completed ->
                    "Completed ${endFormatter.format(card.endDate)} · ${relativeTimeLong(card.endDate, now)}"
                TimerStatus.canceled -> {
                    val base = "Canceled ${endFormatter.format(card.endDate)} · ${relativeTimeLong(card.endDate, now)}"
                    val left = card.remainingAtCancelSeconds?.takeIf { it > 0.0 }
                        ?.let { " · ${calc.formatExtendedClock(it)} left" } ?: ""
                    base + left
                }
            }
            Text(
                secondary,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // Basis line rendered from structured ND/base inputs in the current
            // notation mode (PTIMER-187); falls back to any precomposed baseLine
            // from a pre-update timer that has no structured fields.
            val basisText = TimerBasisPresenter.basisText(
                ndStops = card.identity.ndStops,
                baseShutterSeconds = card.identity.baseShutterSeconds,
                adjustedShutterSeconds = card.identity.adjustedShutterSeconds,
                includesAdjusted = card.identity.basisIncludesAdjusted,
                mode = ndNotationMode,
                formatShutter = ::basisShutterLabel,
            ) ?: card.identity.baseLine.takeIf { it.isNotEmpty() }
            if (basisText != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        basisText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        // Bare creation-order number beside the slot badge (iOS
                        // RunningTimerItem.order) so repeated timers are distinct.
                        Text(
                            "${card.order}",
                            style = MaterialTheme.typography.labelMedium,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (card.identity.slotLabel.isNotEmpty()) {
                            Text(card.identity.slotLabel, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }

            Spacer(Modifier.size(12.dp))
            CardActions(card, onEvent, onConfirm)
        }
    }
}

@Composable
private fun StatusBadge(status: TimerStatus) {
    val label = when (status) {
        TimerStatus.running -> "Running"
        TimerStatus.paused -> "Paused"
        TimerStatus.completed -> "Done"
        TimerStatus.canceled -> "Canceled"
    }
    // Active states use the accent color so the live status reads first;
    // terminal states stay muted so stacked history cards don't shout.
    val color = when (status) {
        TimerStatus.running, TimerStatus.paused -> MaterialTheme.colorScheme.primary
        TimerStatus.completed, TimerStatus.canceled -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, color = color)
}

/**
 * A pending confirmation for a timer action. Clone, Cancel, and Remove never
 * execute straight from the card — each opens an [AlertDialog] first. Clone is
 * non-destructive (it keeps the source timer); Cancel and Remove are
 * destructive and shown with destructive styling.
 */
private data class ConfirmRequest(
    val intent: ShootingIntent,
    val title: String,
    val message: String,
    val confirmLabel: String,
    val destructive: Boolean,
)

private fun cloneConfirm(id: UUID) = ConfirmRequest(
    intent = ShootingIntent.Clone(id),
    title = "Clone timer",
    message = "Start a new timer with the same settings. This timer will stay unchanged.",
    confirmLabel = "Clone",
    destructive = false,
)

private fun cancelConfirm(id: UUID) = ConfirmRequest(
    intent = ShootingIntent.Cancel(id),
    title = "Cancel timer",
    message = "This timer will be marked as canceled and moved to history.",
    confirmLabel = "Cancel timer",
    destructive = true,
)

private fun removeConfirm(id: UUID) = ConfirmRequest(
    intent = ShootingIntent.Remove(id),
    title = "Remove timer",
    message = "This timer record will be removed.",
    confirmLabel = "Remove",
    destructive = true,
)

private fun clearCompletedConfirm() = ConfirmRequest(
    intent = ShootingIntent.ClearCompleted,
    title = "Clear completed timers?",
    message = "Completed timer records will be removed. Canceled timers will be kept.",
    confirmLabel = "Clear",
    destructive = true,
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CardActions(
    card: TimerCardState,
    onEvent: (ShootingIntent) -> Unit,
    onConfirm: (ConfirmRequest) -> Unit,
) {
    // FlowRow so the paused set (Resume, Clone, Cancel, Remove) wraps instead of
    // clipping on a narrow card. Pause/Resume run immediately; Clone, Cancel and
    // Remove are routed through a confirmation dialog.
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        when (card.status) {
            TimerStatus.running -> {
                CompactFilledAction("Pause") { onEvent(ShootingIntent.Pause(card.id)) }
                CompactOutlinedAction("Clone") { onConfirm(cloneConfirm(card.id)) }
                CompactOutlinedAction("Cancel") { onConfirm(cancelConfirm(card.id)) }
            }
            TimerStatus.paused -> {
                CompactFilledAction("Resume") { onEvent(ShootingIntent.Resume(card.id)) }
                CompactOutlinedAction("Clone") { onConfirm(cloneConfirm(card.id)) }
                CompactOutlinedAction("Cancel") { onConfirm(cancelConfirm(card.id)) }
                CompactOutlinedAction("Remove") { onConfirm(removeConfirm(card.id)) }
            }
            TimerStatus.completed, TimerStatus.canceled -> {
                CompactFilledAction("Clone") { onConfirm(cloneConfirm(card.id)) }
                CompactOutlinedAction("Remove") { onConfirm(removeConfirm(card.id)) }
            }
        }
    }
}

// Compact action buttons keep the timer-card action row dense (closer to the
// iOS small-control weight): reduced height + horizontal padding, no oversized
// pill, while staying readable with a reasonable tap target. Action policy is
// unchanged — these are styling-only wrappers.
private val CompactActionPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)
private val CompactActionMinHeight = 34.dp

@Composable
private fun CompactFilledAction(text: String, onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        contentPadding = CompactActionPadding,
        modifier = Modifier.defaultMinSize(minWidth = 0.dp, minHeight = CompactActionMinHeight),
    ) { Text(text, style = MaterialTheme.typography.labelLarge) }
}

@Composable
private fun CompactOutlinedAction(text: String, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        contentPadding = CompactActionPadding,
        modifier = Modifier.defaultMinSize(minWidth = 0.dp, minHeight = CompactActionMinHeight),
    ) { Text(text, style = MaterialTheme.typography.labelLarge) }
}

/**
 * A presentation clock that advances about once per second while this
 * composable is in composition, so visible History relative-time labels
 * ("just now" -> "1 min ago" -> "1 hr ago" ...) refresh even when no timer
 * is running and the coordinator has stopped ticking [state.now].
 *
 * Seeded from [fallback] (the coordinator's last published now) so it never
 * reads behind the model. Presentation-only: it does not call
 * [ShootingViewModel.tick], keep the coordinator running, or persist — and
 * it stops as soon as the hosting UI leaves composition. Ticking is gated on
 * [enabled] so an active-only workspace (already driven by the coordinator)
 * does not recompose every second for nothing.
 */
@Composable
private fun rememberPresentationNow(fallback: Instant, enabled: Boolean): Instant {
    var tick by remember { mutableStateOf(fallback) }
    LaunchedEffect(enabled) {
        if (!enabled) return@LaunchedEffect
        while (true) {
            tick = Instant.now()
            delay(1000)
        }
    }
    return maxOf(tick, fallback)
}

internal fun relativeTime(instant: Instant, now: Instant): String {
    val seconds = java.time.Duration.between(instant, now).seconds
    return when {
        seconds < 5 -> "just now"
        seconds < 60 -> "${seconds}s ago"
        seconds < 3600 -> "${seconds / 60}m ago"
        seconds < 86400 -> "${seconds / 3600}h ago"
        else -> "${seconds / 86400}d ago"
    }
}

/**
 * Long relative time for the full history line, matching the iOS regular
 * wording (just now / N min ago / N hr ago / N day(s) ago) so the
 * Completed/Canceled copy does not diverge across platforms.
 */
internal fun relativeTimeLong(instant: Instant, now: Instant): String {
    val seconds = java.time.Duration.between(instant, now).seconds
    return when {
        seconds < 60 -> "just now"
        seconds < 3600 -> "${seconds / 60} min ago"
        seconds < 86400 -> "${seconds / 3600} hr ago"
        else -> {
            val days = seconds / 86400
            "$days ${if (days == 1L) "day" else "days"} ago"
        }
    }
}
