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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.calculator.StartActionState
import com.sangwook.ptimer.details.DetailsUi
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.timer.TimerItemUi
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import com.sangwook.ptimer.vm.FilmRowUi
import com.sangwook.ptimer.vm.ShootingIntent
import com.sangwook.ptimer.vm.SlotsUiState

/**
 * Minimal, functional shooting screen: a calculator section (base shutter,
 * ND, film + model selection, adjusted/corrected results, Start Timer) above
 * the timer list. Behavior over polish.
 */
@Composable
fun ShootingScreen(
    slots: SlotsUiState,
    calc: CalculatorUiState,
    films: List<FilmRowUi>,
    timers: TimerWorkspaceUiState,
    details: DetailsUi?,
    onEvent: (ShootingIntent) -> Unit,
) {
    details?.let { DetailsDialog(it, onEvent) }
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Text("PTimer · ${slots.activeLabel}", style = MaterialTheme.typography.headlineSmall) }
        item { SlotBar(slots, onEvent) }
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
private fun SlotBar(slots: SlotsUiState, onEvent: (ShootingIntent) -> Unit) {
    var renaming by remember { mutableStateOf(false) }
    var draftName by remember { mutableStateOf("") }
    val activeId = slots.slots.firstOrNull { it.isActive }?.id

    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
        slots.slots.forEach { slot ->
            FilterChip(
                selected = slot.isActive,
                onClick = { onEvent(ShootingIntent.SelectSlot(slot.id)) },
                label = { Text(slot.label) },
            )
        }
        TextButton(onClick = { draftName = slots.activeLabel; renaming = true }) { Text("Rename") }
    }

    if (renaming && activeId != null) {
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Rename ${slots.activeLabel}") },
            text = {
                OutlinedTextField(value = draftName, onValueChange = { draftName = it }, singleLine = true)
            },
            confirmButton = {
                TextButton(onClick = { onEvent(ShootingIntent.RenameSlot(activeId, draftName)); renaming = false }) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(onClick = { onEvent(ShootingIntent.ResetSlotName(activeId)); renaming = false }) {
                    Text("Reset")
                }
            },
        )
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

            // Adjusted shutter — its own start.
            ResultActionRow("Adjusted shutter", calc.adjustedShutterLabel, calc.adjustedAction) {
                onEvent(ShootingIntent.StartAdjusted)
            }

            if (calc.filmName != null) {
                // Reciprocity — basis badge + details, no start.
                Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    Text("Reciprocity")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        calc.reciprocityBadge?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
                        TextButton(onClick = { onEvent(ShootingIntent.OpenDetails) }) { Text("Details") }
                    }
                }
                // Corrected exposure — its own start; disabled (with reason) when non-quantified.
                val corrected = calc.correctedAction
                ResultActionRow(
                    "Corrected exposure",
                    calc.correctedExposureLabel ?: (corrected?.disabledReason ?: "Unavailable"),
                    corrected,
                ) { onEvent(ShootingIntent.StartCorrected) }
            }

            calc.fittedPreviewSummary?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            if (calc.isCustomTable) {
                OutlinedButton(onClick = { onEvent(ShootingIntent.CreateFormulaFromSelectedTable) }) {
                    Text("Create formula from this table")
                }
            }
            calc.selectedCustomFilmId?.let { id ->
                OutlinedButton(onClick = { onEvent(ShootingIntent.DeleteCustomFilm(id)) }) { Text("Delete custom film") }
            }

            TargetSection(calc, onEvent)

            CustomFilmCreators(onEvent)
        }
    }
}

