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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemory
import com.sangwook.ptimer.app.vm.FilterSetItemOrder
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.app.vm.FilterSetRenameCommit
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.slots.CameraSlotIdentity
import com.sangwook.ptimer.ui.theme.filterSetColor

/**
 * Everything the management surface may change. Bundled so the display
 * layer stays free of the controller type while the surface keeps one
 * call site.
 */
internal class FilterSetManagementActions(
    val suggestCreationColor: () -> FilterSetColor,
    val createFilterSet: (String, FilterSetColor) -> FilterSet?,
    val createFilterSetHolding: (String, FilterSetColor, FilterItem) -> FilterSet?,
    val renameFilterSet: (FilterSetId, String) -> Unit,
    val recolorFilterSet: (FilterSetId, FilterSetColor) -> Unit,
    val deleteFilterSet: (FilterSetId) -> Unit,
    val deleteFilterItem: (FilterItemId) -> Unit,
    val saveFilterItem: (FilterItem, FilterSetId) -> FilterItemSaveOutcome,
    val camerasAffectedByDeletingFilterSet: (FilterSetId) -> List<CameraSlotIdentity>,
    val camerasAffectedByDeletingItem: (FilterItemId) -> List<CameraSlotIdentity>,
)

/**
 * One Filter Set's editor (FILTER-SET-001/002/006), opened from its row
 * in Shooting Filters or in Filter management: rename, recolor, manage
 * its physical filters, and delete it globally after a confirmation that
 * names it. Material puts dismissal on the leading
 * navigation icon; the system back button follows the same path. When
 * the set is deleted the editor closes. (iOS: `FilterSetDetailView`.)
 */
@Composable
internal fun FilterSetManagementScreen(
    inventory: FilterInventory,
    filterSetId: FilterSetId,
    actions: FilterSetManagementActions,
    onDismiss: () -> Unit,
) {
    val filterSet = inventory.filterSet(filterSetId)
    // Deleted here or elsewhere: nothing left to edit.
    LaunchedEffect(filterSet == null) { if (filterSet == null) onDismiss() }
    if (filterSet == null) return
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        // Each Dialog hosts its own AndroidComposeView and re-derives
        // LocalDensity, so the app's font-scale cap is reapplied here.
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                // The rename draft and notation memory are keyed on the
                // set, so each one starts fresh.
                FilterSetDetailLevel(
                    filterSet = filterSet,
                    filterSets = inventory.filterSets,
                    actions = actions,
                    onBack = onDismiss,
                )
            }
        }
    }
}

