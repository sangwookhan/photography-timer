// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.clip
import com.sangwook.ptimer.core.customfilm.CustomFilmCheckpointRow
import com.sangwook.ptimer.core.customfilm.CustomFilmReferencePointRow
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.CustomFilmDraft
import androidx.compose.ui.res.stringResource
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.ui.localizedCoreText
import com.sangwook.ptimer.app.ui.localizedFilmName


/**
 * Tier-2 shooting screen: film selection + alternate model, the shared
 * SnapWheel for base shutter and ND, the adjusted/corrected result with its
 * confidence label, and Start. Resembles iOS, adapted to Material.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShootingScreen(
    state: CalculatorUiState,
    onShutterIndex: (Int) -> Unit,
    onNdIndex: (Int) -> Unit,
    onSelectNotation: (NDNotationMode) -> Unit,
    onSelectFilm: (String?) -> Unit,
    onSelectProfile: (String) -> Unit,
    onSelectSlot: (CameraSlotId) -> Unit,
    onRenameSlot: (String?) -> Unit,
    onSetTarget: (Double?) -> Unit,
    onStartTarget: () -> Unit,
    onStartAdjusted: () -> Unit,
    onStartCorrected: () -> Unit,
    onOpenDetails: () -> Unit,
    onResetSettings: () -> Unit,
    onResetSettingsAndName: () -> Unit,
    onCreateCustomFilm: (CustomFormulaFilmInput, editFilmId: String?) -> Boolean,
    onCreateCustomTableFilm: (CustomTableFilmInput, editFilmId: String?) -> Boolean,
    onEditCustomFilm: (String) -> CustomFilmDraft?,
    onDeleteCustomFilm: (String) -> Unit,
    onPreviewCustomFilm: (CustomFormulaFilmInput) -> ReciprocityGraph?,
    onPreviewCustomTableFilm: (CustomTableFilmInput) -> ReciprocityGraph?,
    onFormulaCheckpoints: (CustomFormulaFilmInput) -> List<CustomFilmCheckpointRow>,
    onTableCheckpoints: (CustomTableFilmInput) -> List<CustomFilmCheckpointRow>,
    onCalculationBasis: (CustomFormulaFilmInput) -> String,
    onPreviewTableFit: (CustomTableFilmInput) -> CustomTableFittedFormula.Outcome?,
    onCreateFormulaFromTable: (CustomTableFilmInput, editFilmId: String?) -> Boolean,
    onReferencePoints: (CustomFormulaFilmInput, List<Pair<Double, Double>>) -> List<CustomFilmReferencePointRow>,
    onOpenAbout: () -> Unit,
    showExactAlarmSettingsAction: Boolean,
    onOpenExactAlarmSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showFilmPicker by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    // Non-null when editing an existing custom film (prefilled dialog, save in place).
    var editDraft by remember { mutableStateOf<CustomFilmDraft?>(null) }
    var showTarget by remember { mutableStateOf(false) }
    var showEditor by remember { mutableStateOf(false) }
    // Gates the destructive reset behind an explicit confirmation so a
    // single accidental tap (Reset sits next to the About icon) cannot
    // wipe the slot's shooting setup. PTIMER-208.
    var showResetConfirm by remember { mutableStateOf(false) }

    val activeIndex = state.slots.indexOfFirst { it.isActive }.coerceAtLeast(0)
    val pagerState = rememberPagerState(initialPage = activeIndex) { state.slots.size }

    // Swiping the pager settles on a page → make that camera the active slot
    // (capture-on-switch). The reverse effect keeps the pager aligned when the
    // slot changes from elsewhere (e.g. a restored session).
    LaunchedEffect(pagerState.settledPage) {
        val idx = pagerState.settledPage
        if (idx in state.slots.indices) onSelectSlot(state.slots[idx].id)
    }
    LaunchedEffect(activeIndex) {
        if (!pagerState.isScrollInProgress && pagerState.currentPage != activeIndex) {
            pagerState.animateScrollToPage(activeIndex)
        }
    }

    Scaffold(modifier = modifier) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) { page ->
                // Each page renders its OWN slot's state so a swipe reveals the
                // destination camera immediately (no clone-until-settle). Editing
                // controls still target the active slot, which the settle handler
                // keeps aligned with the on-screen page (capture-on-switch).
                // No vertical scroll: the whole calculator must fit at a glance.
                val pageState = state.slotStates.getOrNull(page) ?: state
                // The shared wheel callbacks write to the ACTIVE slot. The pager
                // keeps adjacent pages composed, and SnapWheel auto-emits its
                // centered value on (re)layout — so during a swipe an incoming
                // page's wheel would write its value into the still-active
                // outgoing slot, resetting it. Gate the writes so only the page
                // that IS the active slot edits it; off-active pages are
                // display-only.
                val writesActiveSlot = page == activeIndex
                val onShutterForPage: (Int) -> Unit = if (writesActiveSlot) onShutterIndex else { _ -> }
                val onNdForPage: (Int) -> Unit = if (writesActiveSlot) onNdIndex else { _ -> }
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                ) {
                    // Header: camera name (tap to rename) + Reset.
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            // weight(fill = false) keeps a long renamed camera
                            // name from squeezing the action icons (PTIMER-219).
                            modifier = Modifier.clickable { showRename = true }.weight(1f, fill = false),
                        ) {
                            Text(
                                pageState.activeSlotName,
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Icon(
                                Icons.Filled.Edit,
                                contentDescription = stringResource(R.string.rename_camera_title),
                                modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            // Show Reset only on the active page and only when
                            // something is resettable (matches iOS). The reset
                            // callbacks target the active slot, so gating on the
                            // active page also avoids resetting from a peeked page.
                            if (writesActiveSlot && pageState.canReset) {
                                TextButton(onClick = { showResetConfirm = true }) { Text(stringResource(R.string.action_reset)) }
                            }
                            // Exact alarms are off (PTIMER-219): keep a
                            // persistent status icon next to the existing
                            // info icon instead of a separate row or banner
                            // that only shows post-dismissal.
                            if (showExactAlarmSettingsAction) {
                                IconButton(onClick = onOpenExactAlarmSettings) {
                                    Icon(
                                        Icons.Outlined.Warning,
                                        contentDescription = stringResource(R.string.alarm_warning_title),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            IconButton(onClick = onOpenAbout) {
                                Icon(
                                    Icons.Outlined.Info,
                                    contentDescription = "About PTIMER",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    // Film selector. No standalone "Film" label: the "No
                    // film" placeholder value already names it for a
                    // first-time user, and once a film is picked the row's
                    // position + chevron carry the same context (PTIMER-219).
                    Card(
                        modifier = Modifier.fillMaxWidth().clickable { showFilmPicker = true },
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(CardRowPadding),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                localizedFilmName(pageState.selectedFilmName),
                                style = MaterialTheme.typography.titleMedium,
                                modifier = Modifier.weight(1f, fill = false),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Spacer(Modifier.width(8.dp))
                            Icon(
                                Icons.Filled.KeyboardArrowDown,
                                contentDescription = "Choose film",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    if (pageState.modelOptions.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        // Equal width per option (PTIMER-219): without weight(),
                        // the first chip's wrap-content width claims whatever it
                        // needs and squeezes a longer-labeled sibling into a
                        // narrow, character-wrapped column at large font scale.
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            pageState.modelOptions.forEach { option ->
                                FilterChip(
                                    selected = option.id == pageState.selectedProfileId,
                                    onClick = { onSelectProfile(option.id) },
                                    label = { Text(option.label) },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Target Shutter row (value + stop-diff + ▶), tap to edit.
                    TargetShutterRow(
                        display = pageState.targetDisplay,
                        onEdit = { showTarget = true },
                        onStartTarget = onStartTarget,
                    )

                    Spacer(Modifier.height(8.dp))

                    // Base shutter + ND wheels (compact: 3 visible rows).
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(CardRowPadding),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                // Header height matches the ND column's title+toggle
                                // row so the two wheels stay vertically aligned.
                                Box(
                                    modifier = Modifier.fillMaxWidth().height(NotationToggleHeight),
                                    contentAlignment = Alignment.CenterStart,
                                ) {
                                    Text(stringResource(R.string.shooting_base_shutter), style = MaterialTheme.typography.labelLarge)
                                }
                                SnapWheel(
                                    pageState.shutterLabels,
                                    pageState.shutterIndex,
                                    onShutterForPage,
                                    visibleCount = 3,
                                    itemHeight = 34.dp,
                                    accessibilityLabel = stringResource(R.string.shooting_base_shutter),
                                )
                            }
                            Column(
                                modifier = Modifier.weight(1f),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                // One horizontal header row: a stronger "ND Filter"
                                // title with the compact notation toggle, matching
                                // the iOS placement (PTIMER-187).
                                Row(
                                    modifier = Modifier.fillMaxWidth().height(NotationToggleHeight),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(stringResource(R.string.shooting_nd_filter), style = MaterialTheme.typography.labelLarge)
                                    Spacer(Modifier.weight(1f))
                                    NotationToggle(
                                        mode = pageState.ndNotationMode,
                                        enabled = writesActiveSlot,
                                        onSelect = onSelectNotation,
                                    )
                                }
                                SnapWheel(
                                    pageState.ndLabels,
                                    pageState.ndIndex,
                                    onNdForPage,
                                    visibleCount = 3,
                                    itemHeight = 34.dp,
                                    accessibilityLabel = stringResource(R.string.shooting_nd_filter),
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    ResultCard(
                        state = pageState,
                        onStartAdjusted = onStartAdjusted,
                        onStartCorrected = onStartCorrected,
                        onOpenDetails = onOpenDetails,
                    )
                }
            }

            // Page dots + "N of M" at the bottom; swipe to change camera.
            PagerDots(count = state.slots.size, current = pagerState.currentPage)
            Spacer(Modifier.height(8.dp))
        }
    }

    if (showFilmPicker) {
        FilmPickerSheet(
            filmOptions = state.filmOptions,
            selectedFilmId = state.selectedFilmId,
            onSelect = { id -> onSelectFilm(id); showFilmPicker = false },
            onCreateNew = { showFilmPicker = false; editDraft = null; showEditor = true },
            onEditFilm = { id ->
                onEditCustomFilm(id)?.let { draft ->
                    showFilmPicker = false
                    editDraft = draft
                    showEditor = true
                }
            },
            onDeleteFilm = { id -> onDeleteCustomFilm(id) },
            onDismiss = { showFilmPicker = false },
        )
    }

    if (showEditor) {
        CustomFilmEditorDialog(
            initial = editDraft,
            onCreateFormula = { input, editId ->
                onCreateCustomFilm(input, editId).also { if (it) { showEditor = false; editDraft = null } }
            },
            onCreateTable = { input, editId ->
                onCreateCustomTableFilm(input, editId).also { if (it) { showEditor = false; editDraft = null } }
            },
            onPreviewFormula = onPreviewCustomFilm,
            onPreviewTable = onPreviewCustomTableFilm,
            onFormulaCheckpoints = onFormulaCheckpoints,
            onTableCheckpoints = onTableCheckpoints,
            onCalculationBasis = onCalculationBasis,
            onPreviewTableFit = onPreviewTableFit,
            onCreateFormulaFromTable = { input, editId ->
                onCreateFormulaFromTable(input, editId).also { if (it) { showEditor = false; editDraft = null } }
            },
            onReferencePoints = onReferencePoints,
            onDismiss = { showEditor = false; editDraft = null },
        )
    }

    if (showRename) {
        RenameSlotDialog(
            initial = state.activeSlotName,
            onConfirm = { name -> onRenameSlot(name); showRename = false },
            onDismiss = { showRename = false },
        )
    }

    if (showTarget) {
        val current = (state.targetDisplay as? TargetShutterDisplayState.Available)?.state?.targetSeconds
        TargetShutterSheet(
            initialSeconds = current,
            onConfirm = { seconds -> onSetTarget(seconds); showTarget = false },
            onDismiss = { showTarget = false },
        )
    }

    if (showResetConfirm) {
        // AlertDialog composes each slot inside its own dialog window, which
        // re-derives LocalDensity from the system Configuration rather than
        // inheriting ShootingApp's font-scale cap (PTIMER-219) — every slot
        // needs its own CappedFontScale wrap, not just the AlertDialog call site.
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { CappedFontScale { Text(stringResource(R.string.reset_shooting_title)) } },
            // Two destructive choices: keep the camera name, or clear it
            // too. Stacked in the confirm slot (with Cancel) so the
            // single Reset entry point still gates the wipe behind a
            // deliberate choice.
            confirmButton = {
                CappedFontScale {
                    Column(horizontalAlignment = Alignment.End) {
                        TextButton(onClick = { onResetSettings(); showResetConfirm = false }) {
                            Text(stringResource(R.string.reset_settings), color = MaterialTheme.colorScheme.error)
                        }
                        TextButton(onClick = { onResetSettingsAndName(); showResetConfirm = false }) {
                            Text(stringResource(R.string.reset_settings_and_name), color = MaterialTheme.colorScheme.error)
                        }
                        TextButton(onClick = { showResetConfirm = false }) { Text(stringResource(R.string.action_cancel)) }
                    }
                }
            },
        )
    }
}


/** Shared content padding for the film/wheel/result cards (PTIMER-219): one
 *  consistent value instead of each card picking its own (was 16/8/12dp). */
