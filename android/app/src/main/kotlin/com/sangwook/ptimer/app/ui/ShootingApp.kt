// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.SheetValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import kotlinx.coroutines.launch
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.sangwook.ptimer.app.notify.AndroidExactAlarmAvailability
import com.sangwook.ptimer.app.notify.AndroidTimerAlertCoordinator
import com.sangwook.ptimer.app.notify.TimerAlertPlanner
import com.sangwook.ptimer.app.notify.TimerNotifications
import com.sangwook.ptimer.app.persistence.DataStoreCustomFilmLibraryStore
import com.sangwook.ptimer.app.persistence.DataStoreDisplaySettingsStore
import com.sangwook.ptimer.app.persistence.DataStoreSlotSessionStore
import com.sangwook.ptimer.app.persistence.DataStoreTimerWorkspaceStore
import com.sangwook.ptimer.app.timer.AndroidTimerCoordinator
import com.sangwook.ptimer.core.timer.TimerStatus
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import com.sangwook.ptimer.app.ui.details.ReciprocityDetailsScreen
import com.sangwook.ptimer.app.ui.shooting.ShootingScreen
import com.sangwook.ptimer.app.ui.timer.FullTimerList
import com.sangwook.ptimer.app.ui.timer.MiniTimerBar
import com.sangwook.ptimer.app.ui.timer.MiniTimerBarHeight
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingViewModel
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder
import com.sangwook.ptimer.core.customfilm.CustomFilmLibrary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.withContext
import java.time.Instant

/**
 * App host: builds the timer ViewModel + coordinator (DataStore-backed) and the
 * shooting calculator controller (whose Start feeds the timer workspace), and
 * switches between the shooting screen and the full-screen timer list. The
 * coordinator ticks only while a timer is running.
 */
