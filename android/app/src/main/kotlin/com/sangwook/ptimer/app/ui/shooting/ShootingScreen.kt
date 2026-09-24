// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Settings
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
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.mapSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.app.vm.CalculatorUiState
import com.sangwook.ptimer.app.vm.CustomFilmDraft
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentDirection
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
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
    // Mixed Filter Stack (PTIMER-199 / PTIMER-221): per-wheel activity and
    // selection, the Plus addition for a chosen source, the assistive row
    // scan, and the overscroll removal — all keyed by wheel identity.
    onNdWheelActive: (Int, Boolean) -> Unit,
    onNdWheelValue: (Int, Int) -> Unit,
    onAddFilterWheel: (FilterSource) -> Unit,
    onAdjustFilterWheel: (Int, FilterWheelAdjustmentDirection) -> FilterWheelAdjustmentOutcome,
    onFilterAddUnavailability: (FilterSource) -> FilterAddUnavailability?,
    onRemoveNdWheelOverscroll: (Int) -> Unit,
    onManageFilterSets: () -> Unit,
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
    // rememberSaveable (PTIMER-218): these gate which dialog/sheet is on
    // screen, so a configuration change or process recreation must reopen
    // whichever one was showing rather than silently dropping it.
    var showFilmPicker by rememberSaveable { mutableStateOf(false) }
    var showRename by rememberSaveable { mutableStateOf(false) }
    // Non-null when editing an existing custom film (prefilled dialog, save
    // in place). CustomFilmDraft isn't a Bundle-primitive type, so it needs
    // the explicit CustomFilmDraftSaver rather than the default Saver.
    var editDraft by rememberSaveable(stateSaver = CustomFilmDraftSaver) { mutableStateOf<CustomFilmDraft?>(null) }
    var showTarget by rememberSaveable { mutableStateOf(false) }
    var showEditor by rememberSaveable { mutableStateOf(false) }
    // Gates the destructive reset behind an explicit confirmation so a
    // single accidental tap (Reset sits next to the About icon) cannot
    // wipe the slot's shooting setup. PTIMER-208.
    var showResetConfirm by rememberSaveable { mutableStateOf(false) }

    val activeIndex = state.slots.indexOfFirst { it.isActive }.coerceAtLeast(0)
    val pagerState = rememberPagerState(initialPage = activeIndex) { state.slots.size }

    // The pager is the single source of truth for slot switching:
    // swiping settles on a page → that camera becomes the active slot
    // (capture-on-switch). There is deliberately NO reverse effect
    // driving the pager from the controller's active slot — two-way
    // sync could fight (a late signal while the controller still saw
    // the previous slot could snap the pager back mid-swipe). A
    // restored session is covered by rememberPagerState(initialPage),
    // and nothing else changes the active slot outside this handler.
    LaunchedEffect(pagerState.settledPage) {
        val idx = pagerState.settledPage
        if (idx in state.slots.indices) onSelectSlot(state.slots[idx].id)
    }

    Scaffold(modifier = modifier) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth().weight(1f),
                // The default page connection lets CHILD scrolls steer the
                // pager (re-settling it while unsettled, consuming leftover
                // child flings). A wheel fling overlapping a page swipe can
                // thereby drag the pager back to the origin page (observed
                // on device: the pager returned mid-session with no slot
                // switch involved). Pages hold no scrollables that should
                // ever steer the pager, so child nested scroll is ignored
                // entirely — page swipes are the pager's own drags and are
                // unaffected.
                pageNestedScrollConnection = remember { object : NestedScrollConnection {} },
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
                                    contentDescription = stringResource(R.string.shooting_about_cd),
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
                                contentDescription = stringResource(R.string.shooting_choose_film_cd),
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
                        // The stack owns the card's whole content column so
                        // its one-row status region spans the full content
                        // width (FILTER-STACK-008) instead of starting at
                        // the filter sub-column; the wheels come back
                        // through the slot to sit beside Base Shutter.
                        FilterStackGroup(
                            state = pageState,
                            onWheelActive = if (writesActiveSlot) onNdWheelActive else { _, _ -> },
                            onWheelValue = if (writesActiveSlot) onNdWheelValue else { _, _ -> },
                            onAddFilterWheel = if (writesActiveSlot) onAddFilterWheel else { _ -> },
                            onAdjustFilterWheel = if (writesActiveSlot) {
                                onAdjustFilterWheel
                            } else {
                                { _, _ -> FilterWheelAdjustmentOutcome.Boundary }
                            },
                            onOverscrollRemove = if (writesActiveSlot) onRemoveNdWheelOverscroll else { _ -> },
                            onFilterAddUnavailability = onFilterAddUnavailability,
                            onManageFilterSets = if (writesActiveSlot) onManageFilterSets else fun() {},
                            modifier = Modifier.padding(CardRowPadding),
                        ) { wheels ->
                            val baseShutterCaption = stringResource(R.string.shooting_base_shutter)
                            val ndFilterTitle = stringResource(R.string.shooting_nd_filter)
                            BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                                val split = ndCardColumnSplit(
                                    available = maxWidth - NdColumnGutter,
                                    ndTitle = ndFilterTitle,
                                    baseShutterCaption = baseShutterCaption,
                                    shutterLabels = pageState.shutterLabels,
                                    wheelCount = pageState.filterWheels.size,
                                    plusVisible = pageState.plus.isVisible,
                                )
                                // Three rows, not two columns: a caption band,
                                // the notation/management band, then the picker
                                // band. Whatever height the first two take is
                                // the height BOTH columns reserve, so the
                                // pickers start on one line without anyone
                                // measuring anyone (FILTER-STACK-008).
                                Column(modifier = Modifier.fillMaxWidth()) {
                                    Row(modifier = Modifier.fillMaxWidth()) {
                                        // No fixed height: the caption has no
                                        // maxLines and no overflow, so a box too
                                        // short for the line it needs used to cut
                                        // it off in silence.
                                        Box(
                                            modifier = Modifier
                                                .width(split.shutterWidth)
                                                .heightIn(min = NotationToggleHeight),
                                            contentAlignment = Alignment.CenterStart,
                                        ) {
                                            Text(baseShutterCaption, style = MaterialTheme.typography.labelLarge)
                                        }
                                        Spacer(Modifier.width(NdColumnGutter))
                                        Box(
                                            modifier = Modifier
                                                .width(split.ndWidth)
                                                .heightIn(min = NotationToggleHeight),
                                            contentAlignment = Alignment.CenterStart,
                                        ) {
                                            Text(
                                                ndFilterTitle,
                                                style = MaterialTheme.typography.labelLarge,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                        }
                                    }
                                    NdNotationControls(
                                        mode = pageState.ndNotationMode,
                                        enabled = writesActiveSlot,
                                        onSelectNotation = onSelectNotation,
                                        onManageFilterSets = onManageFilterSets,
                                    )
                                    Row(modifier = Modifier.fillMaxWidth()) {
                                        Column(
                                            modifier = Modifier.width(split.shutterWidth),
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                        ) {
                                            // Reserve the filter columns' persistent
                                            // type/mode label height (FILTER-STACK-007) so
                                            // both pickers' viewports, selection bands, and
                                            // touch centers share one vertical axis.
                                            Spacer(Modifier.height(FilterWheelLabelRowHeight))
                                            SnapWheel(
                                                pageState.shutterLabels,
                                                pageState.shutterIndex,
                                                onShutterForPage,
                                                visibleCount = 3,
                                                // The filter wheels' own minimum, not a
                                                // second literal that has to agree with it
                                                // (FILTER-STACK-008).
                                                itemHeight = WheelItemHeight,
                                                accessibilityLabel = baseShutterCaption,
                                            )
                                        }
                                        Spacer(Modifier.width(NdColumnGutter))
                                        Box(modifier = Modifier.width(split.ndWidth)) { wheels() }
                                    }
                                }
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

/** Minimum height of the mixed-stack card's caption row (PTIMER-187). */
private val NotationToggleHeight = 30.dp

/**
 * Gutter between the Base Shutter column and the ND column. Without
 * one, a case where the shutter column gets exactly the width its
 * caption needs — a narrow screen at a raised font scale — runs the two
 * captions together: `Base ShutterND Filter`, observed at 360dp.
 */
private val NdColumnGutter = 8.dp

/** Height of the notation toggle's rounded track. */
private val NotationTrackHeight = 26.dp

/** Inset between the notation toggle's track and its segments. */
private val NotationTrackPadding = 2.dp

/** Gap between two notation segments. */
private val NotationSegmentSpacing = 2.dp

/** The notation modes the toggle offers, in display order. */
private val NotationOptionModes = listOf(
    NDNotationMode.STOPS,
    NDNotationMode.OPTICAL_DENSITY,
    NDNotationMode.FILTER_FACTOR,
)

/** Labels for [NotationOptionModes], in the same order. */
@Composable
private fun notationOptionLabels(): List<String> = listOf(
    stringResource(R.string.notation_stops),
    "OD",
    "ND",
)

/** Minimum accessible touch/semantics target size (PTIMER-218). */
private val MinTouchTargetSize = 48.dp

/**
 * Saves/restores [CustomFilmDraft] across configuration change and process
 * recreation (PTIMER-218). Not a Bundle-primitive type (it carries an enum
 * and Pair lists), so the default rememberSaveable Saver can't handle it —
 * every field is flattened into Bundle-safe values instead. A blank
 * [CustomFilmDraft.filmId] map key is used as the "no draft" sentinel so the
 * saved value type can stay non-null.
 */
private val CustomFilmDraftSaver: Saver<CustomFilmDraft?, Any> = mapSaver(
    save = { draft ->
        if (draft == null) {
            mapOf("filmId" to "")
        } else {
            mapOf(
                "filmId" to draft.filmId,
                "isTable" to draft.isTable,
                "label" to draft.label,
                "manufacturer" to draft.manufacturer,
                "iso" to draft.iso,
                "tc0" to draft.tc0,
                "tm0" to draft.tm0,
                "exponent" to draft.exponent,
                "offset" to draft.offset,
                "noCorrection" to draft.noCorrection,
                "sourceThrough" to draft.sourceThrough,
                "anchorsMetered" to ArrayList(draft.anchors.map { it.first }),
                "anchorsCorrected" to ArrayList(draft.anchors.map { it.second }),
                "notes" to draft.notes,
                "sourceType" to draft.sourceType.name,
                "referenceUrl" to draft.referenceUrl,
                "referenceTableFilmId" to (draft.referenceTableFilmId ?: ""),
                "linkedAnchorsMetered" to ArrayList(draft.linkedTableAnchors.map { it.first }),
                "linkedAnchorsCorrected" to ArrayList(draft.linkedTableAnchors.map { it.second }),
            )
        }
    },
    restore = { map ->
        val filmId = map["filmId"] as? String
        if (filmId.isNullOrEmpty()) return@mapSaver null
        @Suppress("UNCHECKED_CAST")
        val anchorsMetered = map["anchorsMetered"] as? ArrayList<String> ?: arrayListOf()
        @Suppress("UNCHECKED_CAST")
        val anchorsCorrected = map["anchorsCorrected"] as? ArrayList<String> ?: arrayListOf()
        @Suppress("UNCHECKED_CAST")
        val linkedMetered = map["linkedAnchorsMetered"] as? ArrayList<Double> ?: arrayListOf()
        @Suppress("UNCHECKED_CAST")
        val linkedCorrected = map["linkedAnchorsCorrected"] as? ArrayList<Double> ?: arrayListOf()
        CustomFilmDraft(
            filmId = filmId,
            isTable = map["isTable"] as? Boolean ?: false,
            label = map["label"] as? String ?: "",
            manufacturer = map["manufacturer"] as? String ?: "",
            iso = map["iso"] as? String ?: "",
            tc0 = map["tc0"] as? String ?: "",
            tm0 = map["tm0"] as? String ?: "",
            exponent = map["exponent"] as? String ?: "",
            offset = map["offset"] as? String ?: "",
            noCorrection = map["noCorrection"] as? String ?: "",
            sourceThrough = map["sourceThrough"] as? String ?: "",
            anchors = anchorsMetered.zip(anchorsCorrected),
            notes = map["notes"] as? String ?: "",
            sourceType = (map["sourceType"] as? String)?.let { CustomProfileSourceType.valueOf(it) }
                ?: CustomProfileSourceType.userDefined,
            referenceUrl = map["referenceUrl"] as? String ?: "",
            referenceTableFilmId = (map["referenceTableFilmId"] as? String)?.ifEmpty { null },
            linkedTableAnchors = linkedMetered.zip(linkedCorrected),
        )
    },
)

/**
 * How the mixed-stack card divides its content row between the Base
 * Shutter column and the ND column.
 */
private data class NdCardColumnSplit(
    val shutterWidth: Dp,
    val ndWidth: Dp,
)

/**
 * The width one filter wheel wants: what
 * `FilterWheelLabelLegibilityTest` holds the narrowest supported column
 * to, so `GND FULL` and its source cue stay whole at every supported
 * text size (FILTER-STACK-007). It is a want, not a floor — the label
 * shrinks to fit below it — but the split spends the row's surplus on
 * reaching it before it spends anything on the base-shutter column.
 */
private val FilterWheelWantedWidth = 48.dp

/**
 * Divides the card row by what each side actually needs at the current
 * width, locale and font scale (SHELL-020, FILTER-A11Y-002).
 *
 * The split used to be a pair of fixed weights — a RATIO of whatever
 * width the device happened to have. The ND header's need is not a
 * ratio: the title scales with the font setting and the two controls
 * are held at 1x, so the header needs a width in dp that a 360dp phone
 * simply does not hand it at any ratio tuned on a 411dp one. Measuring
 * both sides makes the decision exact instead.
 *
 * The notation toggle and the management entry are no longer part of
 * this arithmetic: they sit on their own full-card-width row
 * ([NdNotationControls]), which is what lets every notation option own
 * a 48dp target (SHELL-030) without the ND column having to reserve
 * 150dp of chrome it then cannot give to the wheels. What the ND column
 * now has to hold is its title and the wheels beside it.
 *
 * Precedence, in order:
 *
 *  1. The base-shutter VALUE never clips. Its rows are
 *     `maxLines = 1, softWrap = false` with no overflow, so a column a
 *     pixel too narrow cuts a digit off in silence.
 *  2. The ND column keeps its title whole and every wheel at
 *     [FilterWheelWantedWidth] — FILTER-STACK-007's persistent label,
 *     numeric value, source cue and type rail all live in that width.
 *  3. The base-shutter CAPTION gets its own line's width. It is a
 *     required persistent label, but it is the one thing here that can
 *     yield without being cut: it has no `maxLines`, so a narrower
 *     column wraps it instead of clipping it, which is why it sits
 *     below them in this ordering rather than above.
 *  4. Anything left over is split evenly.
 */
@Composable
private fun ndCardColumnSplit(
    available: Dp,
    ndTitle: String,
    baseShutterCaption: String,
    shutterLabels: List<String>,
    wheelCount: Int,
    plusVisible: Boolean,
): NdCardColumnSplit {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val layoutDirection = LocalLayoutDirection.current
    val labelStyle = MaterialTheme.typography.labelLarge
    // The centered row of a non-dense SnapWheel: what the base-shutter
    // values are drawn with.
    val valueStyle = MaterialTheme.typography.titleMedium

    fun textWidth(text: String, style: TextStyle) = with(density) {
        measurer.measure(
            text,
            style,
            softWrap = false,
            maxLines = 1,
            density = density,
            layoutDirection = layoutDirection,
        ).size.width.toDp()
    }

    val valueNeed = remember(shutterLabels, valueStyle, density, layoutDirection) {
        shutterLabels.maxOfOrNull { textWidth(it, valueStyle) } ?: 0.dp
    }
    val captionNeed = textWidth(baseShutterCaption, labelStyle)
    val titleNeed = textWidth(ndTitle, labelStyle)

    val shutterNeed = maxOf(valueNeed, captionNeed)
    // What the wheel row is laid out from, mirrored from FilterStackGroup
    // so the column the card hands over is the column the wheels divide.
    val wheelsNeed = FilterWheelWantedWidth * wheelCount +
        FilterWheelRowSpacing * (wheelCount - 1) +
        (if (plusVisible) FilterPlusControlWidth + FilterWheelRowSpacing else 0.dp)
    val ndNeed = maxOf(titleNeed, wheelsNeed)

    val shutterWidth = if (shutterNeed + ndNeed <= available) {
        shutterNeed + (available - shutterNeed - ndNeed) / 2
    } else {
        shutterNeed.coerceAtMost((available - ndNeed).coerceAtLeast(valueNeed))
    }.coerceIn(0.dp, available)

    return NdCardColumnSplit(shutterWidth, ndWidth = available - shutterWidth)
}

/**
 * The ND notation toggle and the persistent Filter Set management entry
 * (FILTER-SET-001), on their own row across the whole card.
 *
 * They used to share the ND column's header row with the `ND Filter`
 * title. That column is a fraction of the card, and three notation
 * options plus a gear do not fit a fraction of a 360dp phone: they were
 * drawn 14–30dp wide, against SHELL-030's "minimum 48dp interactive
 * target" for ND notation controls, and there was no width left in the
 * column to take without re-clipping the title or the base-shutter
 * caption. Given the whole card width there is: three 48dp options and
 * the gear need about 200dp, and the narrowest supported card is 312dp.
 *
 * The row is 48dp tall and the track inside it stays 26dp. SHELL-030
 * asks for interactive area "independent of their drawn visual size", so
 * the options are laid out to the row's full height around a track that
 * is not: the targets are real and they are contained, rather than
 * overflowing onto the caption above or the wheels below where they
 * would sit on top of something else.
 */
@Composable
private fun NdNotationControls(
    mode: NDNotationMode,
    enabled: Boolean,
    onSelectNotation: (NDNotationMode) -> Unit,
    onManageFilterSets: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().height(MinTouchTargetSize),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        NotationToggle(
            mode = mode,
            enabled = enabled,
            onSelect = onSelectNotation,
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(NotationSegmentSpacing * 2))
        CappedFontScale(maxFontScale = 1f) {
            Box(
                modifier = Modifier
                    .requiredSize(MinTouchTargetSize)
                    .clip(CircleShape)
                    .clickable(enabled = enabled, onClick = onManageFilterSets),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.Settings,
                    contentDescription = stringResource(R.string.filter_manage_sets),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

/**
 * 3-state ND notation toggle (Stops / OD / ND). Reads as one cohesive
 * segmented control: a single low-emphasis rounded track with the current
 * mode rendered as a filled segment. Current mode is always highlighted;
 * a tap selects a mode.
 *
 * The three options divide the track evenly rather than taking their
 * label widths, so the widest and the narrowest option get the same
 * target: on the row [NdNotationControls] gives it that is about 80dp
 * each at 360dp, comfortably over SHELL-030's 48dp minimum, where the
 * content-sized segments this replaces were 14–30dp wide. Each option is
 * laid out 48dp tall independently of the track it is drawn in — the
 * spec asks for interactive area, not for paint.
 */
@Composable
internal fun NotationToggle(
    mode: NDNotationMode,
    enabled: Boolean,
    onSelect: (NDNotationMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    val options = NotationOptionModes.zip(notationOptionLabels())
    // The labels are chrome beside the values and the captions the same
    // row has to fit, and two of the three are 2-character strings with
    // nothing to ellipsize; hold them at 1x rather than letting the
    // track grow with the system font scale (SHELL-020's cap for
    // non-primary chrome).
    CappedFontScale(maxFontScale = 1f) {
        // The track is DRAWN behind the options, not wrapped around
        // them. It used to be the options' parent, and its
        // `clip(CircleShape)` clipped their bounds — and a clipping
        // layer clips pointer input too, so however tall a segment was
        // laid out, only the track's own 26dp of it could ever be
        // touched. Behind them it cannot take anything away.
        Box(modifier = modifier.height(MinTouchTargetSize), contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(NotationTrackHeight)
                    .clip(CircleShape)
                    // Track is a distinct, outlined surface (lighter than the
                    // card's surfaceVariant) so the control reads as a segmented
                    // control and the option labels never blend into the card.
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
            )
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = NotationTrackPadding),
                horizontalArrangement = Arrangement.spacedBy(NotationSegmentSpacing),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                options.forEach { (optionMode, label) ->
                    val selected = optionMode == mode
                    Box(
                        modifier = Modifier
                            // The interactive node itself: the row's full
                            // 48dp of height, and a third of the track's
                            // width rather than its label's (SHELL-030).
                            .weight(1f)
                            .fillMaxHeight()
                            // selectable (not clickable) so TalkBack announces the
                            // segment as a button with its selected state (PTIMER-182).
                            .selectable(selected = selected, enabled = enabled, role = Role.Button) {
                                onSelect(optionMode)
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(NotationTrackHeight - NotationTrackPadding * 2)
                                .clip(CircleShape)
                                .then(
                                    if (selected) {
                                        Modifier.background(MaterialTheme.colorScheme.secondaryContainer)
                                    } else {
                                        Modifier
                                    }
                                ),
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
                                color = if (selected) {
                                    MaterialTheme.colorScheme.onSecondaryContainer
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                            )
                        }
                    }
                }
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
            stringResource(R.string.pager_position_format, current + 1, count),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