private val CardRowPadding = 8.dp

/** Header-row height reserved for the ND notation toggle (PTIMER-187). */
private val NotationToggleHeight = 30.dp

/** Height of the notation toggle's rounded track. */
private val NotationTrackHeight = 26.dp

/**
 * Compact 3-state ND notation toggle (Stops / OD / ND) for the ND Filter
 * header. Reads as one cohesive segmented control: a single low-emphasis
 * rounded track with the current mode rendered as a filled segment. Current
 * mode is always highlighted; a tap selects a mode. Sized to sit on the
 * header row without adding vertical space below the picker (PTIMER-187).
 */
@Composable
private fun NotationToggle(
    mode: NDNotationMode,
    enabled: Boolean,
    onSelect: (NDNotationMode) -> Unit,
) {
    val options = listOf(
        NDNotationMode.STOPS to stringResource(R.string.notation_stops),
        NDNotationMode.OPTICAL_DENSITY to "OD",
        NDNotationMode.FILTER_FACTOR to "ND",
    )
    Row(
        modifier = Modifier
            .height(NotationTrackHeight)
            .clip(CircleShape)
            // Track is a distinct, outlined surface (lighter than the
            // card's surfaceVariant) so the control reads as a segmented
            // control and the option labels never blend into the card.
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape)
            .padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        options.forEach { (optionMode, label) ->
            val selected = optionMode == mode
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .then(
                        if (selected) Modifier.background(MaterialTheme.colorScheme.secondaryContainer)
                        else Modifier
                    )
                    // selectable (not clickable) so TalkBack announces the
                    // segment as a button with its selected state (PTIMER-182).
                    .selectable(selected = selected, enabled = enabled, role = Role.Button) {
                        onSelect(optionMode)
                    }
                    .padding(horizontal = 7.dp, vertical = 3.dp),
                contentAlignment = Alignment.Center,
            ) {
                // Compact selector labels, a step smaller than the "ND Filter"
                // title so the control stays subordinate. Both selected and
                // unselected labels use full-contrast on-container/on-surface
                // colors so every option stays clearly legible; the selected
                // one adds weight + container fill for a calm highlight.
                Text(
                    label,
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    softWrap = false,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                    color = if (selected) MaterialTheme.colorScheme.onSecondaryContainer
                    else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

/** Small circular start button used next to each computed exposure value.
 *  Callers pass a context-specific description (adjusted/corrected/target)
 *  so the three visually identical buttons stay distinguishable to
 *  TalkBack (PTIMER-182). */
@Composable
internal fun StartButton(onClick: () -> Unit, enabled: Boolean, contentDescription: String) {
    // Shrunk from Material3's default 40dp container (PTIMER-219; iOS uses a
    // 40-44pt circle) down to 36dp, while still guaranteeing the 48dp
    // accessibility touch target. minimumInteractiveComponentSize() must wrap
    // the sized Surface from the OUTSIDE via a separate Box: passing
    // Modifier.size() straight into FilledIconButton's own modifier collapses
    // its internal touch-target padding down to that fixed size instead of
    // reserving extra space around it (the old size(32) attempt hit exactly
    // this).
    val colors = IconButtonDefaults.filledIconButtonColors()
    Box(
        modifier = Modifier.minimumInteractiveComponentSize(),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            onClick = onClick,
            enabled = enabled,
            shape = CircleShape,
            color = if (enabled) colors.containerColor else colors.disabledContainerColor,
            contentColor = if (enabled) colors.contentColor else colors.disabledContentColor,
            modifier = Modifier.size(36.dp),
        ) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = contentDescription,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

@Composable
private fun ResultCard(
    state: CalculatorUiState,
    onStartAdjusted: () -> Unit,
    onStartCorrected: () -> Unit,
    onOpenDetails: () -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.fillMaxWidth().padding(CardRowPadding)) {
            ResultRow(
                label = stringResource(R.string.shooting_adjusted_shutter),
                value = state.adjustedText,
                secondary = state.adjustedSecondsText,
                valueColor = MaterialTheme.colorScheme.onSurface,
                numeric = true,
                onStart = onStartAdjusted,
                startEnabled = state.adjustedStartEnabled,
                startContentDescription = stringResource(R.string.start_timer_adjusted_cd),
            )

            if (state.hasFilm) {
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                // Reciprocity status + details entry (ⓘ) between the two values.
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.shooting_reciprocity),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f, fill = false),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.confidenceLabel?.let { Pill(localizedCoreText(it)) }
                        IconButton(onClick = onOpenDetails) {
                            Icon(
                                Icons.Outlined.Info,
                                contentDescription = stringResource(R.string.shooting_reciprocity_details_cd),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                ResultRow(
                    label = stringResource(R.string.shooting_corrected_exposure),
                    value = state.correctedText ?: stringResource(R.string.shooting_no_corrected_value),
                    secondary = state.correctedSecondsText,
                    valueColor = if (state.correctedText == null) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurface,
                    numeric = state.correctedText != null,
                    onStart = onStartCorrected,
                    startEnabled = state.correctedStartEnabled,
                    startContentDescription = stringResource(R.string.start_timer_corrected_cd),
                )
            }
        }
    }
}

@Composable
private fun ResultRow(
    label: String,
    value: String,
    secondary: String?,
    valueColor: androidx.compose.ui.graphics.Color,
    numeric: Boolean,
    onStart: () -> Unit,
    startEnabled: Boolean,
    startContentDescription: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f))
        // Value + the whole-seconds comparison sit side by side on one line so
        // the row height never changes whether or not the seconds are shown
        // (iOS dual-duration display).
        secondary?.let {
            Text(
                it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontFamily = FontFamily.Monospace,
            )
        }
        Text(
            value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            fontFamily = if (numeric) FontFamily.Monospace else FontFamily.Default,
            color = valueColor,
            textAlign = TextAlign.End,
            maxLines = 1,
        )
        StartButton(onClick = onStart, enabled = startEnabled, contentDescription = startContentDescription)
    }
}

