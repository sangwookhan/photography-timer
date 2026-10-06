// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.FilterItemEditorSessionMemory
import com.sangwook.ptimer.app.vm.FilterItemSaveOutcome
import com.sangwook.ptimer.app.vm.FilterSetContentsHint
import com.sangwook.ptimer.app.vm.FilterSetItemOrder
import com.sangwook.ptimer.app.vm.FilterWheelPresenter
import com.sangwook.ptimer.app.vm.SelectedFilterRowDisplayState
import com.sangwook.ptimer.app.vm.SelectedFilterSetAddFilterPlacement
import com.sangwook.ptimer.app.vm.ShootingFiltersMountChange
import com.sangwook.ptimer.app.vm.ShootingFiltersSession
import com.sangwook.ptimer.app.vm.showsNdCue
import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
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
    /** The working Selected Sets grouped for display (FILTER-SET-004). */
    val displayedSelectedFilterSets: (List<FilterSetId>) -> List<FilterSet>,
    val availableFilterSets: (List<FilterSetId>) -> List<FilterSet>,
    /** Every selected filter for the Selected filters panel. */
    val selectedFilterRows: (List<MountedAuxiliaryFilter>) -> List<SelectedFilterRowDisplayState>,
    /** One mount change, refused at once when it would be invalid
     *  (FILTER-AUX-007). */
    val setMount: (ShootingFiltersSession, FilterItemId, MountedAuxiliaryFilter?) -> ShootingFiltersMountChange,
    val isInUse: (FilterSetId) -> Boolean,
    val suggestCreationColor: () -> FilterSetColor,
    val createFilterSet: (String, FilterSetColor) -> FilterSet?,
    val createFilterSetHolding: (String, FilterSetColor, FilterItem) -> FilterSet?,
    val saveFilterItem: (FilterItem, FilterSetId) -> FilterItemSaveOutcome,
    /** Opens the given set's editor. */
    val openFilterSet: (FilterSetId) -> Unit,
    /** Appends fresh, unselected example Filter Set copies (FILTER-SET-008). */
    val addExampleFilterSets: () -> Unit,
)

