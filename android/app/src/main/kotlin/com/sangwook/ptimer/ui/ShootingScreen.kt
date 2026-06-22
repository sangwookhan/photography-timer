@file:OptIn(ExperimentalMaterial3Api::class)

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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.calculator.StartActionState
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.details.DetailsUi
import com.sangwook.ptimer.target.TargetDurationFormat
import com.sangwook.ptimer.target.TargetQuickPresets
import com.sangwook.ptimer.timer.TimerItemUi
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import com.sangwook.ptimer.vm.FilmRowUi
import com.sangwook.ptimer.vm.ShootingIntent
import com.sangwook.ptimer.vm.SlotsUiState
import kotlinx.coroutines.launch

/** Default draft when the photographer has no current target: 1 minute (iOS parity). */
private const val TARGET_DEFAULT_SECONDS: Double = 60.0

/**
 * Material 3 shooting control panel. The main scroll is the calculator only
 * (camera, film, target, base/ND, results with source-specific Starts, a timer
 * summary); the full Active/History timer list lives in a separate Timers
 * workspace opened on demand, so starting a timer never turns the calculator
 * into an archive view. Base shutter, ND, and target use fast bottom-sheet
 * pickers (plus/minus remain as secondary fine controls).
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
    var renaming by remember { mutableStateOf(false) }
    var renameDraft by remember { mutableStateOf("") }
    var baseSheet by remember { mutableStateOf(false) }
    var ndSheet by remember { mutableStateOf(false) }
    var targetSheet by remember { mutableStateOf(false) }
    var timersOpen by remember { mutableStateOf(false) }
    val activeSlotId = slots.slots.firstOrNull { it.isActive }?.id

    Box(Modifier.fillMaxSize()) {
        details?.let { DetailsDialog(it, onEvent) }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(slots.activeLabel) },
                    actions = {
                        TextButton(onClick = { renameDraft = slots.activeLabel; renaming = true }) { Text("Rename") }
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
                verticalArrangement = Arrangement.spacedBy(6.dp),
                contentPadding = PaddingValues(top = 6.dp, bottom = 16.dp),
            ) {
                if (exactAlarmPromptVisible) {
                    item { ExactAlarmNotice(onOpenSettings = onOpenExactAlarmSettings, onDismiss = { onEvent(ShootingIntent.DismissExactAlarmPrompt) }) }
                }
                item { SlotChips(slots, onEvent) }
                item { FilmModelSection(calc, films, onEvent) }
                item { TargetCard(calc, onEdit = { targetSheet = true }, onEvent) }
                item { BaseNdCard(calc, onPickBase = { baseSheet = true }, onPickNd = { ndSheet = true }, onEvent) }
                item { ResultSection(calc, onEvent) }
                item { CustomFilmRow(onEvent) }
                item { TimerSummaryCard(timers, onOpen = { timersOpen = true }) }
            }
        }

        if (!ready) RestoringOverlay()
        if (timersOpen) TimersWorkspace(timers, onEvent, onClose = { timersOpen = false })
    }

    if (renaming && activeSlotId != null) {
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Rename ${slots.activeLabel}") },
            text = { OutlinedTextField(renameDraft, { renameDraft = it }, singleLine = true) },
            confirmButton = {
                TextButton(onClick = { onEvent(ShootingIntent.RenameSlot(activeSlotId, renameDraft)); renaming = false }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { onEvent(ShootingIntent.ResetSlotName(activeSlotId)); renaming = false }) { Text("Reset") }
            },
        )
    }

    if (baseSheet) {
        BaseShutterSheet(calc, onSelect = { onEvent(ShootingIntent.SelectBaseShutterIndex(it)) }, onDismiss = { baseSheet = false })
    }
    if (ndSheet) {
        NdSheet(calc, onSelect = { onEvent(ShootingIntent.SetNdStops(it)) }, onDismiss = { ndSheet = false })
    }
    if (targetSheet) {
        TargetSheet(
            calc,
            onSet = { onEvent(ShootingIntent.SetTarget(it)) },
            onClear = { onEvent(ShootingIntent.ClearTarget) },
            onDismiss = { targetSheet = false },
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
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { },
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
            Text("For more reliable background timer alerts, allow exact alarms.", style = MaterialTheme.typography.bodyMedium)
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
                label = { Text(slot.label, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium) },
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
        calc.fittedPreviewSummary?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (calc.isCustomTable) {
            TextButton(onClick = { onEvent(ShootingIntent.CreateFormulaFromSelectedTable) }) { Text("Create formula from this table") }
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
        Row(Modifier.fillMaxWidth().clickable { expanded = true }, Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(calc.filmName ?: "No film (digital)", style = MaterialTheme.typography.titleMedium)
                calc.authorityLabel?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            TextButton(onClick = { expanded = true }) { Text(if (calc.filmName == null) "Choose" else "Change") }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("No film (digital)") }, onClick = { onEvent(ShootingIntent.ClearFilm); expanded = false })
            films.forEach { film ->
                val suffix = if (film.isCustom) " · custom" else ""
                DropdownMenuItem(text = { Text("${film.name} · ISO ${film.iso}$suffix") }, onClick = { onEvent(ShootingIntent.SelectFilm(film.id)); expanded = false })
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

// MARK: - Target shutter (picker-driven; keeps its own Start)

@Composable
private fun TargetCard(calc: CalculatorUiState, onEdit: () -> Unit, onEvent: (ShootingIntent) -> Unit) {
    SectionCard("Target shutter") {
        if (calc.targetSeconds == null) {
            // Off: whole row taps through to the input sheet (iOS "Off >").
            // Removal lives in the sheet's Use-target-shutter switch, so the
            // card never carries a Clear button and the row stays stable.
            Row(
                Modifier.fillMaxWidth().clickable { onEdit() },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Off", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Set", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            }
        } else {
            // Active: one compact row — [value · stop difference] | [Start].
            // The value/diff area opens the sheet; Start is an independent
            // sibling that stays available whenever a valid target is set.
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Row(
                    Modifier.weight(1f).clickable { onEdit() },
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        calc.targetDurationLabel ?: "",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    TargetStopDifference(calc)
                }
                if (calc.targetAction != null) {
                    StartButton(enabled = calc.targetAction.enabled) { onEvent(ShootingIntent.StartTarget) }
                }
            }
        }
    }
}

/**
 * Compact stop-difference glyph for the active target row, mirroring iOS:
 * a direction arrow plus the signed stop text, color-coded by direction.
 * Comparison unavailable renders a stable em dash so the row never wraps
 * (the Result card below carries the explicit unavailable wording).
 */
