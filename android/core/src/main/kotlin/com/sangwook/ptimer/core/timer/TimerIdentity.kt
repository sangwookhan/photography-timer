// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.timer

import kotlinx.serialization.Serializable

/**
 * Immutable display identity captured when a timer starts, so a running/
 * completed card can describe its shot without re-deriving from live
 * calculator state. The richer fields (film descriptor, selected model label,
 * custom-profile descriptor) are filled in once the calculator/slots arrive;
 * the MVP timer workspace populates what it has.
 */
@Serializable
data class TimerIdentity(
    val title: String,
    val subtitle: String = "",
    val baseLine: String = "",
    val slotLabel: String = "",
)

/**
 * A timer plus its captured display identity and a stable per-timer sequence
 * number. [order] is the creation order (1-based, monotonic across the session
 * and persisted) — mirrors iOS `RunningTimerItem.order`, surfaced as a bare
 * number so repeated timers sharing a camera/film/exposure stay distinguishable.
 */
data class WorkspaceTimer(
    val state: TimerState,
    val identity: TimerIdentity,
    val order: Int = 0,
) {
    val id get() = state.id
}
