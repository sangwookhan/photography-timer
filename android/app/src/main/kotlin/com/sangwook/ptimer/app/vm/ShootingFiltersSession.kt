// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import androidx.annotation.VisibleForTesting
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
     * Follows an inventory edit made from a set editor opened here, which
     * is immediate and not rolled back (FILTER-FLOW-003). Call it whenever
     * the camera's committed state or the inventory changes: it rebases on
     * a committed change and then reconciles against the inventory, so the
     * screen may run it from any trigger, or more than once, with the same
     * result. (iOS: `follow`.)
     */
    fun followed(
        committedFilterSetIds: List<FilterSetId>,
        committedMounts: List<MountedAuxiliaryFilter>,
        inventory: FilterInventory,
    ): ShootingFiltersSession {
        val rebased =
            if (committedFilterSetIds == this.committedFilterSetIds && committedMounts.toSet() == this.committedMounts) this
            else rebased(committedFilterSetIds, committedMounts, inventory)
        return rebased.reconciled(inventory)
    }

    /**
     * The camera's committed state changed underneath the session — an
     * inventory edit made from a set editor opened here, which is
     * immediate and not rolled back (FILTER-FLOW-003). Each item follows
     * the edit only where its committed mount changed: a pick the session
     * had not changed takes the new committed mount, a pick the session had
     * changed keeps its choice, and every other working pick or unmount
     * stays as it is, so Apply never undoes the edit and never loses an
     * unrelated draft change. A committed mount whose item moved stays
     * picked only while the session selects the item's new Set
     * (FILTER-ITEM-009), and one the camera dropped otherwise leaves the
     * session too. A set the camera gained joins the selection, and sets
     * that no longer exist leave it. Together with [reconciled], which
     * leaves these committed picks alone, the result does not depend on
     * which of the two runs first.
     */
    @VisibleForTesting
    internal fun rebased(
        committedFilterSetIds: List<FilterSetId>,
        committedMounts: List<MountedAuxiliaryFilter>,
        inventory: FilterInventory,
    ): ShootingFiltersSession {
        val gained = committedFilterSetIds.filter { it !in this.committedFilterSetIds && it !in selectedFilterSetIds }
        val selected = selectedFilterSetIds + gained
        val before = this.committedMounts.associateBy { it.itemId }
        val after = committedMounts.associateBy { it.itemId }
        val rebased = workingMounts.mapNotNull { working ->
            val old = before[working.itemId]
            val new = after[working.itemId]
            when {
                old == new -> working
                new != null && old != null && old.filterSetId != new.filterSetId && new.filterSetId !in selected -> null
                new != null -> if (working == old || !new.choice.sameRole(working.choice)) new else working.copy(filterSetId = new.filterSetId)
                // The camera dropped a pick the session had not changed. An
                // item that moved to a Set this session selects stays picked
                // there; anything else leaves with the camera's mount.
                working == old -> inventory.item(working.itemId)?.first?.id
                    ?.takeIf { it != working.filterSetId && it in selected }
                    ?.let { owner -> working.copy(filterSetId = owner) }
                    ?.takeIf { FilterStack.resolvedAuxiliaryFilter(it, inventory) != null }
                else -> working
            }
        }
        // A newly committed mount joins the session; one the session had
        // unmounted stays unmounted.
        val joined = committedMounts.filter { mount ->
            mount.itemId !in before && rebased.none { it.itemId == mount.itemId }
        }
        return ShootingFiltersSession(
            selectedFilterSetIds = selected.filter { inventory.filterSet(it) != null },
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
     * selection. A pick whose item now lives in another Set follows it
     * there with its choice while the session selects that Set, and is
     * otherwise cleared for good, so selecting the Set later does not bring
     * it back (FILTER-ITEM-009). A pick that still equals the camera's
     * committed mount is left to [rebased]: the camera's own reconciliation
     * decides it. Every other working choice is kept.
     */
    @VisibleForTesting
    internal fun reconciled(inventory: FilterInventory): ShootingFiltersSession {
        val selected = selectedFilterSetIds.filter { inventory.filterSet(it) != null }
        return copy(
            selectedFilterSetIds = selected,
            workingMounts = workingMounts.mapNotNull { mount ->
                if (mount in committedMounts) return@mapNotNull mount
                val owner = inventory.item(mount.itemId)?.first?.id ?: return@mapNotNull null
                val rehomed = when {
                    owner == mount.filterSetId -> mount
                    owner in selected -> mount.copy(filterSetId = owner)
                    else -> return@mapNotNull null
                }
                rehomed.takeIf { FilterStack.resolvedAuxiliaryFilter(it, inventory) != null }
            },
        )
    }
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
