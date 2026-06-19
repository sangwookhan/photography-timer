package com.sangwook.ptimer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.calculator.StartActionState
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.details.DetailsUi
import com.sangwook.ptimer.timer.TimerItemUi
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import com.sangwook.ptimer.vm.FilmRowUi
import com.sangwook.ptimer.vm.ShootingIntent
import com.sangwook.ptimer.vm.SlotsUiState

/**
 * Functional shooting screen organized into the iOS hierarchy: camera/slot
 * header, film + model, target shutter, base + ND, result (adjusted /
 * reciprocity / corrected, each with its own start), then active + completed
 * timers. Sectioned cards (not one giant card) and safe-area insets so the
 * title clears the status bar / camera cutout. Functional clarity over polish.
 */
@Composable
fun ShootingScreen(
    slots: SlotsUiState,
    calc: CalculatorUiState,
    films: List<FilmRowUi>,
    timers: TimerWorkspaceUiState,
    details: DetailsUi?,
    onEvent: (ShootingIntent) -> Unit,
    ready: Boolean = true,
    exactAlarmPromptVisible: Boolean = false,
    onOpenExactAlarmSettings: () -> Unit = {},
) {
    Box(Modifier.fillMaxSize()) {
        details?.let { DetailsDialog(it, onEvent) }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .testTag(TestTags.SHOOTING_SCREEN)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 12.dp),
        ) {
            if (exactAlarmPromptVisible) {
                item { ExactAlarmNotice(onOpenSettings = onOpenExactAlarmSettings, onDismiss = { onEvent(ShootingIntent.DismissExactAlarmPrompt) }) }
            }
            item { Text(slots.activeLabel, style = MaterialTheme.typography.headlineSmall) }
            item { SlotBar(slots, onEvent) }
            item { FilmModelSection(calc, films, onEvent) }
            item { TargetSection(calc, onEvent) }
            item { BaseNdSection(calc, onEvent) }
            item { ResultSection(calc, onEvent) }
            item { CustomFilmRow(onEvent) }

            if (timers.active.isNotEmpty()) {
                item { SectionLabel("Active") }
                items(timers.active, key = { it.id }) { TimerCard(it, completed = false, onEvent) }
            }
            if (timers.completed.isNotEmpty()) {
                item {
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                        SectionLabel("Recently completed")
                        TextButton(onClick = { onEvent(ShootingIntent.ClearCompleted) }) { Text("Clear") }
                    }
                }
                items(timers.completed, key = { it.id }) { TimerCard(it, completed = true, onEvent) }
            }
        }

        // While restore is in progress the ViewModel ignores intents; surface
        // that with a blocking overlay so input isn't silently dropped.
        if (!ready) RestoringOverlay()
    }
}

/** Simple blocking overlay shown until ShootingViewModel.ready becomes true. */
@Composable
private fun RestoringOverlay() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .testTag(TestTags.RESTORING_OVERLAY)
            .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.4f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { /* swallow input while restoring */ },
        contentAlignment = Alignment.Center,
    ) {
        Surface(shape = RoundedCornerShape(12.dp), tonalElevation = 4.dp) {
            Text("Restoring…", Modifier.padding(24.dp), style = MaterialTheme.typography.titleMedium)
        }
    }
}