@OptIn(FlowPreview::class, ExperimentalMaterial3Api::class)
@Composable
fun ShootingApp(openTimersSignal: Int = 0, notificationFocusTimerId: String? = null) {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()

    val viewModel = remember {
        ShootingViewModel(store = DataStoreTimerWorkspaceStore(context), clock = { Instant.now() })
    }
    val coordinator = remember { AndroidTimerCoordinator(scope, viewModel, clock = { Instant.now() }) }
    val slotStore = remember { DataStoreSlotSessionStore(context) }
    val library = remember { CustomFilmLibrary(store = DataStoreCustomFilmLibraryStore(context)) }
    val displaySettingsStore = remember { DataStoreDisplaySettingsStore(context) }
    val controller = remember {
        CalculatorController(
            films = LaunchPresetFilmCatalogV2.userSelectableFilms + library.customFilms,
            onStart = { duration, identity -> viewModel.onEvent(ShootingIntent.StartTimer(duration, identity)) },
            initialSession = slotStore.loadSession(),
        )
    }
    val aboutVersion = remember {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        packageInfo.versionName ?: "Unavailable"
    }
    val aboutBuild = remember {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toString()
        }
    }

    LaunchedEffect(Unit) { viewModel.restore() }

    // Persist the slot session off the hot wheel-tick path: debounce the state
    // stream and write the latest exported session. `drop(1)` skips the initial
    // emission so a fresh launch does not immediately rewrite the restored state.
    LaunchedEffect(Unit) {
        controller.state.drop(1).debounce(400).collect {
            withContext(Dispatchers.IO) { slotStore.saveSession(controller.exportSession()) }
        }
    }

    // Notifications: ensure channels, request POST_NOTIFICATIONS (API 33+), and
    // reconcile the AlarmManager alarms + ongoing foreground service with state.
    val exactAlarmAvailability = remember { AndroidExactAlarmAvailability(context) }
    val alertCoordinator = remember { AndroidTimerAlertCoordinator(context, exactAlarmAvailability) }
    // Cached exact-alarm permission state; refreshed on resume (e.g. after the
    // user returns from the Alarms & reminders settings).
    var exactAlarmAllowed by remember { mutableStateOf(exactAlarmAvailability.isAllowed()) }
    val clockFormatter = remember {
        DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZoneId.systemDefault())
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* posting is guarded; nothing to do on the result */ }
    LaunchedEffect(Unit) {
        TimerNotifications.ensureChannels(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    val timerState by viewModel.uiState.collectAsStateWithLifecycle()
    val soundingAlarmId by viewModel.soundingAlarmTimerId.collectAsStateWithLifecycle()
    val calcState by controller.state.collectAsStateWithLifecycle()

    // Persisted ND notation display mode (PTIMER-187): seed from the store, then
    // observe it. Keep the controller (picker labels) in sync with the observed
    // value so a change persists and reflects across the picker and timer cards.
    val initialNotationMode = remember { displaySettingsStore.loadNdNotationMode() }
    val notationModeFlow = remember { displaySettingsStore.ndNotationModeFlow() }
    val ndNotationMode by notationModeFlow.collectAsStateWithLifecycle(initialValue = initialNotationMode)
    LaunchedEffect(ndNotationMode) { controller.setNotationMode(ndNotationMode) }

    // Persisted exact-alarm warning acknowledgment (PTIMER-219): once the user
    // dismisses the banner, it stops reappearing on every active timer. The
    // underlying info stays reachable via a small icon instead.
    val initialExactAlarmWarningDismissed = remember { displaySettingsStore.loadExactAlarmWarningDismissed() }
    val exactAlarmWarningDismissedFlow = remember { displaySettingsStore.exactAlarmWarningDismissedFlow() }
    val exactAlarmWarningDismissed by exactAlarmWarningDismissedFlow
        .collectAsStateWithLifecycle(initialValue = initialExactAlarmWarningDismissed)

    LaunchedEffect(timerState.active.size, viewModel.hasRunningTimers) {
        if (viewModel.hasRunningTimers) coordinator.start() else coordinator.stop()
    }

    // Re-sync alarms + the ongoing notification whenever the running set (ids +
    // end instants) changes — not every tick. Collected straight from the
    // ViewModel flow rather than the lifecycle-aware UI state, so the ongoing
    // notification keeps switching to the next timer (and the count-down keeps
    // tracking it) while the app is backgrounded — where
    // collectAsStateWithLifecycle pauses and would otherwise freeze it on a
    // completed timer with a negative count-down.
    LaunchedEffect(Unit) {
        var lastSignature: String? = null
        viewModel.uiState.collect { state ->
            val signature = state.active
                .filter { it.status == TimerStatus.running }
                .joinToString(",") { "${it.id}@${it.endDate.toEpochMilli()}" }
            if (signature != lastSignature) {
                lastSignature = signature
                val plan = TimerAlertPlanner.plan(state.active) {
                    clockFormatter.format(java.time.Instant.ofEpochMilli(it))
                }
                alertCoordinator.sync(plan)
            }
        }
    }

    // Ring the completion alert the moment a timer finishes while the app is
    // alive (foreground or backgrounded-but-running), not only via the
    // AlarmManager alarm. On the inexact-alarm fallback the running-set sync
    // cancels a just-completed timer's alarm before it fires, so a short
    // backgrounded timer would otherwise complete silently. De-duped with the
    // alarm in TimerNotifications.notifyCompletion. The alarm remains the
    // delivery path when the app is killed.
    LaunchedEffect(Unit) {
        var seenRunning = setOf<java.util.UUID>()
        var notified = setOf<java.util.UUID>()
        viewModel.uiState.collect { state ->
            state.history
                .filter { it.status == TimerStatus.completed && it.id in seenRunning && it.id !in notified }
                .forEach { card ->
                    TimerNotifications.ensureChannels(context)
                    TimerNotifications.notifyCompletion(
                        context,
                        card.id.toString(),
                        card.identity.title,
                        card.identity.subtitle,
                    )
                    notified = notified + card.id
                }
            seenRunning = seenRunning +
                state.active.filter { it.status == TimerStatus.running }.map { it.id }
        }
    }

    // Refresh exact-alarm permission on resume (e.g. returning from settings).
    // If it changed, reschedule the active timers' alarms under the new state so
    // a just-granted permission upgrades them to exact.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        val nowAllowed = exactAlarmAvailability.isAllowed()
        if (nowAllowed != exactAlarmAllowed) {
            exactAlarmAllowed = nowAllowed
            val plan = TimerAlertPlanner.plan(viewModel.uiState.value.active) {
                clockFormatter.format(java.time.Instant.ofEpochMilli(it))
            }
            alertCoordinator.sync(plan)
        }
    }

    var details by remember { mutableStateOf<com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState?>(null) }
    var showAbout by remember { mutableStateOf(false) }
    var showExactAlarmInfo by remember { mutableStateOf(false) }
    val scaffoldState = rememberBottomSheetScaffoldState()
    val hasTimers = timerState.active.isNotEmpty() || timerState.history.isNotEmpty()
    // Exact alarms are gated + denied, so completion-alert reliability is
    // limited (fallback is inexact) — relevant regardless of whether a timer
    // is active right now.
    val exactAlarmWarningRelevant = exactAlarmAvailability.isPermissionGated && !exactAlarmAllowed
    // Nudge with the full banner only while it concretely matters (a timer is
    // running) and the user has not already acknowledged it — the header's
    // status icon (showExactAlarmSettingsAction) reflects the same underlying
    // condition at all times regardless of dismissal, so nothing is lost by
    // suppressing the louder banner once dismissed (PTIMER-219).
    val showExactAlarmWarning = exactAlarmWarningRelevant &&
        timerState.active.isNotEmpty() && !exactAlarmWarningDismissed

    // Peek shows the compact MiniTimerBar; the full list appears only once the
    // sheet is expanded. No drag handle is rendered (PTIMER-219: the sheet
    // only opens by tapping a mini card, never by dragging), so the peek is
    // just the bar's own height with nothing extra reserved above it.
    val expanded = scaffoldState.bottomSheetState.currentValue == SheetValue.Expanded
    // The mini card a user tapped to open the full list, so it can be focused.
    var focusTimerId by remember { mutableStateOf<java.util.UUID?>(null) }

    // Opened from a timer notification: expand straight to the full list once
    // timers are available (restore may land just after the tap). One-shot so a
    // later timer change does not re-expand on its own.
    var pendingOpenTimers by remember { mutableStateOf(false) }
    LaunchedEffect(openTimersSignal) {
        if (openTimersSignal > 0) {
            pendingOpenTimers = true
            // Focus the timer the tapped completion notification was for (it is a
            // finished timer, so the list scrolls to it in History).
            notificationFocusTimerId
                ?.let { runCatching { java.util.UUID.fromString(it) }.getOrNull() }
                ?.let { focusTimerId = it }
        }
    }
    LaunchedEffect(pendingOpenTimers, hasTimers) {
        if (pendingOpenTimers && hasTimers) {
            scaffoldState.bottomSheetState.expand()
            pendingOpenTimers = false
        }
    }

    // Keep the sheet at its partial (mini) anchor whenever the timer set appears
    // or empties. On the first timer this shows only the compact peek instead of
    // settling to the full list (the peek height grows from 0). On clearing the
    // last timer it collapses the sheet to the now-zero peek instead of leaving
    // an empty expanded list open. Tapping a mini card is the only expand path.
    // Skipped while a notification open is pending, so the two don't fight.
    LaunchedEffect(hasTimers) {
        if (!pendingOpenTimers) scaffoldState.bottomSheetState.partialExpand()
    }

    // Focus follows a newly started active timer so Clone (and a calculator
    // start) scrolls the fresh timer into view in the expanded list, instead of
    // the list snapping back to the previously focused card and hiding the new
    // one above it. Only genuinely new ids move the focus, so tapping an
    // existing mini card to inspect it is preserved. Keyed on the id list (not
    // the per-second state) so it does not re-run on every tick.
    var knownActiveIds by remember { mutableStateOf<Set<java.util.UUID>>(emptySet()) }
    // Skip the first scan so launch (e.g. opened from a completion notification)
    // does not steal focus to the newest active timer, overriding the notified one.
    var firstActiveScan by remember { mutableStateOf(true) }
    val activeIds = timerState.active.map { it.id }
    LaunchedEffect(activeIds) {
        val current = activeIds.toSet()
        if (firstActiveScan) {
            knownActiveIds = current
            firstActiveScan = false
            return@LaunchedEffect
        }
        val added = current - knownActiveIds
        // active is ordered oldest-first, so the last added id is the newest.
        if (added.isNotEmpty()) {
            timerState.active.lastOrNull { it.id in added }?.let { focusTimerId = it.id }
        }
        knownActiveIds = current
    }

    // System Back / swipe-back returns to the main shooting screen instead of
    // exiting the app: dismiss the full-screen Reciprocity Details overlay
    // first, then collapse an expanded timer sheet. (The film picker, target
    // shutter, and custom-film editor/rename are modal sheets / dialogs that
    // already dismiss on Back via their own handling.)
    BackHandler(enabled = details != null) { details = null }
    BackHandler(enabled = details == null && expanded) {
        scope.launch { scaffoldState.bottomSheetState.partialExpand() }
    }

    // Timers live in a peeking bottom sheet so starting one adds it without
    // leaving the shooting surface (the sheet appears once any timer exists).
    Box(Modifier.fillMaxSize()) {
    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight = if (hasTimers) MiniTimerBarHeight else 0.dp,
        sheetDragHandle = null,
        sheetContent = {
            if (expanded) {
                FullTimerList(
                    state = timerState,
                    onEvent = viewModel::onEvent,
                    onCollapse = { scope.launch { scaffoldState.bottomSheetState.partialExpand() } },
                    focusId = focusTimerId,
                    ndNotationMode = ndNotationMode,
                    modifier = Modifier.fillMaxWidth(),
                    soundingAlarmId = soundingAlarmId,
                    onStopAlarm = { viewModel.stopAlarm() },
                )
            } else {
                MiniTimerBar(
                    state = timerState,
                    onOpen = { id ->
                        focusTimerId = id
                        scope.launch { scaffoldState.bottomSheetState.expand() }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    soundingAlarmId = soundingAlarmId,
                    onStopAlarm = { viewModel.stopAlarm() },
                )
            }
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize()) {
        // Apply + consume the status-bar inset here so the warning banner sits
        // below the status bar; consuming it stops ShootingScreen's own Scaffold
        // from insetting the top a second time.
        Column(
            Modifier
                .padding(innerPadding)
                .windowInsetsPadding(WindowInsets.statusBars),
        ) {
            ShootingScreen(
                    modifier = Modifier.weight(1f),
                    state = calcState,
                    onShutterIndex = controller::setShutterIndex,
                    onNdIndex = controller::setNdIndex,
                    onSelectNotation = { mode ->
                        controller.setNotationMode(mode)
                        scope.launch { displaySettingsStore.setNdNotationMode(mode) }
                    },
                    onSelectFilm = controller::selectFilm,
                    onSelectProfile = controller::selectProfile,
                    onSelectSlot = controller::selectSlot,
                    onRenameSlot = controller::renameActiveSlot,
                    onSetTarget = controller::setTargetShutter,
                    onStartTarget = controller::startFromTarget,
                    onStartAdjusted = controller::startFromAdjusted,
                    onStartCorrected = controller::startFromCorrected,
                    onOpenDetails = { details = controller.detailsState() },
                    onResetSettings = controller::resetActiveSlotSettings,
                    onResetSettingsAndName = controller::resetActiveSlotSettingsAndName,
                    onCreateCustomFilm = { input, editId ->
                        // editId set → update that film in place (reuse its ids); else new.
                        val film = CustomFilmBuilder.buildFormulaFilm(
                            input = input,
                            filmId = editId ?: "custom-film-${java.util.UUID.randomUUID()}",
                            profileId = editId?.let { controller.customFilmProfileId(it) }
                                ?: "custom-profile-${java.util.UUID.randomUUID()}",
                        )
                        if (film == null) {
                            false
                        } else {
                            library.add(film)
                            controller.setFilms(LaunchPresetFilmCatalogV2.userSelectableFilms + library.customFilms)
                            controller.selectFilm(film.id)
                            true
                        }
                    },
                    onCreateCustomTableFilm = { input, editId ->
                        val film = CustomFilmBuilder.buildTableFilm(
                            input = input,
                            filmId = editId ?: "custom-film-${java.util.UUID.randomUUID()}",
                            profileId = editId?.let { controller.customFilmProfileId(it) }
                                ?: "custom-profile-${java.util.UUID.randomUUID()}",
                        )
                        if (film == null) {
                            false
                        } else {
                            library.add(film)
                            controller.setFilms(LaunchPresetFilmCatalogV2.userSelectableFilms + library.customFilms)
                            controller.selectFilm(film.id)
                            true
                        }
                    },
                    onEditCustomFilm = { id -> controller.customFilmDraft(id) },
                    onDeleteCustomFilm = { id ->
                        library.remove(id)
                        controller.setFilms(LaunchPresetFilmCatalogV2.userSelectableFilms + library.customFilms)
                        if (calcState.selectedFilmId == id) controller.selectFilm(null)
                    },
                    onPreviewCustomFilm = { input -> controller.previewFormulaGraph(input) },
                    onPreviewCustomTableFilm = { input -> controller.previewTableGraph(input) },
                    onFormulaCheckpoints = { input -> controller.previewFormulaCheckpoints(input) },
                    onTableCheckpoints = { input -> controller.previewTableCheckpoints(input) },
                    onCalculationBasis = { input -> controller.calculationBasis(input) },
                    onPreviewTableFit = { input -> controller.previewTableFit(input) },
                    onCreateFormulaFromTable = { input, editId ->
                        // Save the table (in place when editing), then create and
                        // select a separate formula film fitted from it, linked back
                        // to the table for live reference points (PTIMER-180).
                        val tableFilmId = editId ?: "custom-film-${java.util.UUID.randomUUID()}"
                        val table = CustomFilmBuilder.buildTableFilm(
                            input = input,
                            filmId = tableFilmId,
                            profileId = editId?.let { controller.customFilmProfileId(it) }
                                ?: "custom-profile-${java.util.UUID.randomUUID()}",
                        )
                        val formula = controller.buildFormulaFilmFromTableInput(
                            input = input,
                            filmId = "custom-film-${java.util.UUID.randomUUID()}",
                            profileId = "custom-profile-${java.util.UUID.randomUUID()}",
                            referenceTableFilmId = tableFilmId,
                        )
                        if (table == null || formula == null) {
                            false
                        } else {
                            library.add(table)
                            library.add(formula)
                            controller.setFilms(LaunchPresetFilmCatalogV2.userSelectableFilms + library.customFilms)
                            controller.selectFilm(formula.id)
                            true
                        }
                    },
                    onReferencePoints = { input, anchors -> controller.referencePoints(input, anchors) },
                    onOpenAbout = { showAbout = true },
                    showExactAlarmSettingsAction = exactAlarmWarningRelevant,
                    onOpenExactAlarmSettings = { showExactAlarmInfo = true },
                )
        }
            // Overlay, not part of the Column above: the calculator's
            // non-scrolling layout must not reflow while the banner is up
            // (PTIMER-219). It floats over the header until dismissed instead
            // of sharing the Column's weight-based space with ShootingScreen.
            if (showExactAlarmWarning) {
                Box(
                    Modifier
                        .padding(innerPadding)
                        .windowInsetsPadding(WindowInsets.statusBars),
                ) {
                    ExactAlarmWarningBanner(
                        onOpenSettings = exactAlarmAvailability::openSettings,
                        onDismiss = {
                            scope.launch { displaySettingsStore.setExactAlarmWarningDismissed(true) }
                        },
                    )
                }
            }
            // Modal scrim while the timer list is expanded: dims and blocks the
            // shooting surface (so Reset and the wheels aren't reachable behind
            // the list) and collapses the sheet on a tap outside it. The standard
            // BottomSheetScaffold provides no scrim of its own.
            if (expanded) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.45f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { scope.launch { scaffoldState.bottomSheetState.partialExpand() } },
                )
            }
        }
    }

        // Reciprocity details is a focused full-screen overlay above the timer
        // bottom sheet, so the timer peek isn't reachable from within it.
        details?.let { activeDetails ->
            Surface(modifier = Modifier.fillMaxSize()) {
                ReciprocityDetailsScreen(
                    state = activeDetails,
                    onBack = { details = null },
                    onSelectModel = { id ->
                        controller.selectProfile(id)
                        details = controller.detailsState()
                    },
                )
            }
        }

        if (showAbout) {
            PTimerAboutDialog(
                versionName = aboutVersion,
                buildCode = aboutBuild,
                onDismiss = { showAbout = false },
            )
        }

        if (showExactAlarmInfo) {
            ExactAlarmInfoDialog(
                onOpenSettings = {
                    exactAlarmAvailability.openSettings()
                    showExactAlarmInfo = false
                },
                onDismiss = { showExactAlarmInfo = false },
            )
        }
    }
}