@Composable
private fun DetailsDialog(details: DetailsUi, onEvent: (ShootingIntent) -> Unit) {
    AlertDialog(
        onDismissRequest = { onEvent(ShootingIntent.CloseDetails) },
        title = { Text(details.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                details.rows.forEach { row ->
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
                        Text(row.label, style = MaterialTheme.typography.bodySmall)
                        Text(row.value, style = MaterialTheme.typography.bodySmall)
                    }
                }
                details.comparisonTitle?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
                details.comparisonLines.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = { TextButton(onClick = { onEvent(ShootingIntent.CloseDetails) }) { Text("Close") } },
    )
}

@Composable
private fun TargetSection(calc: CalculatorUiState, onEvent: (ShootingIntent) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(calc.targetSummary ?: "Target shutter: none", style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (calc.targetAction != null) {
                Button(onClick = { onEvent(ShootingIntent.StartTarget) }, enabled = calc.targetAction.enabled) { Text("Start") }
            }
            OutlinedButton(onClick = { draft = ""; editing = true }) { Text("Set") }
            if (calc.targetSeconds != null) {
                OutlinedButton(onClick = { onEvent(ShootingIntent.ClearTarget) }) { Text("Clear") }
            }
        }
    }
    if (editing) {
        AlertDialog(
            onDismissRequest = { editing = false },
            title = { Text("Target shutter (seconds)") },
            text = { OutlinedTextField(draft, { draft = it }, singleLine = true, label = { Text("seconds") }) },
            confirmButton = {
                TextButton(onClick = {
                    draft.toDoubleOrNull()?.let { onEvent(ShootingIntent.SetTarget(it)) }; editing = false
                }) { Text("Set") }
            },
            dismissButton = { TextButton(onClick = { editing = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun CustomFilmCreators(onEvent: (ShootingIntent) -> Unit) {
    var newFormula by remember { mutableStateOf(false) }
    var newTable by remember { mutableStateOf(false) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { newFormula = true }) { Text("New custom formula") }
        OutlinedButton(onClick = { newTable = true }) { Text("New custom table") }
    }
    if (newFormula) NewFormulaDialog(onDismiss = { newFormula = false }, onCreate = { n, e, nc ->
        onEvent(ShootingIntent.CreateCustomFormula(n, e, nc)); newFormula = false
    })
    if (newTable) NewTableDialog(onDismiss = { newTable = false }, onCreate = { n, anchors ->
        onEvent(ShootingIntent.CreateCustomTable(n, anchors)); newTable = false
    })
}

@Composable
private fun NewFormulaDialog(onDismiss: () -> Unit, onCreate: (String, Double, Double) -> Unit) {
    var name by remember { mutableStateOf("My formula") }
    var exponent by remember { mutableStateOf("1.3") }
    var noCorrection by remember { mutableStateOf("1") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New custom formula") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
                OutlinedTextField(exponent, { exponent = it }, label = { Text("Exponent p") }, singleLine = true)
                OutlinedTextField(noCorrection, { noCorrection = it }, label = { Text("No correction through (s)") }, singleLine = true)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val e = exponent.toDoubleOrNull(); val nc = noCorrection.toDoubleOrNull()
                if (e != null && nc != null) onCreate(name, e, nc)
            }) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun NewTableDialog(onDismiss: () -> Unit, onCreate: (String, List<Pair<Double, Double>>) -> Unit) {
    var name by remember { mutableStateOf("My table") }
    val rows = remember { mutableStateListOf("1" to "2", "10" to "80") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New custom table") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
                rows.forEachIndexed { i, (m, c) ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(m, { rows[i] = it to rows[i].second }, label = { Text("metered s") }, singleLine = true, modifier = Modifier.weight(1f))
                        OutlinedTextField(c, { rows[i] = rows[i].first to it }, label = { Text("corrected s") }, singleLine = true, modifier = Modifier.weight(1f))
                    }
                }
                TextButton(onClick = { rows.add("" to "") }) { Text("Add anchor") }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val anchors = rows.mapNotNull { (m, c) ->
                    val mm = m.toDoubleOrNull(); val cc = c.toDoubleOrNull()
                    if (mm != null && cc != null) mm to cc else null
                }
                if (anchors.size >= 2) onCreate(name, anchors)
            }) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
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
private fun ResultActionRow(label: String, value: String, action: StartActionState?, onStart: () -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(value, fontWeight = FontWeight.Bold)
        }
        Button(onClick = onStart, enabled = action?.enabled == true) { Text("Start") }
    }
}

@Composable
private fun ActiveTimerCard(item: TimerItemUi, onEvent: (ShootingIntent) -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(item.title, style = MaterialTheme.typography.titleMedium)
            Text(item.subtitle, style = MaterialTheme.typography.bodySmall)
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
            Column(Modifier.weight(1f)) {
                Text(item.title, style = MaterialTheme.typography.titleMedium)
                Text(item.subtitle, style = MaterialTheme.typography.bodySmall)
                Text("Done", style = MaterialTheme.typography.bodyMedium)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { onEvent(ShootingIntent.StartAgain(item.id)) }) { Text("Start again") }
                OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(item.id)) }) { Text("Remove") }
            }
        }
    }
}
