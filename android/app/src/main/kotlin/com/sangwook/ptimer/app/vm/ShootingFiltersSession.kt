// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterItemKind
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
     * immediate and not rolled back (FILTER-FLOW-003). Each item follows
     * the edit only where its committed mount changed: a pick the session
     * had not changed takes the new committed mount (or leaves with it), a
     * pick the session had changed keeps its choice under the item's new
     * Set, and every other working pick or unmount stays as it is, so
     * Apply never undoes the edit and never loses an unrelated draft
     * change. A set the camera gained — a moved item's new set — joins the
     * selection, and sets that no longer exist leave it.
     */
    fun rebased(
        committedFilterSetIds: List<FilterSetId>,
        committedMounts: List<MountedAuxiliaryFilter>,
        existingFilterSetIds: Set<FilterSetId>,
    ): ShootingFiltersSession {
        val gained = committedFilterSetIds.filter { it !in this.committedFilterSetIds && it !in selectedFilterSetIds }
        val before = this.committedMounts.associateBy { it.itemId }
        val after = committedMounts.associateBy { it.itemId }
        val rebased = workingMounts.mapNotNull { working ->
            val old = before[working.itemId]
            val new = after[working.itemId]
            when {
                old == new -> working
                working == old -> new
                new != null ->
                    if (new.choice.sameRole(working.choice)) working.copy(filterSetId = new.filterSetId) else new
                else -> working
            }
        }
        // A newly committed mount joins the session; one the session had
        // unmounted stays unmounted.
        val joined = committedMounts.filter { mount ->
            mount.itemId !in before && rebased.none { it.itemId == mount.itemId }
        }
        return ShootingFiltersSession(
            selectedFilterSetIds = (selectedFilterSetIds + gained).filter { it in existingFilterSetIds },
            workingMounts = rebased + joined,
            committedFilterSetIds = committedFilterSetIds,
            committedMounts = committedMounts.toSet(),
        )
    }

    /**
     * An inventory edit made from a set editor opened here can leave the
     * working state naming what no longer exists even when the camera's
     * committed state did not change: a working pick of a deleted item, of
     * an item in a deleted Set, or with a choice no longer configured or no
     * longer fitting the item's kind is dropped, never replaced
     * (FILTER-ITEM-006, FILTER-PERSIST-002), and a deleted Set leaves the
     * selection. A pick whose item now lives in another Set is left as it
     * is. Every other working choice is kept.
     */
    fun reconciled(inventory: FilterInventory): ShootingFiltersSession = copy(
        selectedFilterSetIds = selectedFilterSetIds.filter { inventory.filterSet(it) != null },
        workingMounts = workingMounts.filter { mount ->
            FilterStack.resolvedAuxiliaryFilter(mount, inventory) != null ||
                inventory.item(mount.itemId)?.first?.id.let { owner -> owner != null && owner != mount.filterSetId }
        },
    )
}

/** The same kind of choice: a CPL loss, a GND mode, or a registered loss. */
private fun AuxiliaryFilterChoice.sameRole(other: AuxiliaryFilterChoice): Boolean = when (this) {
    is AuxiliaryFilterChoice.CplLoss -> other is AuxiliaryFilterChoice.CplLoss
    is AuxiliaryFilterChoice.Gnd -> other is AuxiliaryFilterChoice.Gnd
    AuxiliaryFilterChoice.RegisteredLoss -> other == AuxiliaryFilterChoice.RegisteredLoss
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

/**
 * The groups Shooting Filters shows its Selected Filter Sets in, by each
 * set's current items (FILTER-SET-004): ND-only sets first, then sets with
 * both ND and auxiliary filters, then auxiliary-only sets, then empty
 * sets. Only that display is grouped; the camera's selection order is
 * unchanged. (iOS: `SelectedFilterSetGroup`.)
 */
enum class SelectedFilterSetGroup {
    ndOnly,
    mixed,
    auxiliaryOnly,
    empty,
    ;

    companion object {
        fun of(filterSet: FilterSet): SelectedFilterSetGroup {
            val hasNd = filterSet.items.any { it.behavior.kind == FilterItemKind.fixed }
            val hasAuxiliary = filterSet.auxiliaryItems.isNotEmpty()
            return when {
                hasNd && !hasAuxiliary -> ndOnly
                hasNd -> mixed
                hasAuxiliary -> auxiliaryOnly
                else -> empty
            }
        }

        /** [sets] grouped for display, each group keeping the order given
         *  (the working selection order); the sort is stable. */
        fun ordered(sets: List<FilterSet>): List<FilterSet> = sets.sortedBy { of(it).ordinal }
    }
}

/**
 * The passive contents hint of an Available Filter Set row
 * (FILTER-SET-001): every kind the set holds with its registered item
 * count, in the fixed kind order ND, Color, Effect, CPL, GND; absent kinds
 * are left out and an empty set has no entries. Counts are items, never
 * stops, mounts, or CPL choices. The view names the kinds.
 * (iOS: `FilterSetContentsHint`.)
 */
object FilterSetContentsHint {
    data class Entry(val kind: FilterItemKind, val count: Int)

    private val kindOrder = listOf(
        FilterItemKind.fixed,
        FilterItemKind.color,
        FilterItemKind.effect,
        FilterItemKind.cpl,
        FilterItemKind.gnd,
    )

    fun entries(filterSet: FilterSet): List<Entry> = kindOrder.mapNotNull { kind ->
        val count = filterSet.items.count { it.behavior.kind == kind }
        if (count > 0) Entry(kind, count) else null
    }
}

/** A Selected Set that holds ND filters, alone or beside auxiliary
 *  filters, shows a passive inline ND cue in its Shooting Filters header
 *  (FILTER-FLOW-003); its ND values are chosen on Main. */
val FilterSet.showsNdCue: Boolean
    get() = items.any { it.behavior.kind == FilterItemKind.fixed }

/** One mount change in a Shooting Filters session (FILTER-AUX-007):
 *  accepted with the next session, or refused with its reason while the
 *  session stays as it was. */
sealed interface ShootingFiltersMountChange {
    data class Accepted(val session: ShootingFiltersSession) : ShootingFiltersMountChange
    data class Refused(val reason: FilterStackRejection) : ShootingFiltersMountChange
}
