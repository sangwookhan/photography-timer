// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.CandidateFilterSetAssignmentOutcome
import com.sangwook.ptimer.app.vm.FilterItemCategory
import com.sangwook.ptimer.app.vm.FilterSourceUiOption
import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.ui.theme.filterSetColor

/**
 * Everything the shooting popup may do. Bundled so the display layer
 * stays free of the controller type.
 */
internal class ShootingFiltersActions(
    val rejection: (List<MountedAuxiliaryFilter>) -> FilterStackRejection?,
    val subtotal: (List<MountedAuxiliaryFilter>) -> Double,
    val apply: (List<MountedAuxiliaryFilter>) -> FilterStackRejection?,
    val addWheel: (FilterSource) -> Unit,
    val setCandidates: (List<FilterSetId>) -> CandidateFilterSetAssignmentOutcome,
    val manageFilterSets: () -> Unit,
)

/**
 * The shooting popup (FILTER-FLOW-002/003, FILTER-AUX-003): what the
 * active camera mounts for the current shot. The Auxiliary tab — first —
 * edits a working selection (mounting, CPL choices, GND modes) that Apply
 * commits atomically and Close discards; the ND tab adds an ND wheel from
 * Standard or a candidate set immediately, with the same rules and source
 * memory as Plus. Both tabs route to the camera's candidate Filter Sets
 * and to inventory management; stored item definitions are edited there,
 * never here. Material puts dismissal on the leading navigation icon and
 * the confirming action on the trailing edge.
 * (iOS: `ShootingFilterSelectionView`.)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ShootingFiltersScreen(
    inventory: FilterInventory,
    /** The camera's committed mounts in display order. */
    committed: List<MountedAuxiliaryFilter>,
    candidateFilterSetIds: List<FilterSetId>,
    /** Standard and the candidate ND sources, judged against this camera. */
    ndSources: List<FilterSourceUiOption>,
    isNdInteractionQuiet: Boolean,
    actions: ShootingFiltersActions,
    onDismiss: () -> Unit,
) {
    var tab by rememberSaveable { mutableStateOf(FilterItemCategory.auxiliary) }
    // The working selection starts from the camera's mounted items; the
    // committed mounts can change underneath (a kind correction made in
    // management opened from here), and the selection restarts from them
    // so Apply can never undo that change with a stale selection.
    var draft by remember { mutableStateOf(committed) }
    LaunchedEffect(committed) { draft = committed }
    var applyRejection by remember { mutableStateOf<FilterStackRejection?>(null) }
    var showCameraSets by remember { mutableStateOf(false) }

    // Mount order never matters (display order is fixed), so the working
    // selection is compared as a set.
    val hasChanges = draft.toSet() != committed.toSet()
    val rejection = actions.rejection(draft)
    val canApply = hasChanges && rejection == null

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
                                if (tab == FilterItemCategory.auxiliary) {
                                    TextButton(
                                        onClick = {
                                            val refused = actions.apply(draft)
                                            if (refused == null) onDismiss() else applyRejection = refused
                                        },
                                        enabled = canApply,
                                        modifier = Modifier.testTag("shooting-filters-apply"),
                                    ) { Text(stringResource(R.string.filter_shooting_apply)) }
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
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp),
                    ) {
                        val tabs = listOf(FilterItemCategory.auxiliary, FilterItemCategory.nd)
                        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                            tabs.forEachIndexed { index, option ->
                                SegmentedButton(
                                    selected = tab == option,
                                    onClick = { tab = option },
                                    shape = SegmentedButtonDefaults.itemShape(index = index, count = tabs.size),
                                ) {
                                    Text(
                                        stringResource(
                                            if (option == FilterItemCategory.auxiliary) {
                                                R.string.filter_auxiliary_title
                                            } else {
                                                R.string.filter_set_tab_nd
                                            },
                                        ),
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                        when (tab) {
                            FilterItemCategory.auxiliary -> AuxiliaryTab(
                                inventory = inventory,
                                candidateFilterSetIds = candidateFilterSetIds,
                                draft = draft,
                                onDraft = { draft = it },
                                subtotal = actions.subtotal(draft),
                                rejection = rejection,
                            )

                            FilterItemCategory.nd -> NdTab(
                                ndSources = ndSources,
                                isNdInteractionQuiet = isNdInteractionQuiet,
                                onAdd = actions.addWheel,
                            )
                        }
                        Spacer(Modifier.height(16.dp))
                        HorizontalDivider()
                        RouteRow(stringResource(R.string.filter_camera_sets_title)) { showCameraSets = true }
                        HorizontalDivider()
                        RouteRow(stringResource(R.string.filter_manage_sets), actions.manageFilterSets)
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

    if (showCameraSets) {
        CameraFilterSetsScreen(
            inventory = inventory,
            candidateFilterSetIds = candidateFilterSetIds,
            setCandidates = actions.setCandidates,
            onBack = { showCameraSets = false },
        )
    }
}

/** The kinds in the stable auxiliary order (FILTER-AUX-002). */
private val AuxiliaryKindOrder = listOf(FilterItemKind.color, FilterItemKind.effect, FilterItemKind.cpl, FilterItemKind.gnd)

/**
 * The Auxiliary tab: every auxiliary item of the camera's candidate sets,
 * grouped Color, Effect, CPL, GND and within a kind in set order then
 * item order; the whole list scrolls however many there are. The live line
 * shows only the auxiliary subtotal — never the whole Total, which
 * includes ND wheels this tab does not show — or, past 30 stops, the
 * refusal Apply would report.
 */
@Composable
private fun AuxiliaryTab(
    inventory: FilterInventory,
    candidateFilterSetIds: List<FilterSetId>,
    draft: List<MountedAuxiliaryFilter>,
    onDraft: (List<MountedAuxiliaryFilter>) -> Unit,
    subtotal: Double,
    rejection: FilterStackRejection?,
) {
    val auxiliarySets = inventory.filterSets.filter { it.id in candidateFilterSetIds && it.auxiliaryItems.isNotEmpty() }
    if (auxiliarySets.isEmpty()) {
        Text(
            stringResource(R.string.filter_shooting_no_auxiliary),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        return
    }
    for (kind in AuxiliaryKindOrder) {
        val entries = auxiliarySets.flatMap { set ->
            set.auxiliaryItems.filter { it.behavior.kind == kind }.map { set to it }
        }
        if (entries.isEmpty()) continue
        SectionLabel(localizedFilterKindName(kind))
        entries.forEach { (set, item) ->
            AuxiliaryItemRow(
                filterSet = set,
                item = item,
                mount = draft.firstOrNull { it.itemId == item.id },
                onMount = { mount ->
                    onDraft(draft.filter { it.itemId != item.id } + listOfNotNull(mount))
                },
            )
            HorizontalDivider()
        }
        Spacer(Modifier.height(12.dp))
    }
    if (rejection == null) {
        val value = filterStopsText(subtotal)
        val label = stringResource(R.string.filter_auxiliary_subtotal)
        val spoken = stringResource(R.string.filter_auxiliary_subtotal_cd, value)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp)
                .testTag("shooting-filters-auxiliary-subtotal")
                .clearAndSetSemantics { contentDescription = spoken },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp)
                .testTag("shooting-filters-rejection"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Text(filterRejectionText(rejection), color = MaterialTheme.colorScheme.error)
        }
    }
    FooterText(stringResource(R.string.filter_shooting_apply_footer))
}

/**
 * One auxiliary item of a candidate set: a mount switch and — while
 * mounted — the CPL exposure-loss choice or the GND calculation mode
 * (FILTER-CPL-005, FILTER-GND-001/002/003). Color and Effect items show
 * their registered loss; nothing is inferred. The source set is named
 * under the item because the list is ordered by kind.
 */
@Composable
private fun AuxiliaryItemRow(
    filterSet: FilterSet,
    item: FilterItem,
    mount: MountedAuxiliaryFilter?,
    onMount: (MountedAuxiliaryFilter?) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    item.behavior.opticalColor?.let { FilterSetColorSwatch(it, size = 10.dp) }
                    Text(item.name, style = MaterialTheme.typography.bodyLarge)
                }
                Text(
                    filterItemDetailText(item),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    SourceCue(filterSetColor(filterSet.color), size = 8.dp)
                    Text(
                        filterSet.name,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Switch(
                checked = mount != null,
                onCheckedChange = { on ->
                    onMount(
                        if (on) {
                            MountedAuxiliaryFilter(
                                filterSet.id,
                                item.id,
                                MountedAuxiliaryFilter.initialChoice(item) ?: AuxiliaryFilterChoice.RegisteredLoss,
                            )
                        } else {
                            null
                        },
                    )
                },
            )
        }
        val behavior = item.behavior
        if (mount != null && behavior is FilterItemBehavior.Cpl) {
            Spacer(Modifier.height(6.dp))
            val choices = behavior.choices.shootingChoices
            val selected = (mount.choice as? AuxiliaryFilterChoice.CplLoss)?.stops
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                choices.forEachIndexed { index, loss ->
                    SegmentedButton(
                        selected = selected == loss,
                        onClick = { onMount(mount.copy(choice = AuxiliaryFilterChoice.CplLoss(loss))) },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = choices.size),
                    ) { Text(filterStopsText(loss), maxLines = 1) }
                }
            }
        }
        if (mount != null && behavior is FilterItemBehavior.Gnd) {
            Spacer(Modifier.height(6.dp))
            val modes = GndCalculationMode.entries
            val selected = (mount.choice as? AuxiliaryFilterChoice.Gnd)?.mode
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                modes.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = selected == mode,
                        onClick = { onMount(mount.copy(choice = AuxiliaryFilterChoice.Gnd(mode))) },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = modes.size),
                    ) { Text(localizedGndModeName(mode), maxLines = 1) }
                }
            }
            if (selected == GndCalculationMode.applyFullValue) {
                FooterText(stringResource(R.string.filter_gnd_modes_warning))
            }
        }
    }
}

