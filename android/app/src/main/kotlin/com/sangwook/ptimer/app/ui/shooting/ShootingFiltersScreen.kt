// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemory
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.app.vm.FilterSetItemOrder
import com.sangwook.ptimer.app.vm.FilterWheelPresenter
import com.sangwook.ptimer.app.vm.SelectedFilterSetAddFilterPlacement
import com.sangwook.ptimer.app.vm.ShootingFiltersSession
import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter

/**
 * Everything Shooting Filters may do. Bundled so the display layer stays
 * free of the controller type.
 */
internal class ShootingFiltersActions(
    /** What Apply would report for a working session; `null` when it
     *  would succeed. */
    val rejection: (List<FilterSetId>, List<MountedAuxiliaryFilter>) -> FilterStackRejection?,
    val subtotal: (List<MountedAuxiliaryFilter>) -> Double,
    /** Commits the working set selection, in order, and mounts together. */
    val apply: (List<FilterSetId>, List<MountedAuxiliaryFilter>) -> FilterStackRejection?,
    val selectedFilterSets: (List<FilterSetId>) -> List<FilterSet>,
    val availableFilterSets: (List<FilterSetId>) -> List<FilterSet>,
    val selectedFiltersText: (List<MountedAuxiliaryFilter>) -> String?,
    val isInUse: (FilterSetId) -> Boolean,
    val suggestCreationColor: () -> FilterSetColor,
    val createFilterSet: (String, FilterSetColor) -> FilterSet?,
    val saveFilterItem: (FilterItem, FilterSetId) -> FilterItemSaveOutcome,
    /** Opens the given set's editor. */
    val openFilterSet: (FilterSetId) -> Unit,
)

