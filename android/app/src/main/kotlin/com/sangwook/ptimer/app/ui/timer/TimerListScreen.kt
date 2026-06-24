package com.sangwook.ptimer.app.ui.timer

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
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

private val calc = ExposureCalculator()
private val endFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault())

/**
 * Tier-1 clone of the iOS timer-list full screen: an Active section
 * (running/paused) above a History section (completed/canceled). The Add
 * action is a temporary entry to start a timer until the calculator (unit 7)
 * provides real durations.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimerListScreen(
    state: ShootingUiState,
    onEvent: (ShootingIntent) -> Unit,
    onStartSample: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text("Timers") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = onStartSample) {
                Text("+", style = MaterialTheme.typography.headlineSmall)
            }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (state.active.isEmpty() && state.history.isEmpty()) {
                item { EmptyState() }
            }
            if (state.active.isNotEmpty()) {
                item { SectionHeader("Active") }
                items(state.active, key = { it.id }) { card ->
                    TimerCard(card, state.now, onEvent)
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

@Composable
private fun TimerCard(
    card: TimerCardState,
    now: Instant,
    onEvent: (ShootingIntent) -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
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
                    if (card.identity.slotLabel.isNotEmpty()) {
                        Text(card.identity.slotLabel, style = MaterialTheme.typography.labelMedium)
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