/**
 * Filter management, opened from the Settings menu: the read-only
 * Standard row first, then the shared Filter Set inventory by name, each
 * with its contents hint, then Add filter, Add Filter Set, and Add Example
 * Filter Sets. A row opens
 * that set's editor. It holds no camera selection or auxiliary mounting.
 * (iOS: `FilterManagementView`.)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FilterManagementScreen(
    inventory: FilterInventory,
    suggestCreationColor: () -> FilterSetColor,
    createFilterSet: (String, FilterSetColor) -> FilterSet?,
    createFilterSetHolding: (String, FilterSetColor, FilterItem) -> FilterSet?,
    saveFilterItem: (FilterItem, FilterSetId) -> FilterItemSaveOutcome,
    addExampleFilterSets: () -> Unit,
    onOpenFilterSet: (FilterSetId) -> Unit,
    onDismiss: () -> Unit,
) {
    var creationColor by remember { mutableStateOf<FilterSetColor?>(null) }
    var showsStandardList by remember { mutableStateOf(false) }
    // A general Add filter: no Set chosen yet; the color is the one a
    // proposed New Filter Set would get (FILTER-ITEM-009).
    var newFilterColor by remember { mutableStateOf<FilterSetColor?>(null) }
    val editorSession = remember { FilterItemEditorSessionMemory() }
    val filterSets = FilterSetItemOrder.sortedByName(inventory.filterSets)
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.filter_management_title)) },
                            navigationIcon = {
                                IconButton(onClick = onDismiss) {
                                    Icon(
                                        Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = stringResource(R.string.action_close),
                                    )
                                }
                            },
                        )
                    },
                ) { padding ->
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .consumeWindowInsets(padding)
                            .navigationBarsPadding(),
                    ) {
                        item(key = "standard") {
                            StandardFilterSourceRow(
                                showsSelectedCue = false,
                                onOpen = { showsStandardList = true },
                                modifier = Modifier
                                    .padding(horizontal = 16.dp, vertical = 6.dp)
                                    .testTag("filter-management-standard"),
                            )
                            HorizontalDivider()
                        }
                        itemsIndexed(filterSets, key = { _, set -> set.id.rawValue }) { _, filterSet ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 56.dp)
                                    .clickable(
                                        onClickLabel = stringResource(R.string.filter_set_edit_named, filterSet.name),
                                        onClick = { onOpenFilterSet(filterSet.id) },
                                    )
                                    .padding(horizontal = 16.dp, vertical = 6.dp)
                                    .testTag("filter-management-set-${filterSet.id.rawValue}"),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                FilterSetColorSwatch(filterSet.color, size = 12.dp)
                                Spacer(Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        filterSet.name,
                                        style = MaterialTheme.typography.bodyLarge,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        filterSetContentsHintText(filterSet),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Icon(
                                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            HorizontalDivider()
                        }
                        item {
                            // Filter-first registration, never attached to
                            // Standard (FILTER-FLOW-004).
                            TextButton(
                                onClick = { newFilterColor = suggestCreationColor() },
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .padding(top = 8.dp)
                                    .testTag("filter-management-add-filter"),
                            ) {
                                Icon(Icons.Filled.Add, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text(stringResource(R.string.nd_add_filter))
                            }
                            TextButton(
                                onClick = { creationColor = suggestCreationColor() },
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .testTag("filter-management-add-filter-set"),
                            ) {
                                Icon(Icons.Filled.Add, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text(stringResource(R.string.filter_add_filter_set))
                            }
                            // Fresh, unselected copies of the example Filter
                            // Sets, at any time (FILTER-SET-008).
                            TextButton(
                                onClick = addExampleFilterSets,
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .padding(bottom = 8.dp)
                                    .testTag("filter-management-add-example-filter-sets"),
                            ) {
                                Icon(Icons.Filled.Add, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text(stringResource(R.string.filter_add_example_filter_sets))
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
                        createFilterSet(name, chosen)
                    },
                    onDismiss = { creationColor = null },
                )
            }
            newFilterColor?.let { color ->
                FilterItemEditorDialog(
                    target = FilterItemEditorTarget.New(editorSession.initialUnit),
                    filterSets = inventory.filterSets,
                    initialFilterSetId = null,
                    suggestCreationColor = suggestCreationColor,
                    createFilterSet = createFilterSet,
                    createFilterSetHolding = createFilterSetHolding,
                    onSave = saveFilterItem,
                    onSaved = { editorSession.didSaveNewItem(it) },
                    onDismiss = { newFilterColor = null },
                    proposedFilterSetColor = color,
                )
            }
            if (showsStandardList) {
                StandardNdListScreen(onDismiss = { showsStandardList = false })
            }
        }
    }
}

/**
 * Standard as a Set-like row (FILTER-SET-007): a built-in ND source that
 * is always available, never a user inventory Set. It has no edit or
 * removal action; a lock marks it read-only and, in Shooting Filters, a
 * check that cannot be removed marks it selected. Opening it shows its
 * read-only ND list. (iOS: `StandardFilterSourceLabel`.)
 */
