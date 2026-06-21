package com.sangwook.ptimer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.text.style.TextOverflow
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
 * Material 3 shooting screen. Mirrors the iOS information architecture (camera
 * context, film + model, target shutter, base + ND, result outcomes, then
 * Active / History) but expresses it with Android-native components: a
 * [Scaffold] + [TopAppBar], grouped [ElevatedCard] sections, [FilterChip] slot
 * switching, segmented model picker, tonal stepper icon buttons, and labeled
 * Material buttons for start actions. No iOS wheels or sheet styling are cloned.
 */
@OptIn(ExperimentalMaterial3Api::class)
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
    var renaming by remember { mutableStateOf(false) }
    var renameDraft by remember { mutableStateOf("") }
    val activeSlotId = slots.slots.firstOrNull { it.isActive }?.id

    Box(Modifier.fillMaxSize()) {
        details?.let { DetailsDialog(it, onEvent) }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(slots.activeLabel) },
                    actions = {
                        TextButton(onClick = { renameDraft = slots.activeLabel; renaming = true }) {
                            Text("Rename")
                        }
                    },
                )
            },
        ) { innerPadding ->
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .testTag(TestTags.SHOOTING_SCREEN)
                    .padding(innerPadding)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                if (exactAlarmPromptVisible) {
                    item { ExactAlarmNotice(onOpenSettings = onOpenExactAlarmSettings, onDismiss = { onEvent(ShootingIntent.DismissExactAlarmPrompt) }) }
                }
                item { SlotChips(slots, onEvent) }
                item { FilmModelSection(calc, films, onEvent) }
                item { TargetSection(calc, onEvent) }
                item { BaseNdSection(calc, onEvent) }
                item { ResultSection(calc, onEvent) }
                item { CustomFilmRow(onEvent) }

                if (timers.active.isNotEmpty()) {
                    item { SectionLabel("Active") }
                    items(timers.active, key = { it.id }) { TimerCard(it, terminal = false, onEvent) }
                }
                if (timers.completed.isNotEmpty()) {
                    item {
                        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                            SectionLabel("History")
                            // Clear removes completed records only (iOS parity); canceled
                            // records stay, so the button only shows when a completed exists.
                            if (timers.completed.any { it.status == TimerStatus.COMPLETED }) {
                                TextButton(onClick = { onEvent(ShootingIntent.ClearCompleted) }) { Text("Clear") }
                            }
                        }
                    }
                    items(timers.completed, key = { it.id }) { TimerCard(it, terminal = true, onEvent) }
                }
            }
        }

        // While restore is in progress the ViewModel ignores intents; surface
        // that with a blocking overlay so input isn't silently dropped.
        if (!ready) RestoringOverlay()
    }

    if (renaming && activeSlotId != null) {
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Rename ${slots.activeLabel}") },
            text = { OutlinedTextField(renameDraft, { renameDraft = it }, singleLine = true) },
            confirmButton = {
                TextButton(onClick = { onEvent(ShootingIntent.RenameSlot(activeSlotId, renameDraft)); renaming = false }) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(onClick = { onEvent(ShootingIntent.ResetSlotName(activeSlotId)); renaming = false }) {
                    Text("Reset")
                }
            },
        )
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
    ElevatedCard(Modifier.fillMaxWidth().testTag(TestTags.EXACT_ALARM_NOTICE)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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

// MARK: - Camera / slot switcher

@Composable
private fun SlotChips(slots: SlotsUiState, onEvent: (ShootingIntent) -> Unit) {
    // Equal-weight chips fill the row so all slots stay fully visible on a
    // phone width (no horizontal clipping of the last camera).
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        slots.slots.forEach { slot ->
            FilterChip(
                modifier = Modifier.weight(1f),
                selected = slot.isActive,
                onClick = { onEvent(ShootingIntent.SelectSlot(slot.id)) },
                label = {
                    Text(
                        slot.label,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
            )
        }
    }
}

// MARK: - Film + model

@Composable
private fun FilmModelSection(calc: CalculatorUiState, films: List<FilmRowUi>, onEvent: (ShootingIntent) -> Unit) {
    SectionCard("Film") {
        FilmSelector(calc, films, onEvent)
        if (calc.availableModels.isNotEmpty()) ModelSelector(calc, onEvent)
        // Custom-film extras stay with the film, not the result rows.
        calc.fittedPreviewSummary?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
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
        Row(
            Modifier.fillMaxWidth().clickable { expanded = true },
            Arrangement.SpaceBetween,
            Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(calc.filmName ?: "No film (digital)", style = MaterialTheme.typography.titleMedium)
                calc.authorityLabel?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            TextButton(onClick = { expanded = true }) { Text(if (calc.filmName == null) "Choose" else "Change") }
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
            Text(
                calc.targetSummary ?: "Off",
                Modifier.weight(1f),
                style = MaterialTheme.typography.bodyLarge,
                color = if (calc.targetSeconds == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (calc.targetSeconds != null) {
                    TextButton(onClick = { onEvent(ShootingIntent.ClearTarget) }) { Text("Clear") }
                }
                OutlinedButton(onClick = { draft = ""; editing = true }) { Text("Set") }
                if (calc.targetAction != null) {
                    StartButton(enabled = calc.targetAction.enabled) { onEvent(ShootingIntent.StartTarget) }
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
        // Value is the focus; the inline label keeps the row to a single line so
        // the two steppers stay compact.
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            FilledTonalIconButton(onClick = onMinus, modifier = Modifier.size(36.dp)) {
                Text("−", style = MaterialTheme.typography.titleMedium)
            }
            val plusModifier = Modifier.size(36.dp).let { if (plusTag != null) it.testTag(plusTag) else it }
            FilledTonalIconButton(onClick = onPlus, modifier = plusModifier) {
                Text("+", style = MaterialTheme.typography.titleMedium)
            }
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
            HorizontalDivider()
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text("Reciprocity", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    calc.reciprocityBadge?.let { ReciprocityBadge(it) }
                    TextButton(onClick = { onEvent(ShootingIntent.OpenDetails) }) { Text("Details") }
                }
            }
            HorizontalDivider()
            val corrected = calc.correctedAction
            // Stay truthful for limited/unsupported films: show the reason
            // (never a fabricated value) and keep the start action disabled.
            val correctedValue = calc.correctedExposureLabel ?: corrected?.disabledReason ?: "No corrected value"
            val correctedUnavailable = calc.correctedExposureLabel == null
            ResultActionRow(
                "Corrected exposure",
                correctedValue,
                corrected,
                valueColor = if (correctedUnavailable) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            ) { onEvent(ShootingIntent.StartCorrected) }
        }
    }
}

@Composable
private fun ResultActionRow(
    label: String,
    value: String,
    action: StartActionState?,
    buttonTag: String? = null,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface,
    onStart: () -> Unit,
) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = valueColor)
        }
        StartButton(enabled = action?.enabled == true, tag = buttonTag, onStart = onStart)
    }
}

