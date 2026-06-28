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
    // Structured ND/exposure basis captured at start (PTIMER-187), so the timer
    // card renders the basis line in the current ND notation mode instead of
    // parsing a precomposed string. All defaulted/nullable so snapshots written
    // before these fields decode unchanged (nil-safe; no migration).
    val ndStops: Double? = null,
    val baseShutterSeconds: Double? = null,
    val adjustedShutterSeconds: Double? = null,
    // True for corrected/target timers, where the adjusted shutter is an
    // intermediate distinct from the final duration and shown as the `Adj`
    // basis segment.
    val basisIncludesAdjusted: Boolean = false,
    // Compact film cue captured at start (PTIMER-198), e.g. "Fomapan 100"
    // or "No film" for the digital workflow, so the bottom mini timer can
    // show the same film identity the iOS mini does. Defaulted/nullable so
    // snapshots written before this field decode unchanged.
    val filmName: String? = null,
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
