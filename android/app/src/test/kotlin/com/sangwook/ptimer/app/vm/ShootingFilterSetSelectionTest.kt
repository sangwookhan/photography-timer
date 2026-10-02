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
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
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
 * of the working selection; filter-first registration into a new or an
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

    @Test fun severalSelectedSetsOfferTheirGroupedUnionInTheSelectedSetsOrder() {
        val small = FilterSet("52mm", FilterSetColor.red, listOf(cpl, red, nd8))
        val big = FilterSet("82mm", FilterSetColor.blue, listOf(gnd, night))
        val (c, _) = controller(small, big)
        assertEquals("A fresh camera starts with no selected Set.", emptyList<FilterSetId>(), c.state.value.candidateFilterSetIds)

        // What Shooting Filters lists: each Selected Set's strip, in the
        // order the Selected Sets are shown.
        fun offered(selected: List<FilterSetId>) =
            c.displayedSelectedFilterSets(selected).flatMap { FilterSetItemOrder.ordered(it.auxiliaryItems) }
        assertEquals("ND items are never offered here.", listOf(red, cpl), offered(listOf(small.id)))
        assertEquals("Grouped by set, each in Color, Effect, CPL, GND order.", listOf(red, cpl, night, gnd), offered(listOf(small.id, big.id)))
        assertEquals(
            "A mixed Set precedes an auxiliary-only one whatever the selection order (FILTER-SET-004).",
            listOf(red, cpl, night, gnd),
            offered(listOf(big.id, small.id)),
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
        assertEquals("Applied in the order the sets were added.", listOf(big.id, small.id), c.state.value.candidateFilterSetIds)
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

        assertFalse("Its group is hidden at once.", c.displayedSelectedFilterSets(working.selectedFilterSetIds).any { it.id == kit.id })
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
        assertEquals("Not committed yet.", emptyList<FilterSetId>(), c.state.value.candidateFilterSetIds)
        assertNull(apply(c, working))
        assertEquals(listOf(kit.id), c.state.value.candidateFilterSetIds)
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

    /** FILTER-ITEM-009, FILTER-FLOW-004: with no Set yet, a filter
     *  saves with the New Filter Set made for it, which neither selects
     *  the Set for the camera nor mounts the filter; an inline Set made
     *  from the editor works the same way. */
    @Test fun filterFirstRegistrationSavesIntoANewOrInlineSetWithoutSelectingIt() {
        val (c, model) = controller()
        assertTrue("No built-in Set.", model.inventory.value.filterSets.isEmpty())

        val proposed = c.createFilterSet("New Filter Set", FilterSetColor.red, red)!!
        assertEquals(listOf(red), model.inventory.value.filterSet(proposed.id)!!.items)
        assertTrue("Registration does not select the Set.", c.state.value.candidateFilterSetIds.isEmpty())
        assertTrue("Registration mounts nothing.", c.state.value.mountedAuxiliaryFilters.isEmpty())

        val inline = c.createFilterSet("52mm", FilterSetColor.red)
        assertNotNull(inline)
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, inline!!.id))
        assertEquals(listOf(cpl), model.inventory.value.filterSet(inline.id)!!.items)
        assertEquals(listOf(proposed.id, inline.id), model.inventory.value.filterSets.map { it.id })
        assertTrue("Creating a set does not select it.", c.state.value.candidateFilterSetIds.isEmpty())
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
    }

    @Test fun globalDeletionRemovesTheSetAndReconcilesTheCamera() {
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red))
        val (c, model) = controller(kit)
        assertNull(c.applyShootingFilters(listOf(kit.id), listOf(mount(kit, red))))
        c.selectSlot(CameraSlotId.camera2)
        assertTrue("Selection is per camera; a fresh one has none.", c.state.value.candidateFilterSetIds.isEmpty())
        c.selectSlot(CameraSlotId.camera1)

        c.deleteFilterSet(kit.id)
        assertNull("Deleting is the inventory action.", model.inventory.value.filterSet(kit.id))
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
        assertTrue(c.state.value.candidateFilterSetIds.isEmpty())
    }

    /** FILTER-CAMERA-001: every fresh camera starts with no selected Set,
     *  and the Samples stay unselected; an emptied selection stays empty
     *  across a restore. */
    @Test fun aFreshCameraStartsWithNoSelectedSet() {
        val samples = FilterInventorySamples.inventory("Sample ND", "Sample ND — Extended", "Sample Aux Filter Set")
        val (c, model) = controller(*samples.filterSets.toTypedArray())
        assertTrue("Samples are not selected.", c.state.value.candidateFilterSetIds.isEmpty())
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
        assertEquals("Standard stays available on its own.", listOf(FilterWheelSelection.Standard(0.0)), wheels(c))
        c.selectSlot(CameraSlotId.camera3)
        assertTrue("Every fresh camera starts the same way.", c.state.value.candidateFilterSetIds.isEmpty())
        c.selectSlot(CameraSlotId.camera1)

        assertNull(c.applyShootingFilters(listOf(samples.filterSets.first().id), emptyList()))
        assertNull(c.applyShootingFilters(emptyList(), emptyList()))
        val restored = CalculatorController(films = emptyList(), initialSession = c.exportSession(), inventoryModel = model)
        assertTrue("An emptied selection stays empty.", restored.state.value.candidateFilterSetIds.isEmpty())
    }

    @Test fun selectedSetsKeepTheirOrderAndAvailableSetsReadByName() {
        val zeta = FilterSet("Zeta", FilterSetColor.red)
        val alpha = FilterSet("alpha", FilterSetColor.blue)
        val ten = FilterSet("Filter 10", FilterSetColor.teal)
        val nine = FilterSet("Filter 9", FilterSetColor.teal)
        val (c, _) = controller(zeta, alpha, ten, nine)
        var working = session(c)
        assertTrue(c.selectedFilterSets(working.selectedFilterSetIds).isEmpty())
        assertEquals(
            "By name, case ignored; creation order never matters.",
            listOf(alpha.id, ten.id, nine.id, zeta.id),
            c.availableFilterSets(working.selectedFilterSetIds).map { it.id },
        )

        // The trailing add control appends; the leading remove control
        // moves a set back among the Available Sets by name.
        working = working.withSelected(zeta.id, true).withSelected(alpha.id, true)
        working = working.withSelected(nine.id, true)
        assertEquals(listOf(zeta.id, alpha.id, nine.id), c.selectedFilterSets(working.selectedFilterSetIds).map { it.id })
        assertEquals(listOf(ten.id), c.availableFilterSets(working.selectedFilterSetIds).map { it.id })
        working = working.withSelected(nine.id, false)
        assertEquals(listOf(zeta.id, alpha.id), c.selectedFilterSets(working.selectedFilterSetIds).map { it.id })
        assertEquals(listOf(ten.id, nine.id), c.availableFilterSets(working.selectedFilterSetIds).map { it.id })
        assertTrue("Nothing is committed before Apply.", c.state.value.candidateFilterSetIds.isEmpty())

        assertNull(apply(c, working))
        assertEquals(listOf(zeta.id, alpha.id), c.state.value.candidateFilterSetIds)
        assertEquals("Reopening keeps the order.", listOf(zeta.id, alpha.id), session(c).selectedFilterSetIds)
    }

    @Test fun anEmptySelectedSetOffersAnAddFilterRowAndAFilledOneAHeaderControl() {
        assertEquals(SelectedFilterSetAddFilterPlacement.fullWidthRow, SelectedFilterSetAddFilterPlacement.of(FilterSet("Empty", FilterSetColor.red)))
        assertEquals(SelectedFilterSetAddFilterPlacement.headerControl, SelectedFilterSetAddFilterPlacement.of(FilterSet("ND only", FilterSetColor.blue, listOf(nd8))))
        assertEquals(SelectedFilterSetAddFilterPlacement.headerControl, SelectedFilterSetAddFilterPlacement.of(FilterSet("Kit", FilterSetColor.teal, listOf(red))))
    }

    @Test fun selectedFiltersListEveryFilterWithItsWholeNameKindAndContribution() {
        val soft = FilterItem("Soft GND 2", FilterItemBehavior.Gnd(FilterRegisteredValue(2.0, FilterValueUnit.stops)))
        val hard = FilterItem("Hard GND 3", FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops)))
        val marumi = FilterItem("MARUMI Red R2X1 72mm", FilterItemBehavior.Color(FilterExposureLoss(1.0), FilterSetColor.red))
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red, cpl, soft, hard, marumi))
        val (c, _) = controller(kit)
        assertEquals("Nothing selected.", emptyList<SelectedFilterRowDisplayState>(), c.selectedFilterRows(emptyList()))
        val rows = c.selectedFilterRows(
            listOf(
                mount(kit, soft),
                mount(kit, hard, AuxiliaryFilterChoice.Gnd(GndCalculationMode.applyFullValue)),
                mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)),
                mount(kit, red),
                mount(kit, marumi),
            ),
        )
        assertEquals("Every filter, in Main's order, with its whole name.", listOf("Red 25A", "MARUMI Red R2X1 72mm", "CPL", "Soft GND 2", "Hard GND 3"), rows.map { it.name })
        assertEquals(listOf(FilterItemKind.color, FilterItemKind.color, FilterItemKind.cpl, FilterItemKind.gnd, FilterItemKind.gnd), rows.map { it.kind })
        assertEquals(listOf(3.0, 1.0, 1.5, 0.0, 3.0), rows.map { it.contributionStops })
        assertEquals(listOf(null, null, null, GndCalculationMode.recordOnly, GndCalculationMode.applyFullValue), rows.map { it.gndMode })
        assertEquals(listOf(FilterSetColor.red, FilterSetColor.red, null, null, null), rows.map { it.opticalColor })
    }

    @Test fun selectedSetsShowGroupedByContentsInSelectionOrderAndRegroupAtOnce() {
        val wide = FilterItem("77mm", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
        val auxA = FilterSet("Aux A", FilterSetColor.red, listOf(red))
        val empty = FilterSet("Empty", FilterSetColor.green)
        val ndOnly = FilterSet("ND only", FilterSetColor.blue, listOf(nd8))
        val auxB = FilterSet("Aux B", FilterSetColor.pink, listOf(wide))
        val nd64 = FilterItem("ND64", FilterItemBehavior.Fixed(FilterRegisteredValue(6.0, FilterValueUnit.stops)))
        val mixed = FilterSet("Mixed", FilterSetColor.teal, listOf(nd64, cpl))
        val bag = FilterSet("Bag", FilterSetColor.blue)
        val (c, model) = controller(auxA, empty, ndOnly, auxB, mixed, bag)
        val selection = listOf(auxA.id, bag.id, empty.id, ndOnly.id, auxB.id, mixed.id)
        assertEquals(
            "ND-only, mixed, auxiliary-only, empty; selection order within a group.",
            listOf(ndOnly.id, mixed.id, auxA.id, auxB.id, bag.id, empty.id),
            c.displayedSelectedFilterSets(selection).map { it.id },
        )
        assertEquals("The selection order itself is unchanged.", selection, c.selectedFilterSets(selection).map { it.id })

        model.relocateItem(wide, empty.id)
        assertEquals(
            "A moved item regroups both sets at once.",
            listOf(ndOnly.id, mixed.id, auxA.id, empty.id, bag.id, auxB.id),
            c.displayedSelectedFilterSets(selection).map { it.id },
        )
        model.addItem(FilterItem("ND1000", FilterItemBehavior.Fixed(FilterRegisteredValue(10.0, FilterValueUnit.stops))), auxA.id)
        assertEquals(
            "Gaining an ND filter makes a set mixed; selection order decides within the group.",
            listOf(ndOnly.id, auxA.id, mixed.id, empty.id, bag.id, auxB.id),
            c.displayedSelectedFilterSets(selection).map { it.id },
        )
    }

    @Test fun everySetWithNdFiltersShowsTheNdCue() {
        assertFalse("An empty set has its Add Filter row.", FilterSet("Empty", FilterSetColor.red).showsNdCue)
        assertTrue(FilterSet("ND only", FilterSetColor.blue, listOf(nd8)).showsNdCue)
        assertTrue("A mixed set shows it beside its strip.", FilterSet("Mixed", FilterSetColor.green, listOf(nd8, red)).showsNdCue)
        assertFalse("No ND filter, no cue.", FilterSet("Kit", FilterSetColor.teal, listOf(cpl)).showsNdCue)
    }

    @Test fun aMountOverThirtyStopsIsRefusedAtOnceAndTheSessionStays() {
        val soft = FilterItem("Soft GND 3", FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops)))
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(soft, red))
        val (c, _) = controller(kit)
        val wheel = c.state.value.filterWheels.first()
        c.setNdWheelActive(wheel.id, true)
        c.setNdWheelValue(wheel.id, wheel.rows.indexOfFirst { it.selection == FilterWheelSelection.Standard(30.0) })
        c.setNdWheelActive(wheel.id, false)
        val start = ShootingFiltersSession(listOf(kit.id), emptyList())

        val recordOnly = (c.shootingFiltersSessionSettingMount(start, soft.id, mount(kit, soft)) as ShootingFiltersMountChange.Accepted).session
        assertEquals("A Record-only GND mounts at 30 stops.", listOf(mount(kit, soft)), recordOnly.mounts)
        assertEquals(
            "Applying its value would pass 30 stops.",
            ShootingFiltersMountChange.Refused(FilterStackRejection.exceedsTotalLimit),
            c.shootingFiltersSessionSettingMount(recordOnly, soft.id, mount(kit, soft, AuxiliaryFilterChoice.Gnd(GndCalculationMode.applyFullValue))),
        )
        assertEquals(ShootingFiltersMountChange.Refused(FilterStackRejection.exceedsTotalLimit), c.shootingFiltersSessionSettingMount(recordOnly, red.id, mount(kit, red)))
        assertEquals(
            "Unmounting is always accepted.",
            emptyList<MountedAuxiliaryFilter>(),
            (c.shootingFiltersSessionSettingMount(recordOnly, soft.id, null) as ShootingFiltersMountChange.Accepted).session.mounts,
        )
        assertEquals("No ND wheel changes.", 1, c.state.value.filterWheels.size)
    }

    @Test fun aMountBesideFourKeptNdWheelsIsRefusedUntilASetReleasesOne() {
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(red))
        val holder = FilterSet("Holder", FilterSetColor.blue, listOf(nd8))
        val (c, _) = controller(kit, holder)
        c.setCandidateFilterSets(listOf(kit.id, holder.id))
        c.addFilterWheel(FilterSource.FilterSet(holder.id))
        c.addFilterWheel(FilterSource.Standard)
        c.addFilterWheel(FilterSource.Standard)
        assertEquals(4, c.state.value.filterWheels.size)
        var working = ShootingFiltersSession(listOf(kit.id, holder.id), emptyList())

        assertEquals(ShootingFiltersMountChange.Refused(FilterStackRejection.tooManyNDWheels), c.shootingFiltersSessionSettingMount(working, red.id, mount(kit, red)))
        assertEquals("No committed ND wheel is removed to fit the mount.", 4, c.state.value.filterWheels.size)

        working = working.withSelected(holder.id, false)
        val released = c.shootingFiltersSessionSettingMount(working, red.id, mount(kit, red))
        assertTrue("Removing the Holder set frees its wheel for Apply.", released is ShootingFiltersMountChange.Accepted)
        assertEquals("Nothing is committed before Apply.", 4, c.state.value.filterWheels.size)
    }

    @Test fun movingAnItemToAnotherSetKeepsItsIdAndEveryCameraReference() {
        val bag = FilterSet("Bag", FilterSetColor.blue)
        val kit = FilterSet("Kit", FilterSetColor.teal)
        val (c, model) = controller(bag, kit)
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(red, bag.id))
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(nd8, bag.id))
        val bagSet = model.inventory.value.filterSet(bag.id)!!

        // Camera 1 mounts Red and an ND8 wheel from Bag; camera 2,
        // active while the items move, mounts Red only.
        c.setCandidateFilterSets(listOf(bag.id))
        assertNull(c.applyAuxiliaryFilters(listOf(mount(bagSet, red))))
        c.addFilterWheel(FilterSource.FilterSet(bag.id))
        val wheel = c.state.value.filterWheels.first { it.source == FilterSource.FilterSet(bag.id) }
        val row = wheel.rows.indexOfFirst { it.selection == FilterWheelSelection.Item(FilterRowSelection(nd8.id, FilterRowChoice.Fixed)) }
        c.setNdWheelValue(wheel.id, row)
        c.setNdWheelActive(wheel.id, false)
        val cameraOneWheels = wheels(c)
        c.selectSlot(CameraSlotId.camera2)
        c.setCandidateFilterSets(listOf(bag.id))
        assertNull(c.applyAuxiliaryFilters(listOf(mount(bagSet, red))))

        val renamed = red.copy(name = "Red 25A Hoya")
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(renamed, kit.id))
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(nd8, kit.id))
        assertEquals("The same items, with their ids.", listOf(red.id, nd8.id), model.inventory.value.filterSet(kit.id)!!.items.map { it.id })
        assertTrue(model.inventory.value.filterSet(bag.id)!!.items.isEmpty())

        // The active camera keeps Red under Kit; Kit joins its sets and
        // Bag stays.
        assertEquals(listOf(MountedAuxiliaryFilter(kit.id, red.id, AuxiliaryFilterChoice.RegisteredLoss)), c.state.value.mountedAuxiliaryFilters)
        assertEquals(listOf(bag.id, kit.id), c.state.value.candidateFilterSetIds)

        // The inactive camera kept both references the same way.
        c.selectSlot(CameraSlotId.camera1)
        assertEquals(listOf(kit.id), c.state.value.mountedAuxiliaryFilters.map { it.filterSetId })
        assertTrue("The ND8 wheel follows its item.", c.state.value.filterWheels.any { it.source == FilterSource.FilterSet(kit.id) })
        assertEquals(cameraOneWheels, wheels(c))
        assertEquals(listOf(bag.id, kit.id), c.state.value.candidateFilterSetIds)
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
    }

    private fun ndSet(name: String, nd: Int, auxiliary: Boolean = false) = FilterSet(
        name,
        FilterSetColor.teal,
        List(nd) { FilterItem("ND${it + 1}", FilterItemBehavior.Fixed(FilterRegisteredValue((it + 1).toDouble(), FilterValueUnit.stops))) } +
            if (auxiliary) listOf(FilterItem("Red", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))) else emptyList(),
    )

    private fun plusSource(c: CalculatorController): FilterSource = c.state.value.plus.let { it.sources[it.selectedIndex].source }

    /** Full touch cycle on one wheel: grab, settle on [selection], release. */
    private fun commit(c: CalculatorController, wheel: Int, selection: FilterWheelSelection) {
        val state = c.state.value.filterWheels[wheel]
        c.setNdWheelActive(state.id, true)
        c.setNdWheelValue(state.id, state.rows.indexOfFirst { it.selection == selection })
        c.setNdWheelActive(state.id, false)
    }

    @Test fun preferredNdSourceRanksByCountThenNdOnlyThenNameThenSelectionOrder() {
        val two = ndSet("Two", 2)
        val three = ndSet("Three", 3)
        val mixedThree = ndSet("A mixed", 3, auxiliary = true)
        val auxOnly = ndSet("Aux", 0, auxiliary = true)
        val beta = ndSet("Beta", 1)
        val alpha = ndSet("alpha", 1)
        val sameA = ndSet("Same", 1)
        val sameB = ndSet("Same", 1)

        assertEquals("Most registered ND items wins.", three.id, PreferredNdSource.winner(listOf(two, three)))
        assertEquals("On a tie an ND-only Set beats a mixed one.", three.id, PreferredNdSource.winner(listOf(mixedThree, three)))
        assertEquals("Then the name, locale-aware.", alpha.id, PreferredNdSource.winner(listOf(beta, alpha)))
        assertEquals("Equal names keep the selection order.", sameB.id, PreferredNdSource.winner(listOf(sameB, sameA)))
        assertNull("A Set without ND items is not eligible.", PreferredNdSource.winner(listOf(auxOnly)))
        assertNull(PreferredNdSource.winner(emptyList()))
    }

    @Test fun applyAddingSetsWhilePlusIsStandardPrefersTheWinnerAndEmptiesZeroStandardWheels() {
        val small = ndSet("Small", 1)
        val big = ndSet("Big", 2)
        val (c, _) = controller(small, big)
        c.addFilterWheel()
        commit(c, 1, FilterWheelSelection.Standard(2.0))
        c.addFilterWheel()
        val before = wheels(c)
        assertEquals(2, before.count { it == FilterWheelSelection.Standard(0.0) })
        assertEquals(FilterSource.Standard, plusSource(c))
        val idsBefore = c.state.value.filterWheels.map { it.id }
        val sourcesBefore = c.state.value.filterWheels.map { it.source }
        val totalBefore = c.state.value.ndTotalStopsText

        assertNull(c.applyShootingFilters(listOf(small.id, big.id), emptyList()))

        assertEquals("Plus remembers the preferred Set.", FilterSource.FilterSet(big.id), plusSource(c))
        assertEquals(
            "Standard 0 wheels become Empty wheels of that Set in place; the non-zero Standard wheel stays.",
            before.map { if (it == FilterWheelSelection.Standard(0.0)) FilterWheelSelection.Empty else it },
            wheels(c),
        )
        assertEquals(
            before.zip(sourcesBefore) { selection, source -> if (selection == FilterWheelSelection.Standard(0.0)) FilterSource.FilterSet(big.id) else source },
            c.state.value.filterWheels.map { it.source },
        )
        assertEquals("Wheel identities are kept.", idsBefore, c.state.value.filterWheels.map { it.id })
        assertEquals("Nothing is mounted; the total is unchanged.", totalBefore, c.state.value.ndTotalStopsText)

        c.selectSlot(CameraSlotId.camera2)
        assertEquals("Another camera keeps its own source.", FilterSource.Standard, plusSource(c))
        assertEquals(listOf(FilterWheelSelection.Standard(0.0)), wheels(c))
    }

    @Test fun preferredSourceAlsoTakesTheFallbackWheelAndSurvivesARestore() {
        val old = ndSet("Old", 1)
        val fresh = ndSet("Fresh", 1)
        val (c, model) = controller(old, fresh)
        c.setCandidateFilterSets(listOf(old.id))
        c.addFilterWheel(FilterSource.FilterSet(old.id))
        commit(c, 1, FilterWheelSelection.Item(FilterRowSelection(old.items[0].id, FilterRowChoice.Fixed)))
        val standardWheel = { c.state.value.filterWheels.first { it.source == FilterSource.Standard }.id }
        c.removeNdWheelFromOverscroll(standardWheel())
        c.addFilterWheel(FilterSource.Standard)
        c.removeNdWheelFromOverscroll(standardWheel())
        assertEquals(listOf(FilterSource.FilterSet(old.id)), c.state.value.filterWheels.map { it.source })
        assertEquals(FilterSource.Standard, plusSource(c))

        assertNull(c.applyShootingFilters(listOf(fresh.id), emptyList()))
        assertEquals("The Standard 0 fallback Apply adds becomes an Empty wheel of the winner.", listOf(FilterWheelSelection.Empty), wheels(c))
        assertEquals(listOf(FilterSource.FilterSet(fresh.id)), c.state.value.filterWheels.map { it.source })
        assertEquals(FilterSource.FilterSet(fresh.id), plusSource(c))

        val restored = CalculatorController(films = emptyList(), initialSession = c.exportSession(), inventoryModel = model)
        assertEquals("The remembered source survives a restore.", FilterSource.FilterSet(fresh.id), plusSource(restored))
        assertEquals(listOf(FilterWheelSelection.Empty), wheels(restored))
        assertEquals(listOf(FilterSource.FilterSet(fresh.id)), restored.state.value.filterWheels.map { it.source })
    }

    /** Standard 2, a Standard 0, and a Kit ND wheel in the settled order,
     *  Plus on Standard, and an auxiliary-only Pouch not selected yet. */
    private fun conversionScenario(): Triple<CalculatorController, FilterSet, FilterSet> {
        val kit = ndSet("Kit", 1)
        val pouch = ndSet("Pouch", 0, auxiliary = true)
        val (c, _) = controller(kit, pouch)
        commit(c, 0, FilterWheelSelection.Standard(2.0))
        c.setCandidateFilterSets(listOf(kit.id))
        c.addFilterWheel(FilterSource.FilterSet(kit.id))
        commit(c, 1, kitNd(kit))
        c.addFilterWheel(FilterSource.Standard)
        // A commit settles the new Standard 0 into the Standard group.
        commit(c, 0, FilterWheelSelection.Standard(2.0))
        assertEquals(
            listOf(FilterWheelSelection.Standard(2.0), FilterWheelSelection.Standard(0.0), kitNd(kit)),
            wheels(c),
        )
        assertEquals(FilterSource.Standard, plusSource(c))
        return Triple(c, kit, pouch)
    }

    private fun kitNd(kit: FilterSet) = FilterWheelSelection.Item(FilterRowSelection(kit.items[0].id, FilterRowChoice.Fixed))

    /** FILTER-PLUS-006 with FILTER-STACK-005: the converted Empty wheel
     *  joins its Set's group after the Set's non-empty rows, and every
     *  wheel keeps its identity through the move. */
    @Test fun theConvertedEmptyWheelTakesTheSettledOrderWithItsIdentity() {
        val (c, kit, pouch) = conversionScenario()
        val ids = c.state.value.filterWheels.map { it.id }

        assertNull(c.applyShootingFilters(listOf(kit.id, pouch.id), emptyList()))

        assertEquals(FilterSource.FilterSet(kit.id), plusSource(c))
        assertEquals(listOf(FilterWheelSelection.Standard(2.0), kitNd(kit), FilterWheelSelection.Empty), wheels(c))
        assertEquals(
            listOf(FilterSource.Standard, FilterSource.FilterSet(kit.id), FilterSource.FilterSet(kit.id)),
            c.state.value.filterWheels.map { it.source },
        )
        assertEquals("Identity follows each wheel.", listOf(ids[0], ids[2], ids[1]), c.state.value.filterWheels.map { it.id })
    }

    /** FILTER-A11Y-006: while the screen reader orders the wheels, Apply
     *  keeps the current positions; the one reconciliation on resume
     *  settles them. */
    @Test fun theConversionKeepsPositionsWhileTheScreenReaderOrdersThenReconcilesOnce() {
        val (c, kit, pouch) = conversionScenario()
        c.setFilterStackOrderingSuspended(true)
        val ids = c.state.value.filterWheels.map { it.id }

        assertNull(c.applyShootingFilters(listOf(kit.id, pouch.id), emptyList()))
        assertEquals(listOf(FilterWheelSelection.Standard(2.0), FilterWheelSelection.Empty, kitNd(kit)), wheels(c))
        assertEquals(ids, c.state.value.filterWheels.map { it.id })

        c.setFilterStackOrderingSuspended(false)
        assertEquals(listOf(FilterWheelSelection.Standard(2.0), kitNd(kit), FilterWheelSelection.Empty), wheels(c))
        assertEquals(listOf(ids[0], ids[2], ids[1]), c.state.value.filterWheels.map { it.id })
    }

    /** Checking a session allocates no wheel identity; only a successful
     *  Apply does. */
    @Test fun checkingASessionAllocatesNoWheelIdentity() {
        val kit = ndSet("Kit", 1)
        fun camera(): CalculatorController {
            val (c, _) = controller(kit)
            // Plus moves to Kit and the Standard 0 wheel becomes Kit's Empty wheel.
            assertNull(c.applyShootingFilters(listOf(kit.id), emptyList()))
            assertEquals(listOf(FilterSource.FilterSet(kit.id)), c.state.value.filterWheels.map { it.source })
            return c
        }
        val checked = camera()
        val unchecked = camera()

        // Leaving Kit out would need a fresh Standard 0 wheel.
        repeat(3) { assertNull(checked.shootingFiltersRejection(emptyList(), emptyList())) }

        assertNull(checked.applyShootingFilters(emptyList(), emptyList()))
        assertNull(unchecked.applyShootingFilters(emptyList(), emptyList()))
        assertEquals(unchecked.state.value.filterWheels.map { it.id }, checked.state.value.filterWheels.map { it.id })
        checked.addFilterWheel(FilterSource.Standard)
        unchecked.addFilterWheel(FilterSource.Standard)
        assertEquals(unchecked.state.value.filterWheels.map { it.id }, checked.state.value.filterWheels.map { it.id })
    }

    @Test fun noPreferenceWithoutAnAddedNdSetOrWhenPlusAlreadyNamesASet() {
        val kit = ndSet("Kit", 2)
        val other = ndSet("Other", 3)
        val aux = ndSet("Aux", 0, auxiliary = true)
        val (c, _) = controller(kit, other, aux)

        assertNull(c.applyShootingFilters(listOf(aux.id), emptyList()))
        assertEquals("No selected Set holds ND: Standard stays.", FilterSource.Standard, plusSource(c))
        assertEquals(listOf(FilterWheelSelection.Standard(0.0)), wheels(c))

        assertNull(c.applyShootingFilters(listOf(aux.id, kit.id), emptyList()))
        assertEquals(FilterSource.FilterSet(kit.id), plusSource(c))

        assertNull(c.applyShootingFilters(listOf(aux.id, kit.id, other.id), emptyList()))
        assertEquals("Plus already names a Set: it is kept.", FilterSource.FilterSet(kit.id), plusSource(c))

        c.addFilterWheel(FilterSource.Standard)
        assertEquals(FilterSource.Standard, plusSource(c))
        val before = wheels(c)
        assertNull(c.applyShootingFilters(c.state.value.candidateFilterSetIds, listOf(mount(aux, aux.items[0]))))
        assertEquals("An auxiliary-only change adds no Set and keeps Standard.", FilterSource.Standard, plusSource(c))
        assertEquals(before, wheels(c))
    }

    @Test fun availableSetContentsHintCountsRegisteredItemsByKindInFixedOrder() {
        val nd64 = FilterItem("ND64", FilterItemBehavior.Fixed(FilterRegisteredValue(6.0, FilterValueUnit.stops)))
        val nd1000 = FilterItem("ND1000", FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor)))
        val yellow = FilterItem("Yellow", FilterItemBehavior.Color(FilterExposureLoss(1.0), FilterSetColor.yellow))
        val kit = FilterSet("Kit", FilterSetColor.teal, listOf(cpl, red, nd8, night, nd64, nd1000, yellow))

        assertEquals(
            "ND, Color, Effect, CPL, GND order; absent kinds left out; CPL counts one item, not its three choices.",
            listOf(
                FilterSetContentsHint.Entry(FilterItemKind.fixed, 3),
                FilterSetContentsHint.Entry(FilterItemKind.color, 2),
                FilterSetContentsHint.Entry(FilterItemKind.effect, 1),
                FilterSetContentsHint.Entry(FilterItemKind.cpl, 1),
            ),
            FilterSetContentsHint.entries(kit),
        )
        assertEquals(emptyList<FilterSetContentsHint.Entry>(), FilterSetContentsHint.entries(FilterSet("Empty", FilterSetColor.green)))
        assertEquals(
            "The hint follows the set's items.",
            listOf(FilterSetContentsHint.Entry(FilterItemKind.fixed, 3), FilterSetContentsHint.Entry(FilterItemKind.color, 2), FilterSetContentsHint.Entry(FilterItemKind.effect, 1)),
            FilterSetContentsHint.entries(kit.copy(items = kit.items - cpl)),
        )
    }
}
