package com.sangwook.ptimer.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.Manifest
import android.os.Build
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.withContext
import com.sangwook.ptimer.app.ui.details.ReciprocityDetailsScreen
import com.sangwook.ptimer.app.ui.shooting.ShootingScreen
import com.sangwook.ptimer.app.ui.timer.TimerListScreen
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingViewModel
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalog
import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder
import com.sangwook.ptimer.core.customfilm.CustomFilmLibrary
import java.time.Instant

/**
 * App host: builds the timer ViewModel + coordinator (DataStore-backed) and the
 * shooting calculator controller (whose Start feeds the timer workspace), and
 * switches between the shooting screen and the full-screen timer list. The
 * coordinator ticks only while a timer is running.
 */
@OptIn(FlowPreview::class)
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
    // stream and write the latest exported session (drop the initial emission).
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

    var showTimers by remember { mutableStateOf(false) }
    var details by remember { mutableStateOf<ReciprocityDetailsDisplayState?>(null) }

    val activeDetails = details
    if (activeDetails != null) {
        ReciprocityDetailsScreen(
            state = activeDetails,
            onBack = { details = null },
            onSelectModel = { id -> controller.selectProfile(id); details = controller.detailsState() },
        )
    } else if (showTimers) {
        TimerListScreen(
            state = timerState,
            onEvent = viewModel::onEvent,
            onBack = { showTimers = false },
        )
    } else {
        ShootingScreen(
            state = calcState,
            timersCount = timerState.active.size + timerState.history.size,
            onShutterIndex = controller::setShutterIndex,
            onNdIndex = controller::setNdIndex,
            onSelectFilm = controller::selectFilm,
            onSelectProfile = controller::selectProfile,
            onSelectSlot = controller::selectSlot,
            onRenameSlot = controller::renameActiveSlot,
            onSetTarget = controller::setTargetShutter,
            onStartTarget = { controller.startFromTarget(); showTimers = true },
            onOpenDetails = { details = controller.detailsState() },
            onCreateCustomFilm = { input, editId ->
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
            onStart = { controller.start(); showTimers = true },
            onOpenTimers = { showTimers = true },
        )
    }
}