@Composable
internal fun StandardFilterSourceRow(showsSelectedCue: Boolean, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val standard = stringResource(R.string.filter_source_standard)
    val builtIn = stringResource(R.string.filter_standard_built_in)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(onClick = onOpen)
            .semantics(mergeDescendants = true) {
                if (showsSelectedCue) selected = true
            }
            .then(modifier),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (showsSelectedCue) {
            Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(12.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(standard, style = MaterialTheme.typography.bodyLarge, maxLines = 1)
            Text(builtIn, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(
            Icons.Filled.Lock,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(8.dp))
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Standard's ND values, read-only (FILTER-SET-007, ND-001): whole stops
 * 1–30 with their OD and ND factor. Zero is no ND filter and is not
 * listed. (iOS: `StandardNDListView`.)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun StandardNdListScreen(onDismiss: () -> Unit) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.filter_source_standard)) },
                            navigationIcon = {
                                IconButton(onClick = onDismiss) {
                                    Icon(
                                        Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = stringResource(R.string.action_close),
                                    )
                                }
                            },
                        )
                    },
                ) { padding ->
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .consumeWindowInsets(padding)
                            .navigationBarsPadding()
                            .testTag("standard-nd-list"),
                    ) {
                        items((1..ExposureScale.MAXIMUM_WHOLE_ND_STOPS).toList()) { stops ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 48.dp)
                                    .padding(horizontal = 16.dp)
                                    .semantics(mergeDescendants = true) {},
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(filterStopsText(stops.toDouble()), modifier = Modifier.weight(1f))
                                Text(
                                    listOf(NDNotationMode.OPTICAL_DENSITY, NDNotationMode.FILTER_FACTOR)
                                        .joinToString(" · ") { NDNotationFormatter.display(stops.toDouble(), it).inline },
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            HorizontalDivider()
                        }
                    }
                }
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
    filterSets: List<FilterSet>,
    actions: FilterSetManagementActions,
    onBack: () -> Unit,
) {
    var isDeletionPending by remember { mutableStateOf(false) }
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
            // One physical-item list, ND first, then Color, Effect, CPL,
            // GND, each kind by name, with no manual reorder (FILTER-SET-001,
            // FILTER-ITEM-001).
            val orderedItems = FilterSetItemOrder.ordered(filterSet.items)
            if (orderedItems.isEmpty()) {
                Text(
                    stringResource(R.string.filter_items_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            orderedItems.forEach { item ->
                FilterItemRow(
                    item = item,
                    isEditing = isEditing,
                    onOpen = { editorTarget = FilterItemEditorTarget.Existing(item) },
                    onDelete = { pendingDeletion = item },
                )
                HorizontalDivider()
            }
            Spacer(Modifier.height(8.dp))
            // One Add Filter action; the type is chosen in the editor.
            TextButton(
                onClick = { editorTarget = FilterItemEditorTarget.New(editorSession.initialUnit) },
                modifier = Modifier.testTag("filter-set-add-filter"),
            ) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.nd_add_filter))
            }
            FooterText(stringResource(R.string.filter_items_footer))
            // Global deletion belongs to the set's editor, never to its
            // Shooting Filters row (FILTER-SET-006).
            Spacer(Modifier.height(16.dp))
            HorizontalDivider()
            TextButton(
                onClick = { isDeletionPending = true },
                modifier = Modifier.testTag("filter-set-delete"),
            ) {
                Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.filter_set_delete), color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (isDeletionPending) {
        val cameras = actions.camerasAffectedByDeletingFilterSet(filterSet.id)
        ConfirmDeleteDialog(
            title = stringResource(R.string.filter_set_delete_named_title, filterSet.name),
            message = if (cameras.isEmpty()) {
                stringResource(R.string.filter_set_delete_global_message, filterSet.name)
            } else {
                stringResource(
                    R.string.filter_set_delete_global_message_cameras,
                    filterSet.name,
                    localizedCameraNames(cameras),
                )
            },
            confirmLabel = stringResource(R.string.action_delete),
            onConfirm = {
                isDeletionPending = false
                actions.deleteFilterSet(filterSet.id)
            },
            onDismiss = { isDeletionPending = false },
        )
    }

    editorTarget?.let { target ->
        FilterItemEditorDialog(
            target = target,
            filterSets = filterSets,
            initialFilterSetId = filterSet.id,
            suggestCreationColor = actions.suggestCreationColor,
            createFilterSet = actions.createFilterSet,
            createFilterSetHolding = actions.createFilterSetHolding,
            onSave = actions.saveFilterItem,
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
                stringResource(R.string.filter_item_delete_message_cameras, localizedCameraNames(cameras))
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
    onOpen: () -> Unit,
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
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                // A Color filter shows its actual color beside its name
                // (FILTER-COLOR-001); the name is spoken.
                item.behavior.opticalColor?.let { FilterSetColorSwatch(it, size = 10.dp) }
                Text(item.name, style = MaterialTheme.typography.bodyLarge)
            }
            Text(
                detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (isEditing) {
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
 * Creation dialog (FILTER-SET-003): a name plus the required color,
 * preselected with the suggestion taken when this dialog opened.
 */
@Composable
internal fun NewFilterSetDialog(
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

/** Destructive confirmation naming what it changes. Cancel, the back
 *  button, and a tap outside it all dismiss it unchanged. */
@Composable
internal fun ConfirmDeleteDialog(
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

/** Nine-token color grid in hue order; each swatch carries its color
 *  name. Shared by Filter Sets and Color filters (FILTER-COLOR-001). */
@Composable
internal fun FilterSetColorGrid(selection: FilterSetColor, onSelect: (FilterSetColor) -> Unit, rowSpacing: Dp = 8.dp) {
    val tokens = FilterSetColor.entries
    Column(verticalArrangement = Arrangement.spacedBy(rowSpacing)) {
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
internal fun FilterSetColorSwatch(token: FilterSetColor, size: Dp = 16.dp) {
    Box(
        modifier = Modifier
            .size(size)
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

// Nine palette colors read in hue order over two rows.
private const val COLOR_GRID_COLUMNS = 5