@Composable
private fun TargetStopDifference(calc: CalculatorUiState) {
    if (calc.targetUnavailable) {
        Text("—", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val stops = calc.targetStopDifference ?: 0.0
    val (arrow, color) = when {
        calc.targetIsMatch -> "=" to MaterialTheme.colorScheme.primary
        stops > 0 -> "↑" to MaterialTheme.colorScheme.primary
        else -> "↓" to MaterialTheme.colorScheme.tertiary
    }
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(arrow, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = color)
        Text(
            calc.targetComparisonLabel ?: "",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = color,
            maxLines = 1,
        )
    }
}

// MARK: - Base shutter + ND (tap value to open a fast picker; +/- secondary)

@Composable
private fun BaseNdCard(calc: CalculatorUiState, onPickBase: () -> Unit, onPickNd: () -> Unit, onEvent: (ShootingIntent) -> Unit) {
    SectionCard("Base shutter + ND") {
        PickerRow(
            label = "Base shutter", value = calc.baseShutterLabel, onTap = onPickBase,
            onMinus = { onEvent(ShootingIntent.NudgeBaseShutter(-1)) },
            onPlus = { onEvent(ShootingIntent.NudgeBaseShutter(1)) },
        )
        PickerRow(
            label = "ND stops", value = calc.ndStops.toString(), onTap = onPickNd,
            onMinus = { onEvent(ShootingIntent.SetNdStops(calc.ndStops - 1)) },
            onPlus = { onEvent(ShootingIntent.SetNdStops(calc.ndStops + 1)) },
            plusTag = TestTags.ND_PLUS_BUTTON,
        )
    }
}

@Composable
private fun PickerRow(label: String, value: String, onTap: () -> Unit, onMinus: () -> Unit, onPlus: () -> Unit, plusTag: String? = null) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        // Tapping the value is the primary, fast path (opens a picker); the
        // plus/minus buttons remain as secondary one-third-stop fine control.
        Row(Modifier.weight(1f).clickable { onTap() }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            FilledTonalIconButton(onClick = onMinus, modifier = Modifier.size(32.dp)) { Text("−", style = MaterialTheme.typography.titleMedium) }
            val plusModifier = Modifier.size(32.dp).let { if (plusTag != null) it.testTag(plusTag) else it }
            FilledTonalIconButton(onClick = onPlus, modifier = plusModifier) { Text("+", style = MaterialTheme.typography.titleMedium) }
        }
    }
}

