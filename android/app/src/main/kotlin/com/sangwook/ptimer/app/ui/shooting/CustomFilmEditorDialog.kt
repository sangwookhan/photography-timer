// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import com.sangwook.ptimer.R
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmDurationParser
import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.app.vm.CustomFilmDraft
/**
 * Single custom-film editor with a Formula/Table segmented toggle (iOS's
 * "New custom film"): a shared identity card, the mode toggle, then the
 * mode-specific fields and a live preview. Handles both create and edit
 * (prefilled from [initial], saved in place under the same id).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CustomFilmEditorDialog(
    initial: CustomFilmDraft?,
    onCreateFormula: (CustomFormulaFilmInput, String?) -> Boolean,
    onCreateTable: (CustomTableFilmInput, String?) -> Boolean,
    onPreviewFormula: (CustomFormulaFilmInput) -> ReciprocityGraph?,
    onPreviewTable: (CustomTableFilmInput) -> ReciprocityGraph?,
    onFormulaCheckpoints: (CustomFormulaFilmInput) -> List<CustomFilmCheckpointRow>,
    onTableCheckpoints: (CustomTableFilmInput) -> List<CustomFilmCheckpointRow>,
    onCalculationBasis: (CustomFormulaFilmInput) -> String,
    onPreviewTableFit: (CustomTableFilmInput) -> CustomTableFittedFormula.Outcome?,
    onCreateFormulaFromTable: (CustomTableFilmInput, String?) -> Boolean,
    onReferencePoints: (CustomFormulaFilmInput, List<Pair<Double, Double>>) -> List<CustomFilmReferencePointRow>,
    onDismiss: () -> Unit,
) {
    // A formula derived from a table keeps a link back to it; its current anchors
    // (resolved when the editor opened) drive the live reference-points table.
    val referenceTableFilmId = initial?.referenceTableFilmId
    val linkedTableAnchors = initial?.linkedTableAnchors ?: emptyList()
    val editId = initial?.filmId
    val isEditing = initial != null
    var isTable by remember { mutableStateOf(initial?.isTable ?: false) }

    // Shared identity. A blank numeric field falls back to its default so the
    // form is creatable without filling every box (no required-field dead ends).
    var label by remember { mutableStateOf(initial?.label ?: "") }
    var manufacturer by remember { mutableStateOf(initial?.manufacturer ?: "") }
    var iso by remember { mutableStateOf(initial?.iso ?: "100") }
    // Blank by default: formula falls back to 1s; table derives first-anchor ÷ 10
    // (so a typical table like 1→2 / 10→20 isn't rejected by a no-correction time
    // that collides with the first anchor).
    var noCorrection by remember { mutableStateOf(initial?.noCorrection ?: "") }
    // Formula fields (all default to a usable starting point, incl. Tc₀).
    var tc0 by remember { mutableStateOf(initial?.tc0?.ifEmpty { "1" } ?: "1") }
    var tm0 by remember { mutableStateOf(initial?.tm0?.ifEmpty { "1" } ?: "1") }
    var exponent by remember { mutableStateOf(initial?.exponent?.ifEmpty { "1.3" } ?: "1.3") }
    var offset by remember { mutableStateOf(initial?.offset?.ifEmpty { "0" } ?: "0") }
    var sourceThrough by remember { mutableStateOf(initial?.sourceThrough?.ifEmpty { "Unlimited" } ?: "Unlimited") }
    // Details (provenance) — descriptive only, never read by the calculation.
    var notes by remember { mutableStateOf(initial?.notes ?: "") }
    var sourceType by remember { mutableStateOf(initial?.sourceType ?: CustomProfileSourceType.userDefined) }
    var referenceUrl by remember { mutableStateOf(initial?.referenceUrl ?: "") }
    // Table anchors (prefilled; start with two empty rows when creating).
    val metered = remember {
        val seed = initial?.anchors?.map { it.first } ?: emptyList()
        mutableStateListOf<String>().apply { addAll(if (seed.size >= 2) seed else listOf("", "")) }
    }
    val corrected = remember {
        val seed = initial?.anchors?.map { it.second } ?: emptyList()
        mutableStateListOf<String>().apply { addAll(if (seed.size >= 2) seed else listOf("", "")) }
    }
    // Which formula/identity value is expanded for inline stepper/preset editing
    // (one at a time). Table anchor cells are plain numeric fields (iOS parity).
    var editing by remember { mutableStateOf<EditField?>(null) }
    // Formula concept help panel, toggled by the (i) button (iOS parity).
    var showHelp by remember { mutableStateOf(false) }
    fun toggle(f: EditField) { editing = if (editing == f) null else f }

    // Sort complete (both-filled) anchor rows by metered time, keeping any
    // half-typed rows in place at the end — iOS sorts at the focus-leave commit
    // point so a finished row settles into order without jumping mid-entry.
    fun sortAnchors() {
        val rows = metered.indices.map { metered[it] to corrected[it] }
        val complete = rows.filter { it.first.trim().toDoubleOrNull() != null && it.second.trim().toDoubleOrNull() != null }
        val incomplete = rows.filterNot { it.first.trim().toDoubleOrNull() != null && it.second.trim().toDoubleOrNull() != null }
        val sorted = complete.sortedBy { it.first.trim().toDouble() } + incomplete
        if (sorted == rows) return
        metered.clear(); metered.addAll(sorted.map { it.first })
        corrected.clear(); corrected.addAll(sorted.map { it.second })
    }

    // Formula no-correction: blank falls back to 1s (iOS neutral default).
    fun parsedNoCorrection(): Double = when (val p = CustomFilmDurationParser.parse(noCorrection.ifBlank { "1" })) {
        is CustomFilmDurationParser.ParsedDuration.Seconds -> p.value
        else -> 1.0
    }

    // Table no-correction: blank derives the first anchor ÷ 10 so it always sits
    // safely below the first metered anchor (iOS: defaultTableNoCorrectionSeconds).
    fun tableNoCorrection(firstAnchorSeconds: Double): Double =
        when (val p = CustomFilmDurationParser.parse(noCorrection)) {
            is CustomFilmDurationParser.ParsedDuration.Seconds -> p.value
            else -> firstAnchorSeconds / 10.0
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
            notes = notes.trim().ifEmpty { null }, sourceType = sourceType,
            referenceUrl = referenceUrl.trim().ifEmpty { null },
            referenceTableFilmId = referenceTableFilmId,
        )
    }

    fun parsedTable(): CustomTableFilmInput? {
        val labelV = label.trim().ifEmpty { return null }
        val isoV = iso.trim().ifEmpty { "100" }.toIntOrNull() ?: return null
        val anchors = metered.indices.mapNotNull { i ->
            val m = metered[i].trim().toDoubleOrNull()
            val c = corrected[i].trim().toDoubleOrNull()
            if (m != null && c != null) m to c else null
        }
        if (anchors.size < 2) return null
        val firstAnchor = anchors.minOf { it.first }
        return CustomTableFilmInput(
            filmLabel = labelV, profileName = labelV, iso = isoV, anchors = anchors,
            noCorrectionThroughSeconds = tableNoCorrection(firstAnchor), manufacturer = manufacturer.trim().ifEmpty { null },
            notes = notes.trim().ifEmpty { null }, sourceType = sourceType,
            referenceUrl = referenceUrl.trim().ifEmpty { null },
        )
    }

    val context = LocalContext.current
    FullScreenFormDialog(
        title = if (isEditing) stringResource(R.string.cf_edit) else stringResource(R.string.cf_new),
        confirmLabel = if (isEditing) stringResource(R.string.action_save) else stringResource(R.string.action_create),
        // Value-equal key over every field, so a validation error clears the
        // moment any input changes (no stale message after a fix), but survives
        // recomposition when nothing changed.
        clearErrorOn = "$isTable|$label|$iso|$manufacturer|$tc0|$tm0|$exponent|$offset|" +
            "$noCorrection|$sourceThrough|${metered.joinToString(",")}|${corrected.joinToString(",")}",
        onConfirm = {
            if (isTable) {
                val input = parsedTable()
                when {
                    input == null -> context.getString(R.string.cf_validation_table)
                    !onCreateTable(input, editId) -> context.getString(R.string.cf_validation_table_order)
                    else -> null
                }
            } else {
                val input = parsedFormula()
                when {
                    input == null -> context.getString(R.string.cf_validation_formula_name)
                    !onCreateFormula(input, editId) -> context.getString(R.string.cf_validation_formula_shorten)
                    else -> null
                }
            }
        },
        onDismiss = onDismiss,
    ) {
        val optionalHint = stringResource(R.string.common_optional)
        val requiredHint = stringResource(R.string.common_required)
        CustomFilmTitle(manufacturer, label, iso)
        SectionLabel(stringResource(R.string.shooting_film))
        // iOS identity order: Manufacturer, Label, ISO — each a compact
        // tap-to-edit row that expands an inline value editor below it.
        FormCard {
            EditorRow(stringResource(R.string.cf_manufacturer), manufacturer.ifBlank { optionalHint }, editing == EditField.Manufacturer) { toggle(EditField.Manufacturer) }
            if (editing == EditField.Manufacturer) {
                ValueEditPanel(manufacturer, { manufacturer = it }, step = null, presets = MANUFACTURER_PRESETS, onClose = { editing = null })
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            EditorRow(stringResource(R.string.cf_label), label.ifBlank { requiredHint }, editing == EditField.Label) { toggle(EditField.Label) }
            if (editing == EditField.Label) {
                ValueEditPanel(label, { label = it }, step = null, presets = emptyList(), onClose = { editing = null })
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            EditorRow("ISO", iso.ifBlank { requiredHint }, editing == EditField.Iso) { toggle(EditField.Iso) }
            if (editing == EditField.Iso) {
                ValueEditPanel(iso, { iso = it }, step = null, presets = ISO_PRESETS, onClose = { editing = null })
            }
        }

        // The calculation kind is fixed once a film is saved (iOS hides this
        // picker in the edit flow): a table film stays a table, a formula film
        // stays a formula — editing can never silently convert one into the other.
        if (!isEditing) {
            Spacer(Modifier.height(16.dp))
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = !isTable,
                    onClick = { isTable = false; editing = null },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                ) { Text(stringResource(R.string.cf_formula)) }
                SegmentedButton(
                    selected = isTable,
                    onClick = { isTable = true; editing = null },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                ) { Text(stringResource(R.string.cf_table)) }
            }
        }
        Spacer(Modifier.height(12.dp))

        if (isTable) {
            // iOS table card: editable Tm → Tc anchor rows with add/delete, an
            // editable no-correction boundary, and a read-only derived source
            // range (the last anchor). Plain numeric fields, like iOS.
            SectionLabel(stringResource(R.string.cf_table_header))
            FormCard {
                Text(
                    stringResource(R.string.cf_table_instructions),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(10.dp))
                metered.indices.forEach { i ->
                    Row(
                        modifier = Modifier.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Box(Modifier.weight(1f)) { AnchorField("Tm", metered[i], { metered[i] = it }, onFocusLost = ::sortAnchors) }
                        EquationText("→")
                        Box(Modifier.weight(1f)) { AnchorField("Tc", corrected[i], { corrected[i] = it }, onFocusLost = ::sortAnchors) }
                        IconButton(
                            onClick = { metered.removeAt(i); corrected.removeAt(i) },
                            enabled = metered.size > 2,
                            modifier = Modifier.size(40.dp),
                        ) {
                            Icon(
                                Icons.Filled.Delete,
                                contentDescription = stringResource(R.string.cf_remove_row),
                                tint = if (metered.size > 2) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                            )
                        }
                    }
                }
                TextButton(onClick = { metered.add(""); corrected.add("") }) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.cf_add_row))
                }
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                val firstMetered = metered.mapNotNull { it.trim().toDoubleOrNull() }.minOrNull()
                val noCorrPlaceholder = firstMetered?.let { stringResource(R.string.cf_no_correction_auto_fmt, trimNum(it / 10.0)) } ?: stringResource(R.string.cf_auto)
                EditorRow(stringResource(R.string.cf_no_correction), if (noCorrection.isBlank()) noCorrPlaceholder else durationRowLabel(noCorrection), editing == EditField.NoCorrection) { toggle(EditField.NoCorrection) }
                if (editing == EditField.NoCorrection) {
                    ValueEditPanel(
                        noCorrection, { noCorrection = it }, step = 0.1, presets = NO_CORRECTION_PRESETS, onClose = { editing = null },
                        hint = stringResource(R.string.cf_no_correction_hint_table),
                    )
                }
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                val lastMetered = metered.mapNotNull { it.trim().toDoubleOrNull() }.maxOrNull()
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        stringResource(R.string.cf_source_data),
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    Text(
                        if (lastMetered != null) stringResource(R.string.cf_source_range, trimNum(lastMetered)) else stringResource(R.string.cf_source_last_anchor),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            ReciprocityPreviewSection(
                graph = parsedTable()?.let(onPreviewTable),
                checkpoints = parsedTable()?.let(onTableCheckpoints) ?: emptyList(),
            )
            // App-derived formula preview (iOS PTIMER-179/180): the fit from the
            // current anchors, inspection-only, with a Create Custom Formula CTA.
            parsedTable()?.let(onPreviewTableFit)?.let { outcome ->
                FittedFormulaSection(
                    outcome = outcome,
                    onCreateFormula = { parsedTable()?.let { onCreateFormulaFromTable(it, editId) } },
                )
            }
        } else {
            SectionLabel(stringResource(R.string.cf_formula))
            FormCard {
                // Symbolic line names each value (so you always know which chip is
                // p, which is b…); the (i) toggle expands the concept definitions.
                // The filled line below carries tappable, keyboard-free value chips
                // — typeset like iOS: a stacked Tm/Tm₀ fraction inside tall parens,
                // p as a raised exponent.
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { FormulaTemplate() }
                    IconButton(onClick = { showHelp = !showHelp }) {
                        Icon(
                            Icons.Outlined.Info,
                            contentDescription = if (showHelp) stringResource(R.string.cf_hide_formula_help) else stringResource(R.string.cf_show_formula_help),
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
                    EditField.Tc0 -> FormulaValuePanel(stringResource(R.string.cf_tc0_label)) {
                        ValueEditPanel(tc0, { tc0 = it }, step = 1.0, presets = TC_PRESETS, onClose = { editing = null })
                    }
                    EditField.Tm0 -> FormulaValuePanel(stringResource(R.string.cf_tm0_label)) {
                        ValueEditPanel(tm0, { tm0 = it }, step = 1.0, presets = TM_PRESETS, onClose = { editing = null })
                    }
                    EditField.P -> FormulaValuePanel(stringResource(R.string.cf_p_label)) {
                        ValueEditPanel(exponent, { exponent = it }, step = 0.01, presets = P_PRESETS, onClose = { editing = null })
                    }
                    EditField.B -> FormulaValuePanel(stringResource(R.string.cf_b_label)) {
                        ValueEditPanel(offset, { offset = it }, step = 0.5, presets = B_PRESETS, onClose = { editing = null })
                    }
                    else -> {}
                }
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                EditorRow(stringResource(R.string.cf_no_correction), if (noCorrection.isBlank()) stringResource(R.string.cf_no_correction_default_formula) else durationRowLabel(noCorrection), editing == EditField.NoCorrection) { toggle(EditField.NoCorrection) }
                if (editing == EditField.NoCorrection) {
                    ValueEditPanel(
                        noCorrection, { noCorrection = it }, step = 0.1, presets = NO_CORRECTION_PRESETS, onClose = { editing = null },
                        hint = stringResource(R.string.cf_no_correction_hint_formula),
                    )
                }
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                EditorRow(stringResource(R.string.cf_source_data), localizedDurationRowLabel(sourceThrough.ifBlank { "Unlimited" }), editing == EditField.SourceData) { toggle(EditField.SourceData) }
                if (editing == EditField.SourceData) {
                    ValueEditPanel(
                        sourceThrough, { sourceThrough = it }, step = null, presets = SOURCE_PRESETS, onClose = { editing = null },
                        hint = stringResource(R.string.cf_source_hint_formula),
                    )
                }
            }
            ReciprocityPreviewSection(
                graph = parsedFormula()?.let(onPreviewFormula),
                basis = parsedFormula()?.let(onCalculationBasis),
                checkpoints = parsedFormula()?.let(onFormulaCheckpoints) ?: emptyList(),
            )
            // Reference points vs the source table (iOS PTIMER-180): when this
            // formula was derived from a table, compare it against that table's
            // current anchors so added/changed anchors show up here.
            if (linkedTableAnchors.isNotEmpty()) {
                val refRows = parsedFormula()?.let { onReferencePoints(it, linkedTableAnchors) } ?: emptyList()
                if (refRows.isNotEmpty()) ReferencePointsSection(refRows)
            }
        }

        // Details (provenance) — lower-priority metadata below the preview, as on
        // iOS. Descriptive only; never affects the calculation.
        Spacer(Modifier.height(16.dp))
        SectionLabel(stringResource(R.string.cf_details))
        FormCard {
            SourceTypeRow(sourceType) { sourceType = it }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(
                stringResource(R.string.cf_notes),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                placeholder = { Text(stringResource(R.string.common_optional)) },
                minLines = 1,
                maxLines = 4,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            )
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            OutlinedTextField(
                value = referenceUrl,
                onValueChange = { referenceUrl = it },
                label = { Text(stringResource(R.string.cf_reference_url)) },
                placeholder = { Text(stringResource(R.string.common_optional)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // Generous trailing whitespace so the preview graph + legend sit
        // comfortably above the bottom rather than flush against it.
        Spacer(Modifier.height(72.dp))
    }
}
