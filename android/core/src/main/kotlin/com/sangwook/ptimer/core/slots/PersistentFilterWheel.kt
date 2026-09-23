// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

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
        null -> null
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
 * The slot's restored mixed Filter Stack wheels (FILTER-PERSIST-001/002).
 * The additive [SlotCalculatorSnapshot.filterStack] is authoritative when
 * it is present and EVERY wheel restores structurally; the surviving
 * wheels are then re-resolved against the live inventory (unknown sets
 * dropped, vanished items and CPL choices restored as Empty, never
 * another choice). Anything else — the field absent, a structurally
 * corrupted wheel, or more than four wheels — falls back to the legacy
 * Standard-only stack, which itself falls back to the legacy scalar.
 */
fun SlotCalculatorSnapshot.restoredFilterWheels(inventory: FilterInventory): List<FilterWheel> {
    val persisted = filterStack
    if (!persisted.isNullOrEmpty()) {
        val restored = persisted.map { it.restoredWheel() }
        if (restored.none { it == null }) {
            FilterStack.normalizedWheels(restored.filterNotNull(), inventory)?.let { return it }
        }
    }
    return canonicalNdStackStops().map { FilterWheel.standard(it) }
}

/**
 * The slot's remembered Filter Source for the Plus wheel
 * (FILTER-PLUS-004). A fresh camera, an absent field, and a Filter Set
 * that no longer exists all fall back to Standard.
 */
fun SlotCalculatorSnapshot.restoredLastFilterSource(inventory: FilterInventory): FilterSource {
    if (lastFilterSourceKind != PersistentFilterWheel.FILTER_SET_SOURCE_KIND) return FilterSource.Standard
    val setId = lastFilterSetId?.takeIf { it.isNotEmpty() } ?: return FilterSource.Standard
    val source = FilterSource.FilterSet(FilterSetId(setId))
    return if (inventory.contains(source)) source else FilterSource.Standard
}

/**
 * Writes [stack] and [lastSource] into the snapshot (FILTER-PERSIST-001).
 * The additive mixed-stack field is authoritative for new builds; the
 * pre-Filter-Set fields describe only the stack's STANDARD wheels — one
 * Standard 0 wheel when it has none — so an older build restores a valid
 * Standard-only projection, with the legacy scalar carrying the strongest
 * Standard wheel exactly as the Standard-only path writes it.
 */
fun SlotCalculatorSnapshot.writingFilterStack(
    stack: FilterStack,
    lastSource: FilterSource,
): SlotCalculatorSnapshot {
    val standardStops = stack.wheels.mapNotNull { it.standardStops }
    val projected = standardStops.ifEmpty { listOf(0.0) }
    val strongest = projected.max()
    return copy(
        ndIndex = NDStep(strongest).wholeStops ?: strongest.roundToInt(),
        ndStops = ExposureScale.commercialNDPresetStop(strongest),
        ndStack = projected,
        filterStack = stack.wheels.map { PersistentFilterWheel.from(it) },
        lastFilterSourceKind = when (lastSource) {
            is FilterSource.Standard -> PersistentFilterWheel.STANDARD_SOURCE_KIND
            is FilterSource.FilterSet -> PersistentFilterWheel.FILTER_SET_SOURCE_KIND
        },
        lastFilterSetId = lastSource.filterSetId?.rawValue,
    )
}