/** The ND tab: Standard and the candidate ND sources, each with an
 *  explicit Add ND wheel action (FILTER-FLOW-003, FILTER-PLUS-004/005). */
@Composable
private fun NdTab(
    ndSources: List<FilterSourceUiOption>,
    isNdInteractionQuiet: Boolean,
    onAdd: (FilterSource) -> Unit,
) {
    SectionLabel(stringResource(R.string.filter_shooting_nd_sources))
    ndSources.forEach { option ->
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    option.color?.let { FilterSetColorSwatch(it, size = 10.dp) }
                    Text(localizedSourceName(option.name), style = MaterialTheme.typography.bodyLarge)
                }
                option.addUnavailability?.let {
                    Text(
                        filterAddUnavailabilityText(it),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            OutlinedButton(
                onClick = { onAdd(option.source) },
                enabled = option.addUnavailability == null && isNdInteractionQuiet,
            ) { Text(stringResource(R.string.filter_shooting_add_nd_wheel)) }
        }
        HorizontalDivider()
    }
    FooterText(stringResource(R.string.filter_shooting_nd_footer))
}

@Composable
private fun RouteRow(label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
    }
}

/**
 * Camera Filter Sets (FILTER-CAMERA-001/002): choose which inventory sets
 * the active camera offers. Assignment saves immediately and mounts
 * nothing; excluding a set the camera still uses is refused with its name.
 * Standard is always available and is not listed.
 * (iOS: `CameraFilterSetsView`.)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CameraFilterSetsScreen(
    inventory: FilterInventory,
    candidateFilterSetIds: List<FilterSetId>,
    setCandidates: (List<FilterSetId>) -> CandidateFilterSetAssignmentOutcome,
    onBack: () -> Unit,
) {
    var blocked by remember { mutableStateOf<List<FilterSet>?>(null) }
    Dialog(
        onDismissRequest = onBack,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.filter_camera_sets_title)) },
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
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .consumeWindowInsets(padding)
                            .navigationBarsPadding()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp),
                    ) {
                        if (inventory.filterSets.isEmpty()) {
                            Text(
                                stringResource(R.string.filter_camera_sets_empty),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        inventory.filterSets.forEach { set ->
                            val isCandidate = set.id in candidateFilterSetIds
                            fun toggle() {
                                val next = if (isCandidate) {
                                    candidateFilterSetIds - set.id
                                } else {
                                    candidateFilterSetIds + set.id
                                }
                                val outcome = setCandidates(next)
                                if (outcome is CandidateFilterSetAssignmentOutcome.Blocked) {
                                    blocked = outcome.referencedFilterSets
                                }
                            }
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { toggle() }
                                    .padding(vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(checked = isCandidate, onCheckedChange = { toggle() })
                                Spacer(Modifier.width(8.dp))
                                FilterSetColorSwatch(set.color, size = 12.dp)
                                Spacer(Modifier.width(8.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(set.name, style = MaterialTheme.typography.bodyLarge)
                                    Text(
                                        filterSetKindCountText(set),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            HorizontalDivider()
                        }
                        FooterText(stringResource(R.string.filter_camera_sets_footer))
                        Spacer(Modifier.height(24.dp))
                    }
                }
            }
        }
    }

    blocked?.let { sets ->
        AlertDialog(
            onDismissRequest = { blocked = null },
            title = { CappedFontScale { Text(stringResource(R.string.filter_camera_sets_in_use_title)) } },
            text = {
                CappedFontScale {
                    Text(stringResource(R.string.filter_camera_sets_in_use_message, sets.joinToString(", ") { it.name }))
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

/** `2 auxiliary · 3 ND` — what a set holds for each tab. */
@Composable
private fun filterSetKindCountText(set: FilterSet): String =
    stringResource(R.string.filter_camera_sets_counts, set.auxiliaryItems.size, set.ndItems.size)
