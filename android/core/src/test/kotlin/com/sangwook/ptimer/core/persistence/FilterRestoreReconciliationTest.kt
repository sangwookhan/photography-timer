// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterExposureLoss
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheel
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.slots.restoredCandidateFilterSetIds
import com.sangwook.ptimer.core.slots.restoredFilterStack
import com.sangwook.ptimer.core.slots.writingFilterStack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The inventory and the slot session are saved separately, so a relaunch
 * can meet an inventory edit the slot snapshot has not seen yet. The
 * restore applies it the way the live reconciliation does
 * (FILTER-ITEM-005/009, FILTER-PERSIST-002): a moved item keeps its
 * references under its new Set, a kind change moves the selection into the
 * item's new role, and a deleted item keeps the deletion rules.
 * (iOS: `FilterRestoreReconciliationTests`.)
 */
class FilterRestoreReconciliationTest {

    private val nd8 = FilterItem("ND8", FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops)), FilterItemId("i-nd8"))
    private val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))), FilterItemId("i-cpl"))
    private val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red), FilterItemId("i-red"))
    private val kitId = FilterSetId("s-kit")
    private val pouchId = FilterSetId("s-pouch")
    private val kit = FilterSet("Kit", FilterSetColor.teal, listOf(nd8, cpl, red), kitId)
    private val pouch = FilterSet("Pouch", FilterSetColor.orange, emptyList(), pouchId)

    private fun ndWheel(setId: FilterSetId, item: FilterItem) =
        FilterWheel(FilterSource.FilterSet(setId), FilterWheelSelection.Item(FilterRowSelection(item.id, FilterRowChoice.Fixed)))

    private val cplAt15 = AuxiliaryFilterChoice.CplLoss(1.5)

    /** The camera saved with a Kit ND8 wheel beside Standard 2, the CPL at
     *  1.5 and the Red mounted, and Kit selected. */
    private val saved: SlotCalculatorSnapshot = run {
        val inventory = FilterInventory(listOf(kit, pouch))
        val stack = FilterStack.validated(
            listOf(ndWheel(kitId, nd8), FilterWheel.standard(2.0)),
            listOf(MountedAuxiliaryFilter(kitId, cpl.id, cplAt15), MountedAuxiliaryFilter(kitId, red.id, AuxiliaryFilterChoice.RegisteredLoss)),
            inventory,
        )!!
        val written = SlotCalculatorSnapshot(shutterIndex = 3, ndIndex = 0, selectedFilmId = null, selectedProfileId = null)
            .writingFilterStack(stack, FilterSource.FilterSet(kitId), listOf(kitId))
        val session = PersistentSlotSession(activeSlotId = CameraSlotId.camera1, snapshots = mapOf(CameraSlotId.camera1 to written))
        SlotSessionCodec.decode(SlotSessionCodec.encode(session))!!.snapshots.getValue(CameraSlotId.camera1)
    }

    private val savedStops = saved.restoredFilterStack(FilterInventory(listOf(kit, pouch))).effectiveStops

    /** One saved inventory moved an ND item and an auxiliary item into
     *  Pouch, which the camera does not select. The auxiliary rule is judged
     *  against the stored selection, so the CPL is unmounted even though the
     *  ND wheel follows its item into Pouch (today's ND-wheel behavior, its
     *  policy still open on #70, 6001226087). */
    @Test fun aMovedNdWheelFollowsAndAMovedAuxiliaryItemIsJudgedAgainstTheStoredSelection() {
        val moved = FilterInventory(listOf(kit.copy(items = listOf(red)), pouch.copy(items = listOf(nd8, cpl))))

        val restored = saved.restoredFilterStack(moved)

        assertTrue("${restored.wheels}", ndWheel(pouchId, nd8) in restored.wheels)
        assertEquals(
            "The ND wheel does not select Pouch for the CPL.",
            listOf(MountedAuxiliaryFilter(kitId, red.id, AuxiliaryFilterChoice.RegisteredLoss)),
            restored.auxiliaryFilters,
        )
        assertEquals("Pouch is referenced by the ND wheel.", listOf(kitId, pouchId), saved.restoredCandidateFilterSetIds(moved))
        assertEquals("Only the CPL's contribution is gone.", savedStops - 1.5, restored.effectiveStops, 1e-9)
    }

    /** FILTER-ITEM-009 at restore: an auxiliary item moved to a Set the
     *  camera does not select restores unmounted, without selecting that
     *  Set; moved to a selected Set, it restores under it. */
    @Test fun aMovedAuxiliaryItemRestoresOnlyUnderASelectedSet() {
        val moved = FilterInventory(listOf(kit.copy(items = listOf(nd8, red)), pouch.copy(items = listOf(cpl))))

        val unselected = saved.restoredFilterStack(moved)
        assertEquals(listOf(MountedAuxiliaryFilter(kitId, red.id, AuxiliaryFilterChoice.RegisteredLoss)), unselected.auxiliaryFilters)
        assertEquals("The destination is not selected.", listOf(kitId), saved.restoredCandidateFilterSetIds(moved))

        val withPouch = saved.copy(candidateFilterSetIds = listOf(kitId.rawValue, pouchId.rawValue))
        assertEquals(
            setOf(MountedAuxiliaryFilter(pouchId, cpl.id, cplAt15), MountedAuxiliaryFilter(kitId, red.id, AuxiliaryFilterChoice.RegisteredLoss)),
            withPouch.restoredFilterStack(moved).auxiliaryFilters.toSet(),
        )
    }

    @Test fun aKindChangeMovesTheSelectionIntoTheItemsNewRole() {
        // Red becomes an ND filter; ND8 becomes an Effect filter.
        val edited = FilterInventory(
            listOf(
                kit.copy(
                    items = listOf(
                        nd8.copy(behavior = FilterItemBehavior.Effect(FilterExposureLoss(3.0))),
                        cpl,
                        red.copy(behavior = FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops))),
                    ),
                ),
                pouch,
            ),
        )

        val restored = saved.restoredFilterStack(edited)

        assertTrue("${restored.wheels}", ndWheel(kitId, red) in restored.wheels)
        assertFalse(restored.wheels.any { it.mountedItemId == nd8.id })
        assertEquals(
            setOf(MountedAuxiliaryFilter(kitId, cpl.id, cplAt15), MountedAuxiliaryFilter(kitId, nd8.id, AuxiliaryFilterChoice.RegisteredLoss)),
            restored.auxiliaryFilters.toSet(),
        )
    }

    @Test fun aDeletedItemKeepsTheDeletionRules() {
        val deleted = FilterInventory(listOf(kit.copy(items = listOf(red)), pouch))

        val restored = saved.restoredFilterStack(deleted)

        assertTrue("A deleted wheel item reads Empty.", FilterWheel.empty(kitId) in restored.wheels)
        assertEquals(
            "A deleted auxiliary item is unmounted.",
            listOf(MountedAuxiliaryFilter(kitId, red.id, AuxiliaryFilterChoice.RegisteredLoss)),
            restored.auxiliaryFilters,
        )
    }
}
