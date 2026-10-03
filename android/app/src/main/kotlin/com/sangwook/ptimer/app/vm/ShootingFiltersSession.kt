// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter

/**
 * The working state of one Shooting Filters session (FILTER-AUX-003,
 * FILTER-CAMERA-003, FILTER-FLOW-003): the Filter Sets selected for the
 * camera and the mounted auxiliary filters, copied from the camera's
 * committed state when the screen opens. Nothing here is committed;
 * Apply commits [selectedFilterSetIds] and [mounts] together, and Cancel
 * simply drops the session.
 *
 * The selected sets keep their selection order: an added set goes last
 * (FILTER-SET-004). Removing a set hides its auxiliary filters but keeps
 * their working mounts for the session, so adding it again restores
 * them.
 * (iOS: `ShootingFiltersSession`.)
 */
data class ShootingFiltersSession(
    val selectedFilterSetIds: List<FilterSetId>,
    /** Every working mount, including those of sets removed right now. */
    private val workingMounts: List<MountedAuxiliaryFilter>,
    private val committedFilterSetIds: List<FilterSetId>,
    private val committedMounts: Set<MountedAuxiliaryFilter>,
) {
    constructor(committedFilterSetIds: List<FilterSetId>, committedMounts: List<MountedAuxiliaryFilter>) : this(
        selectedFilterSetIds = committedFilterSetIds,
        workingMounts = committedMounts,
        committedFilterSetIds = committedFilterSetIds,
        committedMounts = committedMounts.toSet(),
    )

    /** The mounts Apply commits: the working mounts of selected sets. */
    val mounts: List<MountedAuxiliaryFilter>
        get() = workingMounts.filter { it.filterSetId in selectedFilterSetIds }

    /**
     * Apply is offered when either the set selection, its order included,
     * or the mounts differ from the camera's committed state. Mount order
     * never matters; the display order is fixed.
     */
    val hasChanges: Boolean
        get() = selectedFilterSetIds != committedFilterSetIds || mounts.toSet() != committedMounts

    fun isSelected(id: FilterSetId): Boolean = id in selectedFilterSetIds

    /** Adds a set to the end of the working selection, or removes it, in
     *  the working state only. */
    fun withSelected(id: FilterSetId, selected: Boolean): ShootingFiltersSession = copy(
        selectedFilterSetIds = when {
            !selected -> selectedFilterSetIds - id
            id in selectedFilterSetIds -> selectedFilterSetIds
            else -> selectedFilterSetIds + id
        },
    )

    fun mount(itemId: FilterItemId): MountedAuxiliaryFilter? = workingMounts.firstOrNull { it.itemId == itemId }

    /** Mounts, changes, or (with `null`) unmounts one item in the working
     *  selection. */
    fun withMount(itemId: FilterItemId, mount: MountedAuxiliaryFilter?): ShootingFiltersSession =
        copy(workingMounts = workingMounts.filter { it.itemId != itemId } + listOfNotNull(mount))

    /**
     * The camera's committed state changed underneath the session — an
     * inventory edit made from a set editor opened here, which is
     * immediate and not rolled back (FILTER-FLOW-003). The mounts restart
     * from the new committed state so Apply can never undo that edit, a
     * set the camera gained — a moved item's new set — joins the
     * selection, and sets that no longer exist leave it.
     */
    fun rebased(
        committedFilterSetIds: List<FilterSetId>,
        committedMounts: List<MountedAuxiliaryFilter>,
        existingFilterSetIds: Set<FilterSetId>,
    ): ShootingFiltersSession {
        val gained = committedFilterSetIds.filter { it !in this.committedFilterSetIds && it !in selectedFilterSetIds }
        return ShootingFiltersSession(
            selectedFilterSetIds = (selectedFilterSetIds + gained).filter { it in existingFilterSetIds },
            workingMounts = committedMounts,
            committedFilterSetIds = committedFilterSetIds,
            committedMounts = committedMounts.toSet(),
        )
    }
}

/**
 * Where a Selected Set in Shooting Filters offers New Filter
 * (FILTER-SET-001, FILTER-FLOW-004): a trailing control in its header
 * while it holds at least one filter, otherwise a full-width Add Filter
 * row in its place. (iOS: `SelectedFilterSetAddFilterPlacement`.)
 */
enum class SelectedFilterSetAddFilterPlacement {
    headerControl,
    fullWidthRow,
    ;

    companion object {
        fun of(filterSet: FilterSet): SelectedFilterSetAddFilterPlacement =
            if (filterSet.items.isEmpty()) fullWidthRow else headerControl
    }
}
