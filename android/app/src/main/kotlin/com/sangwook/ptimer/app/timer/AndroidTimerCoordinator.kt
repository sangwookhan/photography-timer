// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.timer

import com.sangwook.ptimer.app.vm.ShootingViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Owns the wall-clock tick loop for the timer workspace. While any timer is
 * running it calls [ShootingViewModel.tick] at [tickIntervalMillis] so the
 * countdown advances and running timers auto-complete. Composables never tick.
 *
 * The clock and scope are injected; pass `viewModelScope` (or an Activity
 * scope) in production and a test scope in tests.
 */
class AndroidTimerCoordinator(
    private val scope: CoroutineScope,
    private val viewModel: ShootingViewModel,
    private val clock: () -> Instant = { Instant.now() },
    private val tickIntervalMillis: Long = 200L,
) {
    private var job: Job? = null

    /** Starts the tick loop if a timer is running and none is active yet. */
    fun start() {
        if (job?.isActive == true) return
        job = scope.launch {
            while (isActive && viewModel.hasRunningTimers) {
                viewModel.tick(clock())
                delay(tickIntervalMillis)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }
}