/**
 * Shooting Filters (FILTER-FLOW-002..005, FILTER-SET-001,
 * FILTER-CAMERA-003, FILTER-AUX-003/006/007): auxiliary filters only; ND
 * stays on Main. One working session covers the Filter Sets selected for
 * the active camera and the auxiliary selection — mounting, CPL choices,
 * GND modes; Apply commits both atomically and Cancel discards both. From
 * the top: a fixed-height Selected filters panel with the count, the
 * exposure reduction, and every selected filter; the read-only Standard
 * row, always selected, then the Selected Filter Sets, grouped by
 * contents, each with its auxiliary filters in one strip of equal-width
 * controls below it; the Available Filter Sets, by name; then Add filter
 * and Add Filter Set, and apart from them the secondary Add Example Filter
 * Sets. A Selected Set is removed at its leading control, edited from its name, and gets a
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
    // FILTER-ITEM-005/009). The working mounts follow that edit item by
    // item, so Apply can never undo it with a stale selection and
    // unrelated draft picks stay. The same edits can touch only working
    // picks, which the camera never committed. The session decides both.
    // Mount order never matters.
    LaunchedEffect(candidateFilterSetIds, committed.toSet(), inventory) {
        session = session.followed(candidateFilterSetIds, committed, inventory)
    }
    var applyRejection by remember { mutableStateOf<FilterStackRejection?>(null) }
    // New Filter opened in a Selected Set (or, from the general Add filter,
    // in no Set yet), with its starting notation.
    var newFilter by remember { mutableStateOf<Pair<FilterValueUnit, FilterSetId?>?>(null) }
    // The color a proposed New Filter Set gets from the general Add filter.
    var proposedFilterSetColor by remember { mutableStateOf(FilterSetColor.blue) }
    var showsStandardList by remember { mutableStateOf(false) }
    // This screen's New Filter session memory (FILTER-ITEM-007).
    val editorSession = remember { FilterItemEditorSessionMemory() }
    var creationColor by remember { mutableStateOf<FilterSetColor?>(null) }
    // Why the last mount or choice was refused; the working selection
    // stayed as it was (FILTER-AUX-007). Cleared by the next accepted
    // change or a Set added or removed.
    var refusal by remember { mutableStateOf<FilterStackRejection?>(null) }
    // Each strip's scroll position, kept while the screen recomposes.
    val stripScrollStates = remember { mutableMapOf<FilterSetId, ScrollState>() }

    val rejection = actions.rejection(session.selectedFilterSetIds, session.mounts)
    val canApply = session.hasChanges && rejection == null
    val selectedSets = actions.displayedSelectedFilterSets(session.selectedFilterSetIds)
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
                        SelectedFiltersPanel(
                            rows = actions.selectedFilterRows(session.mounts),
                            exposureReduction = actions.subtotal(session.mounts),
                            rejection = refusal ?: rejection,
                        )
                        Spacer(Modifier.height(16.dp))
                        SelectedFilterSetsHeading()
                        GroupedRegion(modifier = Modifier.testTag("shooting-filters-selected-sets")) {
                        // Standard first, always selected and read-only; with
                        // no user Set selected it is the whole region, a
                        // normal state (FILTER-SET-007, FILTER-FLOW-003).
                        StandardFilterSourceRow(
                            showsSelectedCue = true,
                            onOpen = { showsStandardList = true },
                            modifier = Modifier
                                .padding(horizontal = 16.dp, vertical = 4.dp)
                                .testTag("shooting-filters-standard"),
                        )
                        if (selectedSets.isNotEmpty()) RowSeparator(start = 16.dp)
                        selectedSets.forEachIndexed { index, filterSet ->
                            key(filterSet.id.rawValue) {
                                SelectedFilterSet(
                                    filterSet = filterSet,
                                    isInUse = actions.isInUse(filterSet.id),
                                    mountOf = session::mount,
                                    onMount = { itemId, mount ->
                                        when (val change = actions.setMount(session, itemId, mount)) {
                                            is ShootingFiltersMountChange.Accepted -> {
                                                session = change.session
                                                refusal = null
                                            }
                                            is ShootingFiltersMountChange.Refused -> refusal = change.reason
                                        }
                                    },
                                    onRemove = {
                                        session = session.withSelected(filterSet.id, false)
                                        refusal = null
                                    },
                                    onEdit = { actions.openFilterSet(filterSet.id) },
                                    onAddFilter = { newFilter = editorSession.initialUnit to filterSet.id },
                                    stripScrollState = stripScrollStates.getOrPut(filterSet.id) { ScrollState(0) },
                                )
                                if (index < selectedSets.lastIndex) RowSeparator(start = StripIndent)
                            }
                        }
                        }
                        if (availableSets.isNotEmpty()) {
                            Spacer(Modifier.height(16.dp))
                            SectionLabel(stringResource(R.string.filter_available_sets))
                            GroupedRegion(modifier = Modifier.testTag("shooting-filters-available-sets")) {
                                availableSets.forEachIndexed { index, filterSet ->
                                    key(filterSet.id.rawValue) {
                                        AvailableFilterSetRow(
                                            filterSet = filterSet,
                                            isInUse = actions.isInUse(filterSet.id),
                                            onEdit = { actions.openFilterSet(filterSet.id) },
                                            onAdd = {
                                                session = session.withSelected(filterSet.id, true)
                                                refusal = null
                                            },
                                        )
                                        if (index < availableSets.lastIndex) RowSeparator(start = 46.dp)
                                    }
                                }
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        // Filter-first registration, never attached to
                        // Standard (FILTER-FLOW-004, FILTER-ITEM-009).
                        TextButton(
                            onClick = {
                                proposedFilterSetColor = actions.suggestCreationColor()
                                newFilter = editorSession.initialUnit to null
                            },
                            modifier = Modifier.testTag("shooting-filters-add-filter"),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.nd_add_filter))
                        }
                        TextButton(
                            onClick = { creationColor = actions.suggestCreationColor() },
                            modifier = Modifier.testTag("shooting-filters-add-filter-set"),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.filter_add_filter_set))
                        }
                        // A secondary action, set apart from the ordinary
                        // creation actions (FILTER-SET-008).
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                        TextButton(
                            onClick = actions.addExampleFilterSets,
                            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurfaceVariant),
                            modifier = Modifier.testTag("shooting-filters-add-example-filter-sets"),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.filter_add_example_filter_sets), style = MaterialTheme.typography.bodyMedium)
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
            createFilterSetHolding = actions.createFilterSetHolding,
            onSave = actions.saveFilterItem,
            onSaved = { editorSession.didSaveNewItem(it) },
            onDismiss = { newFilter = null },
            proposedFilterSetColor = proposedFilterSetColor,
        )
    }

    if (showsStandardList) {
        StandardNdListScreen(onDismiss = { showsStandardList = false })
    }
}

/**
 * The Selected filters panel (FILTER-FLOW-003, FILTER-AUX-007): a fixed
 * height, so the sets below never move as filters are picked. The count of
 * selected auxiliary filters (a Record-only GND counts; ND wheels never do)
 * or the explicit zero state, and the exposure reduction of the auxiliary
 * filters only, on one line; then every selected filter in a list that
 * scrolls inside the panel. A refused mount or choice shows its reason in
 * one row taken from that list, never in place of the count or the
 * reduction.
 */