@Composable
internal fun Pill(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Text(text, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
    }
}

/** Manufacturer section header in the film picker (iOS groups films by maker). */
@Composable
private fun RenameSlotDialog(
    initial: String,
    onConfirm: (String?) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    // AlertDialog composes each slot inside its own dialog window, which
    // re-derives LocalDensity from the system Configuration rather than
    // inheriting ShootingApp's font-scale cap (PTIMER-219) — every slot
    // needs its own CappedFontScale wrap, not just the AlertDialog call site.
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { CappedFontScale { Text(stringResource(R.string.rename_camera_title)) } },
        text = {
            CappedFontScale {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    label = { Text(stringResource(R.string.camera_name)) },
                )
            }
        },
        confirmButton = {
            CappedFontScale {
                TextButton(onClick = { onConfirm(text) }) { Text(stringResource(R.string.action_save)) }
            }
        },
        dismissButton = {
            // Empty name clears the custom label back to the canonical default.
            CappedFontScale {
                TextButton(onClick = { onConfirm(null) }) { Text(stringResource(R.string.action_reset)) }
            }
        },
    )
}

@Composable
internal fun PagerDots(count: Int, current: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { index ->
            val color = if (index == current) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            }
            Box(
                modifier = Modifier
                    .padding(horizontal = 4.dp)
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(color),
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            "${current + 1} of $count",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
