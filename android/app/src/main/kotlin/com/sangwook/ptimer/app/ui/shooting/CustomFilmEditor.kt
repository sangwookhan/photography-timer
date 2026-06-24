package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import com.sangwook.ptimer.ui.component.GraphLegend
import com.sangwook.ptimer.ui.component.ReciprocityGraphView
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmDurationParser
import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.ui.theme.StatusWarning
import com.sangwook.ptimer.app.vm.CustomFilmDraft

// Custom-film editor (formula + table) extracted from ShootingScreen so that
// file stays focused on the main shooting surface. Same package, so the
// shooting screen calls CustomFilmEditorDialog directly.

/**
 * Inline "App-derived formula preview" under the table editor (iOS
 * PTIMER-179/180): the power-law fit from the current anchors, inspection-only,
 * with a per-anchor source-vs-fit comparison, a quality classification, and a
 * Create Custom Formula CTA. The table always stays the reliable calculation.
 */
@Composable
private fun FittedFormulaSection(
    outcome: CustomTableFittedFormula.Outcome,
    onCreateFormula: () -> Unit,
) {
    Spacer(Modifier.height(16.dp))
    Text(
        "APP-DERIVED FORMULA",
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
                "${f.quality.displayLabel} · worst ${fitNum(f.worstAbsoluteStopError)} st",
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
                    "Fit passes through the two anchors exactly — add more to judge curve quality.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "App-derived from your table anchors. Not manufacturer-published guidance.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Button(onClick = onCreateFormula, modifier = Modifier.fillMaxWidth()) {
                Text("Create Custom Formula")
            }
            Spacer(Modifier.height(4.dp))
            Text(
                "Your table is saved, then a separate custom formula film is created from this fit.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun fitNum(value: Double): String = ((value * 10000).toLong() / 10000.0).toString()

/**
 * "Preview" reciprocity curve at the foot of a custom-film editor (matches the
 * iOS editor's Preview section). Shows the live log-log graph once the inputs
 * form a buildable profile, with a placeholder hint until then.
 */
@Composable
private fun ReciprocityPreviewSection(
    graph: ReciprocityGraph?,
    basis: String? = null,
    checkpoints: List<CustomFilmCheckpointRow> = emptyList(),
) {
    Spacer(Modifier.height(16.dp))
    Text(
        "Preview",
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(8.dp))
    if (graph == null) {
        Text(
            "Fill in the fields above to preview the reciprocity curve.",
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
        GraphLegend(showAnchors = graph.anchors.isNotEmpty())
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
private fun CalculationBasisBlock(basis: String) {
    Text(
        "CALCULATION BASIS",
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
private fun CheckpointTable(rows: List<CustomFilmCheckpointRow>) {
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
private fun ReferencePointsSection(rows: List<CustomFilmReferencePointRow>) {
    Spacer(Modifier.height(16.dp))
    Text(
        "REFERENCE POINTS · SOURCE TABLE",
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
private fun clockLabel(seconds: Double): String {
    val s = (Math.round(seconds * 10.0) / 10.0)
    val whole = if (s == s.toLong().toDouble()) s.toLong().toString() else s.toString()
    if (seconds < 60.0) return "${whole}s"
    val total = Math.round(seconds).toInt()
    val m = total / 60
    val rem = total % 60
    val clock = if (rem == 0) "${m}m" else "${m}m ${rem}s"
    return "${total}s ($clock)"
}

/**
 * Custom-film editor — formula path. A shared identity card (manufacturer,
 * label, ISO) over the typeset reciprocity formula with tap-to-edit value
 * chips. Handles create and edit (prefilled from [initial], saved in place).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CustomFilmEditorDialog(
    initial: CustomFilmDraft?,
    onCreateFormula: (CustomFormulaFilmInput, String?) -> Boolean,
    onDismiss: () -> Unit,
) {
    val editId = initial?.filmId
    val isEditing = initial != null

    var label by remember { mutableStateOf(initial?.label ?: "") }
    var manufacturer by remember { mutableStateOf(initial?.manufacturer ?: "") }
    var iso by remember { mutableStateOf(initial?.iso ?: "100") }
    var noCorrection by remember { mutableStateOf(initial?.noCorrection ?: "") }
    var tc0 by remember { mutableStateOf(initial?.tc0?.ifEmpty { "1" } ?: "1") }
    var tm0 by remember { mutableStateOf(initial?.tm0?.ifEmpty { "1" } ?: "1") }
    var exponent by remember { mutableStateOf(initial?.exponent?.ifEmpty { "1.3" } ?: "1.3") }
    var offset by remember { mutableStateOf(initial?.offset?.ifEmpty { "0" } ?: "0") }
    var sourceThrough by remember { mutableStateOf(initial?.sourceThrough?.ifEmpty { "Unlimited" } ?: "Unlimited") }
    var editing by remember { mutableStateOf<EditField?>(null) }
    var showHelp by remember { mutableStateOf(false) }
    fun toggle(f: EditField) { editing = if (editing == f) null else f }

    fun parsedNoCorrection(): Double = when (val p = CustomFilmDurationParser.parse(noCorrection.ifBlank { "1" })) {
        is CustomFilmDurationParser.ParsedDuration.Seconds -> p.value
        else -> 1.0
    }

    fun parsedFormula(): CustomFormulaFilmInput? {
        val labelV = label.trim().ifEmpty { return null }
        val isoV = iso.trim().ifEmpty { "100" }.toIntOrNull() ?: return null
        val tc = tc0.trim().ifEmpty { "1" }.toDoubleOrNull() ?: return null
        val tm = tm0.trim().ifEmpty { "1" }.toDoubleOrNull() ?: return null
        val exp = exponent.trim().ifEmpty { "1.3" }.toDoubleOrNull() ?: return null
        val off = offset.trim().ifEmpty { "0" }.toDoubleOrNull() ?: return null
        val through: Double? = when (val p = CustomFilmDurationParser.parse(sourceThrough)) {
            is CustomFilmDurationParser.ParsedDuration.Seconds -> p.value
            else -> null
        }
        return CustomFormulaFilmInput(
            filmLabel = labelV, profileName = labelV, iso = isoV,
            coefficientSeconds = tc, referenceMeteredTimeSeconds = tm, exponent = exp, offsetSeconds = off,
            noCorrectionThroughSeconds = parsedNoCorrection(), sourceRangeThroughSeconds = through,
            manufacturer = manufacturer.trim().ifEmpty { null },
        )
    }

    FullScreenFormDialog(
        title = if (isEditing) "Edit custom film" else "New custom film",
        confirmLabel = if (isEditing) "Save" else "Create",
        clearErrorOn = "$label|$iso|$manufacturer|$tc0|$tm0|$exponent|$offset|$noCorrection|$sourceThrough",
        onConfirm = {
            val input = parsedFormula()
            when {
                input == null -> "Add a film name (other fields fall back to defaults)."
                !onCreateFormula(input, editId) -> "This formula would shorten exposure in its range. Raise Tc₀ or p, or lower b."
                else -> null
            }
        },
        onDismiss = onDismiss,
    ) {
        CustomFilmTitle(manufacturer, label, iso)
        SectionLabel("Film")
        FormCard {
            EditorRow("Manufacturer", manufacturer.ifBlank { "Optional" }, editing == EditField.Manufacturer) { toggle(EditField.Manufacturer) }
            if (editing == EditField.Manufacturer) {
                ValueEditPanel(manufacturer, { manufacturer = it }, step = null, presets = MANUFACTURER_PRESETS, onClose = { editing = null })
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            EditorRow("Label", label.ifBlank { "Required" }, editing == EditField.Label) { toggle(EditField.Label) }
            if (editing == EditField.Label) {
                ValueEditPanel(label, { label = it }, step = null, presets = emptyList(), onClose = { editing = null })
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            EditorRow("ISO", iso.ifBlank { "Required" }, editing == EditField.Iso) { toggle(EditField.Iso) }
            if (editing == EditField.Iso) {
                ValueEditPanel(iso, { iso = it }, step = null, presets = ISO_PRESETS, onClose = { editing = null })
            }
        }
        Spacer(Modifier.height(12.dp))
        SectionLabel("Formula")
        FormCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { FormulaTemplate() }
                IconButton(onClick = { showHelp = !showHelp }) {
                    Icon(
                        Icons.Outlined.Info,
                        contentDescription = if (showHelp) "Hide formula help" else "Show formula help",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            if (showHelp) FormulaHelpPanel()
            Spacer(Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                EquationText("=")
                FormulaChip("${tc0}s", editing == EditField.Tc0) { toggle(EditField.Tc0) }
                EquationText("×")
                Paren("(")
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.width(IntrinsicSize.Max),
                ) {
                    EquationText("Tm")
                    HorizontalDivider(
                        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 3.dp),
                        thickness = 1.dp,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    FormulaChip("${tm0}s", editing == EditField.Tm0) { toggle(EditField.Tm0) }
                }
                Paren(")")
                Box(Modifier.offset(y = (-12).dp)) {
                    FormulaChip(exponent, editing == EditField.P, compact = true) { toggle(EditField.P) }
                }
                EquationText("+")
                FormulaChip("${offset}s", editing == EditField.B) { toggle(EditField.B) }
            }
            when (editing) {
                EditField.Tc0 -> FormulaValuePanel("Tc₀ — corrected point (s)") {
                    ValueEditPanel(tc0, { tc0 = it }, step = 1.0, presets = TC_PRESETS, onClose = { editing = null })
                }
                EditField.Tm0 -> FormulaValuePanel("Tm₀ — metered point (s)") {
                    ValueEditPanel(tm0, { tm0 = it }, step = 1.0, presets = TM_PRESETS, onClose = { editing = null })
                }
                EditField.P -> FormulaValuePanel("p — curve strength") {
                    ValueEditPanel(exponent, { exponent = it }, step = 0.01, presets = P_PRESETS, onClose = { editing = null })
                }
                EditField.B -> FormulaValuePanel("b — fixed add-on (s)") {
                    ValueEditPanel(offset, { offset = it }, step = 0.5, presets = B_PRESETS, onClose = { editing = null })
                }
                else -> {}
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            EditorRow("No correction", if (noCorrection.isBlank()) "1s (auto)" else durationRowLabel(noCorrection), editing == EditField.NoCorrection) { toggle(EditField.NoCorrection) }
            if (editing == EditField.NoCorrection) {
                ValueEditPanel(
                    noCorrection, { noCorrection = it }, step = 0.1, presets = NO_CORRECTION_PRESETS, onClose = { editing = null },
                    hint = "Exposures at or below this metered time need no correction.",
                )
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            EditorRow("Source data", durationRowLabel(sourceThrough.ifBlank { "Unlimited" }), editing == EditField.SourceData) { toggle(EditField.SourceData) }
            if (editing == EditField.SourceData) {
                ValueEditPanel(
                    sourceThrough, { sourceThrough = it }, step = null, presets = SOURCE_PRESETS, onClose = { editing = null },
                    hint = "The longest metered time the formula is backed by. Past it the result still computes but reads as \"beyond source range\". Use Unlimited if there's no published limit.",
                )
            }
        }
        Spacer(Modifier.height(72.dp))
    }
}

/**
 * Material full-screen dialog for a multi-field input form: a top app bar with
 * a leading close (X) and a trailing confirm action over a scrolling body.
 * [onConfirm] runs validation and returns an error message (rendered at the top
 * of the form; the body scrolls up to it on failure) or null on success.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FullScreenFormDialog(
    title: String,
    confirmLabel: String,
    onConfirm: () -> String?,
    onDismiss: () -> Unit,
    clearErrorOn: Any? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    // Drop a stale validation message when the caller's reset key changes
    // (e.g. the Formula/Table toggle) so a formula error never lingers on the
    // table form, and vice versa.
    LaunchedEffect(clearErrorOn) { error = null }
    Dialog(
        onDismissRequest = onDismiss,
        // Draw edge-to-edge so the Scaffold's system-bar insets and imePadding
        // apply: without this the dialog window keeps the platform insets and
        // the on-screen keyboard covers the focused field (and the content's
        // bottom slides under the navigation bar).
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Surface(modifier = Modifier.fillMaxSize()) {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(title) },
                        navigationIcon = {
                            IconButton(onClick = onDismiss) {
                                Icon(Icons.Filled.Close, contentDescription = "Close")
                            }
                        },
                        actions = {
                            TextButton(onClick = {
                                error = onConfirm()
                                if (error != null) scope.launch { scroll.animateScrollTo(0) }
                            }) { Text(confirmLabel) }
                        },
                    )
                },
            ) { padding ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        // Consume the Scaffold's insets, then reserve the nav bar
                        // (so the bottom content — the preview graph + legend —
                        // clears the home indicator) and the keyboard on top of it
                        // (the canonical navigationBarsPadding().imePadding() stack,
                        // which avoids double-counting the overlap).
                        .consumeWindowInsets(padding)
                        .navigationBarsPadding()
                        .imePadding()
                        .padding(horizontal = 16.dp)
                        .verticalScroll(scroll),
                ) {
                    error?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            it,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Spacer(Modifier.height(4.dp))
                    }
                    content()
                }
            }
        }
    }
}


/**
 * Compact numeric Tm/Tc cell in the table editor (iOS: decimal-pad anchor
 * field). A slim bordered box — not the 56dp Material outlined field — so two
 * cells plus the delete control sit on one tidy line.
 */
@Composable
private fun AnchorField(
    placeholder: String,
    value: String,
    onValue: (String) -> Unit,
    onFocusLost: () -> Unit = {},
) {
    val shape = RoundedCornerShape(8.dp)
    val textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace)
    var wasFocused by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f), shape)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (value.isEmpty()) {
            Text(placeholder, style = textStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        BasicTextField(
            value = value,
            onValueChange = onValue,
            singleLine = true,
            textStyle = textStyle.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier
                .fillMaxWidth()
                // Sorting fires when a cell loses focus (iOS commit point), so a
                // completed row settles into metered order without jumping mid-type.
                .onFocusChanged {
                    if (wasFocused && !it.isFocused) onFocusLost()
                    wasFocused = it.isFocused
                },
        )
    }
}

/** Which custom-film value row is expanded for inline editing. */
private enum class EditField { Manufacturer, Label, Iso, Tc0, Tm0, P, B, NoCorrection, SourceData }

// Preset ladders mirror the iOS field sheets (CustomFilmEditorFieldSheets).
// The formula value chips store bare seconds (the equation appends "s" and the
// steppers parse doubles); the duration-parsed Source-data field keeps unit
// suffixes since the parser accepts s/m/h and "Unlimited".
private val MANUFACTURER_PRESETS = listOf("ADOX", "Kodak", "Ilford", "Fujifilm", "Foma", "Rollei")
private val ISO_PRESETS = listOf(
    "6", "12", "20", "25", "50", "64", "80", "100", "125", "160", "200", "250",
    "320", "400", "500", "640", "800", "1000", "1250", "1600", "3200",
)
private val TC_PRESETS = listOf("0.1", "0.5", "1", "2", "5", "10", "30", "60")
private val TM_PRESETS = listOf("0.5", "1", "2", "5", "10")
private val P_PRESETS = listOf("1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "1.8", "1.9")
private val B_PRESETS = listOf("-1", "-0.5", "0", "0.5", "1", "2")
private val NO_CORRECTION_PRESETS = listOf("0.5", "1", "2", "5", "10", "30")
private val SOURCE_PRESETS = listOf("Unlimited", "30s", "1m", "2m", "5m", "10m", "30m", "1h")

/**
 * Compact list row (label + current value + chevron) that toggles an inline
 * editor below it. The chevron points down while expanded. Keeps editing inside
 * the scrolling form — no nested popup window (which renders unreliably inside
 * the editor's Dialog).
 */
@Composable
private fun EditorRow(label: String, value: String, expanded: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                value.ifBlank { "—" },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(
                if (expanded) Icons.Filled.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** "Source" provenance row in Details: current label + a dropdown of the
 *  CustomProfileSourceType options (iOS: the Source picker). */
@Composable
private fun SourceTypeRow(value: CustomProfileSourceType, onSelect: (CustomProfileSourceType) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Source", style = MaterialTheme.typography.bodyLarge)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(value.displayLabel, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            CustomProfileSourceType.values().forEach { type ->
                DropdownMenuItem(text = { Text(type.displayLabel) }, onClick = { onSelect(type); open = false })
            }
        }
    }
}

/**
 * Inline value editor shown under an expanded [EditorRow]: an optional +/- step
 * stepper around a typable field, plus a row of quick "Common" presets — so a
 * value can be set without the keyboard (mirrors the iOS per-value sheet).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ValueEditPanel(
    value: String,
    onValue: (String) -> Unit,
    step: Double?,
    presets: List<String>,
    onClose: () -> Unit = {},
    hint: String? = null,
) {
    // Scroll the freshly-expanded panel fully into view so a row near the bottom
    // (e.g. No correction) isn't left hidden below the fold / keyboard.
    val bringIntoView = remember { BringIntoViewRequester() }
    LaunchedEffect(Unit) {
        delay(50)
        bringIntoView.bringIntoView()
    }
    Column(Modifier.fillMaxWidth().bringIntoViewRequester(bringIntoView).padding(bottom = 8.dp)) {
        hint?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
        }
        if (step != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { onValue(adjustValue(value, -step)) }) { Text("-${trimNum(step)}") }
                OutlinedTextField(
                    value = value,
                    onValueChange = onValue,
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    textStyle = MaterialTheme.typography.titleMedium.copy(textAlign = TextAlign.Center),
                )
                OutlinedButton(onClick = { onValue(adjustValue(value, step)) }) { Text("+${trimNum(step)}") }
            }
        } else {
            OutlinedTextField(
                value = value,
                onValueChange = onValue,
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (presets.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                presets.forEach { p ->
                    // Picking a preset is a complete choice — apply it and collapse.
                    FilterChip(selected = value == p, onClick = { onValue(p); onClose() }, label = { Text(p) })
                }
            }
        }
    }
}

/**
 * Read-only symbolic structure line shown above the filled equation (iOS:
 * CustomFilmFormulaSymbolicLine). Maps token-for-token onto the value row so
 * the photographer always knows which chip is p, which is b, etc.
 */
@Composable
private fun FormulaTemplate() {
    Text(
        buildAnnotatedString {
            append("Tc = Tc₀ × (Tm / Tm₀)")
            withStyle(SpanStyle(baselineShift = BaselineShift.Superscript, fontSize = 9.sp)) { append("p") }
            append(" + b")
        },
        style = MaterialTheme.typography.bodyMedium,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

/** Tall, light parenthesis bracketing the Tm/Tm₀ fraction (iOS: 30pt light). */
@Composable
private fun Paren(text: String) {
    Text(
        text,
        fontSize = 32.sp,
        fontWeight = FontWeight.Light,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

/** Concept definitions toggled by the (i) button (iOS help-panel wording). */
@Composable
private fun FormulaHelpPanel() {
    val lines = listOf(
        "Tc₀ — corrected exposure at the metered anchor.",
        "Tm₀ — metered exposure used as the anchor.",
        "p — curve strength; higher gives stronger correction at long exposures.",
        "b — fixed time added after the curve.",
        "No correction — Tm at or below this value stays unchanged.",
        "Source data — results past this value read as beyond source range.",
    )
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        lines.forEach {
            Text(
                "•  $it",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Static monospace token in the inline equation. */
@Composable
private fun EquationText(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

/**
 * Tappable value pill embedded in the equation; accent-tinted, with a thin
 * border that strengthens while the pill is being edited (iOS pill style).
 */
@Composable
private fun FormulaChip(value: String, selected: Boolean, compact: Boolean = false, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = if (selected) 0.28f else 0.12f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(
            if (selected) 1.dp else 0.5.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = if (selected) 0.9f else 0.3f),
        ),
    ) {
        Text(
            value,
            // The exponent renders compact so it reads as a raised superscript
            // rather than a full-size term.
            style = if (compact) MaterialTheme.typography.labelMedium else MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(
                horizontal = if (compact) 5.dp else 7.dp,
                vertical = if (compact) 2.dp else 3.dp,
            ),
        )
    }
}

/** Label + inline editor shown under the equation for the tapped chip. */
@Composable
private fun FormulaValuePanel(label: String, content: @Composable () -> Unit) {
    Spacer(Modifier.height(12.dp))
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(4.dp))
    content()
}

/** Adds [delta] to a numeric string, formatted without trailing zeros. */
private fun adjustValue(value: String, delta: Double): String =
    trimNum((value.trim().toDoubleOrNull() ?: 0.0) + delta)

private fun trimNum(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString()
    else (Math.round(value * 100.0) / 100.0).toString()

/**
 * Normalizes a duration row's displayed value: a bare number gains an "s"
 * (0.5 → 0.5s), "unlimited" any-case reads "Unlimited", and unit-bearing text
 * (5m, 1h) is shown as typed — so No correction / Source data read consistently.
 */
private fun durationRowLabel(raw: String): String {
    val t = raw.trim()
    if (t.equals("unlimited", ignoreCase = true)) return "Unlimited"
    return t.toDoubleOrNull()?.let { "${trimNum(it)}s" } ?: t
}

/** Live editor title derived from the in-progress maker/label/ISO (iOS header). */
@Composable
private fun CustomFilmTitle(manufacturer: String, label: String, iso: String) {
    val name = listOf(manufacturer.trim(), label.trim()).filter { it.isNotEmpty() }.joinToString(" ")
    val isoText = iso.trim().toIntOrNull()?.let { " · ISO $it" } ?: ""
    Text(
        if (name.isEmpty()) "New custom film" else "$name$isoText",
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.Bold,
    )
    Spacer(Modifier.height(12.dp))
}

/** Section label above a grouped editor card (iOS groups fields under headers). */
@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(bottom = 6.dp),
    )
}

/** Card grouping a set of editor fields, matching iOS's grouped-list look. */
@Composable
private fun FormCard(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp), content = content)
    }
}
