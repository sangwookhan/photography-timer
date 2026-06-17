package com.sangwook.ptimer.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.timer.TimerItemUi
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import com.sangwook.ptimer.vm.FilmRowUi
import com.sangwook.ptimer.vm.ShootingIntent

/**
 * Minimal, functional shooting screen: a calculator section (base shutter,
 * ND, film + model selection, adjusted/corrected results, Start Timer) above
 * the timer list. Behavior over polish.
 */
@Composable
fun ShootingScreen(
    calc: CalculatorUiState,
    films: List<FilmRowUi>,
    timers: TimerWorkspaceUiState,
    onEvent: (ShootingIntent) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Text("PTimer", style = MaterialTheme.typography.headlineSmall) }
        item { CalculatorCard(calc, films, onEvent) }

        if (timers.active.isNotEmpty()) {
            item { Text("Active", style = MaterialTheme.typography.titleMedium) }
            items(timers.active, key = { it.id }) { ActiveTimerCard(it, onEvent) }
        }
        if (timers.completed.isNotEmpty()) {
            item {
                Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    Text("Recently completed", style = MaterialTheme.typography.titleMedium)
                    OutlinedButton(onClick = { onEvent(ShootingIntent.ClearCompleted) }) { Text("Clear") }
                }
            }
            items(timers.completed, key = { it.id }) { CompletedTimerCard(it, onEvent) }
        }
    }
}

@Composable
private fun CalculatorCard(calc: CalculatorUiState, films: List<FilmRowUi>, onEvent: (ShootingIntent) -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Stepper("Base shutter", calc.baseShutterLabel,
                onMinus = { onEvent(ShootingIntent.NudgeBaseShutter(-1)) },
                onPlus = { onEvent(ShootingIntent.NudgeBaseShutter(1)) })
            Stepper("ND stops", calc.ndStops.toString(),
                onMinus = { onEvent(ShootingIntent.SetNdStops(calc.ndStops - 1)) },
                onPlus = { onEvent(ShootingIntent.SetNdStops(calc.ndStops + 1)) })

            FilmSelector(calc, films, onEvent)
            if (calc.availableModels.isNotEmpty()) ModelSelector(calc, onEvent)

            ResultRow("Adjusted shutter", calc.adjustedShutterLabel)
            if (calc.filmName != null) {
                ResultRow("Corrected exposure", calc.correctedExposureLabel ?: "—")
                calc.reciprocityBadge?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
            }

            Button(onClick = { onEvent(ShootingIntent.StartFromResult) }, enabled = calc.canStartTimer) {
                Text("Start timer")
            }
            if (!calc.canStartTimer) calc.startDisabledHint?.let {
                Text(it, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun Stepper(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text("$label: $value")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onMinus) { Text("−") }
            OutlinedButton(onClick = onPlus) { Text("+") }
        }
    }
}

@Composable
private fun FilmSelector(calc: CalculatorUiState, films: List<FilmRowUi>, onEvent: (ShootingIntent) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column {
                Text("Film: ${calc.filmName ?: "No film (digital)"}")
                calc.authorityLabel?.let { Text(it, style = MaterialTheme.typography.labelSmall) }
            }
            OutlinedButton(onClick = { expanded = true }) { Text("Choose") }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("No film (digital)") }, onClick = {
                onEvent(ShootingIntent.ClearFilm); expanded = false
            })
            films.forEach { film ->
                DropdownMenuItem(text = { Text("${film.name} · ISO ${film.iso}") }, onClick = {
                    onEvent(ShootingIntent.SelectFilm(film.id)); expanded = false
                })
            }
        }
    }
}

@Composable
private fun ModelSelector(calc: CalculatorUiState, onEvent: (ShootingIntent) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val selected = calc.availableModels.firstOrNull { it.isSelected }?.label ?: "Default"
    Box {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text("Model: $selected")
            OutlinedButton(onClick = { expanded = true }) { Text("Change") }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            calc.availableModels.forEachIndexed { index, model ->
                DropdownMenuItem(text = { Text(model.label) }, onClick = {
                    // index 0 is the primary profile -> null selection.
                    onEvent(ShootingIntent.SelectModel(if (index == 0) null else model.profileId))
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun ResultRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
        Text(label)
        Text(value, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun ActiveTimerCard(item: TimerItemUi, onEvent: (ShootingIntent) -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            Arrangement.SpaceBetween, Alignment.CenterVertically,
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
