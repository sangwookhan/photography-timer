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
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.SheetValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.shooting.ShootingFiltersActions
import com.sangwook.ptimer.app.ui.shooting.ShootingFiltersScreen
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.sangwook.ptimer.app.notify.AndroidExactAlarmAvailability
import com.sangwook.ptimer.app.notify.AndroidTimerAlarmPlayer
import com.sangwook.ptimer.app.notify.AndroidTimerAlarmScheduling
import com.sangwook.ptimer.app.notify.AndroidTimerAlertCoordinator
import com.sangwook.ptimer.app.notify.AndroidTimerForegroundServiceControlling
import com.sangwook.ptimer.app.notify.TimerAlertPlanner
import com.sangwook.ptimer.app.notify.TimerNotifications
import com.sangwook.ptimer.app.persistence.DataStoreTimerWorkspaceStore
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.timer.TimerStatus
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import com.sangwook.ptimer.app.ui.details.ReciprocityDetailsScreen
import com.sangwook.ptimer.app.ui.shooting.FilterManagementScreen
import com.sangwook.ptimer.app.ui.shooting.FilterSetManagementActions
import com.sangwook.ptimer.app.ui.shooting.filterReferenceVocabulary
import com.sangwook.ptimer.app.ui.shooting.CameraManagementActions
import com.sangwook.ptimer.app.ui.shooting.FilterSetManagementScreen
import com.sangwook.ptimer.app.ui.shooting.ShootingScreen
import com.sangwook.ptimer.app.ui.shooting.FilmClassificationBadgeVisibility
import com.sangwook.ptimer.app.ui.shooting.besideFold
import com.sangwook.ptimer.app.ui.shooting.CompactTimerRailWidth
import com.sangwook.ptimer.app.ui.shooting.FoldSide
import com.sangwook.ptimer.app.ui.shooting.PageSpace
import com.sangwook.ptimer.app.ui.shooting.prefersSideRail
import com.sangwook.ptimer.app.ui.shooting.prefersTabletopRail
import com.sangwook.ptimer.app.ui.shooting.ShootingPageRoom
import com.sangwook.ptimer.app.ui.shooting.rememberWindowFold
import com.sangwook.ptimer.app.ui.timer.FullTimerList
import com.sangwook.ptimer.app.ui.timer.MiniTimerBar
import com.sangwook.ptimer.app.ui.timer.MiniTimerBarHeight
import com.sangwook.ptimer.app.ui.timer.MiniTimerRail
import com.sangwook.ptimer.app.vm.FilterInventorySamples
import com.sangwook.ptimer.app.vm.ShootingAppViewModel
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder

/**
 * App host: renders the screen state owned by the Activity-scoped
 * [ShootingAppViewModel] (PTIMER-223) — the timer workspace, the shooting
 * calculator (whose Start feeds the timer workspace), and the custom film
 * library — and switches between the shooting screen and the full-screen timer
 * list. The tick loop, timer restore, and calculator persistence live in the
 * ViewModel, not the composition, so they survive Activity recreation.
 *
 * [bootstrap] carries the catalog parse and every initial store read, already
 * performed off the main thread before this composes (PTIMER-217) — no
 * `remember` block here performs a blocking read. On a configuration-change
 * recreation the fresh bootstrap only gates the splash; the retained ViewModel
 * keeps the state holders built from the first one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShootingApp(
    bootstrap: ShootingAppBootstrap,
    openTimersSignal: Int = 0,
    notificationFocusTimerId: String? = null,
) {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()

    // Created once per Activity ViewModelStore: the first composition after a
    // cold launch builds it from the bootstrap; a recreation reuses the
    // retained instance (committed in-memory state included) and ignores this
    // initializer.
    val holder: ShootingAppViewModel = viewModel {
        ShootingAppViewModel(
            films = bootstrap.presetFilms + bootstrap.library.customFilms,
            library = bootstrap.library,
            initialCameraList = bootstrap.initialCameraList,
            timerStore = DataStoreTimerWorkspaceStore.create(context),
            alarmPlayer = AndroidTimerAlarmPlayer.instance(context),
            cameraListPersistence = bootstrap.cameraListPersistence,
            needsInitialCameraListSave = bootstrap.needsInitialCameraListSave,
            defaultCameraName = bootstrap.defaultCameraName,
            inventoryStore = bootstrap.inventoryStore,
            initialInventory = bootstrap.initialInventory,
            // The bootstrap always reads the store: `null` is a fresh install.
            initialInventoryIsStoreRead = true,
            firstLaunchInventory = FilterInventorySamples.inventory(),
            // Read per start, so the reference string a timer captures is
            // written in the language in use at that moment.
            referenceVocabulary = { filterReferenceVocabulary(context.resources) },
            // In-app completion alert, de-duped with the AlarmManager path in
            // TimerNotifications.notifyCompletion. The alarm remains the
            // delivery path when the app process is killed.
            completionNotifier = { card ->
                TimerNotifications.ensureChannels(context)
                TimerNotifications.notifyCompletion(
                    context,
                    card.id.toString(),
                    card.identity.title,
                    card.identity.subtitle,
                )
            },
        )
    }
    val viewModel = holder.timers
    val controller = holder.calculator
    val library = holder.library
    val displaySettingsStore = bootstrap.displaySettingsStore

    // FILTER-A11Y-006: while the platform's touch-exploration mode is
    // active the Filter Stack freezes its wheel order; turning the mode
    // off queues exactly one reconciliation. Detected as a platform
    // capability, so every compatible screen reader behaves alike.
    val touchExplorationEnabled = rememberTouchExplorationEnabled()
    LaunchedEffect(touchExplorationEnabled) {
        controller.setFilterStackOrderingSuspended(touchExplorationEnabled)
    }
    // FILTER-STACK-006: an automatic cleanup that actually removed
    // wheels is announced once, while the same mode is active.
    val view = LocalView.current
    val resources = LocalResources.current
    val announceRemovals by rememberUpdatedState(touchExplorationEnabled)
    LaunchedEffect(controller) {
        controller.emptyWheelRemovals.collect { removed ->
            if (!announceRemovals) return@collect
            view.announceForAccessibility(
                if (removed <= 1) {
                    resources.getString(R.string.filter_empty_wheel_removed)
                } else {
                    resources.getString(R.string.filter_empty_wheels_removed, removed)
                },
            )
        }
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

    // Notifications: ensure channels, request POST_NOTIFICATIONS (API 33+), and
    // reconcile the AlarmManager alarms + ongoing foreground service with state.
    val exactAlarmAvailability = remember { AndroidExactAlarmAvailability(context) }
    val alertCoordinator = remember {
        AndroidTimerAlertCoordinator(
            availability = exactAlarmAvailability,
            scheduler = AndroidTimerAlarmScheduling(context),
            foregroundService = AndroidTimerForegroundServiceControlling(context),
        )
    }
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

    // Camera management and the pager's utility page (CAMERA-PAGER-002/007).
    val cameraActions = remember(holder) {
        CameraManagementActions(
            isEditable = holder.cameras.isEditable,
            // Reserving the next `Camera N` is durable I/O: it runs on the
            // owner's scope, so a recreation does not cancel it half-way.
            add = { holder.viewModelScope.async { holder.cameras.addCamera() }.await() },
            rename = holder.cameras::renameCamera,
            setDisplayed = holder.cameras::setCameraDisplayed,
            move = holder.cameras::moveCamera,
            hide = holder.cameras::hideCameras,
            delete = holder.cameras::deleteCameras,
            activeCamera = {
                controller.state.value.slots.firstOrNull { it.isActive }
                    ?.let { controller.cameraIdentity(it.id) }
            },
        )
    }

    // Persisted ND notation display mode (PTIMER-187): seed from the bootstrap
    // read, then observe the store. Keep the controller (picker labels) in sync
    // with the observed value so a change persists and reflects across the
    // picker and timer cards.
    val initialNotationMode = bootstrap.initialNdNotationMode
    val notationModeFlow = remember { displaySettingsStore.ndNotationModeFlow() }
    val ndNotationMode by notationModeFlow.collectAsStateWithLifecycle(initialValue = initialNotationMode)
    LaunchedEffect(ndNotationMode) { controller.setNotationMode(ndNotationMode) }

    val requiredNDPreference = remember { displaySettingsStore.showRequiredNDFlow() }
    val showRequiredND by requiredNDPreference.collectAsStateWithLifecycle(initialValue = bootstrap.initialShowRequiredND)
    LaunchedEffect(showRequiredND) { controller.setShowRequiredND(showRequiredND) }

    // Persisted exact-alarm warning acknowledgment (PTIMER-219): once the user
    // dismisses the banner, it stops reappearing on every active timer. The
    // underlying info stays reachable via a small icon instead.
    val exactAlarmWarningDismissedFlow = remember { displaySettingsStore.exactAlarmWarningDismissedFlow() }
    val exactAlarmWarningDismissed by exactAlarmWarningDismissedFlow
        .collectAsStateWithLifecycle(initialValue = bootstrap.initialExactAlarmWarningDismissed)

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

    // The open destinations are saved so a recreation reopens them
    // (SHELL-021/053). Details keeps only whether it is open; its content
    // is derived again from the restored shooting state.
    var detailsOpen by rememberSaveable { mutableStateOf(false) }
    var details by remember {
        mutableStateOf(if (detailsOpen) controller.detailsState() else null)
    }
    LaunchedEffect(details != null) { detailsOpen = details != null }
    var showAbout by rememberSaveable { mutableStateOf(false) }
    // Filter management from the Settings menu: the shared inventory,
    // with no camera selection.
    var showFilterManagement by rememberSaveable { mutableStateOf(false) }
    // Shooting Filters (FILTER-FLOW-002), opened from the Select Filters
    // button, the Plus Shooting filters action, and the mounted summary.
    var showShootingFilters by rememberSaveable { mutableStateOf(false) }
    // The Filter Set whose editor is open above Shooting Filters; it reads
    // the inventory live so an edit inside it redraws the list.
    var editedFilterSetId by rememberSaveable(stateSaver = FilterSetIdSaver) { mutableStateOf<FilterSetId?>(null) }
    val filterInventory by holder.filterInventory.collectAsStateWithLifecycle()
    var showExactAlarmInfo by rememberSaveable { mutableStateOf(false) }
    var mainReturnBadgeToken by remember { mutableStateOf(0) }
    var wasMainSurfaceCovered by remember { mutableStateOf(false) }
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

    // The sheet holds the full list only. No drag handle is rendered
    // (PTIMER-219: it only opens by tapping a compact card, never by
    // dragging).
    val expanded = scaffoldState.bottomSheetState.currentValue == SheetValue.Expanded
    val isMainSurfaceCovered = details != null || showAbout || showFilterManagement
        || showShootingFilters || editedFilterSetId != null || showExactAlarmInfo || expanded
    LaunchedEffect(isMainSurfaceCovered) {
        if (isMainSurfaceCovered) controller.invalidateRequiredND()
        if (FilmClassificationBadgeVisibility.isMainReturn(wasMainSurfaceCovered, isMainSurfaceCovered)) {
            mainReturnBadgeToken++
        }
        wasMainSurfaceCovered = isMainSurfaceCovered
    }
    // The Timers destination counts as open from the moment the sheet starts
    // opening until it has fully closed; the side rail hides meanwhile.
    val timersOpen = expanded ||
        scaffoldState.bottomSheetState.targetValue == SheetValue.Expanded
    // Bottom strip or trailing side rail for the compact summary, decided
    // from the active page's room and content (WORKSPACE-032). Without timers
    // there is no summary, so nothing is reserved.
    // A half-open or separating fold places the page around it (SHELL-061).
    // Beside a tabletop fold the rail is kept above the fold, so the strip
    // does not take the room the inputs need below it.
    val fold = rememberWindowFold()
    val tabletop = fold?.isVertical == false
    var sideRail by remember { mutableStateOf(false) }
    if (sideRail && !hasTimers) sideRail = false
    val bottomStrip = hasTimers && !sideRail
    // The page's room as measured with each placement, kept per window size
    // so a placement that was tried and does not fit is not tried again.
    val windowSize = LocalWindowInfo.current.containerSize
    val measuredRooms = remember(windowSize) { arrayOfNulls<PageSpace>(2) }
    // The last room the active page reported, to decide again when the
    // fold changes without the room changing.
    val lastRoom = remember { arrayOfNulls<ShootingPageRoom>(1) }
    val density = LocalDensity.current
    fun prefersRail(room: ShootingPageRoom): Boolean {
        if (!hasTimers) return false
        val f = fold
        if (f == null || f.isVertical) {
            return prefersSideRail(measuredRooms[0], measuredRooms[1], room.needed, MiniTimerBarHeight)
        }
        val bottom = measuredRooms[0] ?: PageSpace(room.width, room.height)
        val rail = measuredRooms[1]
            ?: PageSpace(bottom.width - CompactTimerRailWidth, bottom.height + MiniTimerBarHeight)
        return with(density) {
            prefersTabletopRail(
                foldTop = f.bounds.top.toDp(),
                foldBottom = f.bounds.bottom.toDp(),
                pageTop = room.top,
                railPageHeight = rail.height,
                railPageWidth = rail.width,
                aboveFold = room.aboveTabletopFold,
                belowFold = room.belowTabletopFold,
            )
        }
    }
    LaunchedEffect(fold, hasTimers) {
        lastRoom[0]?.let { sideRail = prefersRail(it) }
    }
    // The mini card a user tapped to open the full list, so it can be focused.
    var focusTimerId by rememberSaveable { mutableStateOf<java.util.UUID?>(null) }
    // A compact card (bottom strip or side rail) opens the full Timers list
    // focused on that timer, or unfocused for the overflow entry.
    val openTimers: (java.util.UUID?) -> Unit = { id ->
        focusTimerId = id
        scope.launch { scaffoldState.bottomSheetState.expand() }
    }

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

    // Keep the sheet closed whenever the timer set appears or empties. On the
    // first timer only the compact summary shows; on clearing the last timer
    // the sheet closes instead of leaving an empty list open. Tapping a
    // compact card is the only expand path.
    // Skipped while a notification open is pending, so the two don't fight.
    // Only a real change counts: the presence last acted on is saved, so a
    // recreation, which runs this effect again, leaves a restored open list
    // open (SHELL-021).
    var settledHasTimers by rememberSaveable { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(hasTimers) {
        if (settledHasTimers != hasTimers && !pendingOpenTimers) {
            scaffoldState.bottomSheetState.partialExpand()
        }
        settledHasTimers = hasTimers
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
        // active is ordered newest-first (PTIMER-194), so the first added id is
        // the newest.
        if (added.isNotEmpty()) {
            timerState.active.firstOrNull { it.id in added }?.let { focusTimerId = it.id }
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

    // The window draws behind the system bars (PTIMER-231): the compact
    // cards stay above the navigation bar, the expanded list starts below the
    // status or caption bar, and side bars or cutouts pad the content
    // horizontally.
    // systemBars covers the status, navigation and caption (window-control)
    // bars, so a free-form window's title bar is reserved too.
    val barsAndCutout = WindowInsets.systemBars.union(WindowInsets.displayCutout)
    val topInsets = barsAndCutout.only(WindowInsetsSides.Top)
    val bottomInsets = barsAndCutout.only(WindowInsetsSides.Bottom)
    val bottomInset = bottomInsets.asPaddingValues().calculateBottomPadding()
    val sideInsets = barsAndCutout.only(WindowInsetsSides.Horizontal)

    // Starting a timer adds it to the compact summary without leaving the
    // shooting surface; the full Timers list lives in a bottom sheet.
    Box(Modifier.fillMaxSize()) {
    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        // The sheet is only the full-screen Timers destination: it has no
        // peek and always holds the full list, so opening it slides the list
        // straight up (WORKSPACE-003/035). The compact summary is drawn below
        // as a bottom strip or a side rail.
        sheetPeekHeight = 0.dp,
        sheetDragHandle = null,
        // The destination covers the whole window, however few timers it
        // lists and however wide the window is (WORKSPACE-001); the list
        // itself stays bounded and centered.
        sheetMaxWidth = Dp.Unspecified,
        sheetContent = {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                CappedFontScale(MaxTimersFontScale) {
                    FullTimerList(
                        state = timerState,
                        onEvent = viewModel::onEvent,
                        onCollapse = { scope.launch { scaffoldState.bottomSheetState.partialExpand() } },
                        focusId = focusTimerId,
                        ndNotationMode = ndNotationMode,
                        modifier = Modifier
                            .besideFold(fold, FoldSide.Larger, fillsHeight = true)
                            .windowInsetsPadding(sideInsets)
                            .windowInsetsPadding(topInsets)
                            .widthIn(max = BottomSheetDefaults.SheetMaxWidth)
                            .fillMaxHeight(),
                        contentPadding = PaddingValues(bottom = bottomInset),
                        soundingAlarmId = soundingAlarmId,
                        onStopAlarm = { viewModel.stopAlarm() },
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize()) {
        // Apply + consume the top and side insets here so the warning banner sits
        // below the status or caption bar; consuming them stops ShootingScreen's
        // own Scaffold from insetting them a second time.
        Column(
            Modifier
                .padding(innerPadding)
                .padding(bottom = if (bottomStrip) MiniTimerBarHeight + bottomInset else 0.dp)
                .windowInsetsPadding(topInsets)
                .windowInsetsPadding(sideInsets),
        ) {
            ShootingScreen(
                    modifier = Modifier
                        .weight(1f)
                        .padding(end = if (sideRail) CompactTimerRailWidth else 0.dp),
                    fold = fold,
                    onPageRoom = { room ->
                        measuredRooms[if (sideRail) 1 else 0] = PageSpace(room.width, room.height)
                        lastRoom[0] = room
                        sideRail = prefersRail(room)
                    },
                    state = calcState,
                    onShutterIndex = controller::setShutterIndex,
                    onBaseInteractionBegin = controller::beginBaseInteraction,
                    onBaseSettled = controller::finishBaseInteraction,
                    onRequiredNDComplete = controller::completeRequiredNDCrossfade,
                    onInvalidateRequiredND = controller::invalidateRequiredND,
                    onShowRequiredND = { enabled ->
                        controller.setShowRequiredND(enabled)
                        scope.launch { displaySettingsStore.setShowRequiredND(enabled) }
                    },
                    onNdWheelActive = controller::setNdWheelActive,
                    onNdWheelValue = controller::setNdWheelValue,
                    onAddFilterWheel = controller::addFilterWheel,
                    onAdjustFilterWheel = controller::adjustFilterWheel,
                    onRemoveNdWheelOverscroll = controller::removeNdWheelFromOverscroll,
                    onOpenShootingFilters = { controller.invalidateRequiredND(); showShootingFilters = true },
                    onSelectNotation = { mode ->
                        controller.setNotationMode(mode)
                        scope.launch { displaySettingsStore.setNdNotationMode(mode) }
                    },
                    onSelectFilm = controller::selectFilm,
                    onSelectProfile = controller::selectProfile,
                    onSelectSlot = controller::selectSlot,
                    onRenameSlot = { name ->
                        controller.state.value.slots.firstOrNull { it.isActive }
                            ?.let { holder.cameras.renameCamera(it.id, name) }
                    },
                    onSetTarget = controller::setTargetShutter,
                    onStartTarget = controller::startFromTarget,
                    onStartAdjusted = controller::startFromAdjusted,
                    onStartCorrected = controller::startFromCorrected,
                    onOpenDetails = { details = controller.detailsState() },
                    mainReturnBadgeToken = mainReturnBadgeToken,
                    onResetSettings = controller::resetActiveSlotSettings,
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
                        // Persist the source table before opening the seeded formula
                        // draft. Only the editor's explicit Save creates the formula.
                        val tableFilmId = editId ?: "custom-film-${java.util.UUID.randomUUID()}"
                        val table = CustomFilmBuilder.buildTableFilm(
                            input = input,
                            filmId = tableFilmId,
                            profileId = editId?.let { controller.customFilmProfileId(it) }
                                ?: "custom-profile-${java.util.UUID.randomUUID()}",
                        )
                        if (table == null) {
                            false
                        } else {
                            library.add(table)
                            controller.setFilms(LaunchPresetFilmCatalogV2.userSelectableFilms + library.customFilms)
                            true
                        }
                    },
                    onReferencePoints = { input, anchors -> controller.referencePoints(input, anchors) },
                    onOpenAbout = { showAbout = true },
                    onOpenFilterManagement = { showFilterManagement = true },
                    showExactAlarmSettingsAction = exactAlarmWarningRelevant,
                    onOpenExactAlarmSettings = { showExactAlarmInfo = true },
                    reserveNavigationBarInset = !bottomStrip,
                    cameraActions = cameraActions,
                )
        }
            if (bottomStrip) {
                // Drawn like the former sheet peek: same surface, shape and
                // width limit, so phones look as before.
                Surface(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .besideFold(fold, FoldSide.Larger)
                        .widthIn(max = BottomSheetDefaults.SheetMaxWidth)
                        .fillMaxWidth(),
                    shape = BottomSheetDefaults.ExpandedShape,
                    color = BottomSheetDefaults.ContainerColor,
                    shadowElevation = BottomSheetDefaults.Elevation,
                ) {
                    CappedFontScale(MaxMiniTimerFontScale) {
                        MiniTimerBar(
                            state = timerState,
                            onOpen = openTimers,
                            readablePhoneText = fold == null &&
                                with(density) { windowSize.width.toDp() in 360.dp..<600.dp &&
                                    windowSize.height.toDp() >= 800.dp },
                            modifier = Modifier
                                .fillMaxWidth()
                                .windowInsetsPadding(sideInsets)
                                .windowInsetsPadding(bottomInsets),
                            soundingAlarmId = soundingAlarmId,
                            onStopAlarm = { viewModel.stopAlarm() },
                        )
                    }
                }
            }
            if (sideRail && !timersOpen) {
                CappedFontScale(MaxMiniTimerFontScale) {
                    MiniTimerRail(
                        state = timerState,
                        onOpen = openTimers,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(innerPadding)
                            .windowInsetsPadding(topInsets)
                            .windowInsetsPadding(sideInsets)
                            .windowInsetsPadding(bottomInsets)
                            // Above a tabletop fold only, so it never runs across it.
                            .besideFold(if (tabletop) fold else null, FoldSide.Leading, fillsHeight = true)
                            .fillMaxHeight()
                            .width(CompactTimerRailWidth)
                            .padding(vertical = 8.dp),
                        soundingAlarmId = soundingAlarmId,
                        onStopAlarm = { viewModel.stopAlarm() },
                    )
                }
            }
            // Overlay, not part of the Column above: the calculator's
            // non-scrolling layout must not reflow while the banner is up
            // (PTIMER-219). It floats over the header until dismissed instead
            // of sharing the Column's weight-based space with ShootingScreen.
            if (showExactAlarmWarning) {
                Box(
                    Modifier
                        .padding(innerPadding)
                        .windowInsetsPadding(topInsets)
                        .windowInsetsPadding(sideInsets),
                ) {
                    CappedFontScale {
                        ExactAlarmWarningBanner(
                            onOpenSettings = exactAlarmAvailability::openSettings,
                            onDismiss = {
                                scope.launch { displaySettingsStore.setExactAlarmWarningDismissed(true) }
                            },
                        )
                    }
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
        // bottom sheet, so the compact timers aren't reachable from within it.
        details?.let { activeDetails ->
            CappedFontScale(MaxDetailsFontScale) {
                BoundedModalSurface {
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
        }

        if (showShootingFilters) {
          CappedFontScale {
            ShootingFiltersScreen(
                inventory = filterInventory,
                committed = calcState.mountedAuxiliaryFilters,
                candidateFilterSetIds = calcState.candidateFilterSetIds,
                actions = remember(controller) {
                    ShootingFiltersActions(
                        rejection = controller::shootingFiltersRejection,
                        subtotal = controller::auxiliaryFiltersSubtotal,
                        apply = controller::applyShootingFilters,
                        displayedSelectedFilterSets = controller::displayedSelectedFilterSets,
                        availableFilterSets = controller::availableFilterSets,
                        selectedFilterRows = controller::selectedFilterRows,
                        setMount = controller::shootingFiltersSessionSettingMount,
                        isInUse = controller::isFilterSetInUseOnActiveCamera,
                        suggestCreationColor = controller::suggestFilterSetCreationColor,
                        createFilterSet = { name, color -> controller.createFilterSet(name, color) },
                        createFilterSetHolding = { name, color, item -> controller.createFilterSet(name, color, item) },
                        saveFilterItem = controller::saveFilterItem,
                        openFilterSet = { editedFilterSetId = it },
                        addExampleFilterSets = { controller.addExampleFilterSets() },
                    )
                },
                onDismiss = { showShootingFilters = false },
            )
          }
        }

        if (showFilterManagement) {
          CappedFontScale {
            FilterManagementScreen(
                inventory = filterInventory,
                suggestCreationColor = controller::suggestFilterSetCreationColor,
                createFilterSet = { name, color -> controller.createFilterSet(name, color) },
                createFilterSetHolding = { name, color, item -> controller.createFilterSet(name, color, item) },
                saveFilterItem = controller::saveFilterItem,
                addExampleFilterSets = { controller.addExampleFilterSets() },
                onOpenFilterSet = { editedFilterSetId = it },
                onDismiss = { showFilterManagement = false },
            )
          }
        }

        editedFilterSetId?.let { filterSetId ->
          CappedFontScale {
            FilterSetManagementScreen(
                inventory = filterInventory,
                filterSetId = filterSetId,
                actions = remember(controller) {
                    FilterSetManagementActions(
                        suggestCreationColor = controller::suggestFilterSetCreationColor,
                        createFilterSet = { name, color -> controller.createFilterSet(name, color) },
                        createFilterSetHolding = { name, color, item -> controller.createFilterSet(name, color, item) },
                        renameFilterSet = controller::renameFilterSet,
                        recolorFilterSet = controller::recolorFilterSet,
                        deleteFilterSet = controller::deleteFilterSet,
                        deleteFilterItem = controller::deleteFilterItem,
                        saveFilterItem = controller::saveFilterItem,
                        camerasAffectedByDeletingFilterSet = controller::camerasAffectedByDeletingFilterSet,
                        camerasAffectedByDeletingItem = controller::camerasAffectedByDeletingItem,
                    )
                },
                onDismiss = { editedFilterSetId = null },
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
 * Reopens the banner's explanation on demand from the header's warning icon
 * (PTIMER-219): a deliberate second step before leaving the app, rather than
 * jumping straight to system settings with no context or way back.
 */
@Composable
private fun ExactAlarmInfoDialog(onOpenSettings: () -> Unit, onDismiss: () -> Unit) {
    // AlertDialog composes each slot inside its own dialog window, which
    // re-derives LocalDensity from the system Configuration rather than
    // inheriting ShootingApp's font-scale cap (PTIMER-219) — every slot needs
    // its own CappedFontScale wrap, not just the AlertDialog call site.
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { CappedFontScale { Text(stringResource(R.string.alarm_warning_title)) } },
        text = { CappedFontScale { Text(stringResource(R.string.alarm_warning_body)) } },
        confirmButton = {
            CappedFontScale {
                TextButton(onClick = onOpenSettings) { Text(stringResource(R.string.alarm_warning_open_settings)) }
            }
        },
        dismissButton = {
            CappedFontScale {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.alarm_warning_dismiss)) }
            }
        },
    )
}

/** Saves a Filter Set id by its raw value. */
private val FilterSetIdSaver = Saver<FilterSetId?, String>(
    save = { it?.rawValue },
    restore = { FilterSetId(it) },
)