/**
 * Non-intrusive banner shown when exact alarms are denied while a timer is
 * active: completion alerts fall back to inexact (less reliable), with a path
 * to the system Alarms & reminders settings. Dismiss acknowledges the
 * limitation so it stops reappearing on every timer (PTIMER-219); the
 * explanation stays reachable afterward via a header icon next to About
 * (see `showExactAlarmSettingsAction` on `ShootingScreen`), which reopens
 * [ExactAlarmInfoDialog] rather than jumping straight to system settings.
 */
@Composable
private fun ExactAlarmWarningBanner(onOpenSettings: () -> Unit, onDismiss: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.alarm_warning_title), style = MaterialTheme.typography.bodyMedium)
                Text(
                    stringResource(R.string.alarm_warning_body),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            TextButton(onClick = onOpenSettings) { Text(stringResource(R.string.alarm_warning_open_settings)) }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.alarm_warning_dismiss)) }
        }
    }
}

/**
 * Reopens the banner's explanation on demand from the header's settings icon
 * (PTIMER-219): a deliberate second step before leaving the app, rather than
 * jumping straight to system settings with no context or way back.
 */
@Composable
private fun ExactAlarmInfoDialog(onOpenSettings: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.alarm_warning_title)) },
        text = { Text(stringResource(R.string.alarm_warning_body)) },
        confirmButton = {
            TextButton(onClick = onOpenSettings) { Text(stringResource(R.string.alarm_warning_open_settings)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.alarm_warning_dismiss)) }
        },
    )
}
