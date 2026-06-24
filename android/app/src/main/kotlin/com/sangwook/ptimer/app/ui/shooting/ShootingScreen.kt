package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointRow
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.CustomFilmDraft

/**
 * Tier-2 shooting screen: film selection + alternate model, the shared
 * SnapWheel for base shutter and ND, the adjusted/corrected result with its
 * confidence label, and Start. Resembles iOS, adapted to Material.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShootingScreen(
    state: CalculatorUiState,
    timersCount: Int,
    onShutterIndex: (Int) -> Unit,
    onNdIndex: (Int) -> Unit,
    onSelectFilm: (String?) -> Unit,
    onSelectProfile: (String) -> Unit,
    onSelectSlot: (CameraSlotId) -> Unit,
    onRenameSlot: (String?) -> Unit,
    onSetTarget: (Double?) -> Unit,
    onStartTarget: () -> Unit,
    onOpenDetails: () -> Unit,
    onCreateCustomFilm: (CustomFormulaFilmInput, editFilmId: String?) -> Boolean,
    onCreateCustomTableFilm: (CustomTableFilmInput, editFilmId: String?) -> Boolean,
    onEditCustomFilm: (String) -> CustomFilmDraft?,
    onDeleteCustomFilm: (String) -> Unit,
    onPreviewCustomFilm: (CustomFormulaFilmInput) -> ReciprocityGraph?,
    onPreviewCustomTableFilm: (CustomTableFilmInput) -> ReciprocityGraph?,
    onFormulaCheckpoints: (CustomFormulaFilmInput) -> List<CustomFilmCheckpointRow>,
    onTableCheckpoints: (CustomTableFilmInput) -> List<CustomFilmCheckpointRow>,
    onCalculationBasis: (CustomFormulaFilmInput) -> String,
    onPreviewTableFit: (CustomTableFilmInput) -> CustomTableFittedFormula.Outcome?,
    onCreateFormulaFromTable: (CustomTableFilmInput, editFilmId: String?) -> Boolean,
    onReferencePoints: (CustomFormulaFilmInput, List<Pair<Double, Double>>) -> List<CustomFilmReferencePointRow>,
    onStart: () -> Unit,
    onOpenTimers: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showFilmPicker by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    var showTarget by remember { mutableStateOf(false) }
    var showEditor by remember { mutableStateOf(false) }
    var editDraft by remember { mutableStateOf<CustomFilmDraft?>(null) }

    val activeIndex = state.slots.indexOfFirst { it.isActive }.coerceAtLeast(0)
    val pagerState = rememberPagerState(initialPage = activeIndex) { state.slots.size }
    // Swiping settles on a page -> make that camera active (capture-on-switch);
    // the reverse effect realigns the pager when the slot changes elsewhere.
    LaunchedEffect(pagerState.settledPage) {
        val idx = pagerState.settledPage
        if (idx in state.slots.indices) onSelectSlot(state.slots[idx].id)
    }
    LaunchedEffect(activeIndex) {
        if (!pagerState.isScrollInProgress && pagerState.currentPage != activeIndex) {
            pagerState.animateScrollToPage(activeIndex)
        }
    }

    Column(modifier = modifier.fillMaxWidth().padding(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                state.activeSlotName,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable { showRename = true },
            )
            OutlinedButton(onClick = onOpenTimers) { Text("Timers ($timersCount)") }
        }

        Spacer(Modifier.height(8.dp))
        PagerDots(count = state.slots.size, current = pagerState.currentPage)
        Spacer(Modifier.height(8.dp))

        // Each page renders its own slot's state so a swipe reveals that camera;
        // editing controls still target the active slot, which the settle handler
        // keeps aligned with the on-screen page (capture-on-switch).
        HorizontalPager(state = pagerState, modifier = Modifier.fillMaxWidth()) { page ->
            val pageState = state.slotStates.getOrNull(page) ?: state
            Column {
                Card(
                    modifier = Modifier.fillMaxWidth().clickable { showFilmPicker = true },
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Film", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(pageState.selectedFilmName, style = MaterialTheme.typography.titleMedium)
                    }
                }

                if (pageState.modelOptions.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        pageState.modelOptions.forEach { option ->
                            FilterChip(
                                selected = option.id == pageState.selectedProfileId,
                                onClick = { onSelectProfile(option.id) },
                                label = { Text(option.label) },
                            )
                        }
                    }
                }

                Spacer(Modifier.height(16.dp))

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Base shutter", style = MaterialTheme.typography.labelMedium)
                        SnapWheel(pageState.shutterLabels, pageState.shutterIndex, onShutterIndex)
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("ND (stops)", style = MaterialTheme.typography.labelMedium)
                        SnapWheel(pageState.ndLabels, pageState.ndIndex, onNdIndex)
                    }
                }

                Spacer(Modifier.height(16.dp))

                ResultBlock(pageState, onOpenDetails)

                Spacer(Modifier.height(12.dp))

                TargetShutterRow(
                    display = pageState.targetDisplay,
                    onEdit = { showTarget = true },
                    onStartTarget = onStartTarget,
                )

                Spacer(Modifier.height(16.dp))

                Button(
                    onClick = onStart,
                    enabled = pageState.startEnabled,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Start timer") }
            }
        }
    }

    if (showFilmPicker) {
        FilmPickerSheet(
            filmOptions = state.filmOptions,
            selectedFilmId = state.selectedFilmId,
            onSelect = { id -> onSelectFilm(id); showFilmPicker = false },
            onCreateNew = { showFilmPicker = false; editDraft = null; showEditor = true },
            onEditFilm = { id ->
                onEditCustomFilm(id)?.let { draft ->
                    showFilmPicker = false
                    editDraft = draft
                    showEditor = true
                }
            },
            onDeleteFilm = { id -> onDeleteCustomFilm(id) },
            onDismiss = { showFilmPicker = false },
        )
    }

    if (showEditor) {
        CustomFilmEditorDialog(
            initial = editDraft,
            onCreateFormula = { input, editId ->
                onCreateCustomFilm(input, editId).also { if (it) { showEditor = false; editDraft = null } }
            },
            onCreateTable = { input, editId ->
                onCreateCustomTableFilm(input, editId).also { if (it) { showEditor = false; editDraft = null } }
            },
            onPreviewFormula = onPreviewCustomFilm,
            onPreviewTable = onPreviewCustomTableFilm,
            onFormulaCheckpoints = onFormulaCheckpoints,
            onTableCheckpoints = onTableCheckpoints,
            onCalculationBasis = onCalculationBasis,
            onPreviewTableFit = onPreviewTableFit,
            onCreateFormulaFromTable = { input, editId ->
                onCreateFormulaFromTable(input, editId).also { if (it) { showEditor = false; editDraft = null } }
            },
            onReferencePoints = onReferencePoints,
            onDismiss = { showEditor = false; editDraft = null },
        )
    }

    if (showRename) {
        RenameSlotDialog(
            initial = state.activeSlotName,
            onConfirm = { name -> onRenameSlot(name); showRename = false },
            onDismiss = { showRename = false },
        )
    }

    if (showTarget) {
        val current = (state.targetDisplay as? TargetShutterDisplayState.Available)?.state?.targetSeconds
        TargetShutterSheet(
            initialSeconds = current,
            onConfirm = { seconds -> onSetTarget(seconds); showTarget = false },
            onDismiss = { showTarget = false },
        )
    }
}

@Composable
internal fun StartButton(onClick: () -> Unit, enabled: Boolean) {
    FilledIconButton(onClick = onClick, enabled = enabled) {
        Icon(
            Icons.Filled.PlayArrow,
            contentDescription = "Start timer",
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
internal fun Pill(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Text(text, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
    }
}

@Composable
internal fun PagerDots(count: Int, current: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { index ->
            val color = if (index == current) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            }
            Box(
                modifier = Modifier
                    .padding(horizontal = 4.dp)
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(color),
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            "${current + 1} of $count",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun RenameSlotDialog(
    initial: String,
    onConfirm: (String?) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename camera") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
                label = { Text("Camera name") },
            )
        },
        confirmButton = { TextButton(onClick = { onConfirm(text) }) { Text("Save") } },
        dismissButton = {
            // Empty name clears the custom label back to the canonical default.
            TextButton(onClick = { onConfirm(null) }) { Text("Reset") }
        },
    )
}

@Composable
private fun ResultBlock(state: CalculatorUiState, onOpenDetails: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Text("Adjusted shutter", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(state.adjustedText, style = MaterialTheme.typography.headlineMedium, fontFamily = FontFamily.Monospace)

            if (state.correctedText != null) {
                Spacer(Modifier.height(8.dp))
                Text("Corrected exposure", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(state.correctedText, style = MaterialTheme.typography.headlineMedium, fontFamily = FontFamily.Monospace)
            }
            if (state.confidenceLabel != null) {
                Spacer(Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(state.confidenceLabel, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    TextButton(onClick = onOpenDetails) { Text("Details") }
                }
            }
            if (state.hint != null) {
                Spacer(Modifier.height(4.dp))
                Text(state.hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
