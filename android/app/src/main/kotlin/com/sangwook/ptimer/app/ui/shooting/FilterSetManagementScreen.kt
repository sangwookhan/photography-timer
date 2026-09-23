// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemory
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.app.vm.FilterSetRenameCommit
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.ui.theme.filterSetColor

/**
 * Everything the management surface may change. Bundled so the display
 * layer stays free of the controller type while the surface keeps one
 * call site.
 */
internal class FilterSetManagementActions(
    val suggestCreationColor: () -> FilterSetColor,
    val createFilterSet: (String, FilterSetColor) -> Unit,
    val renameFilterSet: (FilterSetId, String) -> Unit,
    val recolorFilterSet: (FilterSetId, FilterSetColor) -> Unit,
    val moveFilterSet: (Int, Int) -> Unit,
    val deleteFilterSet: (FilterSetId) -> Unit,
    val moveFilterItem: (FilterSetId, Int, Int) -> Unit,
    val deleteFilterItem: (FilterItemId) -> Unit,
    val saveFilterItem: (FilterItem, FilterSetId) -> FilterItemSaveOutcome,
    val camerasAffectedByDeletingFilterSet: (FilterSetId) -> List<String>,
    val camerasAffectedByDeletingItem: (FilterItemId) -> List<String>,
)

/**
 * The single Filter Set management surface (FILTER-SET-001): create,
 * rename, recolor, reorder, and delete Filter Sets, and manage each
 * set's physical filters. Reached from the ND header entry and from the
 * Plus wheel's management long press.
 *
 * Two levels in one full-screen dialog. Material puts dismissal on the
 * leading navigation icon, so the list level closes the surface with a
 * Close icon while the detail level goes Back with an arrow; the system
 * back button follows the same path. Wherever edit mode is actionable
 * the Edit / Finish Editing toggle stays a directly visible trailing
 * text action, never behind an overflow menu, and is worded apart from
 * the dismissal; an empty list presents no such control at all.
 * (iOS: `FilterSetManagementView`.)
 */
