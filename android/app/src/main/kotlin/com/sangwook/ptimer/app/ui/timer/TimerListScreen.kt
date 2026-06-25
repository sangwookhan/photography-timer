package com.sangwook.ptimer.app.ui.timer

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingUiState
import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.timer.TimerStatus
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
            MiniTimerCard(card, state.now) { onOpen(card.id) }
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
    modifier: Modifier = Modifier,
) {
    val activeReversed = state.active.asReversed()
    val listState = rememberLazyListState()
    // When the user taps a mini card, bring its full card into view (the row at
    // index 0 is the header) and highlight it. For the first active card, anchor
    // on the header so the close X stays visible.
    LaunchedEffect(focusId, activeReversed.size) {
        if (focusId == null) return@LaunchedEffect
        val pos = activeReversed.indexOfFirst { it.id == focusId }
        if (pos < 0) return@LaunchedEffect
        listState.animateScrollToItem(if (pos == 0) 0 else pos + 1)
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
                TimerCard(card, state.now, onEvent, highlighted = card.id == focusId)
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
                    TextButton(onClick = {
                        state.history.forEach { onEvent(ShootingIntent.Remove(it.id)) }
                    }) { Text("Clear") }
                }
            }
            items(state.history, key = { it.id }) { card ->
                TimerCard(card, state.now, onEvent)
            }
        }
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
 * Compact, display-only card for an active timer in the bottom-sheet peek row:
 * title + slot, the remaining countdown, and a paused hint. Tapping it expands
 * the sheet to [FullTimerList], where Pause/Resume/Cancel live.
 */
@Composable
private fun MiniTimerCard(card: TimerCardState, now: Instant, onClick: () -> Unit) {
    val terminal = card.status == TimerStatus.completed || card.status == TimerStatus.canceled
    // Tall portrait card (iOS compact dock proportions) rather than a wide
    // landscape strip: status on top, the countdown (or, once finished, the
    // relative completion time) centred, the slot at foot.
    Card(
        modifier = Modifier.width(96.dp).height(116.dp).clickable { onClick() },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(12.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                when (card.status) {
                    TimerStatus.running -> "Running"
                    TimerStatus.paused -> "Paused"
                    TimerStatus.completed -> "Done"
                    TimerStatus.canceled -> "Canceled"
                },
                style = MaterialTheme.typography.labelSmall,
                color = if (terminal) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.primary,
                maxLines = 1,
            )
            Text(
                if (terminal) relativeTime(card.endDate, now)
                else calc.formatExtendedClock(card.remainingSeconds),
                style = MaterialTheme.typography.titleMedium,
                fontFamily = if (terminal) FontFamily.Default else FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 1,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                card.identity.slotLabel,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
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

@Composable
private fun TimerCard(
    card: TimerCardState,
    now: Instant,
    onEvent: (ShootingIntent) -> Unit,
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

            // Primary line: countdown for active timers, terminal label for history.
            val primary = when (card.status) {
                TimerStatus.running, TimerStatus.paused -> calc.formatExtendedClock(card.remainingSeconds)
                TimerStatus.completed -> "Done"
                TimerStatus.canceled -> "Canceled · ${calc.formatExtendedClock(card.remainingAtCancelSeconds ?: 0.0)} left"
            }
            Text(
                primary,
                style = MaterialTheme.typography.headlineMedium,
                fontFamily = FontFamily.Monospace,
            )

            val secondary = when (card.status) {
                TimerStatus.running -> "Ends ${endFormatter.format(card.endDate)}"
                TimerStatus.paused -> "Paused"
                TimerStatus.completed -> "Completed ${relativeTime(card.endDate, now)}"
                TimerStatus.canceled -> "Canceled ${relativeTime(card.endDate, now)}"
            }
            Text(
                secondary,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (card.identity.baseLine.isNotEmpty()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        card.identity.baseLine,
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
            CardActions(card, onEvent)
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
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun CardActions(card: TimerCardState, onEvent: (ShootingIntent) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        when (card.status) {
            TimerStatus.running -> {
                FilledTonalButton(onClick = { onEvent(ShootingIntent.Pause(card.id)) }) { Text("Pause") }
                OutlinedButton(onClick = { onEvent(ShootingIntent.StartAgain(card.id)) }) { Text("Start New") }
            }
            TimerStatus.paused -> {
                FilledTonalButton(onClick = { onEvent(ShootingIntent.Resume(card.id)) }) { Text("Resume") }
                OutlinedButton(onClick = { onEvent(ShootingIntent.Cancel(card.id)) }) { Text("Cancel") }
            }
            TimerStatus.completed, TimerStatus.canceled -> {
                FilledTonalButton(onClick = { onEvent(ShootingIntent.StartAgain(card.id)) }) { Text("Start Again") }
                OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(card.id)) }) { Text("Remove") }
            }
        }
    }
}

private fun relativeTime(instant: Instant, now: Instant): String {
    val seconds = java.time.Duration.between(instant, now).seconds
    return when {
        seconds < 5 -> "just now"
        seconds < 60 -> "${seconds}s ago"
        seconds < 3600 -> "${seconds / 60}m ago"
        seconds < 86400 -> "${seconds / 3600}h ago"
        else -> "${seconds / 86400}d ago"
    }
}