@Composable
private fun SelectedFiltersPanel(rows: List<SelectedFilterRowDisplayState>, exposureReduction: Double, rejection: FilterStackRejection?) {
    val count = if (rows.isEmpty()) {
        stringResource(R.string.filter_auxiliary_none)
    } else {
        pluralStringResource(R.plurals.filter_auxiliary_count, rows.size, rows.size)
    }
    val reduction = stringResource(R.string.filter_exposure_reduction_cd, filterStopsText(exposureReduction))
    // A count that wraps in a longer language takes its line from the
    // list, so the panel keeps one height in every language.
    val headerLineHeight = with(LocalDensity.current) { MaterialTheme.typography.titleSmall.lineHeight.toDp() }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp)
            .clip(GroupShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .height(headerLineHeight + PanelDividerHeight + SelectedListHeight)
            .testTag("shooting-filters-selected-filters"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                count,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).testTag("shooting-filters-selected-count"),
            )
            Text(
                reduction,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                modifier = Modifier.testTag("shooting-filters-exposure-reduction"),
            )
        }
        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
        Column(modifier = Modifier.weight(1f)) {
            if (rejection != null) {
                Row(
                    modifier = Modifier.height(RefusalRowHeight).testTag("shooting-filters-rejection"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(16.dp))
                    Text(
                        filterRejectionText(rejection),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Column(modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState())) {
                rows.forEach { row -> SelectedFilterRow(row) }
            }
        }
    }
}

/** The grouped surface of each Shooting Filters region (FILTER-SET-001):
 *  the Selected filters panel, the Selected Filter Sets, and the Available
 *  Filter Sets each sit on one, so the region boundary reads before the
 *  separators inside it. */
private val GroupShape = RoundedCornerShape(16.dp)

@Composable
private fun GroupedRegion(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(GroupShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        content = content,
    )
}

/** A separator between two rows of one region, inset from the leading
 *  edge and lighter than the region boundary. */
@Composable
private fun RowSeparator(start: Dp) {
    HorizontalDivider(
        modifier = Modifier.padding(start = start),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f),
    )
}

/** The Selected filters list's height under a one-line count: three rows
 *  and part of a fourth, so a fourth selected filter shows that the list
 *  scrolls. */
private val SelectedListHeight = 96.dp

/** The divider under the count and its padding. */
private val PanelDividerHeight = 9.dp

/** The row a refusal reason takes from the list, so the panel never grows. */
private val RefusalRowHeight = 24.dp

/** One selected filter: a Color filter's swatch, the whole name (cut only
 *  when it does not fit), the kind, and the contribution or GND mode.
 *  Informational only. */
