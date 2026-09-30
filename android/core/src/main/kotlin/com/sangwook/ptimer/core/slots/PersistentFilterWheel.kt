// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterWheel
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.exposure.NDStep
import com.sangwook.ptimer.core.exposure.NdFilterStack
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

/**
 * One wheel of the mixed Filter Stack in its on-disk shape (Filter Set
 * contract, FILTER-PERSIST-001). A Standard wheel carries its canonical
 * stop value; a Filter Set wheel names its set and — when an item is
 * mounted — the item id, the row kind, and the row's parameter (CPL loss
 * in stops or the GND mode). Every field beyond [sourceKind] is optional
 * so the shape stays additive. (iOS: PersistentFilterWheelSnapshot.)
 *
 * This lives beside [SlotCalculatorSnapshot] rather than in the
 * persistence package because the snapshot that embeds it is owned here.
 */
@Serializable
data class PersistentFilterWheel(
    val sourceKind: String,
    val filterSetId: String? = null,
    val stops: Double? = null,
    val itemId: String? = null,
    /** [FilterItemKind] token of the mounted row's item. */
    val rowKind: String? = null,
    val cplLossStops: Double? = null,
    /** [GndCalculationMode] token. */
    val gndMode: String? = null,
) {
    /**
     * Restores the wheel reference. A Standard wheel is accepted only on
     * the shipping ladder (the same envelope the PTIMER-199 stack restore
     * enforces — reject, never clamp). Filter Set wheels restore as
     * references; whether the set / item still exist is decided against
     * the live inventory by the caller. `null` marks a structurally
     * corrupted wheel.
     */
    fun restoredWheel(): FilterWheel? = when (sourceKind) {
        STANDARD_SOURCE_KIND -> {
            val value = stops
            if (value != null && NdFilterStack.isValidRestoredStack(listOf(value))) {
                FilterWheel.standard(value)
            } else {
                null
            }
        }

        FILTER_SET_SOURCE_KIND -> {
            val setId = filterSetId?.takeIf { it.isNotEmpty() }
            if (setId == null) {
                null
            } else {
                val source = FilterSource.FilterSet(FilterSetId(setId))
                val mountedItemId = itemId?.takeIf { it.isNotEmpty() }
                if (mountedItemId == null) {
                    FilterWheel(source, FilterWheelSelection.Empty)
                } else {
                    restoredChoice()?.let { choice ->
                        FilterWheel(
                            source,
                            FilterWheelSelection.Item(
                                FilterRowSelection(FilterItemId(mountedItemId), choice),
                            ),
                        )
                    }
                }
            }
        }

        else -> null
    }

    private fun restoredChoice(): FilterRowChoice? = when (FilterItemKind.fromToken(rowKind)) {
        FilterItemKind.fixed -> FilterRowChoice.Fixed
        FilterItemKind.cpl -> cplLossStops?.takeIf { it.isFinite() }?.let { FilterRowChoice.CplLoss(it) }
        FilterItemKind.gnd -> GndCalculationMode.fromToken(gndMode)?.let { FilterRowChoice.Gnd(it) }
        // Color and Effect items are never wheel rows.
        FilterItemKind.color, FilterItemKind.effect, null -> null
    }

    companion object {
        const val STANDARD_SOURCE_KIND: String = "standard"
        const val FILTER_SET_SOURCE_KIND: String = "filterSet"

        fun from(wheel: FilterWheel): PersistentFilterWheel {
            val setId = wheel.source.filterSetId
            return when (val selection = wheel.selection) {
                is FilterWheelSelection.Standard ->
                    PersistentFilterWheel(STANDARD_SOURCE_KIND, stops = selection.stops)

                is FilterWheelSelection.Empty -> if (setId == null) {
                    corrupted()
                } else {
                    PersistentFilterWheel(FILTER_SET_SOURCE_KIND, filterSetId = setId.rawValue)
                }

                is FilterWheelSelection.Item -> if (setId == null) {
                    corrupted()
                } else {
                    val base = PersistentFilterWheel(
                        sourceKind = FILTER_SET_SOURCE_KIND,
                        filterSetId = setId.rawValue,
                        itemId = selection.selection.itemId.rawValue,
                    )
                    when (val choice = selection.selection.choice) {
                        is FilterRowChoice.Fixed -> base.copy(rowKind = FilterItemKind.fixed.name)
                        is FilterRowChoice.CplLoss -> base.copy(
                            rowKind = FilterItemKind.cpl.name,
                            cplLossStops = choice.stops,
                        )

                        is FilterRowChoice.Gnd -> base.copy(
                            rowKind = FilterItemKind.gnd.name,
                            gndMode = choice.mode.name,
                        )
                    }
                }
            }
        }

        // Inconsistent runtime wheels never exist; persist the safest
        // equivalent so decode still resolves.
        private fun corrupted() = PersistentFilterWheel(STANDARD_SOURCE_KIND, stops = 0.0)
    }
}

