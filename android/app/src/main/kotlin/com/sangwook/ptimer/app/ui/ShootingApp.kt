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
import com.sangwook.ptimer.app.persistence.DataStoreTimerWorkspaceStore
import com.sangwook.ptimer.app.timer.AndroidTimerCoordinator
import com.sangwook.ptimer.app.ui.shooting.ShootingScreen
import com.sangwook.ptimer.app.ui.timer.TimerListScreen
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingViewModel
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalog
import java.time.Instant

/**
 * App host: builds the timer ViewModel + coordinator (DataStore-backed) and the
 * shooting calculator controller (whose Start feeds the timer workspace), and
 * switches between the shooting screen and the full-screen timer list. The
 * coordinator ticks only while a timer is running.
 */
@Composable
fun ShootingApp() {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()

    val viewModel = remember {
        ShootingViewModel(store = DataStoreTimerWorkspaceStore(context), clock = { Instant.now() })
    }
    val coordinator = remember { AndroidTimerCoordinator(scope, viewModel, clock = { Instant.now() }) }
    val controller = remember {
        CalculatorController(
            films = LaunchPresetFilmCatalog.films,
            onStart = { duration, identity -> viewModel.onEvent(ShootingIntent.StartTimer(duration, identity)) },
        )
    }

    LaunchedEffect(Unit) { viewModel.restore() }

    val timerState by viewModel.uiState.collectAsStateWithLifecycle()
    val calcState by controller.state.collectAsStateWithLifecycle()

    LaunchedEffect(timerState.active.size, viewModel.hasRunningTimers) {
        if (viewModel.hasRunningTimers) coordinator.start() else coordinator.stop()
    }

    var showTimers by remember { mutableStateOf(false) }

    if (showTimers) {
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
            onStart = controller::start,
            onOpenTimers = { showTimers = true },
        )
    }
}
