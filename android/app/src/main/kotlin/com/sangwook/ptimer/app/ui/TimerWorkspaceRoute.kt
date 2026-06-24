package com.sangwook.ptimer.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sangwook.ptimer.app.persistence.DataStoreTimerWorkspaceStore
import com.sangwook.ptimer.app.timer.AndroidTimerCoordinator
import com.sangwook.ptimer.app.ui.timer.TimerListScreen
import com.sangwook.ptimer.app.vm.ShootingIntent
import com.sangwook.ptimer.app.vm.ShootingViewModel
import com.sangwook.ptimer.core.timer.TimerIdentity
import java.time.Instant

/**
 * Hosts the timer workspace: builds the ShootingViewModel + coordinator backed
 * by DataStore, restores on launch, observes UI state, and runs the tick loop
 * while a timer is active. The "Start" action seeds a sample timer until the
 * calculator (unit 7) provides real durations.
 */
@Composable
fun TimerWorkspaceRoute() {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()

    val viewModel = remember {
        ShootingViewModel(
            store = DataStoreTimerWorkspaceStore(context),
            clock = { Instant.now() },
        )
    }
    val coordinator = remember { AndroidTimerCoordinator(scope, viewModel, clock = { Instant.now() }) }

    LaunchedEffect(Unit) { viewModel.restore() }

    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    // Drive the tick loop whenever a timer is running.
    LaunchedEffect(uiState.active.size, viewModel.hasRunningTimers) {
        if (viewModel.hasRunningTimers) coordinator.start() else coordinator.stop()
    }

    TimerListScreen(
        state = uiState,
        onEvent = viewModel::onEvent,
        onStartSample = {
            viewModel.onEvent(
                ShootingIntent.StartTimer(
                    duration = 45.0,
                    identity = TimerIdentity(
                        title = "Sample · No film",
                        subtitle = "Calculated · 0 stops",
                        baseLine = "Base 1/30s · 0 stops",
                        slotLabel = "C1",
                    ),
                ),
            )
        },
    )
}
