// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.FilterSetItemOrder
import com.sangwook.ptimer.app.vm.FilterItemEditorDraft
import com.sangwook.ptimer.app.vm.FilterItemSaveBlockReason
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterValueUnit

/** Which physical filter the editor opened on. */
internal sealed class FilterItemEditorTarget {
    /** A brand-new item from an Add Filter action, starting at ND in the
     *  session's remembered notation (FILTER-ITEM-003/007); the type and
     *  the Filter Set are chosen inside the editor. */
    data class New(val initialUnit: FilterValueUnit) : FilterItemEditorTarget()

    data class Existing(val item: FilterItem) : FilterItemEditorTarget()
}

/**
 * Registers or edits one physical filter (FILTER-ITEM-002/003/004,
 * FILTER-CPL-001..004, FILTER-GND-001/003, FILTER-COLOR-001/002). The
 * kind is chosen explicitly; ND and GND take a decimal value in Stops,
 * OD, or ND factor with the canonical conversion shown live, a CPL
 * exposes its three exposure-loss fields on a decimal keyboard, a Color
 * filter records its optical color beside an explicit loss in stops, and
 * an Effect filter its explicit loss. Saving is refused —
 * with the affected cameras — when a stack would exceed 30 stops or
 * would lose a row it currently mounts (FILTER-ITEM-005).
 *
 * A new filter always shows its Filter Set (FILTER-ITEM-009): it starts
 * in [initialFilterSetId] — Default from Shooting Filters, the
 * containing set from a set editor — may move to any set, and Add Filter
 * Set creates one in place and returns with it selected and the entered
 * values kept. The field stays enabled for an existing filter: saving it
 * into another set moves it there with its identity.
 *
 * [onSaved] receives the committed item so the owning Filter Set editor
 * can remember a NEW item's notation. (iOS: `FilterItemEditorView`.)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FilterItemEditorDialog(
    target: FilterItemEditorTarget,
    filterSets: List<FilterSet>,
    initialFilterSetId: FilterSetId,
    suggestCreationColor: () -> FilterSetColor,
    createFilterSet: (String, FilterSetColor) -> FilterSet?,
    onSave: (FilterItem, FilterSetId) -> FilterItemSaveOutcome,
    onSaved: (FilterItem) -> Unit,
    onDismiss: () -> Unit,
) {
    var filterSetId by remember(target) { mutableStateOf(initialFilterSetId) }
    var creationColor by remember { mutableStateOf<FilterSetColor?>(null) }
    var draft by remember(target) {
        mutableStateOf(
            when (target) {
                is FilterItemEditorTarget.New -> FilterItemEditorDraft(
                    kind = FilterSetItemOrder.newItemKind,
                    unit = target.initialUnit,
                )
                is FilterItemEditorTarget.Existing ->
                    FilterItemEditorDraft.editing(target.item.name, target.item.behavior)
            },
        )
    }
    var blocked by remember { mutableStateOf<FilterItemSaveOutcome.Blocked?>(null) }
    val nameFocus = remember { FocusRequester() }
    val isNew = target is FilterItemEditorTarget.New
    // Every type, ND first, for a new and an existing item alike: a new
    // filter chooses its type here, an existing one may be corrected.
    val selectableKinds = FilterSetItemOrder.kinds
    LaunchedEffect(target) { if (isNew) runCatching { nameFocus.requestFocus() } }

    fun save() {
        val item = draft.toItem((target as? FilterItemEditorTarget.Existing)?.item?.id) ?: return
        when (val outcome = onSave(item, filterSetId)) {
            is FilterItemSaveOutcome.Saved -> {
                onSaved(item)
                onDismiss()
            }

            is FilterItemSaveOutcome.Blocked -> blocked = outcome
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        // Edge-to-edge so the Scaffold's own insets and imePadding apply and
        // the keyboard never covers the focused field (see FullScreenFormDialog).
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = {
                                Text(
                                    stringResource(
                                        if (isNew) R.string.filter_item_new else R.string.filter_item_edit,
                                    ),
                                )
                            },
                            // Material: dismiss is the leading navigation icon.
                            navigationIcon = {
                                IconButton(onClick = onDismiss) {
                                    Icon(
                                        Icons.Filled.Close,
                                        contentDescription = stringResource(R.string.action_cancel),
                                    )
                                }
                            },
                            actions = {
                                TextButton(onClick = ::save, enabled = draft.canSave) {
                                    Text(stringResource(R.string.action_save))
                                }
                            },
                        )
                    },
                ) { padding ->
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .consumeWindowInsets(padding)
                            .navigationBarsPadding()
                            .imePadding()
                            .padding(horizontal = 16.dp)
                            .verticalScroll(rememberScrollState()),
                    ) {
                        FilterSetField(
                            filterSets = filterSets,
                            selection = filterSetId,
                            onSelect = { filterSetId = it },
                            onAddFilterSet = { creationColor = suggestCreationColor() },
                        )
                        Spacer(Modifier.height(16.dp))
                        OutlinedTextField(
                            value = draft.name,
                            onValueChange = { draft = draft.copy(name = it) },
                            label = { Text(stringResource(R.string.filter_item_name)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(nameFocus),
                        )
                        // The type comes first, before its type-specific
                        // fields (FILTER-ITEM-003).
                        Spacer(Modifier.height(16.dp))
                        SectionLabel(stringResource(R.string.filter_item_kind))
                        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                            selectableKinds.forEachIndexed { index, kind ->
                                SegmentedButton(
                                    selected = draft.kind == kind,
                                    onClick = { draft = draft.copy(kind = kind) },
                                    shape = SegmentedButtonDefaults.itemShape(
                                        index = index,
                                        count = selectableKinds.size,
                                    ),
                                ) { Text(localizedFilterKindName(kind), maxLines = 1) }
                            }
                        }
                        FooterText(stringResource(R.string.filter_item_kind_footer))

                        Spacer(Modifier.height(20.dp))
                        when (draft.kind) {
                            FilterItemKind.fixed, FilterItemKind.gnd ->
                                RegisteredValueSection(draft) { draft = it }

                            FilterItemKind.cpl -> CplChoicesSection(draft) { draft = it }

                            FilterItemKind.color -> {
                                OpticalColorSection(draft) { draft = it }
                                Spacer(Modifier.height(20.dp))
                                ExposureLossSection(draft) { draft = it }
                            }

                            FilterItemKind.effect -> ExposureLossSection(draft) { draft = it }
                        }

                        if (draft.kind == FilterItemKind.gnd) {
                            Spacer(Modifier.height(20.dp))
                            SectionLabel(stringResource(R.string.filter_gnd_modes))
                            Text(
                                stringResource(R.string.filter_gnd_modes_body),
                                style = MaterialTheme.typography.bodySmall,
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                stringResource(R.string.filter_gnd_modes_warning),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Spacer(Modifier.height(24.dp))
                    }
                }
            }
        }
    }

    creationColor?.let { color ->
        NewFilterSetDialog(
            suggestedColor = color,
            onSave = { name, chosen ->
                creationColor = null
                // Back in the editor with the new set selected; the
                // entered values are this dialog's state and stay.
                createFilterSet(name, chosen)?.let { filterSetId = it.id }
            },
            onDismiss = { creationColor = null },
        )
    }

    blocked?.let { outcome ->
        val cameras = localizedCameraNames(outcome.affectedCameras)
        AlertDialog(
            onDismissRequest = { blocked = null },
            title = { CappedFontScale { Text(stringResource(R.string.filter_item_save_blocked_title)) } },
            text = {
                CappedFontScale {
                    Text(
                        stringResource(
                            when (outcome.reason) {
                                FilterItemSaveBlockReason.exceedsTotalLimit ->
                                    R.string.filter_item_save_blocked_limit

                                FilterItemSaveBlockReason.removesSelectedChoice ->
                                    R.string.filter_item_save_blocked_choice

                                FilterItemSaveBlockReason.tooManyNDWheels ->
                                    R.string.filter_item_save_blocked_nd_wheels
                            },
                            cameras,
                        ),
                    )
                }
            },
            confirmButton = {
                CappedFontScale {
                    TextButton(onClick = { blocked = null }) { Text(stringResource(R.string.action_confirm)) }
                }
            },
        )
    }
}

/** Fixed / GND registered value: decimal field, unit choice, live
 *  canonical conversion (FILTER-ITEM-004). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RegisteredValueSection(draft: FilterItemEditorDraft, onDraft: (FilterItemEditorDraft) -> Unit) {
    SectionLabel(
        stringResource(
            if (draft.kind == FilterItemKind.gnd) {
                R.string.filter_item_full_density
            } else {
                R.string.filter_item_exposure_loss
            },
        ),
    )
    OutlinedTextField(
        value = draft.valueText,
        onValueChange = { onDraft(draft.copy(valueText = it)) },
        label = { Text(stringResource(R.string.filter_item_value)) },
        singleLine = true,
        isError = draft.hasValueError,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(8.dp))
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        FilterValueUnit.entries.forEachIndexed { index, unit ->
            SegmentedButton(
                selected = draft.unit == unit,
                onClick = { onDraft(draft.copy(unit = unit)) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = FilterValueUnit.entries.size),
            ) {
                Text(
                    stringResource(
                        when (unit) {
                            FilterValueUnit.stops -> R.string.notation_stops
                            FilterValueUnit.opticalDensity -> R.string.notation_od
                            FilterValueUnit.filterFactor -> R.string.notation_nd
                        },
                    ),
                )
            }
        }
    }
    draft.canonicalStops?.let { stops ->
        Spacer(Modifier.height(8.dp))
        Text(
            stringResource(R.string.filter_item_conversion, filterStopsText(stops)),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    if (draft.hasValueError) {
        Spacer(Modifier.height(4.dp))
        ErrorText(stringResource(R.string.filter_item_value_error))
    }
    FooterText(stringResource(R.string.filter_item_value_footer))
}

/** Color of a Color filter (FILTER-COLOR-001): chosen from the same
 *  palette as Filter Sets, each choice drawn in its actual color, with
 *  the selected color's name, separate from the loss. */