/**
 * Shooting Filters (FILTER-FLOW-002..005, FILTER-SET-001,
 * FILTER-CAMERA-003, FILTER-AUX-003/006/007): auxiliary filters only; ND
 * stays on Main. One working session covers the Filter Sets selected for
 * the active camera and the auxiliary selection — mounting, CPL choices,
 * GND modes; Apply commits both atomically and Close discards both. From
 * the top: a one-line Selected filters summary with the exposure
 * reduction; the Selected Sets, each with its auxiliary filters in one
 * horizontal strip below it; the Available Sets, by name; then Add Filter
 * Set. A Selected
 * Set is removed at its leading control, edited from its name, and gets a
 * new filter from its trailing control — or, while it holds no filter,
 * from a full-width Add Filter row. An Available Set is edited from its
 * name and added at its trailing control. There is no manual reorder.
 * Material puts dismissal on the leading navigation icon and the
 * confirming action on the trailing edge.
 * (iOS: `ShootingFilterSelectionView`.)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ShootingFiltersScreen(
    inventory: FilterInventory,
    /** The camera's committed mounts in display order. */
    committed: List<MountedAuxiliaryFilter>,
    candidateFilterSetIds: List<FilterSetId>,
    actions: ShootingFiltersActions,
    onDismiss: () -> Unit,
) {
    // The working set selection and mounts start from the camera's
    // committed state; nothing changes until Apply (FILTER-AUX-003,
    // FILTER-CAMERA-003).
    var session by remember { mutableStateOf(ShootingFiltersSession(candidateFilterSetIds, committed)) }
    // The committed state can change underneath through an inventory edit
    // made from here, which is immediate — an item's kind corrected or
    // moved, or a set deleted, in a set editor (FILTER-FLOW-003,
    // FILTER-ITEM-005/009). The working mounts restart from it so Apply
    // can never undo that edit with a stale selection. Mount order never
    // matters.
    val committedState = candidateFilterSetIds to committed.toSet()
    var lastCommitted by remember { mutableStateOf(committedState) }
    LaunchedEffect(committedState) {
        if (committedState != lastCommitted) {
            lastCommitted = committedState
            session = session.rebased(candidateFilterSetIds, committed, inventory.filterSets.map { it.id }.toSet())
        }
    }
    var applyRejection by remember { mutableStateOf<FilterStackRejection?>(null) }
    // New Filter opened in a Selected Set, with its starting notation.
    var newFilter by remember { mutableStateOf<Pair<FilterValueUnit, FilterSetId>?>(null) }
    // This popup's New Filter session memory (FILTER-ITEM-007).
    val editorSession = remember { FilterItemEditorSessionMemory() }
    var creationColor by remember { mutableStateOf<FilterSetColor?>(null) }
    // The filter last touched in a strip; one shared detail line under its
    // set's strip describes it (FILTER-AUX-006).
    var activeItemId by remember { mutableStateOf<FilterItemId?>(null) }
    // Each strip's scroll position, kept while the screen recomposes.
    val stripScrollStates = remember { mutableMapOf<FilterSetId, ScrollState>() }

    val rejection = actions.rejection(session.selectedFilterSetIds, session.mounts)
    val canApply = session.hasChanges && rejection == null
    val selectedSets = actions.selectedFilterSets(session.selectedFilterSetIds)
    val availableSets = actions.availableFilterSets(session.selectedFilterSetIds)

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.filter_shooting_title)) },
                            navigationIcon = {
                                IconButton(onClick = onDismiss) {
                                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.action_cancel))
                                }
                            },
                            actions = {
                                TextButton(
                                    onClick = {
                                        // A removed set's filters and ND wheels
                                        // come off this camera, with no further
                                        // confirmation (FILTER-CAMERA-003).
                                        val refused = actions.apply(session.selectedFilterSetIds, session.mounts)
                                        if (refused == null) onDismiss() else applyRejection = refused
                                    },
                                    enabled = canApply,
                                    modifier = Modifier.testTag("shooting-filters-apply"),
                                ) { Text(stringResource(R.string.filter_shooting_apply)) }
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
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp),
                    ) {
                        SelectedFiltersSummary(
                            text = actions.selectedFiltersText(session.mounts),
                            exposureReduction = actions.subtotal(session.mounts),
                            rejection = rejection,
                        )
                        Spacer(Modifier.height(8.dp))
                        SectionLabel(stringResource(R.string.filter_selected_sets))
                        if (selectedSets.isEmpty()) {
                            Text(
                                stringResource(R.string.filter_selected_sets_empty),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(vertical = 8.dp),
                            )
                        }
                        selectedSets.forEach { filterSet ->
                            key(filterSet.id.rawValue) {
                                SelectedFilterSet(
                                    filterSet = filterSet,
                                    isInUse = actions.isInUse(filterSet.id),
                                    mountOf = session::mount,
                                    onMount = { itemId, mount -> session = session.withMount(itemId, mount) },
                                    onRemove = { session = session.withSelected(filterSet.id, false) },
                                    onEdit = { actions.openFilterSet(filterSet.id) },
                                    onAddFilter = { newFilter = editorSession.initialUnit to filterSet.id },
                                    activeItemId = activeItemId,
                                    onTouch = { activeItemId = it },
                                    contributionOf = { FilterStack.resolvedAuxiliaryFilter(it, inventory)?.contributionStops },
                                    stripScrollState = stripScrollStates.getOrPut(filterSet.id) { ScrollState(0) },
                                )
                            }
                        }
                        if (availableSets.isNotEmpty()) {
                            Spacer(Modifier.height(8.dp))
                            SectionLabel(stringResource(R.string.filter_available_sets))
                            availableSets.forEach { filterSet ->
                                key(filterSet.id.rawValue) {
                                    AvailableFilterSetRow(
                                        filterSet = filterSet,
                                        isInUse = actions.isInUse(filterSet.id),
                                        onEdit = { actions.openFilterSet(filterSet.id) },
                                        onAdd = { session = session.withSelected(filterSet.id, true) },
                                    )
                                    HorizontalDivider()
                                }
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        TextButton(
                            onClick = { creationColor = actions.suggestCreationColor() },
                            modifier = Modifier.testTag("shooting-filters-add-filter-set"),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.filter_add_filter_set))
                        }
                        Spacer(Modifier.height(24.dp))
                    }
                }
            }
        }
    }

    applyRejection?.let { refused ->
        AlertDialog(
            onDismissRequest = { applyRejection = null },
            title = { CappedFontScale { Text(stringResource(R.string.filter_shooting_cannot_apply)) } },
            text = { CappedFontScale { Text(filterRejectionText(refused)) } },
            confirmButton = {
                CappedFontScale {
                    TextButton(onClick = { applyRejection = null }) { Text(stringResource(R.string.action_confirm)) }
                }
            },
        )
    }

    // Add Filter Set adds the set to the inventory and returns here; it
    // selects and mounts nothing (FILTER-FLOW-005).
    creationColor?.let { color ->
        NewFilterSetDialog(
            suggestedColor = color,
            onSave = { name, chosen ->
                creationColor = null
                actions.createFilterSet(name, chosen)
            },
            onDismiss = { creationColor = null },
        )
    }

    newFilter?.let { (unit, setId) ->
        FilterItemEditorDialog(
            target = FilterItemEditorTarget.New(unit),
            filterSets = inventory.filterSets,
            initialFilterSetId = setId,
            suggestCreationColor = actions.suggestCreationColor,
            createFilterSet = actions.createFilterSet,
            onSave = actions.saveFilterItem,
            onSaved = { editorSession.didSaveNewItem(it) },
            onDismiss = { newFilter = null },
        )
    }
}

