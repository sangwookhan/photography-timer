// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.details

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.sangwook.ptimer.ui.component.GraphLegend
import com.sangwook.ptimer.ui.component.ReciprocityGraphView
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState
import com.sangwook.ptimer.core.reciprocity.ReciprocityReferenceRow
import com.sangwook.ptimer.core.reciprocity.ReciprocityStatusTone
import com.sangwook.ptimer.ui.theme.StatusSuccess
import com.sangwook.ptimer.ui.theme.StatusWarning

/**
 * Reciprocity details, structured like the iOS Film Details sheet: subtitle,
 * the current result (Adjusted | Corrected + Status), the reciprocity model
 * (Source + Calculation), and the formula equation. The formula-curve graph is
 * added separately.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReciprocityDetailsScreen(
    state: ReciprocityDetailsDisplayState,
    onBack: () -> Unit,
    onSelectModel: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(state.title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.Close, contentDescription = "Close")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Spacer(Modifier.height(2.dp))
            Text(state.subtitle, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)

            // Current result: Adjusted | Corrected side by side, then Status.
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        ResultValue("Adjusted Shutter", state.adjustedShutterText, Modifier.weight(1f))
                        ResultValue("Corrected Exposure", state.correctedExposureText, Modifier.weight(1f))
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Status", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            state.statusText,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            color = toneColor(state.statusTone),
                        )
                    }
                    // Explanatory sentence under the status (iOS parity); only for
                    // beyond-range / limited / warned results.
                    state.statusDetailText?.let { detail ->
                        Spacer(Modifier.height(6.dp))
                        Text(
                            detail,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (state.statusTone == ReciprocityStatusTone.warning) {
                                StatusWarning
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                }
            }

            // Reciprocity model: optional model toggle + Source + Calculation.
            Column(Modifier.fillMaxWidth()) {
                Text("Reciprocity model", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (state.modelOptions.size > 1) {
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.modelOptions.forEach { option ->
                            FilterChip(
                                selected = option.id == state.selectedModelId,
                                onClick = { onSelectModel(option.id) },
                                label = { Text(option.label) },
                            )
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                ModelRow("Source", state.sourceText)
                Spacer(Modifier.height(6.dp))
                ModelRow("Calculation", state.calculationText)
            }

            // Custom-profile provenance (notes / reference URL), shown only when
            // the photographer supplied them — iOS parity with the editor Details.
            if (state.notesText != null || state.referenceUrlText != null) {
                HorizontalDivider()
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Details", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    state.notesText?.let { notes ->
                        Column {
                            Text("Notes", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(notes, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    state.referenceUrlText?.let { url ->
                        Column {
                            Text("Reference URL", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(url, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }

            state.equationText?.let { equation ->
                HorizontalDivider()
                Column(Modifier.fillMaxWidth()) {
                    Text("Equation", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(6.dp))
                    Text(equation, style = MaterialTheme.typography.titleMedium, fontFamily = FontFamily.Monospace)
                }
            }

            state.graph?.let { graph ->
                HorizontalDivider()
                Column(Modifier.fillMaxWidth()) {
                    Text("Reciprocity graph", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    ReciprocityGraphView(graph, Modifier.fillMaxWidth().height(240.dp))
                    Spacer(Modifier.height(8.dp))
                    GraphLegend(graph)
                }
            }

            // Source reference table (metered exposure → published correction,
            // with the color filter / development note on an indented sub-line)
            // and the guidance-boundary rows — matching iOS Film Details. Sit
            // below the graph, above the legend.
            if (state.referenceRows.isNotEmpty()) {
                HorizontalDivider()
                ReferenceTable("Reference", state.referenceRows, warningTone = false)
            }
            if (state.sourceReferenceRows.isNotEmpty()) {
                HorizontalDivider()
                ReferenceTable("Source reference", state.sourceReferenceRows, warningTone = false)
            }
            if (state.guidanceBoundaryRows.isNotEmpty()) {
                HorizontalDivider()
                ReferenceTable("Guidance boundary", state.guidanceBoundaryRows, warningTone = true)
            }

            // Legend glossary explaining the reference annotations — at the very
            // bottom, matching iOS.
            if (state.legendLines.isNotEmpty()) {
                HorizontalDivider()
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Legend", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    state.legendLines.forEach { line ->
                        Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            // Sources citation (publisher · title · version) + reference line,
            // last, matching iOS "Sources". Shown for every published profile.
            if (state.sourceCitationText != null || state.sourceCitationLink != null) {
                HorizontalDivider()
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Sources", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    state.sourceCitationText?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    state.sourceCitationLink?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun ResultValue(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace, maxLines = 1)
    }
}

@Composable
private fun ReferenceTable(title: String, rows: List<ReciprocityReferenceRow>, warningTone: Boolean) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        rows.forEach { row -> ReferenceRowView(row, warningTone) }
    }
}

@Composable
private fun ReferenceRowView(row: ReciprocityReferenceRow, warningTone: Boolean) {
    val valueColor = if (warningTone) StatusWarning else MaterialTheme.colorScheme.onSurface
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                row.meteredText,
                style = MaterialTheme.typography.labelMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.width(88.dp),
            )
            Text(row.valueText, style = MaterialTheme.typography.bodyMedium, color = valueColor)
        }
        // Color filter / development note, indented under the value column so it
        // stays tied to this metered exposure.
        row.belowNote?.let { note ->
            Text(
                note,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 100.dp),
            )
        }
    }
}

@Composable
private fun ModelRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun toneColor(tone: ReciprocityStatusTone): Color = when (tone) {
    ReciprocityStatusTone.success -> StatusSuccess
    ReciprocityStatusTone.info -> MaterialTheme.colorScheme.primary
    ReciprocityStatusTone.warning -> StatusWarning
    ReciprocityStatusTone.neutral -> MaterialTheme.colorScheme.onSurface
}