@Composable
private fun OpticalColorSection(draft: FilterItemEditorDraft, onDraft: (FilterItemEditorDraft) -> Unit) {
    SectionLabel(stringResource(R.string.filter_item_optical_color))
    FilterSetColorGrid(selection = draft.opticalColor, onSelect = { onDraft(draft.copy(opticalColor = it)) })
    Spacer(Modifier.height(8.dp))
    Text(filterColorName(draft.opticalColor), style = MaterialTheme.typography.bodyMedium)
    FooterText(stringResource(R.string.filter_item_optical_color_footer))
}

/** Explicit loss of a Color or Effect filter in stops
 *  (FILTER-COLOR-001/002): user-supplied, zero allowed, never inferred
 *  from the color or the name. */
@Composable
private fun ExposureLossSection(draft: FilterItemEditorDraft, onDraft: (FilterItemEditorDraft) -> Unit) {
    SectionLabel(stringResource(R.string.filter_item_exposure_loss))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = draft.valueText,
            onValueChange = { onDraft(draft.copy(valueText = it)) },
            label = { Text(stringResource(R.string.filter_item_value)) },
            singleLine = true,
            isError = draft.hasValueError,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.weight(1f),
        )
        Text(
            stringResource(R.string.notation_stops),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    if (draft.hasValueError) {
        Spacer(Modifier.height(4.dp))
        ErrorText(stringResource(R.string.filter_item_loss_error))
    }
    FooterText(stringResource(R.string.filter_item_loss_footer))
}