// MARK: - Result (adjusted / reciprocity / corrected) — source-specific Starts

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

@Composable
private fun StartButton(enabled: Boolean, tag: String? = null, onStart: () -> Unit) {
    val modifier = if (tag != null) Modifier.testTag(tag) else Modifier
    FilledTonalButton(onClick = onStart, enabled = enabled, modifier = modifier) { Text("Start") }
}

@Composable
private fun ReciprocityBadge(text: String) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(50)) {
        Text(text, Modifier.padding(horizontal = 10.dp, vertical = 2.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSecondaryContainer)
    }
}

// MARK: - Custom film actions (low priority support row)

@Composable
private fun CustomFilmRow(onEvent: (ShootingIntent) -> Unit) {
    var newFormula by remember { mutableStateOf(false) }
    var newTable by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), Arrangement.spacedBy(4.dp), Alignment.CenterVertically) {
        Text("Custom films", Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton(onClick = { newFormula = true }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp)) { Text("New formula", style = MaterialTheme.typography.labelMedium) }
        TextButton(onClick = { newTable = true }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp)) { Text("New table", style = MaterialTheme.typography.labelMedium) }
    }
    if (newFormula) NewFormulaDialog(onDismiss = { newFormula = false }, onCreate = { n, e, nc -> onEvent(ShootingIntent.CreateCustomFormula(n, e, nc)); newFormula = false })
    if (newTable) NewTableDialog(onDismiss = { newTable = false }, onCreate = { n, anchors -> onEvent(ShootingIntent.CreateCustomTable(n, anchors)); newTable = false })
}

// MARK: - Timer summary (main) + workspace (separate surface)

@Composable
private fun TimerSummaryCard(timers: TimerWorkspaceUiState, onOpen: () -> Unit) {
    val running = timers.active.count { it.status == TimerStatus.RUNNING }
    val paused = timers.active.count { it.status == TimerStatus.PAUSED }
    val history = timers.completed.size
    val summary = when {
        running == 0 && paused == 0 && history == 0 -> "No timers yet"
        else -> buildList {
            if (running > 0) add("$running running")
            if (paused > 0) add("$paused paused")
            add("$history in history")
        }.joinToString(" · ")
    }
    ElevatedCard(Modifier.fillMaxWidth().clickable { onOpen() }) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Timers", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text(summary, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            FilledTonalButton(onClick = onOpen, modifier = Modifier.testTag(TestTags.OPEN_TIMERS_BUTTON)) { Text("Open") }
        }
    }
}