@Composable
private fun SelectedFilterRow(row: SelectedFilterRowDisplayState) {
    val contribution = filterStopsText(row.contributionStops)
    val value = row.gndMode?.let { "${localizedGndModeName(it)} · $contribution" } ?: contribution
    val kind = localizedFilterKindName(row.kind)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 28.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(8.dp)) {
            row.opticalColor?.let { FilterSetColorSwatch(it, size = 8.dp) }
        }
        Text(row.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(kind, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        Text(value, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
    }
}

/** The Selected Filter Sets title with a passive instruction directly
 *  below it: ND values are chosen on Main (FILTER-FLOW-003). Not an
 *  action; it does not imply that every selected set holds ND filters. */
@Composable
private fun SelectedFilterSetsHeading() {
    Column(modifier = Modifier.padding(bottom = 6.dp)) {
        Text(
            stringResource(R.string.filter_selected_sets),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            stringResource(R.string.filter_nd_on_main_instruction),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.testTag("shooting-filters-nd-on-main"),
        )
    }
}

/**
 * One Selected Set (FILTER-SET-001, FILTER-FLOW-004): its header — a
 * leading remove control, the name area that opens the set's editor, and
 * a trailing add-filter control while the set holds a filter, and an
 * inline ND cue while it holds ND filters — then its auxiliary filters in
 * one indented strip of equal-width controls, or a full-width Add Filter
 * row while it holds none. Picking a filter never changes the set's
 * height.
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
        FilterSetEditArea(filterSet, isInUse, onEdit, Modifier.weight(1f), showsNdCue = filterSet.showsNdCue)
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
        // The strip scrolls freely on its own, without snapping, and keeps
        // its position (FILTER-AUX-006, FILTER-FLOW-003). Every control has
        // the same width, sized so three whole controls and part of the
        // next show at once. A strip with a GND reserves two lines in every
        // bottom row, so the whole mode name fits and the set keeps one
        // height whatever is mounted.
        val bottomLines = if (items.any { it.behavior is FilterItemBehavior.Gnd }) 2 else 1
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = StripIndent, bottom = 6.dp),
        ) {
            val controlWidth = maxWidth / 3.2f - StripSpacing
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(stripScrollState)
                    .height(IntrinsicSize.Max)
                    .testTag("shooting-filters-strip-${filterSet.id.rawValue}"),
                horizontalArrangement = Arrangement.spacedBy(StripSpacing),
            ) {
                items.forEach { item ->
                    FilterItemStripControl(
                        filterSet = filterSet,
                        item = item,
                        mount = mountOf(item.id),
                        onMount = { mount -> onMount(item.id, mount) },
                        bottomLines = bottomLines,
                        modifier = Modifier.width(controlWidth),
                    )
                }
            }
        }
    }
}

/** An Available Set (FILTER-SET-001): the name area opens its editor, a
 *  passive hint below the name tells what the set holds, and the trailing
 *  control adds it to the Selected Sets. */
@Composable
private fun AvailableFilterSetRow(filterSet: FilterSet, isInUse: Boolean, onEdit: () -> Unit, onAdd: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("shooting-filters-available-set-${filterSet.id.rawValue}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.width(16.dp))
        FilterSetEditArea(filterSet, isInUse, onEdit, Modifier.weight(1f), contentsHint = filterSetContentsHintText(filterSet))
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

/** A Filter Set's color and name on one line, with an inline ND cue for a
 *  Selected Set holding ND filters and an inline In use while this camera
 *  mounts from it (FILTER-SET-001, FILTER-FLOW-003); tapping opens the
 *  set's editor. */
@Composable
private fun FilterSetEditArea(
    filterSet: FilterSet,
    isInUse: Boolean,
    onEdit: () -> Unit,
    modifier: Modifier,
    showsNdCue: Boolean = false,
    contentsHint: String? = null,
) {
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
        Column(modifier = Modifier.weight(1f, fill = false).padding(vertical = 4.dp)) {
            Text(
                filterSet.name,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            contentsHint?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.testTag("shooting-filters-available-set-contents-${filterSet.id.rawValue}"),
                )
            }
        }
        if (showsNdCue) {
            // A passive cue: this set offers ND filters on Main
            // (FILTER-FLOW-003).
            Spacer(Modifier.width(8.dp))
            Text(
                "ND",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .border(BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp),
            )
        }
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

/** How far a set's strip sits in from its header, so the set that owns it
 *  reads at once. */
private val StripIndent = 48.dp

/** The gap between two controls of a strip. */
private val StripSpacing = 6.dp

/**
 * One auxiliary item of a set's strip (FILTER-AUX-006, FILTER-CPL-005,
 * FILTER-GND-001/002/003): an equal-width Material card whose upper part
 * mounts or unmounts the item — a check while mounted and a plus while
 * not, so the state does not rest on color — and shows the kind apart from
 * the name, which may wrap to two lines. Its bottom row is a mounted CPL's
 * or GND's choice menu, which never unmounts it, or else the registered
 * value, so every control keeps one height. A GND mode changes at once
 * with no confirmation.
 */
@Composable
private fun FilterItemStripControl(
    filterSet: FilterSet,
    item: FilterItem,
    mount: MountedAuxiliaryFilter?,
    onMount: (MountedAuxiliaryFilter?) -> Unit,
    bottomLines: Int,
    modifier: Modifier = Modifier,
) {
    val isMounted = mount != null
    val detail = filterItemDetailText(item)
    val colors = if (isMounted) {
        CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary)
    } else {
        CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHighest)
    }
    Card(
        colors = colors,
        border = if (isMounted) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = modifier.fillMaxHeight(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(role = Role.Checkbox) {
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
                }
                .semantics(mergeDescendants = true) {
                    contentDescription = "${item.name}, $detail"
                    selected = isMounted
                }
                .padding(horizontal = 8.dp, vertical = 6.dp)
                .testTag("auxiliary-item-toggle-${item.id.rawValue}"),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(
                    if (isMounted) Icons.Filled.CheckCircle else Icons.Outlined.AddCircle,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                )
                Text(localizedFilterKindName(item.behavior.kind), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, maxLines = 1)
                FilterKindIcon(item.behavior.kind)
                item.behavior.opticalColor?.let { FilterSetColorSwatch(it, size = 8.dp) }
            }
            Spacer(Modifier.height(2.dp))
            // The whole name in up to two lines; a long one shrinks a little
            // before it is cut.
            Text(
                item.name,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                minLines = 2,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                autoSize = TextAutoSize.StepBased(minFontSize = 10.sp, maxFontSize = 12.sp, stepSize = 0.5.sp),
            )
        }
        HorizontalDivider(color = if (isMounted) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.4f) else MaterialTheme.colorScheme.outlineVariant)
        Box(modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 40.dp), contentAlignment = Alignment.CenterStart) {
            val behavior = item.behavior
            val choice = mount?.choice
            when {
                behavior is FilterItemBehavior.Cpl && choice is AuxiliaryFilterChoice.CplLoss ->
                    ChoiceMenu(
                        label = filterStopsText(choice.stops),
                        options = behavior.choices.shootingChoices.map { filterStopsText(it) to it },
                        tag = "auxiliary-item-cpl-choice-${item.id.rawValue}",
                        lines = bottomLines,
                        onSelect = { onMount(mount.copy(choice = AuxiliaryFilterChoice.CplLoss(it))) },
                    )
                behavior is FilterItemBehavior.Gnd && choice is AuxiliaryFilterChoice.Gnd -> {
                    val stops = behavior.value.canonicalStops ?: 0.0
                    ChoiceMenu(
                        label = localizedGndModeName(choice.mode),
                        options = GndCalculationMode.entries.map { mode ->
                            "${localizedGndModeName(mode)} · ${filterStopsText(if (mode == GndCalculationMode.applyFullValue) stops else 0.0)}" to mode
                        },
                        tag = "auxiliary-item-gnd-mode-${item.id.rawValue}",
                        lines = bottomLines,
                        onSelect = { onMount(mount.copy(choice = AuxiliaryFilterChoice.Gnd(it))) },
                    )
                }
                else -> Text(
                    trailingValue(item),
                    style = MaterialTheme.typography.labelSmall,
                    minLines = bottomLines,
                    maxLines = bottomLines,
                    modifier = Modifier.padding(horizontal = 8.dp),
                )
            }
        }
    }
}