/** Compact, dismissible reliability notice shown when exact alarms are not permitted. */
@Composable
private fun ExactAlarmNotice(onOpenSettings: () -> Unit, onDismiss: () -> Unit) {
    Card(Modifier.fillMaxWidth().testTag(TestTags.EXACT_ALARM_NOTICE), colors = whiteCardColors()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "For more reliable background timer alerts, allow exact alarms.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onOpenSettings) { Text("Open settings") }
                TextButton(onClick = onDismiss) { Text("Not now") }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) = Text(text, style = MaterialTheme.typography.titleMedium)

// MARK: - Camera / slot header

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
        if (activeId != null) TextButton(onClick = { onEvent(ShootingIntent.ResetSlotName(activeId)) }) { Text("Reset") }
    }

    if (renaming && activeId != null) {
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Rename ${slots.activeLabel}") },
            text = { OutlinedTextField(draftName, { draftName = it }, singleLine = true) },
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

// MARK: - Film + model

@Composable
private fun FilmModelSection(calc: CalculatorUiState, films: List<FilmRowUi>, onEvent: (ShootingIntent) -> Unit) {
    SectionCard("Film") {
        FilmSelector(calc, films, onEvent)
        if (calc.availableModels.isNotEmpty()) ModelSelector(calc, onEvent)
        // Custom-film extras stay with the film, not the result rows.
        calc.fittedPreviewSummary?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        if (calc.isCustomTable) {
            TextButton(onClick = { onEvent(ShootingIntent.CreateFormulaFromSelectedTable) }) {
                Text("Create formula from this table")
            }
        }
        calc.selectedCustomFilmId?.let { id ->
            TextButton(onClick = { onEvent(ShootingIntent.DeleteCustomFilm(id)) }) { Text("Delete custom film") }
        }
    }
}

@Composable
private fun FilmSelector(calc: CalculatorUiState, films: List<FilmRowUi>, onEvent: (ShootingIntent) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(calc.filmName ?: "No film (digital)", style = MaterialTheme.typography.titleMedium)
                calc.authorityLabel?.let { Text(it, style = MaterialTheme.typography.labelSmall) }
            }
            OutlinedButton(onClick = { expanded = true }) { Text("Choose") }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("No film (digital)") }, onClick = {
                onEvent(ShootingIntent.ClearFilm); expanded = false
            })
            films.forEach { film ->
                val suffix = if (film.isCustom) " · custom" else ""
                DropdownMenuItem(text = { Text("${film.name} · ISO ${film.iso}$suffix") }, onClick = {
                    onEvent(ShootingIntent.SelectFilm(film.id)); expanded = false
                })
            }
        }
    }
}

@Composable
private fun ModelSelector(calc: CalculatorUiState, onEvent: (ShootingIntent) -> Unit) {
    // iOS-style segmented model picker (replaces the dropdown).
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        calc.availableModels.forEachIndexed { index, model ->
            SegmentedButton(
                selected = model.isSelected,
                onClick = { onEvent(ShootingIntent.SelectModel(if (index == 0) null else model.profileId)) },
                shape = SegmentedButtonDefaults.itemShape(index, calc.availableModels.size),
            ) { Text(model.label, style = MaterialTheme.typography.labelMedium) }
        }
    }
}

// MARK: - Target shutter

@Composable
private fun TargetSection(calc: CalculatorUiState, onEvent: (ShootingIntent) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    SectionCard("Target shutter") {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text(calc.targetSummary ?: "Off", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { draft = ""; editing = true }) { Text("Set") }
                if (calc.targetSeconds != null) {
                    OutlinedButton(onClick = { onEvent(ShootingIntent.ClearTarget) }) { Text("Clear") }
                }
                if (calc.targetAction != null) {
                    PlayButton(enabled = calc.targetAction.enabled) { onEvent(ShootingIntent.StartTarget) }
                }
            }
        }
    }
    if (editing) {
        AlertDialog(
            onDismissRequest = { editing = false },
            title = { Text("Target shutter (seconds)") },
            text = { OutlinedTextField(draft, { draft = it }, singleLine = true, label = { Text("seconds") }) },
            confirmButton = {
                TextButton(onClick = { draft.toDoubleOrNull()?.let { onEvent(ShootingIntent.SetTarget(it)) }; editing = false }) { Text("Set") }
            },
            dismissButton = { TextButton(onClick = { editing = false }) { Text("Cancel") } },
        )
    }
}

// MARK: - Base shutter + ND

@Composable
private fun BaseNdSection(calc: CalculatorUiState, onEvent: (ShootingIntent) -> Unit) {
    SectionCard("Base shutter + ND") {
        Stepper("Base shutter", calc.baseShutterLabel,
            onMinus = { onEvent(ShootingIntent.NudgeBaseShutter(-1)) },
            onPlus = { onEvent(ShootingIntent.NudgeBaseShutter(1)) })
        Stepper("ND stops", calc.ndStops.toString(),
            onMinus = { onEvent(ShootingIntent.SetNdStops(calc.ndStops - 1)) },
            onPlus = { onEvent(ShootingIntent.SetNdStops(calc.ndStops + 1)) },
            plusTag = TestTags.ND_PLUS_BUTTON)
    }
}

@Composable
private fun Stepper(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit, plusTag: String? = null) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text("$label: $value", Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onMinus) { Text("−") }
            val plusModifier = if (plusTag != null) Modifier.testTag(plusTag) else Modifier
            OutlinedButton(onClick = onPlus, modifier = plusModifier) { Text("+") }
        }
    }
}