/** The three CPL exposure-loss fields (FILTER-CPL-001/002/003). */
@Composable
private fun CplChoicesSection(draft: FilterItemEditorDraft, onDraft: (FilterItemEditorDraft) -> Unit) {
    SectionLabel(stringResource(R.string.filter_cpl_section))
    val errors = draft.cplFieldErrors
    val placeholder = stringResource(R.string.filter_empty)
    val stopsLabel = stringResource(R.string.notation_stops)
    repeat(CplExposureLossChoices.FIELD_COUNT) { index ->
        val fieldLabel = stringResource(R.string.filter_cpl_choice_cd, index + 1)
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.filter_cpl_choice, index + 1),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = draft.cplTexts.getOrElse(index) { "" },
                onValueChange = { text ->
                    onDraft(
                        draft.copy(
                            cplTexts = draft.cplTexts.mapIndexed { i, old -> if (i == index) text else old },
                        ),
                    )
                },
                placeholder = { Text(placeholder) },
                singleLine = true,
                isError = errors.getOrElse(index) { false },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.End),
                modifier = Modifier
                    .width(120.dp)
                    .semantics { contentDescription = fieldLabel },
            )
            Text(
                stopsLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (errors.getOrElse(index) { false }) {
            ErrorText(stringResource(R.string.filter_cpl_field_error))
        }
        Spacer(Modifier.height(4.dp))
    }
    if (draft.cplIsEmpty) ErrorText(stringResource(R.string.filter_cpl_required))
    FooterText(stringResource(R.string.filter_cpl_footer))
}

@Composable
private fun ErrorText(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
}

/** Explanatory copy under a section, matching the iOS Form footers. */
@Composable
internal fun FooterText(text: String) {
    Spacer(Modifier.height(6.dp))
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/**
 * The Filter Set a filter is saved into (FILTER-ITEM-009): a menu of
 * Default and every user set, and Add Filter Set, enabled for a new and
 * an existing filter alike.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterSetField(
    filterSets: List<FilterSet>,
    selection: FilterSetId,
    onSelect: (FilterSetId) -> Unit,
    onAddFilterSet: () -> Unit,
) {
    val selected = filterSets.firstOrNull { it.id == selection }
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
    ) {
        OutlinedTextField(
            value = selected?.name.orEmpty(),
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.filter_set_section_set)) },
            leadingIcon = selected?.let { { FilterSetColorSwatch(it.color, size = 12.dp) } },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                .testTag("filter-item-filter-set"),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            filterSets.forEach { filterSet ->
                DropdownMenuItem(
                    text = { Text(filterSet.name) },
                    leadingIcon = { FilterSetColorSwatch(filterSet.color, size = 12.dp) },
                    onClick = {
                        onSelect(filterSet.id)
                        expanded = false
                    },
                )
            }
        }
    }
    TextButton(onClick = onAddFilterSet, modifier = Modifier.testTag("filter-item-add-filter-set")) {
        Icon(Icons.Filled.Add, contentDescription = null)
        Spacer(Modifier.width(8.dp))
        Text(stringResource(R.string.filter_add_filter_set))
    }
}