/**
 * A supplementary type cue beside a filter's type text (FILTER-FLOW-007):
 * a ring for CPL, a graduated filter for GND, and a sparkle for Effect,
 * drawn in the text's color. Decorative; the type text is what TalkBack
 * reads. (iOS: `FilterKindIcon`.)
 */
@Composable
private fun FilterKindIcon(kind: FilterItemKind) {
    if (kind == FilterItemKind.fixed || kind == FilterItemKind.color) return
    val color = LocalContentColor.current
    Canvas(modifier = Modifier.size(10.dp).testTag("filter-kind-icon-${kind.name}")) {
        val unit = size.minDimension
        val line = unit * 0.12f
        when (kind) {
            FilterItemKind.cpl -> {
                drawCircle(color, radius = (unit - line) / 2, style = Stroke(line))
                drawCircle(color, radius = unit * 0.2f, style = Stroke(line))
            }
            FilterItemKind.gnd -> {
                val corner = CornerRadius(unit * 0.15f)
                val inset = line / 2
                drawRoundRect(color, topLeft = Offset(inset, inset), size = Size(unit - line, unit - line), cornerRadius = corner, style = Stroke(line))
                drawRoundRect(color, size = Size(unit, unit / 2), cornerRadius = corner)
            }
            else -> {
                val c = unit / 2
                val waist = unit * 0.12f
                drawPath(
                    Path().apply {
                        moveTo(c, 0f)
                        quadraticTo(c + waist, c - waist, unit, c)
                        quadraticTo(c + waist, c + waist, c, unit)
                        quadraticTo(c - waist, c + waist, 0f, c)
                        quadraticTo(c - waist, c - waist, c, 0f)
                        close()
                    },
                    color,
                )
            }
        }
    }
}

