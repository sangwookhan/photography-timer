package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.app.vm.CalculatorUiState

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
    onStart: () -> Unit,
    onOpenTimers: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showFilmPicker by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }

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

        // Camera-slot pager: switching captures the active slot's inputs and
        // restores the target slot's. Tap the camera name to rename it.
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(state.slots, key = { it.id }) { slot ->
                FilterChip(
                    selected = slot.isActive,
                    onClick = { onSelectSlot(slot.id) },
                    label = { Text(slot.displayName) },
                )
            }
        }

        Spacer(Modifier.height(12.dp))

        // Film selector
        Card(
            modifier = Modifier.fillMaxWidth().clickable { showFilmPicker = true },
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Column(Modifier.padding(16.dp)) {
                Text("Film", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(state.selectedFilmName, style = MaterialTheme.typography.titleMedium)
            }
        }

        if (state.modelOptions.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                state.modelOptions.forEach { option ->
                    FilterChip(
                        selected = option.id == state.selectedProfileId,
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
                SnapWheel(state.shutterLabels, state.shutterIndex, onShutterIndex)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("ND (stops)", style = MaterialTheme.typography.labelMedium)
                SnapWheel(state.ndLabels, state.ndIndex, onNdIndex)
            }
        }

        Spacer(Modifier.height(16.dp))

        ResultBlock(state)

        Spacer(Modifier.height(16.dp))

        Button(
            onClick = onStart,
            enabled = state.startEnabled,
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Start timer") }
    }

    if (showFilmPicker) {
        ModalBottomSheet(
            onDismissRequest = { showFilmPicker = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            LazyColumn {
                items(state.filmOptions, key = { it.id ?: "__none__" }) { option ->
                    ListItem(
                        headlineContent = { Text(option.name) },
                        modifier = Modifier.clickable {
                            onSelectFilm(option.id)
                            showFilmPicker = false
                        },
                    )
                }
            }
        }
    }

    if (showRename) {
        RenameSlotDialog(
            initial = state.activeSlotName,
            onConfirm = { name -> onRenameSlot(name); showRename = false },
            onDismiss = { showRename = false },
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
private fun ResultBlock(state: CalculatorUiState) {
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
                Text(state.confidenceLabel, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            }
            if (state.hint != null) {
                Spacer(Modifier.height(4.dp))
                Text(state.hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