/** Labeled Material start action (replaces the iOS circular play glyph). */
@Composable
private fun StartButton(enabled: Boolean, tag: String? = null, onStart: () -> Unit) {
    val modifier = if (tag != null) Modifier.testTag(tag) else Modifier
    FilledTonalButton(onClick = onStart, enabled = enabled, modifier = modifier) { Text("Start") }
}

@Composable
private fun ReciprocityBadge(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = RoundedCornerShape(50),
    ) {
        Text(
            text,
            Modifier.padding(horizontal = 10.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
        )
    }
}

// MARK: - Custom film actions (low priority)

@Composable
private fun CustomFilmRow(onEvent: (ShootingIntent) -> Unit) {
    var newFormula by remember { mutableStateOf(false) }
    var newTable by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
        Text("Custom films", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
private fun TimerCard(item: TimerItemUi, terminal: Boolean, onEvent: (ShootingIntent) -> Unit) {
    val rowModifier = Modifier.fillMaxWidth().let { if (!terminal) it.testTag(TestTags.ACTIVE_TIMER_ROW) else it }
    ElevatedCard(rowModifier) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text(item.title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                StatusPill(item.statusLabel)
            }
            Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (item.metadata.isNotBlank()) Text(item.metadata, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            // Active timers lead with the large countdown; completed rows omit it
            // (the Done pill already says so); canceled rows show the compact
            // "Canceled / Canceled · <remaining> left" label as supporting text.
            when {
                !terminal -> {
                    Text(item.remainingLabel, style = MaterialTheme.typography.headlineMedium)
                    item.endsAtLabel?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                item.status == TimerStatus.CANCELED ->
                    Text(item.remainingLabel, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            // Per-state action set, matching the iOS action model:
            //   running            -> Pause, Start new
            //   paused             -> Resume, Start new, Cancel, Remove
            //   completed/canceled -> Start again, Remove
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when {
                    terminal -> {
                        OutlinedButton(onClick = { onEvent(ShootingIntent.StartAgain(item.id)) }) { Text("Start again") }
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(item.id)) }) { Text("Remove") }
                    }
                    item.status == TimerStatus.RUNNING -> {
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Pause(item.id)) }) { Text("Pause") }
                        OutlinedButton(onClick = { onEvent(ShootingIntent.StartNew(item.id)) }) { Text("Start new") }
                    }
                    else -> { // paused
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Resume(item.id)) }) { Text("Resume") }
                        OutlinedButton(onClick = { onEvent(ShootingIntent.StartNew(item.id)) }) { Text("Start new") }
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Cancel(item.id)) }) { Text("Cancel") }
                        OutlinedButton(onClick = { onEvent(ShootingIntent.Remove(item.id)) }) { Text("Remove") }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusPill(label: String) {
    val color = when (label) {
        "Running" -> MaterialTheme.colorScheme.primary
        "Paused" -> MaterialTheme.colorScheme.tertiary
        "Canceled" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.outline
    }
    Surface(color = color.copy(alpha = 0.15f), shape = RoundedCornerShape(50)) {
        Text(label, Modifier.padding(horizontal = 10.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, color = color)
    }
}

// MARK: - shared

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(
            Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
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