// MARK: - Result (adjusted / reciprocity / corrected)

@Composable
private fun ResultSection(calc: CalculatorUiState, onEvent: (ShootingIntent) -> Unit) {
    SectionCard("Result") {
        ResultActionRow("Adjusted shutter", calc.adjustedShutterLabel, calc.adjustedAction, buttonTag = TestTags.START_ADJUSTED_BUTTON) {
            onEvent(ShootingIntent.StartAdjusted)
        }
        if (calc.filmName != null) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text("Reciprocity")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    calc.reciprocityBadge?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
                    TextButton(onClick = { onEvent(ShootingIntent.OpenDetails) }) { Text("Details") }
                }
            }
            val corrected = calc.correctedAction
            ResultActionRow(
                "Corrected exposure",
                calc.correctedExposureLabel ?: (corrected?.disabledReason ?: "Unavailable"),
                corrected,
            ) { onEvent(ShootingIntent.StartCorrected) }
        }
    }
}

@Composable
private fun ResultActionRow(label: String, value: String, action: StartActionState?, buttonTag: String? = null, onStart: () -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(value, fontWeight = FontWeight.Bold)
        }
        PlayButton(enabled = action?.enabled == true, tag = buttonTag, onStart = onStart)
    }
}

/** iOS-style filled circular play action. */
@Composable
private fun PlayButton(enabled: Boolean, tag: String? = null, onStart: () -> Unit) {
    val modifier = if (tag != null) Modifier.testTag(tag) else Modifier
    FilledIconButton(onClick = onStart, enabled = enabled, modifier = modifier) { Text("▶") }
}

// MARK: - Custom film actions (low priority)

@Composable
private fun CustomFilmRow(onEvent: (ShootingIntent) -> Unit) {
    var newFormula by remember { mutableStateOf(false) }
    var newTable by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
        Text("Custom films", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium)
        TextButton(onClick = { newFormula = true }) { Text("New formula") }
        TextButton(onClick = { newTable = true }) { Text("New table") }
    }
    if (newFormula) NewFormulaDialog(onDismiss = { newFormula = false }, onCreate = { n, e, nc ->
        onEvent(ShootingIntent.CreateCustomFormula(n, e, nc)); newFormula = false
    })
    if (newTable) NewTableDialog(onDismiss = { newTable = false }, onCreate = { n, anchors ->
        onEvent(ShootingIntent.CreateCustomTable(n, anchors)); newTable = false
    })
}

// MARK: - Timer cards (vertical so long names never clip the actions)

@Composable
private fun TimerCard(item: TimerItemUi, completed: Boolean, onEvent: (ShootingIntent) -> Unit) {
    val rowModifier = Modifier.fillMaxWidth().let { if (!completed) it.testTag(TestTags.ACTIVE_TIMER_ROW) else it }
    Card(rowModifier, colors = whiteCardColors()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text(item.title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                StatusPill(item.statusLabel)
            }
            Text(item.subtitle, style = MaterialTheme.typography.bodySmall)
            if (item.metadata.isNotBlank()) Text(item.metadata, style = MaterialTheme.typography.labelSmall)
            Text(item.remainingLabel, style = MaterialTheme.typography.headlineMedium)
            item.endsAtLabel?.let { Text(it, style = MaterialTheme.typography.labelSmall) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (completed) {
                    OutlinedButton(onClick = { onEvent(ShootingIntent.StartAgain(item.id)) }) { Text("Start again") }
                } else {
                    if (item.status == TimerStatus.RUNNING) {
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Pause(item.id)) }) { Text("Pause") }
                    } else {
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Resume(item.id)) }) { Text("Resume") }
                    }
                    OutlinedButton(onClick = { onEvent(ShootingIntent.StartNew(item.id)) }) { Text("Start new") }
                }
                OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(item.id)) }) { Text("Remove") }
            }
        }
    }
}

@Composable
private fun StatusPill(label: String) {
    val color = when (label) {
        "Running" -> MaterialTheme.colorScheme.primary
        "Paused" -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.outline
    }
    Surface(color = color.copy(alpha = 0.15f), shape = RoundedCornerShape(50)) {
        Text(label, Modifier.padding(horizontal = 10.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, color = color)
    }
}

// MARK: - shared

@Composable
private fun whiteCardColors() = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth(), colors = whiteCardColors()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            content()
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