/**
 * The top of Shooting Filters as one compact block (FILTER-FLOW-003,
 * FILTER-AUX-007): the label with only the exposure reduction on the same
 * line — never the whole Total, which includes ND wheels that stay on
 * Main — and the working selection in Main's concise names on one more
 * line. Past 30 stops the refusal Apply would report replaces the
 * reduction.
 */
@Composable
private fun SelectedFiltersSummary(text: String?, exposureReduction: Double, rejection: FilterStackRejection?) {
    val label = stringResource(R.string.filter_selected_filters)
    val shown = text ?: stringResource(R.string.filter_selected_filters_none)
    val reduction = if (rejection == null) {
        stringResource(R.string.filter_exposure_reduction_cd, filterStopsText(exposureReduction))
    } else {
        null
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 8.dp)
            .testTag("shooting-filters-selected-filters")
            .clearAndSetSemantics { contentDescription = listOfNotNull(label, reduction, shown).joinToString(", ") },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            if (reduction != null) {
                Text(
                    reduction,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.testTag("shooting-filters-exposure-reduction"),
                )
            }
        }
        Text(
            shown,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (rejection != null) {
            Row(
                modifier = Modifier.padding(top = 4.dp).testTag("shooting-filters-rejection"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text(filterRejectionText(rejection), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
    HorizontalDivider()
}

/**
 * One Selected Set (FILTER-SET-001, FILTER-FLOW-004): its header — a
 * leading remove control, the name area that opens the set's editor, and
 * a trailing add-filter control while the set holds a filter — then its
 * auxiliary filters in one indented horizontal strip, with one shared
 * detail line under it for the filter last touched, or a full-width Add
 * Filter row while it holds none.
 */
@Composable
private fun SelectedFilterSet(
    filterSet: FilterSet,
    isInUse: Boolean,
    mountOf: (FilterItemId) -> MountedAuxiliaryFilter?,
    onMount: (FilterItemId, MountedAuxiliaryFilter?) -> Unit,
    onRemove: () -> Unit,
    onEdit: () -> Unit,
    onAddFilter: () -> Unit,
    activeItemId: FilterItemId?,
    onTouch: (FilterItemId) -> Unit,
    /** A working mount's current contribution in stops. */
    contributionOf: (MountedAuxiliaryFilter) -> Double?,
    stripScrollState: ScrollState,
) {
    val placement = SelectedFilterSetAddFilterPlacement.of(filterSet)
    val removeLabel = stringResource(R.string.filter_set_remove_named, filterSet.name)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("shooting-filters-selected-set-${filterSet.id.rawValue}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(
            onClick = onRemove,
            modifier = Modifier.testTag("shooting-filters-selected-set-remove-${filterSet.id.rawValue}"),
        ) {
            RemoveCircleGlyph(MaterialTheme.colorScheme.error, removeLabel)
        }
        FilterSetEditArea(filterSet, isInUse, onEdit, Modifier.weight(1f))
        if (placement == SelectedFilterSetAddFilterPlacement.headerControl) {
            IconButton(
                onClick = onAddFilter,
                modifier = Modifier.testTag("shooting-filters-set-add-filter-${filterSet.id.rawValue}"),
            ) {
                Icon(
                    Icons.Filled.Add,
                    contentDescription = stringResource(R.string.filter_add_filter_to_named, filterSet.name),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
    if (placement == SelectedFilterSetAddFilterPlacement.fullWidthRow) {
        TextButton(
            onClick = onAddFilter,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("shooting-filters-empty-set-add-filter-${filterSet.id.rawValue}"),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.nd_add_filter), modifier = Modifier.weight(1f))
        }
    }
    val items = FilterSetItemOrder.ordered(filterSet.auxiliaryItems)
    if (items.isNotEmpty()) {
        // The strip scrolls on its own and keeps its position; the next
        // filter showing partly at the edge is the scroll cue
        // (FILTER-AUX-006, FILTER-FLOW-003).
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = StripIndent, bottom = 4.dp)
                .horizontalScroll(stripScrollState)
                .testTag("shooting-filters-strip-${filterSet.id.rawValue}"),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEach { item ->
                FilterItemStripControl(
                    filterSet = filterSet,
                    item = item,
                    mount = mountOf(item.id),
                    onMount = { mount -> onMount(item.id, mount) },
                    onTouch = { onTouch(item.id) },
                )
            }
        }
        items.firstOrNull { it.id == activeItemId }?.let { active ->
            FilterItemDetailLine(active, mountOf(active.id)?.let(contributionOf))
        }
    }
    HorizontalDivider()
}

/** An Available Set (FILTER-SET-001): the name area opens its editor and
 *  the trailing control adds it to the Selected Sets. */
@Composable
private fun AvailableFilterSetRow(filterSet: FilterSet, isInUse: Boolean, onEdit: () -> Unit, onAdd: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("shooting-filters-available-set-${filterSet.id.rawValue}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.width(12.dp))
        FilterSetEditArea(filterSet, isInUse, onEdit, Modifier.weight(1f))
        IconButton(
            onClick = onAdd,
            modifier = Modifier.testTag("shooting-filters-available-set-add-${filterSet.id.rawValue}"),
        ) {
            Icon(
                Icons.Filled.AddCircle,
                contentDescription = stringResource(R.string.filter_set_add_to_selected_named, filterSet.name),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/** A Filter Set's color and name on one line, with an inline In use while
 *  this camera mounts from it (FILTER-SET-001); tapping opens the set's
 *  editor. */
@Composable
private fun FilterSetEditArea(filterSet: FilterSet, isInUse: Boolean, onEdit: () -> Unit, modifier: Modifier) {
    val inUse = stringResource(R.string.filter_in_use)
    val editLabel = stringResource(R.string.filter_set_edit_named, filterSet.name)
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clickable(onClickLabel = editLabel, onClick = onEdit)
            .testTag("shooting-filters-set-edit-${filterSet.id.rawValue}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilterSetColorSwatch(filterSet.color, size = 12.dp)
        Spacer(Modifier.width(10.dp))
        Text(
            filterSet.name,
            style = MaterialTheme.typography.titleSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        if (isInUse) {
            Spacer(Modifier.width(8.dp))
            Text(inUse, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** A filled circle with a bar: the remove control of a Selected Set. */
@Composable
private fun RemoveCircleGlyph(color: Color, contentDescription: String) {
    Canvas(
        modifier = Modifier
            .size(22.dp)
            .semantics { this.contentDescription = contentDescription },
    ) {
        drawCircle(color)
        val inset = size.width * 0.27f
        drawLine(
            Color.White,
            start = Offset(inset, size.height / 2),
            end = Offset(size.width - inset, size.height / 2),
            strokeWidth = 2.dp.toPx(),
            cap = StrokeCap.Round,
        )
    }
}

/** How far a set's strip and detail line sit in from its header, so the
 *  set that owns them reads at once. */
private val StripIndent = 48.dp

/**
 * One auxiliary item of a set's strip (FILTER-AUX-006, FILTER-CPL-005,
 * FILTER-GND-001/002/003): a filter chip that mounts or unmounts the item,
 * with a check while mounted and a plus while not, so the state does not
 * rest on color. A mounted CPL or GND gets an adjacent chip that opens its
 * exposure loss or calculation mode directly; choosing the GND's full
 * value shows its caution once, at that moment.
 */
@Composable
private fun FilterItemStripControl(
    filterSet: FilterSet,
    item: FilterItem,
    mount: MountedAuxiliaryFilter?,
    onMount: (MountedAuxiliaryFilter?) -> Unit,
    onTouch: () -> Unit,
) {
    var showsFullValueCaution by remember { mutableStateOf(false) }
    val detail = filterItemDetailText(item)
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        FilterChip(
            selected = mount != null,
            onClick = {
                onMount(
                    if (mount == null) {
                        MountedAuxiliaryFilter(
                            filterSet.id,
                            item.id,
                            MountedAuxiliaryFilter.initialChoice(item) ?: AuxiliaryFilterChoice.RegisteredLoss,
                        )
                    } else {
                        null
                    },
                )
                onTouch()
            },
            label = { Text(item.name, maxLines = 1) },
            leadingIcon = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (mount != null) Icons.Filled.Check else Icons.Filled.Add,
                        contentDescription = null,
                        modifier = Modifier.size(FilterChipDefaults.IconSize),
                    )
                    item.behavior.opticalColor?.let {
                        Spacer(Modifier.width(4.dp))
                        FilterSetColorSwatch(it, size = 8.dp)
                    }
                }
            },
            modifier = Modifier
                .testTag("auxiliary-item-toggle-${item.id.rawValue}")
                .semantics { contentDescription = "${item.name}, $detail" },
        )
        val behavior = item.behavior
        val choice = mount?.choice
        when {
            behavior is FilterItemBehavior.Cpl && choice is AuxiliaryFilterChoice.CplLoss ->
                ChoiceChip(
                    label = FilterWheelPresenter.decimalStopsValue(choice.stops),
                    options = behavior.choices.shootingChoices.map { filterStopsText(it) to it },
                    tag = "auxiliary-item-cpl-choice-${item.id.rawValue}",
                    onSelect = {
                        onMount(mount.copy(choice = AuxiliaryFilterChoice.CplLoss(it)))
                        onTouch()
                    },
                )
            behavior is FilterItemBehavior.Gnd && choice is AuxiliaryFilterChoice.Gnd ->
                ChoiceChip(
                    label = localizedGndModeShortName(choice.mode),
                    options = GndCalculationMode.entries.map { localizedGndModeName(it) to it },
                    tag = "auxiliary-item-gnd-mode-${item.id.rawValue}",
                    onSelect = { mode ->
                        onMount(mount.copy(choice = AuxiliaryFilterChoice.Gnd(mode)))
                        onTouch()
                        if (mode == GndCalculationMode.applyFullValue && choice.mode != mode) showsFullValueCaution = true
                    },
                )
        }
    }
    if (showsFullValueCaution) {
        AlertDialog(
            onDismissRequest = { showsFullValueCaution = false },
            title = { CappedFontScale { Text(localizedGndModeName(GndCalculationMode.applyFullValue)) } },
            text = { CappedFontScale { Text(stringResource(R.string.filter_gnd_modes_warning)) } },
            confirmButton = {
                CappedFontScale {
                    TextButton(onClick = { showsFullValueCaution = false }) { Text(stringResource(R.string.action_confirm)) }
                }
            },
        )
    }
}

/** The chip beside a mounted CPL or GND: its current value and a drop-down
 *  arrow, opening the other values in a menu without unmounting it. */
@Composable
private fun <T> ChoiceChip(label: String, options: List<Pair<String, T>>, tag: String, onSelect: (T) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        AssistChip(
            onClick = { expanded = true },
            label = { Text(label, maxLines = 1) },
            trailingIcon = { Icon(Icons.Filled.ArrowDropDown, contentDescription = null) },
            colors = AssistChipDefaults.assistChipColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
            border = null,
            modifier = Modifier.testTag(tag),
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (text, value) ->
                DropdownMenuItem(text = { Text(text) }, onClick = {
                    expanded = false
                    onSelect(value)
                })
            }
        }
    }
}

/**
 * The one shared detail line under a set's strip (FILTER-AUX-006): the
 * filter last touched, with its registered definition and, while mounted,
 * its current contribution. Text only; nothing needed to operate the
 * filter lives here, and it stays until the next touch.
 */
@Composable
private fun FilterItemDetailLine(item: FilterItem, contributionStops: Double?) {
    val contribution = contributionStops?.let { stringResource(R.string.filter_contribution, filterStopsText(it)) }
    Text(
        listOfNotNull(item.name, filterItemDetailText(item), contribution).joinToString(" · "),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 2,
        modifier = Modifier
            .padding(start = StripIndent, bottom = 6.dp)
            .testTag("shooting-filters-filter-detail"),
    )
}