@Composable
internal fun FilterSetManagementScreen(
    inventory: FilterInventory,
    actions: FilterSetManagementActions,
    onDismiss: () -> Unit,
) {
    // Survives rotation; the id (not an index) so a reorder underneath
    // never swaps which set the detail level shows.
    var detailSetId by rememberSaveable { mutableStateOf<String?>(null) }
    val detailSet = detailSetId?.let { inventory.filterSet(FilterSetId(it)) }

    val back = { detailSetId = null }
    Dialog(
        // System back reaches the surface as a dismiss request: it leaves
        // the detail level first and only then closes the surface, so the
        // hardware path matches the leading navigation icon.
        onDismissRequest = { if (detailSetId == null) onDismiss() else back() },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        // Each Dialog hosts its own AndroidComposeView and re-derives
        // LocalDensity, so the app's font-scale cap is reapplied here.
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                when {
                    detailSetId == null -> FilterSetListLevel(
                        filterSets = inventory.filterSets,
                        actions = actions,
                        onOpen = { detailSetId = it.rawValue },
                        onDismiss = onDismiss,
                    )

                    detailSet == null -> MissingFilterSetLevel(onBack = back)

                    // The detail level's rename draft and notation memory
                    // are keyed on the set, so each one starts fresh.
                    else -> FilterSetDetailLevel(
                        filterSet = detailSet,
                        actions = actions,
                        onBack = back,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterSetListLevel(
    filterSets: List<FilterSet>,
    actions: FilterSetManagementActions,
    onOpen: (FilterSetId) -> Unit,
    onDismiss: () -> Unit,
) {
    var isEditing by rememberSaveable { mutableStateOf(false) }
    var creationColor by remember { mutableStateOf<FilterSetColor?>(null) }
    // Bound to the STABLE id captured when the confirmation opened, so a
    // reorder underneath cannot redirect the delete (FILTER-SET-001).
    var pendingDeletion by remember { mutableStateOf<FilterSet?>(null) }

    // Deleting the last Filter Set leaves reorder/delete edit mode with
    // nothing to act on, so the mode ends with the control that exits it
    // (FILTER-SET-001) instead of stranding the user in it.
    LaunchedEffect(filterSets.isEmpty()) { if (filterSets.isEmpty()) isEditing = false }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.filter_sets_title)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.action_done))
                    }
                },
                actions = {
                    // No sets, nothing to reorder or delete: an Edit
                    // control here would be a no-op, so it is absent.
                    // Close and New stay.
                    if (filterSets.isNotEmpty()) {
                        TextButton(onClick = { isEditing = !isEditing }) {
                            Text(
                                stringResource(
                                    if (isEditing) R.string.filter_sets_finish_editing else R.string.action_edit,
                                ),
                            )
                        }
                    }
                    IconButton(onClick = { creationColor = actions.suggestCreationColor() }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.filter_set_new))
                    }
                },
            )
        },
    ) { padding ->
        if (filterSets.isEmpty()) {
            Text(
                stringResource(R.string.filter_sets_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(padding).padding(16.dp),
            )
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .consumeWindowInsets(padding)
                    .navigationBarsPadding(),
            ) {
                itemsIndexed(filterSets, key = { _, it -> it.id.rawValue }) { index, filterSet ->
                    FilterSetRow(
                        filterSet = filterSet,
                        isEditing = isEditing,
                        canMoveUp = index > 0,
                        canMoveDown = index < filterSets.lastIndex,
                        onOpen = { onOpen(filterSet.id) },
                        onMoveUp = { actions.moveFilterSet(index, index - 1) },
                        onMoveDown = { actions.moveFilterSet(index, index + 1) },
                        onDelete = { pendingDeletion = filterSet },
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    creationColor?.let { suggestion ->
        NewFilterSetDialog(
            suggestedColor = suggestion,
            onSave = { name, color ->
                actions.createFilterSet(name, color)
                creationColor = null
            },
            onDismiss = { creationColor = null },
        )
    }

    pendingDeletion?.let { filterSet ->
        val cameras = actions.camerasAffectedByDeletingFilterSet(filterSet.id)
        ConfirmDeleteDialog(
            title = stringResource(R.string.filter_set_delete_title),
            message = if (cameras.isEmpty()) {
                stringResource(R.string.filter_set_delete_message)
            } else {
                stringResource(R.string.filter_set_delete_message_cameras, cameras.joinToString(", "))
            },
            confirmLabel = stringResource(R.string.filter_delete_named, filterSet.name),
            onConfirm = {
                actions.deleteFilterSet(filterSet.id)
                pendingDeletion = null
            },
            onDismiss = { pendingDeletion = null },
        )
    }
}

@Composable
private fun FilterSetRow(
    filterSet: FilterSet,
    isEditing: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onOpen: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
) {
    val countText = filterCountText(filterSet.items.size)
    val colorName = filterColorName(filterSet.color)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        FilterSetColorSwatch(filterSet.color)
        Column(
            modifier = Modifier
                .weight(1f)
                // Color is never the only cue: the row reads out its
                // color name beside the name and the filter count.
                .clearAndSetSemantics {
                    contentDescription = "${filterSet.name}, $colorName, $countText"
                },
        ) {
            Text(filterSet.name, style = MaterialTheme.typography.bodyLarge)
            Text(
                countText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (isEditing) {
            ReorderControls(canMoveUp, canMoveDown, onMoveUp, onMoveDown)
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.action_delete),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

/**
 * One Filter Set: rename, recolor, and manage its physical filters
 * (FILTER-SET-002/005, FILTER-ITEM-001/006/007).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterSetDetailLevel(
    filterSet: FilterSet,
    actions: FilterSetManagementActions,
    onBack: () -> Unit,
) {
    var nameDraft by rememberSaveable(filterSet.id.rawValue) { mutableStateOf(filterSet.name) }
    var isEditing by rememberSaveable(filterSet.id.rawValue) { mutableStateOf(false) }
    var editorTarget by remember { mutableStateOf<FilterItemEditorTarget?>(null) }
    var pendingDeletion by remember { mutableStateOf<FilterItem?>(null) }
    // Session memory for the notation of consecutive new items. Plain
    // `remember`, keyed on the set: leaving the Filter Set or restarting
    // the app resets the next new item to Stops (FILTER-ITEM-007).
    val editorSession = remember(filterSet.id.rawValue) { FilterItemEditorSessionMemory() }

    // The draft commits on IME Done, on focus loss, and when the screen is
    // left. All three run the same decision, so a blank draft always
    // restores the current name and a set that vanished is a no-op.
    val commitRename = {
        when (val decision = FilterSetRenameCommit.decide(nameDraft, filterSet.name)) {
            is FilterSetRenameCommit.Rename -> actions.renameFilterSet(filterSet.id, decision.name)
            is FilterSetRenameCommit.Restore -> nameDraft = decision.name
            is FilterSetRenameCommit.None -> Unit
        }
    }
    val latestCommit by rememberUpdatedState(commitRename)
    DisposableEffect(filterSet.id.rawValue) { onDispose { latestCommit() } }
    // An external rename (or a restore) re-seeds the field.
    LaunchedEffect(filterSet.name) {
        if (nameDraft.trim() != filterSet.name) nameDraft = filterSet.name
    }
    // Same rule as the list level: deleting the last Filter Item ends
    // edit mode along with the control that exits it.
    LaunchedEffect(filterSet.items.isEmpty()) { if (filterSet.items.isEmpty()) isEditing = false }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(filterSet.name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.action_close),
                        )
                    }
                },
                actions = {
                    // No items, nothing to reorder or delete: no no-op
                    // Edit control (FILTER-SET-001).
                    if (filterSet.items.isNotEmpty()) {
                        TextButton(onClick = { isEditing = !isEditing }) {
                            Text(
                                stringResource(
                                    if (isEditing) R.string.filter_sets_finish_editing else R.string.action_edit,
                                ),
                            )
                        }
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
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            SectionLabel(stringResource(R.string.filter_set_section_set))
            OutlinedTextField(
                value = nameDraft,
                onValueChange = { nameDraft = it },
                label = { Text(stringResource(R.string.filter_set_name)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { commitRename() }),
                modifier = Modifier
                    .fillMaxWidth()
                    .onFocusChanged { if (!it.isFocused) commitRename() },
            )
            Spacer(Modifier.height(12.dp))
            FilterSetColorGrid(
                selection = filterSet.color,
                onSelect = { actions.recolorFilterSet(filterSet.id, it) },
            )
            FooterText(stringResource(R.string.filter_set_identity_footer))

            Spacer(Modifier.height(24.dp))
            SectionLabel(stringResource(R.string.filter_set_section_filters))
            if (filterSet.items.isEmpty()) {
                Text(
                    stringResource(R.string.filter_items_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            filterSet.items.forEachIndexed { index, item ->
                FilterItemRow(
                    item = item,
                    isEditing = isEditing,
                    canMoveUp = index > 0,
                    canMoveDown = index < filterSet.items.lastIndex,
                    onOpen = { editorTarget = FilterItemEditorTarget.Existing(item) },
                    onMoveUp = { actions.moveFilterItem(filterSet.id, index, index - 1) },
                    onMoveDown = { actions.moveFilterItem(filterSet.id, index, index + 1) },
                    onDelete = { pendingDeletion = item },
                )
                HorizontalDivider()
            }
            Spacer(Modifier.height(8.dp))
            TextButton(
                onClick = { editorTarget = FilterItemEditorTarget.New(editorSession.initialUnit) },
            ) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.nd_add_filter))
            }
            FooterText(stringResource(R.string.filter_items_footer))
            Spacer(Modifier.height(24.dp))
        }
    }

    editorTarget?.let { target ->
        FilterItemEditorDialog(
            target = target,
            onSave = { item -> actions.saveFilterItem(item, filterSet.id) },
            onSaved = { item ->
                // Only a saved NEW item teaches the session its notation.
                if (target is FilterItemEditorTarget.New) editorSession.didSaveNewItem(item)
            },
            onDismiss = { editorTarget = null },
        )
    }

    pendingDeletion?.let { item ->
        val cameras = actions.camerasAffectedByDeletingItem(item.id)
        ConfirmDeleteDialog(
            title = stringResource(R.string.filter_item_delete_title),
            message = if (cameras.isEmpty()) {
                stringResource(R.string.filter_item_delete_message)
            } else {
                stringResource(R.string.filter_item_delete_message_cameras, cameras.joinToString(", "))
            },
            confirmLabel = stringResource(R.string.filter_delete_named, item.name),
            onConfirm = {
                actions.deleteFilterItem(item.id)
                pendingDeletion = null
            },
            onDismiss = { pendingDeletion = null },
        )
    }
}

@Composable
private fun FilterItemRow(
    item: FilterItem,
    isEditing: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onOpen: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
) {
    val detail = filterItemDetailText(item)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .clearAndSetSemantics { contentDescription = "${item.name}, $detail" },
        ) {
            Text(item.name, style = MaterialTheme.typography.bodyLarge)
            Text(
                detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (isEditing) {
            ReorderControls(canMoveUp, canMoveDown, onMoveUp, onMoveDown)
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.action_delete),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

/** The set is gone (deleted from another surface); Back returns to the list. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MissingFilterSetLevel(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.filter_sets_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.action_close),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Text(
            stringResource(R.string.filter_set_missing),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(padding).padding(16.dp),
        )
    }
}

@Composable
private fun ReorderControls(canMoveUp: Boolean, canMoveDown: Boolean, onMoveUp: () -> Unit, onMoveDown: () -> Unit) {
    IconButton(onClick = onMoveUp, enabled = canMoveUp) {
        Icon(
            Icons.Filled.KeyboardArrowUp,
            contentDescription = stringResource(R.string.filter_action_move_up),
        )
    }
    IconButton(onClick = onMoveDown, enabled = canMoveDown) {
        Icon(
            Icons.Filled.KeyboardArrowDown,
            contentDescription = stringResource(R.string.filter_action_move_down),
        )
    }
}

/**
 * Creation dialog (FILTER-SET-003): a name plus the required color,
 * preselected with the suggestion taken when this dialog opened.
 */
@Composable
private fun NewFilterSetDialog(
    suggestedColor: FilterSetColor,
    onSave: (String, FilterSetColor) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by rememberSaveable { mutableStateOf("") }
    // Keyed on the suggestion so each opening starts from the fresh one
    // (FILTER-SET-003) rather than the previous dialog's pick.
    var color by rememberSaveable(suggestedColor) { mutableStateOf(suggestedColor) }
    val nameFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { nameFocus.requestFocus() } }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { CappedFontScale { Text(stringResource(R.string.filter_set_new)) } },
        text = {
            CappedFontScale {
                Column {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = { Text(stringResource(R.string.filter_set_section_name)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            capitalization = KeyboardCapitalization.Words,
                            imeAction = ImeAction.Done,
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(nameFocus),
                    )
                    Spacer(Modifier.height(16.dp))
                    SectionLabel(stringResource(R.string.filter_set_section_color))
                    FilterSetColorGrid(selection = color, onSelect = { color = it })
                    FooterText(stringResource(R.string.filter_set_color_footer))
                }
            }
        },
        confirmButton = {
            CappedFontScale {
                TextButton(
                    onClick = { onSave(name.trim(), color) },
                    enabled = name.trim().isNotEmpty(),
                ) { Text(stringResource(R.string.action_save)) }
            }
        },
        dismissButton = {
            CappedFontScale {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
            }
        },
    )
}

/** Destructive confirmation naming the targeted Filter Set or filter. */
@Composable
private fun ConfirmDeleteDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { CappedFontScale { Text(title) } },
        text = { CappedFontScale { Text(message) } },
        confirmButton = {
            CappedFontScale {
                TextButton(onClick = onConfirm) {
                    Text(confirmLabel, color = MaterialTheme.colorScheme.error)
                }
            }
        },
        dismissButton = {
            CappedFontScale {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
            }
        },
    )
}

/** Twelve-token color grid; each swatch carries its color name. */
@Composable
private fun FilterSetColorGrid(selection: FilterSetColor, onSelect: (FilterSetColor) -> Unit) {
    val tokens = FilterSetColor.entries
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        tokens.chunked(COLOR_GRID_COLUMNS).forEach { rowTokens ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                rowTokens.forEach { token ->
                    val name = filterColorName(token)
                    val isSelected = token == selection
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .clickable { onSelect(token) }
                            .semantics {
                                contentDescription = name
                                selected = isSelected
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(filterSetColor(token))
                                .border(
                                    width = 1.dp,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f),
                                    shape = CircleShape,
                                ),
                        )
                        if (isSelected) {
                            Icon(
                                Icons.Filled.Check,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.surface,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Source-color dot with a hairline outline; the name travels with it. */
@Composable
private fun FilterSetColorSwatch(token: FilterSetColor) {
    Box(
        modifier = Modifier
            .size(16.dp)
            .clip(CircleShape)
            .background(filterSetColor(token))
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f),
                shape = CircleShape,
            ),
    )
}

@Composable
private fun filterCountText(count: Int): String =
    if (count == 1) {
        stringResource(R.string.filter_set_one_filter)
    } else {
        stringResource(R.string.filter_set_filter_count, count)
    }

private const val COLOR_GRID_COLUMNS = 6
