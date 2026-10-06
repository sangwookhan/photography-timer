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
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.slots.CameraSlotId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A Shooting Filters session across inventory edits made from a Set
 * editor opened in it (FILTER-FLOW-003, FILTER-ITEM-006/009,
 * FILTER-PERSIST-002): working-only picks that no longer resolve are
 * dropped without a replacement, a committed change is followed item by
 * item, a moved item stays picked only under a Set the session selects,
 * and every unrelated draft pick, unmount, and choice stays.
 * (iOS: `ShootingFiltersSessionReconciliationTests`.)
 */
class ShootingFiltersSessionReconciliationTest {

    private val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
    private val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
    private val night = FilterItem("Night", FilterItemBehavior.Effect(FilterExposureLoss(1.0)))
    private val kit = FilterSet("Kit", FilterSetColor.teal, listOf(cpl, red))
    private val pouch = FilterSet("Pouch", FilterSetColor.orange, listOf(night))

    /** The camera selects Kit, and Pouch too when [pouchSelected], and
     *  mounts [committed]. */
    private fun controller(
        committed: List<MountedAuxiliaryFilter> = emptyList(),
        pouchSelected: Boolean = false,
    ): Pair<CalculatorController, FilterInventoryModel> {
        val model = FilterInventoryModel(initial = FilterInventory(listOf(kit, pouch)), persistenceWriter = PersistenceWriter { it() })
        val c = CalculatorController(films = emptyList(), inventoryModel = model)
        assertNull(c.applyShootingFilters(if (pouchSelected) listOf(kit.id, pouch.id) else listOf(kit.id), committed))
        return c to model
    }

    private fun mount(set: FilterSet, item: FilterItem, choice: AuxiliaryFilterChoice = AuxiliaryFilterChoice.RegisteredLoss) =
        MountedAuxiliaryFilter(set.id, item.id, choice)

    private fun session(c: CalculatorController) =
        ShootingFiltersSession(c.state.value.candidateFilterSetIds, c.state.value.mountedAuxiliaryFilters)

    /**
     * Makes [change], an inventory edit made from the screen, and runs what
     * the screen runs on it: a rebase when the committed state changed and
     * a reconcile when the inventory changed. Both orders must agree, and
     * [ShootingFiltersSession.followed], which the screen runs, must agree
     * with them.
     */
    private fun edit(s: ShootingFiltersSession, c: CalculatorController, model: FilterInventoryModel, change: () -> Unit): ShootingFiltersSession {
        fun committed() = c.state.value.candidateFilterSetIds to c.state.value.mountedAuxiliaryFilters.toSet()
        val committedBefore = committed()
        val inventoryBefore = model.inventory.value
        change()
        val inventory = model.inventory.value
        val rebase = { w: ShootingFiltersSession ->
            if (committed() == committedBefore) w
            else w.rebased(c.state.value.candidateFilterSetIds, c.state.value.mountedAuxiliaryFilters, inventory)
        }
        val reconcile = { w: ShootingFiltersSession -> if (inventory == inventoryBefore) w else w.reconciled(inventory) }
        val rebasedFirst = reconcile(rebase(s))
        assertEquals("The order of the two triggers does not matter.", rebasedFirst, rebase(reconcile(s)))
        val followed = s.followed(c.state.value.candidateFilterSetIds, c.state.value.mountedAuxiliaryFilters, inventory)
        assertEquals("followed, which the screen runs, agrees.", rebasedFirst, followed)
        assertEquals("Running it again changes nothing.", followed, followed.followed(c.state.value.candidateFilterSetIds, c.state.value.mountedAuxiliaryFilters, inventory))
        return rebasedFirst
    }

    private fun canApply(s: ShootingFiltersSession, c: CalculatorController) =
        s.hasChanges && c.shootingFiltersRejection(s.selectedFilterSetIds, s.mounts) == null

    // --- working-only picks ---