/** Full-screen Timers workspace surface; keeps the full Active/History list off the main calculator. */
@Composable
private fun TimersWorkspace(timers: TimerWorkspaceUiState, onEvent: (ShootingIntent) -> Unit, onClose: () -> Unit) {
    Surface(Modifier.fillMaxSize().testTag(TestTags.TIMERS_WORKSPACE), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Timers") },
                    navigationIcon = { TextButton(onClick = onClose) { Text("Close") } },
                )
            },
        ) { innerPadding ->
            if (timers.active.isEmpty() && timers.completed.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    Text("No timers yet", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(innerPadding).padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(vertical = 12.dp),
                ) {
                    if (timers.active.isNotEmpty()) {
                        item { SectionLabel("Active") }
                        items(timers.active, key = { it.id }) { TimerCard(it, terminal = false, onEvent) }
                    }
                    if (timers.completed.isNotEmpty()) {
                        item {
                            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                                SectionLabel("History")
                                if (timers.completed.any { it.status == TimerStatus.COMPLETED }) {
                                    TextButton(onClick = { onEvent(ShootingIntent.ClearCompleted) }) { Text("Clear") }
                                }
                            }
                        }
                        items(timers.completed, key = { it.id }) { TimerCard(it, terminal = true, onEvent) }
                    }
                }
            }
        }
    }
}

// MARK: - Fast pickers (Material bottom sheets)

@Composable
private fun BaseShutterSheet(calc: CalculatorUiState, onSelect: (Int) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text("Base shutter", Modifier.padding(start = 24.dp, bottom = 8.dp), style = MaterialTheme.typography.titleMedium)
        PickerList(
            labels = calc.baseShutterLadder,
            selectedIndex = calc.baseShutterIndex,
            onSelect = { onSelect(it); onDismiss() },
        )
    }
}

@Composable
private fun NdSheet(calc: CalculatorUiState, onSelect: (Int) -> Unit, onDismiss: () -> Unit) {
    val labels = (0..ExposureScale.MAX_WHOLE_ND_STOPS).map { if (it == 0) "0 (none)" else "$it stops" }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text("ND stops", Modifier.padding(start = 24.dp, bottom = 8.dp), style = MaterialTheme.typography.titleMedium)
        PickerList(
            labels = labels,
            selectedIndex = calc.ndStops.coerceIn(0, ExposureScale.MAX_WHOLE_ND_STOPS),
            onSelect = { onSelect(it); onDismiss() },
        )
    }
}

@Composable
private fun TargetSheet(calc: CalculatorUiState, onSet: (Double) -> Unit, onClear: () -> Unit, onDismiss: () -> Unit) {
    // Draft session, local to the sheet (iOS parity): Quick and Fine Tune are
    // two views of one draft; Confirm commits it (or removes the target when
    // the switch is off), Cancel / dismiss discards. The committed target only
    // changes on Confirm.
    var useTarget by remember { mutableStateOf(true) }
    var draftSeconds by remember { mutableStateOf((calc.targetSeconds ?: TARGET_DEFAULT_SECONDS).coerceAtLeast(1.0)) }
    var quickMode by remember { mutableStateOf(true) }
    val editorAlpha = if (useTarget) 1f else 0.38f
    // Open expanded so the Cancel / Confirm row is fully visible without a
    // drag; the content is short enough that expanded is not oversized.
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Quick mode expresses presets only: entering it parks the draft on the
    // nearest preset (e.g. a 12m fine value parks at 15m) so the wheel's
    // centered value and the readout always agree.
    LaunchedEffect(quickMode, useTarget) {
        if (quickMode && useTarget) {
            draftSeconds = TargetQuickPresets.seconds[TargetQuickPresets.nearestIndex(draftSeconds)]
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            // navigationBarsPadding keeps the action row clear of the gesture
            // bar / home indicator.
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Target shutter", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)

            // Use-target-shutter switch owns removal (iOS parity): off + Confirm
            // removes the target; Cancel after off keeps the committed value.
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text("Use target shutter", style = MaterialTheme.typography.bodyLarge)
                Switch(checked = useTarget, onCheckedChange = { useTarget = it })
            }

            // Prominent draft readout — the source of truth while editing.
            // Dimmed when off to preview the removal Confirm would apply.
            Text(
                targetDraftLabel(draftSeconds),
                Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = if (useTarget) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Quick / Fine tune mode switch — the Material analog of the iOS
            // horizontal wheel pager.
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().alpha(editorAlpha)) {
                SegmentedButton(
                    selected = quickMode,
                    onClick = { if (useTarget) quickMode = true },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                ) { Text("Quick") }
                SegmentedButton(
                    selected = !quickMode,
                    onClick = { if (useTarget) quickMode = false },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                ) { Text("Fine tune") }
            }

            Box(Modifier.fillMaxWidth().height(212.dp).alpha(editorAlpha), contentAlignment = Alignment.Center) {
                if (quickMode) {
                    // Wheel-like: scrolling parks on the centered preset and
                    // commits it to the draft on settle (tap is a shortcut).
                    WheelPicker(
                        items = TargetQuickPresets.seconds.map { targetDraftLabel(it) },
                        selectedIndex = TargetQuickPresets.nearestIndex(draftSeconds),
                        enabled = useTarget,
                        onSelect = { if (useTarget) draftSeconds = TargetQuickPresets.seconds[it] },
                    )
                } else {
                    TargetFineTune(draftSeconds, enabled = useTarget, onChange = { if (useTarget) draftSeconds = it })
                }
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Cancel") }
                Button(
                    onClick = {
                        if (useTarget) onSet(draftSeconds) else onClear()
                        onDismiss()
                    },
                    enabled = !useTarget || draftSeconds > 0,
                    modifier = Modifier.weight(1f),
                ) { Text("Confirm") }
            }
        }
    }
}

