package com.sangwook.ptimer.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.sangwook.ptimer.app.notify.AndroidTimerAlertCoordinator
import com.sangwook.ptimer.app.notify.TimerAlertPlanner
import com.sangwook.ptimer.app.notify.TimerNotifications
import com.sangwook.ptimer.app.persistence.DataStoreCustomFilmLibraryStore
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
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalog
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
fun ShootingApp() {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()

    val viewModel = remember {
        ShootingViewModel(store = DataStoreTimerWorkspaceStore(context), clock = { Instant.now() })
    }
    val coordinator = remember { AndroidTimerCoordinator(scope, viewModel, clock = { Instant.now() }) }
    val slotStore = remember { DataStoreSlotSessionStore(context) }
    val library = remember { CustomFilmLibrary(store = DataStoreCustomFilmLibraryStore(context)) }
    val controller = remember {
        CalculatorController(
            films = LaunchPresetFilmCatalog.films + library.customFilms,
            onStart = { duration, identity -> viewModel.onEvent(ShootingIntent.StartTimer(duration, identity)) },
            initialSession = slotStore.loadSession(),
        )
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
    val alertCoordinator = remember { AndroidTimerAlertCoordinator(context) }
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
    val calcState by controller.state.collectAsStateWithLifecycle()

    LaunchedEffect(timerState.active.size, viewModel.hasRunningTimers) {
        if (viewModel.hasRunningTimers) coordinator.start() else coordinator.stop()
    }

    // Re-sync alarms/service only when the running set (ids + end instants)
    // changes — not on every per-second tick.
    val runningSignature = timerState.active
        .filter { it.status == TimerStatus.running }
        .joinToString(",") { "${it.id}@${it.endDate.toEpochMilli()}" }
    LaunchedEffect(runningSignature) {
        val plan = TimerAlertPlanner.plan(timerState.active) { clockFormatter.format(java.time.Instant.ofEpochMilli(it)) }
        alertCoordinator.sync(plan)
    }

    var details by remember { mutableStateOf<com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState?>(null) }
    val scaffoldState = rememberBottomSheetScaffoldState()
    val hasTimers = timerState.active.isNotEmpty() || timerState.history.isNotEmpty()

    // Peek shows the compact MiniTimerBar; the full list appears only once the
    // sheet is expanded. Peek height = the bar plus the drag-handle region so
    // the mini card is never clipped.
    val expanded = scaffoldState.bottomSheetState.currentValue == SheetValue.Expanded
    val handleHeight = 48.dp
    // The mini card a user tapped to open the full list, so it can be focused.
    var focusTimerId by remember { mutableStateOf<java.util.UUID?>(null) }

    // Keep the sheet at its partial (mini) anchor whenever the timer set appears
    // or empties. On the first timer this shows only the compact peek instead of
    // settling to the full list (the peek height grows from 0). On clearing the
    // last timer it collapses the sheet to the now-zero peek instead of leaving
    // an empty expanded list open. Tapping a mini card is the only expand path.
    LaunchedEffect(hasTimers) {
        scaffoldState.bottomSheetState.partialExpand()
    }

    // Focus follows a newly started active timer so Start New (and a calculator
    // start) scrolls the fresh timer into view in the expanded list, instead of
    // the list snapping back to the previously focused card and hiding the new
    // one above it. Only genuinely new ids move the focus, so tapping an
    // existing mini card to inspect it is preserved. Keyed on the id list (not
    // the per-second state) so it does not re-run on every tick.
    var knownActiveIds by remember { mutableStateOf<Set<java.util.UUID>>(emptySet()) }
    val activeIds = timerState.active.map { it.id }
    LaunchedEffect(activeIds) {
        val current = activeIds.toSet()
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
        sheetPeekHeight = if (hasTimers) MiniTimerBarHeight + handleHeight else 0.dp,
        sheetContent = {
            if (expanded) {
                FullTimerList(
                    state = timerState,
                    onEvent = viewModel::onEvent,
                    onCollapse = { scope.launch { scaffoldState.bottomSheetState.partialExpand() } },
                    focusId = focusTimerId,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                MiniTimerBar(
                    state = timerState,
                    onOpen = { id ->
                        focusTimerId = id
                        scope.launch { scaffoldState.bottomSheetState.expand() }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize()) {
        Box(Modifier.padding(innerPadding)) {
            ShootingScreen(
                    state = calcState,
                    onShutterIndex = controller::setShutterIndex,
                    onNdIndex = controller::setNdIndex,
                    onSelectFilm = controller::selectFilm,
                    onSelectProfile = controller::selectProfile,
                    onSelectSlot = controller::selectSlot,
                    onRenameSlot = controller::renameActiveSlot,
                    onSetTarget = controller::setTargetShutter,
                    onStartTarget = controller::startFromTarget,
                    onStartAdjusted = controller::startFromAdjusted,
                    onStartCorrected = controller::startFromCorrected,
                    onOpenDetails = { details = controller.detailsState() },
                    onReset = controller::resetActiveSlot,
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
                            controller.setFilms(LaunchPresetFilmCatalog.films + library.customFilms)
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
                            controller.setFilms(LaunchPresetFilmCatalog.films + library.customFilms)
                            controller.selectFilm(film.id)
                            true
                        }
                    },
                    onEditCustomFilm = { id -> controller.customFilmDraft(id) },
                    onDeleteCustomFilm = { id ->
                        library.remove(id)
                        controller.setFilms(LaunchPresetFilmCatalog.films + library.customFilms)
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
                            controller.setFilms(LaunchPresetFilmCatalog.films + library.customFilms)
                            controller.selectFilm(formula.id)
                            true
                        }
                    },
                    onReferencePoints = { input, anchors -> controller.referencePoints(input, anchors) },
                )
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
    }
}