/**
 * One mounted auxiliary filter in its on-disk shape (FILTER-AUX,
 * FILTER-PERSIST-001): the owning set, the item, the item's kind, and the
 * per-shot choice — a CPL's loss in stops or a GND's mode; Color and
 * Effect items carry neither and contribute their registered loss.
 * (iOS: PersistentAuxiliaryFilterSnapshot.)
 */
@Serializable
data class PersistentAuxiliaryFilter(
    val filterSetId: String,
    val itemId: String,
    /** [FilterItemKind] token of the mounted item. */
    val kind: String,
    val cplLossStops: Double? = null,
    /** [GndCalculationMode] token. */
    val gndMode: String? = null,
) {
    /**
     * The mount reference; whether the set and item still exist, and
     * whether the choice still fits the item, is decided against the live
     * inventory by the caller. `null` marks a structurally corrupted entry.
     */
    fun restoredMount(): MountedAuxiliaryFilter? {
        if (filterSetId.isEmpty() || itemId.isEmpty()) return null
        val choice = when (FilterItemKind.fromToken(kind)) {
            FilterItemKind.cpl ->
                cplLossStops?.takeIf { it.isFinite() }?.let { AuxiliaryFilterChoice.CplLoss(it) } ?: return null
            FilterItemKind.gnd ->
                GndCalculationMode.fromToken(gndMode)?.let { AuxiliaryFilterChoice.Gnd(it) } ?: return null
            FilterItemKind.color, FilterItemKind.effect -> AuxiliaryFilterChoice.RegisteredLoss
            FilterItemKind.fixed, null -> return null
        }
        return MountedAuxiliaryFilter(FilterSetId(filterSetId), FilterItemId(itemId), choice)
    }

    companion object {
        fun from(mount: MountedAuxiliaryFilter, kind: FilterItemKind): PersistentAuxiliaryFilter {
            val base = PersistentAuxiliaryFilter(mount.filterSetId.rawValue, mount.itemId.rawValue, kind.name)
            return when (val choice = mount.choice) {
                is AuxiliaryFilterChoice.CplLoss -> base.copy(cplLossStops = choice.stops)
                is AuxiliaryFilterChoice.Gnd -> base.copy(gndMode = choice.mode.name)
                is AuxiliaryFilterChoice.RegisteredLoss -> base
            }
        }
    }
}

/**
 * The slot's restored Filter Stack — ND wheels and mounted auxiliary
 * filters (FILTER-PERSIST-001/002). The additive
 * [SlotCalculatorSnapshot.filterStack] is authoritative when it is
 * present and EVERY wheel and auxiliary entry restores structurally; a
 * legacy wheel that mounted a CPL or GND row migrates into an auxiliary
 * filter with the same item, choice, and mode, and the rest re-resolve
 * against the live inventory (unknown sets dropped, vanished items read
 * Empty, an unresolvable auxiliary filter is unmounted, never replaced
 * by another choice). Anything else — the field absent, a structurally
 * corrupted entry, more than four wheels, or a result that no longer
 * fits the limits — falls back to the legacy Standard-only stack, which
 * itself falls back to the legacy scalar.
 */
fun SlotCalculatorSnapshot.restoredFilterStack(inventory: FilterInventory): FilterStack {
    storedFilterReferences()?.let { (wheels, mounts) ->
        val normalized = FilterStack.normalizedWheels(wheels, inventory)
        if (normalized != null) {
            val onWheels = normalized.mapNotNull { it.mountedItemId }.toSet()
            val auxiliary = FilterStack.normalizedAuxiliaryFilters(mounts, inventory)
                .filter { it.itemId !in onWheels }
            FilterStack.validated(normalized, auxiliary, inventory)?.let { return it }
        }
    }
    return FilterStack.validated(canonicalNdStackStops().map { FilterWheel.standard(it) }, inventory)
        ?: FilterStack.single(0.0)
}

/**
 * The stored wheel and auxiliary references before any inventory
 * resolution, with legacy CPL / GND wheel rows already migrated into
 * auxiliary filters. `null` when the mixed-stack field is absent or any
 * entry is structurally corrupted. A caller that has to follow a kind
 * change (FILTER-ITEM-005) reads these, since resolution against the new
 * inventory would already have emptied a wheel whose item left the ND
 * role.
 */