/** The bottom row of a mounted CPL or GND: its current value and a
 *  drop-down arrow, opening the other values in a menu without unmounting
 *  it. */
@Composable
private fun <T> ChoiceMenu(label: String, options: List<Pair<String, T>>, tag: String, lines: Int, onSelect: (T) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 40.dp)
                .clickable(role = Role.DropdownList) { expanded = true }
                .padding(start = 8.dp, end = 2.dp)
                .testTag(tag),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Wrap between words, never inside one ("노출에 / 적용").
            Text(
                label,
                style = MaterialTheme.typography.labelSmall.copy(lineBreak = LineBreak.Heading.copy(wordBreak = LineBreak.WordBreak.Phrase)),
                minLines = lines,
                maxLines = lines,
                overflow = TextOverflow.Ellipsis,
                autoSize = TextAutoSize.StepBased(minFontSize = 9.sp, maxFontSize = 11.sp, stepSize = 0.5.sp),
                modifier = Modifier.weight(1f),
            )
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null, modifier = Modifier.size(20.dp))
        }
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

/** An Available Set's contents hint (FILTER-SET-001): `ND ×3 · Color ×2 ·
 *  CPL`, or Empty. Filter management shows the same hint. */
@Composable
internal fun filterSetContentsHintText(filterSet: FilterSet): String {
    val entries = FilterSetContentsHint.entries(filterSet)
    if (entries.isEmpty()) return stringResource(R.string.filter_empty)
    return entries.map { entry ->
        val name = localizedFilterKindName(entry.kind)
        if (entry.count > 1) "$name ×${entry.count}" else name
    }.joinToString(" · ")
}

/** An unmounted CPL shows its configured losses, a GND its registered
 *  value, Color and Effect their loss. */
@Composable
private fun trailingValue(item: FilterItem): String = when (val behavior = item.behavior) {
    is FilterItemBehavior.Cpl -> behavior.choices.shootingChoices.joinToString(" / ") { FilterWheelPresenter.decimalStopsValue(it) }
    is FilterItemBehavior.Gnd -> filterRegisteredValueText(behavior.value)
    is FilterItemBehavior.Fixed -> filterRegisteredValueText(behavior.value)
    is FilterItemBehavior.Color -> filterStopsText(behavior.loss.stops)
    is FilterItemBehavior.Effect -> filterStopsText(behavior.loss.stops)
}
