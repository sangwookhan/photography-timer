package com.sangwook.ptimer.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.timer.TimerItemUi
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import com.sangwook.ptimer.vm.ShootingIntent

/**
 * Minimal, functional timer workspace UI for the first runnable increment.
 * Behavior over polish: start fixed-duration timers, watch them count down,
 * pause/resume/remove, and Start Again completed ones. The calculator-driven
 * Start Timer flow arrives in a later slice.
 */
@Composable
fun TimerWorkspaceScreen(
    state: TimerWorkspaceUiState,
    onEvent: (ShootingIntent) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("PTimer", style = MaterialTheme.typography.headlineSmall)

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(10.0, 30.0, 60.0).forEach { seconds ->
                Button(onClick = { onEvent(ShootingIntent.StartTimer("${seconds.toInt()}s timer", seconds)) }) {
                    Text("Start ${seconds.toInt()}s")
                }
            }
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (state.active.isNotEmpty()) {
                item { SectionHeader("Active") }
                items(state.active, key = { it.id }) { item ->
                    ActiveTimerCard(item, onEvent)
                }
            }
            if (state.completed.isNotEmpty()) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SectionHeader("Recently completed")
                        OutlinedButton(onClick = { onEvent(ShootingIntent.ClearCompleted) }) { Text("Clear") }
                    }
                }
                items(state.completed, key = { it.id }) { item ->
                    CompletedTimerCard(item, onEvent)
                }
            }
            if (state.active.isEmpty() && state.completed.isEmpty()) {
                item { Text("No timers yet. Start one above.", style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium)
}

@Composable
private fun ActiveTimerCard(item: TimerItemUi, onEvent: (ShootingIntent) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(item.name, style = MaterialTheme.typography.titleMedium)
            Text(item.remainingLabel, style = MaterialTheme.typography.headlineMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (item.status == TimerStatus.RUNNING) {
                    OutlinedButton(onClick = { onEvent(ShootingIntent.Pause(item.id)) }) { Text("Pause") }
                } else {
                    OutlinedButton(onClick = { onEvent(ShootingIntent.Resume(item.id)) }) { Text("Resume") }
                }
                OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(item.id)) }) { Text("Remove") }
            }
        }
    }
}

@Composable
private fun CompletedTimerCard(item: TimerItemUi, onEvent: (ShootingIntent) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(item.name, style = MaterialTheme.typography.titleMedium)
                Text("Done", style = MaterialTheme.typography.bodyMedium)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { onEvent(ShootingIntent.StartAgain(item.id)) }) { Text("Start again") }
                OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(item.id)) }) { Text("Remove") }
            }
        }
    }
}