/** Compact h/m/s draft label, shared with the card via [TargetDurationFormat]. */
private fun targetDraftLabel(seconds: Double): String = TargetDurationFormat.compact(seconds)

/**
 * Fine Tune h / m / s scroll wheels — faster than tap-repeat steppers and the
 * Material counterpart of the iOS Fine Tune wheels. Each column edits one
 * field of the single draft, so Quick <-> Fine transfer is preserved.
 */
@Composable
private fun TargetFineTune(seconds: Double, enabled: Boolean, onChange: (Double) -> Unit) {
    val total = seconds.toInt().coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TargetFineWheel("h", h, 24, enabled, Modifier.weight(1f)) { onChange((it * 3600 + m * 60 + s).toDouble()) }
        TargetFineWheel("m", m, 60, enabled, Modifier.weight(1f)) { onChange((h * 3600 + it * 60 + s).toDouble()) }
        TargetFineWheel("s", s, 60, enabled, Modifier.weight(1f)) { onChange((h * 3600 + m * 60 + it).toDouble()) }
    }
}

@Composable
private fun TargetFineWheel(label: String, value: Int, count: Int, enabled: Boolean, modifier: Modifier, onSet: (Int) -> Unit) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        WheelPicker(
            items = (0 until count).map { it.toString() },
            selectedIndex = value.coerceIn(0, count - 1),
            enabled = enabled,
            onSelect = onSet,
        )
    }
}

/**
 * A lightweight wheel-style scroll selector. The item nearest the viewport
 * center is the current selection: it is highlighted live while scrolling and
 * committed via [onSelect] when the scroll settles (a row tap centers and
 * selects it as a shortcut). An external [selectedIndex] change recenters the
 * wheel without animation. This is the Target-only wheel; the shared
 * [PickerList] (Base / ND) keeps its plain tap-to-select behavior.
 */