    @Test fun deletingAWorkingOnlyPickDropsItAndKeepsTheOtherPicks() {
        val (c, model) = controller()
        var s = session(c)
            .withMount(cpl.id, mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)))
            .withMount(red.id, mount(kit, red))

        s = edit(s, c, model) { c.deleteFilterItem(cpl.id) }
        assertTrue("The camera never committed the pick.", c.state.value.mountedAuxiliaryFilters.isEmpty())

        assertEquals(listOf(mount(kit, red)), s.mounts)
        assertTrue("No hidden stale pick blocks Apply.", canApply(s, c))
    }

    @Test fun deletingAWorkingOnlySetDropsItsSelectionAndPicks() {
        val (c, model) = controller()
        var s = session(c).withSelected(pouch.id, true).withMount(night.id, mount(pouch, night))

        s = edit(s, c, model) { c.deleteFilterSet(pouch.id) }

        assertEquals(listOf(kit.id), s.selectedFilterSetIds)
        assertTrue(s.mounts.isEmpty())
        assertFalse("Nothing is left to apply.", s.hasChanges)
        assertNull("The deleted Set's pick does not come back.", s.withSelected(pouch.id, true).mount(night.id))
    }

    @Test fun removingTheWorkingChoiceOfACplDropsThePickWithoutAReplacement() {
        val (c, model) = controller()
        var s = session(c)
            .withMount(cpl.id, mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(2.0)))
            .withMount(red.id, mount(kit, red))

        val edited = cpl.copy(behavior = FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, null))))
        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(edited, kit.id)) }

        assertNull("A removed choice is never replaced by another.", s.mount(cpl.id))
        assertEquals(listOf(mount(kit, red)), s.mounts)
        assertTrue(canApply(s, c))
    }

    // --- moves (FILTER-ITEM-009) ---

    @Test fun aWorkingOnlyPickMovedToAnAvailableSetIsClearedForGood() {
        val (c, model) = controller()
        var s = session(c).withMount(red.id, mount(kit, red)).withMount(cpl.id, mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)))

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(red, pouch.id)) }

        assertNull("Moved to an unselected Set: unchecked.", s.mount(red.id))
        assertEquals("The destination is not selected.", listOf(kit.id), s.selectedFilterSetIds)
        assertEquals("Unrelated picks stay.", mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), s.mount(cpl.id))
        assertTrue("No stale reference blocks Apply.", canApply(s, c))
        assertNull("Selecting the destination later does not bring it back.", s.withSelected(pouch.id, true).mount(red.id))
    }

    @Test fun aWorkingOnlyPickMovedToASelectedSetKeepsItsChoiceThere() {
        val (c, model) = controller()
        var s = session(c).withSelected(pouch.id, true).withMount(cpl.id, mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(2.0)))

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, pouch.id)) }

        assertEquals("Selected only in the session: it follows.", mount(pouch, cpl, AuxiliaryFilterChoice.CplLoss(2.0)), s.mount(cpl.id))
        assertTrue(canApply(s, c))
    }

    // --- committed changes ---

    /** A kind correction of a committed CPL to a Color filter: the camera
     *  remounts it with the Color filter's choice, and the session follows
     *  whichever of its two triggers runs first. */
    @Test fun aCommittedKindChangeIsFollowedInEitherOrder() {
        val (c, model) = controller(listOf(mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5))))
        var s = session(c)

        val asColor = cpl.copy(behavior = FilterItemBehavior.Color(FilterExposureLoss(1.0), FilterSetColor.yellow))
        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(asColor, kit.id)) }

        assertEquals(listOf(mount(kit, asColor)), c.state.value.mountedAuxiliaryFilters)
        assertEquals("The session keeps the remounted filter.", mount(kit, asColor), s.mount(cpl.id))
        assertFalse("Apply would change nothing.", s.hasChanges)
    }

    @Test fun aCommittedPickWhoseItemIsDeletedLeavesInEitherOrder() {
        val (c, model) = controller(listOf(mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(kit, red)))
        var s = session(c)

        s = edit(s, c, model) { c.deleteFilterItem(cpl.id) }

        assertEquals(listOf(mount(kit, red)), s.mounts)
        assertFalse(s.hasChanges)
    }

    @Test fun aCommittedPickMovedToAnAvailableSetIsUncheckedOnTheCameraAndInTheSession() {
        val (c, model) = controller(listOf(mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(kit, red)))
        var s = session(c).withMount(red.id, null)

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, pouch.id)) }

        assertEquals("The camera unmounts it.", listOf(mount(kit, red)), c.state.value.mountedAuxiliaryFilters)
        assertEquals("The camera does not select the destination.", listOf(kit.id), c.state.value.candidateFilterSetIds)
        assertNull(s.mount(cpl.id))
        assertNull("The draft unmount stays.", s.mount(red.id))
        assertEquals(listOf(kit.id), s.selectedFilterSetIds)
        assertNull("Selecting the destination later does not bring it back.", s.withSelected(pouch.id, true).mount(cpl.id))

        // Cancel: the move and the camera's unmount stay.
        assertEquals(cpl, model.inventory.value.filterSet(pouch.id)?.item(cpl.id))
        assertEquals(listOf(mount(kit, red)), c.state.value.mountedAuxiliaryFilters)
    }

    @Test fun aCommittedPickMovedToASetOnlyTheSessionSelectsStaysPickedThere() {
        val (c, model) = controller(listOf(mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5))))
        var s = session(c).withSelected(pouch.id, true).withMount(night.id, mount(pouch, night))

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, pouch.id)) }

        assertTrue("The camera does not select Pouch, so it unmounts the CPL.", c.state.value.mountedAuxiliaryFilters.isEmpty())
        assertEquals("The session selects Pouch, so the CPL stays picked.", mount(pouch, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), s.mount(cpl.id))
        assertEquals("The draft pick stays.", mount(pouch, night), s.mount(night.id))
        assertNull(c.applyShootingFilters(s.selectedFilterSetIds, s.mounts))
        assertEquals(
            setOf(mount(pouch, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(pouch, night)),
            c.state.value.mountedAuxiliaryFilters.toSet(),
        )
        assertEquals(listOf(kit.id, pouch.id), c.state.value.candidateFilterSetIds)
    }

    @Test fun aCommittedMoveBetweenSelectedSetsKeepsUnrelatedDraftPicksAndUnmounts() {
        val (c, model) = controller(listOf(mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(kit, red)), pouchSelected = true)
        var s = session(c).withMount(red.id, null).withMount(night.id, mount(pouch, night))

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, pouch.id)) }

        assertEquals("The committed move is followed.", mount(pouch, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), s.mount(cpl.id))
        assertNull("The draft unmount stays.", s.mount(red.id))
        assertEquals("The draft pick stays.", mount(pouch, night), s.mount(night.id))
        assertTrue(canApply(s, c))
        assertEquals(
            setOf(mount(pouch, cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(kit, red)),
            c.state.value.mountedAuxiliaryFilters.toSet(),
        )
    }

    @Test fun aCommittedMoveBetweenSelectedSetsKeepsTheDraftChoice() {
        val (c, model) = controller(listOf(mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(1.5))), pouchSelected = true)
        var s = session(c).withMount(cpl.id, mount(kit, cpl, AuxiliaryFilterChoice.CplLoss(2.0)))

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(cpl, pouch.id)) }

        assertEquals(mount(pouch, cpl, AuxiliaryFilterChoice.CplLoss(2.0)), s.mount(cpl.id))
    }

    @Test fun aCommittedChangeKeepsThePicksOfASetRemovedInTheSession() {
        val (c, model) = controller(listOf(mount(kit, red)))
        val bag = c.createFilterSet("Bag", FilterSetColor.blue)!!
        c.arrangeCandidateFilterSets(listOf(kit.id, bag.id))
        var s = session(c)
            .withSelected(pouch.id, true)
            .withMount(night.id, mount(pouch, night))
            .withSelected(pouch.id, false)

        s = edit(s, c, model) { assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(red, bag.id)) }
        assertEquals(mount(bag, red), s.mount(red.id))

        s = s.withSelected(pouch.id, true)
        assertEquals("Adding the Set back restores its pick.", mount(pouch, night), s.mount(night.id))
        assertTrue(mount(pouch, night) in s.mounts)
    }

}
