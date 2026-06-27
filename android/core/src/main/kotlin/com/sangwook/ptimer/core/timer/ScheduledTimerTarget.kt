// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.timer

import java.time.Instant
import java.util.UUID

/**
 * Pure value type shared by the timer coordinator and the notification /
 * ongoing-timer surfaces. Port of iOS PTimerCore ScheduledTimerTarget.
 */
data class ScheduledTimerTarget(
    val timerID: UUID,
    val timerName: String,
    val endDate: Instant,
)