@Composable
private fun WheelPicker(
    items: List<String>,
    selectedIndex: Int,
    enabled: Boolean,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) return
    val itemHeight = 40.dp
    val visible = 5
    val state = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // Recenter when the selection is driven from outside (first open, or
    // entering this mode from the other one) — but never fight a live scroll.
    // The vertical contentPadding already centers index 0 at rest, so a plain
    // scrollToItem(index) lands the target item in the center band.
    LaunchedEffect(selectedIndex) {
        if (!state.isScrollInProgress) {
            state.scrollToItem(selectedIndex.coerceIn(items.indices))
        }
    }

    val centeredIndex by remember(items.size) {
        derivedStateOf {
            val info = state.layoutInfo
            if (info.visibleItemsInfo.isEmpty()) {
                selectedIndex
            } else {
                val center = (info.viewportStartOffset + info.viewportEndOffset) / 2f
                info.visibleItemsInfo.minByOrNull { kotlin.math.abs(it.offset + it.size / 2f - center) }?.index ?: selectedIndex
            }
        }
    }

    // Commit the centered item only after a real user scroll settles (a
    // true -> false transition). The initial / programmatic-centering state
    // is false and must not commit, or it would overwrite the draft.
    LaunchedEffect(state, enabled) {
        var wasScrolling = false
        snapshotFlow { state.isScrollInProgress }.collect { scrolling ->
            if (wasScrolling && !scrolling && enabled) onSelect(centeredIndex)
            wasScrolling = scrolling
        }
    }

    Box(modifier.fillMaxWidth().height(itemHeight * visible)) {
        // Center selection band.
        Box(
            Modifier.align(Alignment.Center).fillMaxWidth().height(itemHeight)
                .background(MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.45f), RoundedCornerShape(8.dp)),
        )
        LazyColumn(
            state = state,
            userScrollEnabled = enabled,
            contentPadding = PaddingValues(vertical = itemHeight * (visible / 2)),
            modifier = Modifier.fillMaxWidth(),
        ) {
            itemsIndexed(items) { index, label ->
                val isCenter = index == centeredIndex
                Box(
                    Modifier.fillMaxWidth().height(itemHeight)
                        .clickable(enabled = enabled) { scope.launch { state.animateScrollToItem(index) } },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        style = if (isCenter) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleMedium,
                        fontWeight = if (isCenter) FontWeight.Bold else FontWeight.Normal,
                        color = if (isCenter) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** Vertical, scrollable selection list with the current value highlighted and scrolled into view. */
@Composable
private fun PickerList(labels: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit) {
    val listState = rememberLazyListState()
    LaunchedEffect(selectedIndex, labels.size) {
        if (selectedIndex in labels.indices) listState.scrollToItem(maxOf(0, selectedIndex - 2))
    }
    LazyColumn(state = listState, modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp)) {
        itemsIndexed(labels) { index, label ->
            val isSelected = index == selectedIndex
            val bg = if (isSelected) MaterialTheme.colorScheme.secondaryContainer else androidx.compose.ui.graphics.Color.Transparent
            Text(
                label,
                Modifier.fillMaxWidth().clickable { onSelect(index) }.background(bg).padding(horizontal = 24.dp, vertical = 14.dp),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                color = if (isSelected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

// MARK: - Timer cards (used inside the Timers workspace)

@Composable
private fun TimerCard(item: TimerItemUi, terminal: Boolean, onEvent: (ShootingIntent) -> Unit) {
    val rowModifier = Modifier.fillMaxWidth().let { if (!terminal) it.testTag(TestTags.ACTIVE_TIMER_ROW) else it }
    ElevatedCard(rowModifier) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text(item.title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                StatusPill(item.statusLabel)
            }
            Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (item.metadata.isNotBlank()) Text(item.metadata, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
            Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when {
                    terminal -> {
                        TimerActionButton("Start again") { onEvent(ShootingIntent.StartAgain(item.id)) }
                        TimerActionButton("Remove") { onEvent(ShootingIntent.Remove(item.id)) }
                    }
                    item.status == TimerStatus.RUNNING -> {
                        TimerActionButton("Pause") { onEvent(ShootingIntent.Pause(item.id)) }
                        TimerActionButton("Start new") { onEvent(ShootingIntent.StartNew(item.id)) }
                    }
                    else -> { // paused
                        TimerActionButton("Resume") { onEvent(ShootingIntent.Resume(item.id)) }
                        TimerActionButton("Start new") { onEvent(ShootingIntent.StartNew(item.id)) }
                        TimerActionButton("Cancel") { onEvent(ShootingIntent.Cancel(item.id)) }
                        TimerActionButton("Remove") { onEvent(ShootingIntent.Remove(item.id)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun TimerActionButton(label: String, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge)
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
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
