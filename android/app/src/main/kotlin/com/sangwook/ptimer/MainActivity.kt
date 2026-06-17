// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sangwook.ptimer.timer.DataStoreCustomFilmStore
import com.sangwook.ptimer.timer.DataStoreSessionStore
import com.sangwook.ptimer.timer.DataStoreTimerStore
import com.sangwook.ptimer.ui.ShootingScreen
import com.sangwook.ptimer.ui.theme.PTimerTheme
import com.sangwook.ptimer.vm.ShootingViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PTimerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    ShootingRoot()
                }
            }
        }
    }
}

@Composable
private fun ShootingRoot() {
    val context = LocalContext.current
    val timerStore = remember { DataStoreTimerStore(context.applicationContext) }
    val sessionStore = remember { DataStoreSessionStore(context.applicationContext) }
    val customStore = remember { DataStoreCustomFilmStore(context.applicationContext) }
    val viewModel: ShootingViewModel =
        viewModel(factory = ShootingViewModel.factory(timerStore, sessionStore, customStore))
    val calcState by viewModel.calcState.collectAsStateWithLifecycle()
    val timerState by viewModel.timerState.collectAsStateWithLifecycle()
    val slotsState by viewModel.slotsState.collectAsStateWithLifecycle()
    val films by viewModel.films.collectAsStateWithLifecycle()
    val details by viewModel.detailsState.collectAsStateWithLifecycle()
    ShootingScreen(
        slots = slotsState,
        calc = calcState,
        films = films,
        timers = timerState,
        details = details,
        onEvent = viewModel::onEvent,
    )
}