fun SlotCalculatorSnapshot.storedFilterReferences(): Pair<List<FilterWheel>, List<MountedAuxiliaryFilter>>? {
    val persisted = filterStack
    if (persisted.isNullOrEmpty() || persisted.size > FilterStack.MAX_WHEEL_COUNT) return null
    val restored = persisted.map { it.restoredWheel() }
    val mounts = auxiliaryFilters.orEmpty().map { it.restoredMount() }
    if (restored.any { it == null } || mounts.any { it == null }) return null
    val (wheels, legacy) = FilterStack.migratingLegacyWheels(restored.filterNotNull())
    return wheels to (mounts.filterNotNull() + legacy)
}

/** The wheels of [restoredFilterStack]. */
fun SlotCalculatorSnapshot.restoredFilterWheels(inventory: FilterInventory): List<FilterWheel> =
    restoredFilterStack(inventory).wheels

/**
 * The slot's candidate Filter Sets (FILTER-CAMERA-001), in user-defined
 * set order: the stored assignment, without sets that no longer exist,
 * plus every set the restored stack still references.
 */
fun SlotCalculatorSnapshot.restoredCandidateFilterSetIds(inventory: FilterInventory): List<FilterSetId> {
    val stack = restoredFilterStack(inventory)
    return inventory.normalizedCandidateFilterSetIds(
        storedCandidateFilterSetIds,
        stack.wheels,
        stack.auxiliaryFilters,
    )
}

/** The raw stored candidate ids, before normalization. */
val SlotCalculatorSnapshot.storedCandidateFilterSetIds: List<FilterSetId>
    get() = candidateFilterSetIds.orEmpty().filter { it.isNotEmpty() }.map { FilterSetId(it) }

/**
 * The Filter Sources the Plus wheel and the popup's ND tab offer for a
 * camera with [candidates] (FILTER-PLUS-001): Standard, then the
 * candidate sets that hold at least one ND item, in set order.
 */
fun FilterInventory.offeredFilterSources(candidates: List<FilterSetId>): List<FilterSource> =
    listOf(FilterSource.Standard) + filterSets
        .filter { it.id in candidates && it.ndItems.isNotEmpty() }
        .map { FilterSource.FilterSet(it.id) }

/**
 * The slot's remembered Filter Source for the Plus wheel
 * (FILTER-PLUS-004). A fresh camera, an absent field, and a Filter Set
 * the camera no longer offers (deleted, no longer a candidate, or without
 * ND items) all fall back to Standard.
 */
fun SlotCalculatorSnapshot.restoredLastFilterSource(inventory: FilterInventory): FilterSource {
    if (lastFilterSourceKind != PersistentFilterWheel.FILTER_SET_SOURCE_KIND) return FilterSource.Standard
    val setId = lastFilterSetId?.takeIf { it.isNotEmpty() } ?: return FilterSource.Standard
    val source = FilterSource.FilterSet(FilterSetId(setId))
    val offered = inventory.offeredFilterSources(restoredCandidateFilterSetIds(inventory))
    return if (source in offered) source else FilterSource.Standard
}

/**
 * Writes [stack], [lastSource], and [candidates] into the snapshot
 * (FILTER-PERSIST-001). The additive mixed-stack, auxiliary, and
 * candidate fields are authoritative for new builds and are omitted while
 * empty; the pre-Filter-Set fields describe only the stack's STANDARD
 * wheels — one Standard 0 wheel when it has none — so an older build
 * restores a valid Standard-only projection, with the legacy scalar
 * carrying the strongest Standard wheel exactly as the Standard-only path
 * writes it.
 */
fun SlotCalculatorSnapshot.writingFilterStack(
    stack: FilterStack,
    lastSource: FilterSource,
    candidates: List<FilterSetId> = storedCandidateFilterSetIds,
): SlotCalculatorSnapshot {
    val standardStops = stack.wheels.mapNotNull { it.standardStops }
    val projected = standardStops.ifEmpty { listOf(0.0) }
    val strongest = projected.max()
    return copy(
        ndIndex = NDStep(strongest).wholeStops ?: strongest.roundToInt(),
        ndStops = ExposureScale.commercialNDPresetStop(strongest),
        ndStack = projected,
        filterStack = stack.wheels.map { PersistentFilterWheel.from(it) },
        auxiliaryFilters = stack.auxiliaryRows
            .map { PersistentAuxiliaryFilter.from(it.mount, it.item.behavior.kind) }
            .ifEmpty { null },
        candidateFilterSetIds = candidates.map { it.rawValue }.ifEmpty { null },
        lastFilterSourceKind = when (lastSource) {
            is FilterSource.Standard -> PersistentFilterWheel.STANDARD_SOURCE_KIND
            is FilterSource.FilterSet -> PersistentFilterWheel.FILTER_SET_SOURCE_KIND
        },
        lastFilterSetId = lastSource.filterSetId?.rawValue,
    )
}
