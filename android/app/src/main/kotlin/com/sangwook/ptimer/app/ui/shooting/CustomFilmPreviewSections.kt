// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.res.stringResource
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.localizedCoreText
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sangwook.ptimer.ui.component.GraphLegend
import com.sangwook.ptimer.ui.component.ReciprocityGraphView
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointRow
import com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.ui.theme.StatusWarning
/**
 * Inline "App-derived formula preview" under the table editor (iOS
 * PTIMER-179/180): the power-law fit from the current anchors, inspection-only,
 * with a per-anchor source-vs-fit comparison, a quality classification, and a
 * Create Custom Formula CTA. The table always stays the reliable calculation.
 */
@Composable
internal fun FittedFormulaSection(
    outcome: CustomTableFittedFormula.Outcome,
    onCreateFormula: () -> Unit,
) {
    Spacer(Modifier.height(16.dp))
    Text(
        stringResource(R.string.cf_app_derived_formula),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(8.dp))
    when (outcome) {
        is CustomTableFittedFormula.Outcome.Unavailable -> {
            Text(outcome.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        is CustomTableFittedFormula.Outcome.Available -> {
            val f = outcome.formula
            Text(
                buildAnnotatedString {
                    append("Tc = ${fitNum(f.coefficientSeconds)} × Tm")
                    withStyle(SpanStyle(baselineShift = BaselineShift.Superscript, fontSize = 11.sp)) {
                        append(fitNum(f.exponent))
                    }
                },
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                "a ${fitNum(f.coefficientSeconds)} · p ${fitNum(f.exponent)} · b ${fitNum(f.offsetSeconds)}",
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            // Per-anchor source-vs-fit comparison.
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                f.comparisonRows.forEach { row ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(clockLabel(row.meteredSeconds), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 1, modifier = Modifier.weight(1.1f))
                        Text(clockLabel(row.sourceCorrectedSeconds), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 1, modifier = Modifier.weight(1.2f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(clockLabel(row.fittedCorrectedSeconds), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 1, modifier = Modifier.weight(1.2f))
                        Text("%+.2f st".format(row.stopError), style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "${localizedCoreText(f.quality.displayLabel)} · worst ${fitNum(f.worstAbsoluteStopError)} st",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = when (f.quality) {
                    CustomTableFittedFormula.FitQuality.good -> MaterialTheme.colorScheme.primary
                    CustomTableFittedFormula.FitQuality.borderline -> StatusWarning
                    CustomTableFittedFormula.FitQuality.poor -> MaterialTheme.colorScheme.error
                },
            )
            if (f.isTwoAnchorExactFit) {
                Spacer(Modifier.height(4.dp))
                Text(
                    stringResource(R.string.cf_two_anchor_note),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.cf_not_manufacturer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Button(onClick = onCreateFormula, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.cf_create_custom_formula))
            }
            Spacer(Modifier.height(4.dp))
            Text(
                stringResource(R.string.cf_table_saved_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

internal fun fitNum(value: Double): String = ((value * 10000).toLong() / 10000.0).toString()

/**
 * "Preview" reciprocity curve at the foot of a custom-film editor (matches the
 * iOS editor's Preview section). Shows the live log-log graph once the inputs
 * form a buildable profile, with a placeholder hint until then.
 */
@Composable
internal fun ReciprocityPreviewSection(
    graph: ReciprocityGraph?,
    basis: String? = null,
    checkpoints: List<CustomFilmCheckpointRow> = emptyList(),
) {
    Spacer(Modifier.height(16.dp))
    Text(
        stringResource(R.string.cf_preview),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(8.dp))
    if (graph == null) {
        Text(
            stringResource(R.string.cf_preview_fill),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    } else {
        ReciprocityGraphView(graph, Modifier.fillMaxWidth().height(220.dp))
        Spacer(Modifier.height(4.dp))
        Text(
            "Horizontal: metered time · Vertical: corrected exposure",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        GraphLegend(graph)
        if (basis != null) {
            Spacer(Modifier.height(16.dp))
            CalculationBasisBlock(basis)
        }
        if (checkpoints.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            CheckpointTable(checkpoints)
        }
    }
    Spacer(Modifier.height(8.dp))
}

/** "Calculation basis" line under the preview graph (iOS parity); the exponent
 *  after `Tm^` renders as a superscript. */
@Composable
internal fun CalculationBasisBlock(basis: String) {
    Text(
        stringResource(R.string.cf_calculation_basis),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(4.dp))
    val caret = basis.indexOf('^')
    val text = if (caret < 0) {
        buildAnnotatedString { append(basis) }
    } else {
        buildAnnotatedString {
            append(basis.substring(0, caret))
            withStyle(SpanStyle(baselineShift = BaselineShift.Superscript, fontSize = 11.sp)) {
                append(basis.substring(caret + 1))
            }
        }
    }
    Text(text, style = MaterialTheme.typography.titleMedium, fontFamily = FontFamily.Monospace)
}

/** Per-sample checkpoint table (metered → corrected → Δstop) mirroring the iOS
 *  editor preview, so the photographer can sanity-check the curve before saving. */
@Composable
internal fun CheckpointTable(rows: List<CustomFilmCheckpointRow>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    clockLabel(row.meteredSeconds),
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    modifier = Modifier.weight(1.15f),
                )
                Text(
                    row.correctedSeconds?.let(::clockLabel) ?: "—",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    modifier = Modifier.weight(1.3f),
                )
                Text(
                    when {
                        row.stopDelta == null -> "No correction"
                        else -> "+%.1f stops".format(row.stopDelta)
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = when {
                        row.stopDelta == null -> MaterialTheme.colorScheme.onSurfaceVariant
                        row.beyondSourceRange -> StatusWarning
                        else -> MaterialTheme.colorScheme.primary
                    },
                    textAlign = TextAlign.End,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

/**
 * Reference points for a formula derived from a table (iOS PTIMER-180): the
 * source table's anchors with the formula's prediction and the stop error,
 * resolved against the table's current anchors so edits to the table appear.
 */
@Composable
internal fun ReferencePointsSection(rows: List<CustomFilmReferencePointRow>) {
    Spacer(Modifier.height(16.dp))
    Text(
        stringResource(R.string.cf_reference_points),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(6.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("Metered", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, modifier = Modifier.weight(1.1f))
        Text("Formula", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, modifier = Modifier.weight(1.2f))
        Text("Table", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, modifier = Modifier.weight(1.2f))
        Text("Error", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
    }
    Spacer(Modifier.height(4.dp))
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        rows.forEach { row ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(clockLabel(row.meteredSeconds), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 1, modifier = Modifier.weight(1.1f))
                Text(row.formulaCorrectedSeconds?.let(::clockLabel) ?: "—", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 1, modifier = Modifier.weight(1.2f))
                Text(clockLabel(row.referenceCorrectedSeconds), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 1, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1.2f))
                Text(
                    row.stopError?.let { "%+.2f st".format(it) } ?: "—",
                    style = MaterialTheme.typography.labelMedium,
                    textAlign = TextAlign.End,
                    color = row.stopError?.let { if (kotlin.math.abs(it) <= 0.1) MaterialTheme.colorScheme.onSurfaceVariant else StatusWarning }
                        ?: MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
    Spacer(Modifier.height(4.dp))
    Text(
        "Formula vs the table it was derived from. Edit the table to update these.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** Compact seconds label with a clock hint past a minute (12s, 79s (1m 19s)). */
internal fun clockLabel(seconds: Double): String {
    val s = (Math.round(seconds * 10.0) / 10.0)
    val whole = if (s == s.toLong().toDouble()) s.toLong().toString() else s.toString()
    if (seconds < 60.0) return "${whole}s"
    val total = Math.round(seconds).toInt()
    val m = total / 60
    val rem = total % 60
    val clock = if (rem == 0) "${m}m" else "${m}m ${rem}s"
    return "${total}s ($clock)"
}
