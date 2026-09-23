// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection

/**
 * One wheel of the mixed Filter Stack as the shooting surface renders it
 * (FILTER-STACK-001/003/007). [id] is the wheel's stable identity
 * (monotonic from 101, position-independent — the Compose row keys on it
 * so the commit sort animates as movement). [selectedIndex] points at the
 * DISPLAYED row (pending selection while the set commit is open),
 * [committedIndex] at the settled one.
 */
data class FilterWheelUiState(
    val id: Int,
    val source: FilterSource,
    /** Canonical `Standard` or the Filter Set's user-defined name. */
    val sourceName: String,
    /** Filter Set source cue; `null` for Standard (FILTER-STACK-008). */
    val sourceColor: FilterSetColor?,
    val rows: List<FilterWheelRowUiState>,
    val selectedIndex: Int,
    val committedIndex: Int,
)

/** One selectable Filter Source on the Plus wheel (FILTER-SET-004). */
data class FilterSourceUiOption(
    val source: FilterSource,
    val name: String,
    val color: FilterSetColor?,
)

/**
 * The Plus wheel (FILTER-PLUS-001/003/004/005): present while fewer than
 * four actual wheels exist, browsing every source in selection order,
 * showing the camera's remembered source, and disabled with a reason when
 * that source cannot currently add a usable row.
 */
data class FilterPlusUiState(
    val isVisible: Boolean,
    val sources: List<FilterSourceUiOption>,
    /** Position of the camera's remembered source in [sources]. */
    val selectedIndex: Int,
    /** Why the remembered source cannot add now; `null` when it can. */
    val addUnavailability: FilterAddUnavailability?,
    /** Present AND the machine is quiet AND the domain allows the add. */
    val canAdd: Boolean,
)

/**
 * One source of the idle summary (FILTER-STACK-008): its name, how many
 * actual wheels it owns, and — for a Filter Set — the user-selected
 * source color shown as a cue beside the name. Standard carries no color
 * and is identified by text alone.
 */
data class FilterSourceSummaryItem(
    val source: FilterSource,
    val name: String,
    val count: Int,
    val color: FilterSetColor?,
)

/**
 * The single stable status region of the mixed-stack interaction
 * (FILTER-STACK-008): exactly one visual row in every state. The leading
 * content is the idle source summary, the moving wheel's row, or a
 * rejection reason; the trailing content is the total, which always stays
 * complete.
 */
data class FilterStatusUiState(
    /** Persistent idle summary; `null` for a Standard-only stack, which
     *  keeps the existing ND status behavior. */
    val idleSourceSummary: List<FilterSourceSummaryItem>?,
    /** Identity of the wheel currently under a finger; `null` at rest. */
    val movingWheelId: Int?,
    /** The displayed row of that wheel. */
    val movingRow: FilterWheelRowUiState?,
    val rejection: FilterRejectionNotice?,
    val totalStopsText: String,
    val totalIsMaximum: Boolean,
)

/**
 * Transient record of a refused wheel change (FILTER-STACK-004) or a
 * refused Plus addition (FILTER-PLUS-003/005). [sequence] increases per
 * notice so two identical rejections in a row still read as two events.
 * (iOS: `FilterRejectionNotice`.)
 */
data class FilterRejectionNotice(
    val sequence: Int,
    /** The refused wheel change; `null` for a refused addition. */
    val rejection: FilterStackRejection? = null,
    /** Why the Plus addition was refused; `null` for a wheel change. */
    val addUnavailability: FilterAddUnavailability? = null,
)

/**
 * One ACTUAL automatic removal of empty wheels (FILTER-STACK-006):
 * published only when a cleanup removed at least one Standard 0 or
 * Filter Set Empty wheel — never when it was scheduled, deferred, or
 * found nothing to remove. [sequence] increases per removal so two equal
 * removals in a row still read as two events; the platform layer
 * announces each exactly once while a screen reader is active.
 * (iOS: `EmptyFilterWheelRemoval`.)
 */
data class EmptyFilterWheelRemoval(
    val sequence: Int,
    val removedCount: Int,
)

/** Why an item save is blocked (FILTER-ITEM-005). */
enum class FilterItemSaveBlockReason {
    /** A camera's active contributions would exceed 30 stops. */
    exceedsTotalLimit,

    /** A camera currently mounts a row of this item that the edit removes
     *  — a selected CPL exposure-loss choice, or a row lost to a kind
     *  change. The selection is never replaced silently. */
    removesSelectedChoice,
}

/**
 * Outcome of saving a physical filter item (FILTER-ITEM-005): the save
 * commits only when every camera stack that references the item stays
 * valid afterwards.
 */
sealed class FilterItemSaveOutcome {
    data object Saved : FilterItemSaveOutcome()

    /** Display names of the cameras whose stack would become invalid,
     *  with the dominant reason (a removed selection outranks the cap). */
    data class Blocked(
        val affectedCameras: List<String>,
        val reason: FilterItemSaveBlockReason,
    ) : FilterItemSaveOutcome()
}
