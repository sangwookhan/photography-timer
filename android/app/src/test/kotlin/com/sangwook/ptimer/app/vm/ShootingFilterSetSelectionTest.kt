// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.AuxiliaryFilterChoice
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterExposureLoss
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.slots.CameraSlotId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Shooting Filters workflow at Spec PR #70 `0c5bbc9d`
 * (FILTER-AUX-003, FILTER-CAMERA-001/003, FILTER-FLOW-003..005,
 * FILTER-ITEM-009, FILTER-SET-001/002/006): one working session over the
 * camera's Filter Set selection and auxiliary mounts, committed together
 * by Apply and dropped by Cancel; the offered list as the grouped union
 * of the working selection; filter-first registration into Default or an
 * inline set; inventory edits that stay immediate; and global deletion
 * kept apart from the camera selection.
 * (iOS: `ShootingFilterSetSelectionTests`.)
 */
class ShootingFilterSetSelectionTest {

    private val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
    private val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
    private val gnd = FilterItem("Soft GND", FilterItemBehavior.Gnd(FilterRegisteredValue(0.6, FilterValueUnit.opticalDensity)))
    private val night = FilterItem("Night", FilterItemBehavior.Effect(FilterExposureLoss(1.0)))
    private val nd8 = FilterItem("ND8", FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops)))

    private fun controller(vararg sets: FilterSet): Pair<CalculatorController, FilterInventoryModel> {
        val model = FilterInventoryModel(initial = FilterInventory(sets.toList()), persistenceWriter = PersistenceWriter { it() })
        return CalculatorController(films = emptyList(), inventoryModel = model) to model
    }

    private fun wheels(c: CalculatorController): List<FilterWheelSelection> =
        c.state.value.filterWheels.map { it.rows[it.committedIndex].selection }

    private fun mount(set: FilterSet, item: FilterItem, choice: AuxiliaryFilterChoice? = null) =
        MountedAuxiliaryFilter(set.id, item.id, choice ?: MountedAuxiliaryFilter.initialChoice(item) ?: AuxiliaryFilterChoice.RegisteredLoss)

    private fun session(c: CalculatorController) =
        ShootingFiltersSession(c.state.value.candidateFilterSetIds, c.state.value.mountedAuxiliaryFilters)

    private fun apply(c: CalculatorController, s: ShootingFiltersSession) = c.applyShootingFilters(s.selectedFilterSetIds, s.mounts)

    @Test fun severalSelectedSetsOfferTheirGroupedUnionAndFollowTheWorkingSelectionAndSetOrder() {
        val small = FilterSet("52mm", FilterSetColor.red, listOf(cpl, red, nd8))
        val big = FilterSet("82mm", FilterSetColor.blue, listOf(gnd, night))
        val (c, _) = controller(small, big)
        assertEquals("A fresh camera starts with Default selected.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)

        assertEquals("ND items are never offered here.", listOf(red, cpl), c.offeredAuxiliaryItems(listOf(small.id)).map { it.second })
        assertEquals(
            "Grouped by set, each in Color, Effect, CPL, GND order.",
            listOf(red, cpl, night, gnd),
            c.offeredAuxiliaryItems(listOf(small.id, big.id)).map { it.second },
        )
        assertEquals(
            "The groups follow the selection order.",
            listOf(night, gnd, red, cpl),
            c.offeredAuxiliaryItems(listOf(big.id, small.id)).map { it.second },
        )
    }

    @Test fun auxiliaryFiltersFromDifferentSelectedSetsApplyTogetherWithTheSetSelection() {
        val small = FilterSet("52mm", FilterSetColor.red, listOf(cpl, red))
        val big = FilterSet("82mm", FilterSetColor.blue, listOf(gnd))
        val (c, _) = controller(small, big)
        val wheelsBefore = wheels(c)
        val working = session(c)
            .withSelected(big.id, true)
            .withSelected(small.id, true)
            .withMount(gnd.id, mount(big, gnd))
            .withMount(cpl.id, mount(small, cpl, AuxiliaryFilterChoice.CplLoss(1.5)))
            .withMount(red.id, mount(small, red))
        assertTrue("Working changes commit nothing.", c.state.value.mountedAuxiliaryFilters.isEmpty())

        assertNull(apply(c, working))
        assertEquals("Applied in the order the sets were added.", listOf(FilterSetId.defaultSet, big.id, small.id), c.state.value.candidateFilterSetIds)
        assertEquals(setOf(red.id, cpl.id, gnd.id), c.state.value.mountedAuxiliaryFilters.map { it.itemId }.toSet())
        assertEquals("Selecting sets changes no ND wheel.", wheelsBefore, wheels(c))
        assertEquals("Red 3 + CPL 1.5 + Record-only GND 0.", 4.5, c.auxiliaryFiltersSubtotal(working.mounts), 1e-9)
    }

    /** A camera using Kit (Red mounted, an ND8 wheel) and Other (CPL). */
    private fun usedSetFixture(): Triple<CalculatorController, FilterInventoryModel, Pair<FilterSet, FilterSet>> {
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red, nd8))
        val other = FilterSet("Other", FilterSetColor.blue, listOf(cpl))
        val (c, model) = controller(kit, other)
        c.setCandidateFilterSets(listOf(kit.id, other.id))
        assertNull(c.applyAuxiliaryFilters(listOf(mount(kit, red), mount(other, cpl, AuxiliaryFilterChoice.CplLoss(1.5)))))
        c.addFilterWheel(FilterSource.FilterSet(kit.id))
        val kitWheel = c.state.value.filterWheels.indexOfFirst { it.source == FilterSource.FilterSet(kit.id) }
        val row = c.state.value.filterWheels[kitWheel].rows.indexOfFirst {
            it.selection == FilterWheelSelection.Item(FilterRowSelection(nd8.id, FilterRowChoice.Fixed))
        }
        c.setNdWheelValue(c.state.value.filterWheels[kitWheel].id, row)
        c.setNdWheelActive(c.state.value.filterWheels[kitWheel].id, false)
        assertTrue(c.isFilterSetInUseOnActiveCamera(kit.id))
        return Triple(c, model, kit to other)
    }

    @Test fun uncheckingAUsedSetChangesNothingCommittedBeforeApply() {
        val (c, _, sets) = usedSetFixture()
        val kit = sets.first
        val before = c.state.value
        val working = session(c).withSelected(kit.id, false)

        assertFalse("Its group is hidden at once.", c.offeredAuxiliaryItems(working.selectedFilterSetIds).any { it.first.id == kit.id })
        assertEquals(before.candidateFilterSetIds, c.state.value.candidateFilterSetIds)
        assertEquals(before.mountedAuxiliaryFilters, c.state.value.mountedAuxiliaryFilters)
        assertEquals(before.filterWheels, c.state.value.filterWheels)
        assertTrue("Still in use until Apply.", c.isFilterSetInUseOnActiveCamera(kit.id))
        assertNull(c.shootingFiltersRejection(working.selectedFilterSetIds, working.mounts))
    }

    @Test fun addingARemovedSetBackRestoresItsRetainedWorkingSelectionsAtTheEnd() {
        val (c, _, sets) = usedSetFixture()
        val (kit, other) = sets
        var working = session(c)
        val redMount = working.mount(red.id)
        val cplMount = working.mount(cpl.id)
        assertNotNull(redMount)

        // The last Selected Set removed and added back: back where it
        // started.
        working = working.withSelected(other.id, false)
        assertFalse("Hidden while removed.", working.mounts.any { it.itemId == cpl.id })
        working = working.withSelected(other.id, true)
        assertEquals(cplMount, working.mount(cpl.id))
        assertFalse("Back where it started.", working.hasChanges)

        // Another set added back goes to the end of the Selected Sets
        // with its picks; the new order is a change to apply.
        working = working.withSelected(kit.id, false)
        assertFalse("Hidden while removed.", working.mounts.any { it.itemId == red.id })
        working = working.withSelected(kit.id, true)
        assertEquals(listOf(other.id, kit.id), working.selectedFilterSetIds)
        assertEquals(redMount, working.mount(red.id))
        assertTrue("The selection order changed.", working.hasChanges)
    }

    @Test fun aSetOnlyChangeOffersApply() {
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red))
        val (c, _) = controller(kit)
        val start = session(c)
        assertFalse(start.hasChanges)

        val working = start.withSelected(kit.id, true)
        assertTrue("Adding a set alone is a change to apply.", working.hasChanges)
        assertEquals("Not committed yet.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
        assertNull(apply(c, working))
        assertEquals("Appended after Default.", listOf(FilterSetId.defaultSet, kit.id), c.state.value.candidateFilterSetIds)
        assertTrue("Selecting a set mounts nothing.", c.state.value.mountedAuxiliaryFilters.isEmpty())
    }

    @Test fun applyRemovesTheUncheckedSetsFiltersAndNdWheelsAndPersistsTheSelection() {
        val (c, model, sets) = usedSetFixture()
        val (kit, other) = sets
        val standard = c.state.value.filterWheels.first { it.source == FilterSource.Standard }
        c.removeNdWheelFromOverscroll(standard.id)
        assertEquals("Only the set's wheel is left.", listOf(FilterSource.FilterSet(kit.id)), c.state.value.filterWheels.map { it.source })

        assertNull("Apply asks for nothing more.", apply(c, session(c).withSelected(kit.id, false)))
        assertEquals(listOf(other.id), c.state.value.candidateFilterSetIds)
        assertEquals("Another set's mount stays.", listOf(cpl.id), c.state.value.mountedAuxiliaryFilters.map { it.itemId })
        assertEquals("One Standard 0-stop wheel is left.", listOf(FilterWheelSelection.Standard(0.0)), wheels(c))
        assertFalse(c.isFilterSetInUseOnActiveCamera(kit.id))
        assertEquals("The set and its items stay in the inventory.", kit, model.inventory.value.filterSet(kit.id))

        val restored = CalculatorController(films = emptyList(), initialSession = c.exportSession(), inventoryModel = model)
        assertEquals("The applied selection is persisted.", listOf(other.id), restored.state.value.candidateFilterSetIds)
        assertEquals(listOf(cpl.id), restored.state.value.mountedAuxiliaryFilters.map { it.itemId })
    }

    @Test fun cancellingASessionLeavesTheCameraAsItWas() {
        val (c, _, sets) = usedSetFixture()
        val before = c.state.value
        val working = session(c)
            .withSelected(sets.first.id, false)
            .withMount(cpl.id, null)
            .withSelected(FilterSetId.defaultSet, true)
        assertTrue(working.hasChanges)

        // Cancel: the session is dropped without Apply.
        assertEquals(before.candidateFilterSetIds, c.state.value.candidateFilterSetIds)
        assertEquals(before.mountedAuxiliaryFilters, c.state.value.mountedAuxiliaryFilters)
        assertEquals(before.filterWheels, c.state.value.filterWheels)
    }

    @Test fun inventoryEditsDuringASessionStayDespiteCancel() {
        val (c, model, sets) = usedSetFixture()
        val kit = sets.first
        var working = session(c).withSelected(kit.id, false)

        // Inventory edits from a set editor opened in the session are
        // immediate.
        val created = c.createFilterSet("Pouch", FilterSetColor.orange)
        assertNotNull(created)
        c.renameFilterSet(kit.id, "Kit 2")
        c.deleteFilterSet(created!!.id)
        working = working.rebased(
            c.state.value.candidateFilterSetIds,
            c.state.value.mountedAuxiliaryFilters,
            model.inventory.value.filterSets.map { it.id }.toSet(),
        )
        assertFalse("A deleted set leaves the working selection.", working.isSelected(created.id))

        // Cancel drops the session; the inventory edits stay.
        assertEquals("Kit 2", model.inventory.value.filterSet(kit.id)!!.name)
        assertNull(model.inventory.value.filterSet(created.id))
        assertTrue("The camera selection is unchanged.", kit.id in c.state.value.candidateFilterSetIds)
    }

    @Test fun removingTheOnlyNdWheelsFallsBackToOneStandardWheel() {
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(nd8))
        val (c, _) = controller(kit)
        c.setCandidateFilterSets(listOf(kit.id))
        c.addFilterWheel(FilterSource.FilterSet(kit.id))
        val standard = c.state.value.filterWheels.first { it.source == FilterSource.Standard }
        c.removeNdWheelFromOverscroll(standard.id)
        assertEquals("Only the set's wheel is left.", listOf(FilterSource.FilterSet(kit.id)), c.state.value.filterWheels.map { it.source })

        assertNull(c.applyShootingFilters(emptyList(), emptyList()))
        assertEquals(listOf(FilterWheelSelection.Standard(0.0)), wheels(c))
    }

    @Test fun filterFirstRegistrationSavesIntoTheSelectedDefaultOrAnInlineSetWithoutSelectingIt() {
        val (c, model) = controller()
        assertEquals("Default exists before any set is created.", listOf(FilterSetId.defaultSet), model.inventory.value.filterSets.map { it.id })

        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(red, FilterSetId.defaultSet))
        assertEquals(listOf(red), model.inventory.value.filterSet(FilterSetId.defaultSet)!!.items)
        assertEquals("A fresh camera has Default selected, so its filter is offered at once.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
        assertEquals(listOf(red), c.offeredAuxiliaryItems(c.state.value.candidateFilterSetIds).map { it.second })

        // Add Filter Set from the editor's Filter Set field: the set is
        // created, then the in-progress filter saves into it.
        val inline = c.createFilterSet("52mm", FilterSetColor.red)
        assertNotNull(inline)
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, inline!!.id))
        assertEquals(listOf(cpl), model.inventory.value.filterSet(inline.id)!!.items)
        assertEquals(listOf(FilterSetId.defaultSet, inline.id), model.inventory.value.filterSets.map { it.id })
        assertEquals("Creating a set does not select it.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
    }

    @Test fun globalDeletionRemovesTheSetAndReconcilesTheCamera() {
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red))
        val (c, model) = controller(kit)
        assertNull(c.applyShootingFilters(listOf(kit.id), listOf(mount(kit, red))))
        c.selectSlot(CameraSlotId.camera2)
        assertEquals("Selection is per camera; a fresh one has Default.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
        c.selectSlot(CameraSlotId.camera1)

        c.deleteFilterSet(kit.id)
        assertNull("Deleting is the inventory action.", model.inventory.value.filterSet(kit.id))
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
        assertTrue(c.state.value.candidateFilterSetIds.isEmpty())

        assertNull(c.applyShootingFilters(listOf(FilterSetId.defaultSet), emptyList()))
        c.deleteFilterSet(FilterSetId.defaultSet)
        assertNotNull("Default is never deleted.", model.inventory.value.filterSet(FilterSetId.defaultSet))
        assertEquals(listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
    }

    @Test fun aFreshCameraStartsWithDefaultAndARemovedDefaultStaysRemoved() {
        val (c, model) = controller()
        assertEquals(listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
        c.selectSlot(CameraSlotId.camera3)
        assertEquals("Every fresh camera starts with Default.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)
        c.selectSlot(CameraSlotId.camera1)

        assertNull(c.applyShootingFilters(emptyList(), emptyList()))
        assertTrue("Default can be removed like any other set.", c.state.value.candidateFilterSetIds.isEmpty())
        val restored = CalculatorController(films = emptyList(), initialSession = c.exportSession(), inventoryModel = model)
        assertTrue("It does not come back as a fresh camera.", restored.state.value.candidateFilterSetIds.isEmpty())
        restored.selectSlot(CameraSlotId.camera3)
        assertEquals(listOf(FilterSetId.defaultSet), restored.state.value.candidateFilterSetIds)
    }

    @Test fun selectedSetsKeepTheirOrderAndAvailableSetsReadByName() {
        val zeta = FilterSet("Zeta", FilterSetColor.red)
        val alpha = FilterSet("alpha", FilterSetColor.blue)
        val ten = FilterSet("Filter 10", FilterSetColor.teal)
        val nine = FilterSet("Filter 9", FilterSetColor.teal)
        val (c, _) = controller(zeta, alpha, ten, nine)
        var working = session(c)
        assertEquals(listOf(FilterSetId.defaultSet), c.selectedFilterSets(working.selectedFilterSetIds).map { it.id })
        assertEquals(
            "By name, case ignored; creation order never matters.",
            listOf(alpha.id, ten.id, nine.id, zeta.id),
            c.availableFilterSets(working.selectedFilterSetIds).map { it.id },
        )

        // The trailing add control appends; the leading remove control
        // moves a set back among the Available Sets by name.
        working = working.withSelected(zeta.id, true).withSelected(alpha.id, true)
        assertEquals(listOf(FilterSetId.defaultSet, zeta.id, alpha.id), c.selectedFilterSets(working.selectedFilterSetIds).map { it.id })
        assertEquals(listOf(ten.id, nine.id), c.availableFilterSets(working.selectedFilterSetIds).map { it.id })
        working = working.withSelected(FilterSetId.defaultSet, false)
        assertEquals(listOf(zeta.id, alpha.id), c.selectedFilterSets(working.selectedFilterSetIds).map { it.id })
        assertEquals(listOf(FilterSetId.defaultSet, ten.id, nine.id), c.availableFilterSets(working.selectedFilterSetIds).map { it.id })
        assertEquals("Nothing is committed before Apply.", listOf(FilterSetId.defaultSet), c.state.value.candidateFilterSetIds)

        assertNull(apply(c, working))
        assertEquals(listOf(zeta.id, alpha.id), c.state.value.candidateFilterSetIds)
        assertEquals("Reopening keeps the order.", listOf(zeta.id, alpha.id), session(c).selectedFilterSetIds)
    }

    @Test fun anEmptySelectedSetOffersAnAddFilterRowAndAFilledOneAHeaderControl() {
        assertEquals(SelectedFilterSetAddFilterPlacement.fullWidthRow, SelectedFilterSetAddFilterPlacement.of(FilterSet("Empty", FilterSetColor.red)))
        assertEquals(SelectedFilterSetAddFilterPlacement.headerControl, SelectedFilterSetAddFilterPlacement.of(FilterSet("ND only", FilterSetColor.blue, listOf(nd8))))
        assertEquals(SelectedFilterSetAddFilterPlacement.headerControl, SelectedFilterSetAddFilterPlacement.of(FilterSet("Kit", FilterSetColor.teal, listOf(red))))
    }

    @Test fun selectedFiltersReadAsOneShortLineInMainsOrder() {
        val soft = FilterItem("Soft GND 2", FilterItemBehavior.Gnd(FilterRegisteredValue(2.0, FilterValueUnit.stops)))
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red, cpl, soft))
        val (c, _) = controller(kit)
        assertNull("Nothing selected.", c.selectedFiltersText(emptyList()))
        assertEquals(
            "Color, CPL, GND as on Main; a name's number never runs into the contribution.",
            "Red 3 · CPL 1.5 · Soft GND 0",
            c.selectedFiltersText(listOf(mount(kit, soft), mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(kit, red))),
        )
    }

    @Test fun movingAnItemOutOfDefaultKeepsItsIdAndEveryCameraReference() {
        val kit = FilterSet("Kit", FilterSetColor.teal)
        val (c, model) = controller(kit)
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(red, FilterSetId.defaultSet))
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(nd8, FilterSetId.defaultSet))
        val defaultSet = model.inventory.value.filterSet(FilterSetId.defaultSet)!!

        // Camera 1 mounts Red and an ND8 wheel from Default; camera 2,
        // active while the items move, mounts Red only.
        assertNull(c.applyAuxiliaryFilters(listOf(mount(defaultSet, red))))
        c.addFilterWheel(FilterSource.FilterSet(FilterSetId.defaultSet))
        val wheel = c.state.value.filterWheels.first { it.source == FilterSource.FilterSet(FilterSetId.defaultSet) }
        val row = wheel.rows.indexOfFirst { it.selection == FilterWheelSelection.Item(FilterRowSelection(nd8.id, FilterRowChoice.Fixed)) }
        c.setNdWheelValue(wheel.id, row)
        c.setNdWheelActive(wheel.id, false)
        val cameraOneWheels = wheels(c)
        c.selectSlot(CameraSlotId.camera2)
        assertNull(c.applyAuxiliaryFilters(listOf(mount(defaultSet, red))))

        val renamed = red.copy(name = "Red 25A Hoya")
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(renamed, kit.id))
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(nd8, kit.id))
        assertEquals("The same items, with their ids.", listOf(red.id, nd8.id), model.inventory.value.filterSet(kit.id)!!.items.map { it.id })
        assertTrue(model.inventory.value.filterSet(FilterSetId.defaultSet)!!.items.isEmpty())

        // The active camera keeps Red under Kit; Kit joins its sets and
        // Default stays.
        assertEquals(listOf(MountedAuxiliaryFilter(kit.id, red.id, AuxiliaryFilterChoice.RegisteredLoss)), c.state.value.mountedAuxiliaryFilters)
        assertEquals(listOf(FilterSetId.defaultSet, kit.id), c.state.value.candidateFilterSetIds)

        // The inactive camera kept both references the same way.
        c.selectSlot(CameraSlotId.camera1)
        assertEquals(listOf(kit.id), c.state.value.mountedAuxiliaryFilters.map { it.filterSetId })
        assertTrue("The ND8 wheel follows its item.", c.state.value.filterWheels.any { it.source == FilterSource.FilterSet(kit.id) })
        assertEquals(cameraOneWheels, wheels(c))
        assertEquals(listOf(FilterSetId.defaultSet, kit.id), c.state.value.candidateFilterSetIds)
    }

    @Test fun itemsReadNdFirstThenByKindAndNameWithoutManualOrder() {
        val nd400 = FilterItem("ND400", FilterItemBehavior.Fixed(FilterRegisteredValue(8.6, FilterValueUnit.stops)))
        val amber = FilterItem("amber", FilterItemBehavior.Color(FilterExposureLoss(1.0), FilterSetColor.orange))
        val stored = listOf(gnd, cpl, red, nd400, night, nd8, amber)
        val ordered = FilterSetItemOrder.ordered(stored)
        assertEquals(
            "ND, Color, Effect, CPL, GND; by name within a kind, case ignored; the stored order never matters.",
            listOf(nd400, nd8, amber, red, night, cpl, gnd).map { it.id },
            ordered.map { it.id },
        )
        assertEquals(ordered, FilterSetItemOrder.ordered(stored.reversed()))
        assertEquals(FilterItemKind.fixed, FilterSetItemOrder.newItemKind)
        assertEquals(listOf(FilterItemKind.color, FilterItemKind.effect, FilterItemKind.cpl, FilterItemKind.gnd), FilterSetItemOrder.auxiliaryKinds)
    }
}
