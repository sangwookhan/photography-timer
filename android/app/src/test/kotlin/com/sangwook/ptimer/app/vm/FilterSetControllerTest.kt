// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.PersistentFilterWheel
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.timer.TimerIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-221: the mixed Filter Stack on the Android controller — item
 * exclusivity and the 30-stop cap, the sighted fallback, source-group
 * ordering, per-camera Plus source memory, cleanup that respects usable
 * Empty wheels, inventory-edit reconciliation across cameras, the
 * assistive adjustment, screen-reader ordering suspension, and the
 * immutable timer capture. Ports the iOS
 * ExposureCalculatorViewModelFilterSetTests / …FilterFallbackTests at
 * controller level.
 */
class FilterSetControllerTest {

    // MARK: - inventory builders

    private fun stops(name: String, value: Double) = FilterItem(
        name,
        FilterItemBehavior.Fixed(FilterRegisteredValue(value, FilterValueUnit.stops)),
    )

    private fun ndFactor(name: String, factor: Double) = FilterItem(
        name,
        FilterItemBehavior.Fixed(FilterRegisteredValue(factor, FilterValueUnit.filterFactor)),
    )

    private fun gnd(name: String, opticalDensity: Double) = FilterItem(
        name,
        FilterItemBehavior.Gnd(FilterRegisteredValue(opticalDensity, FilterValueUnit.opticalDensity)),
    )

    private fun cpl(name: String, vararg choices: Double) = FilterItem(
        name,
        FilterItemBehavior.Cpl(CplExposureLossChoices(choices.toList())),
    )

    // MARK: - fixture

    private class Fixture(
        inventory: FilterInventory,
        session: PersistentSlotSession? = null,
    ) {
        val started = mutableListOf<Pair<Double, TimerIdentity>>()
        val model = FilterInventoryModel(
            initial = inventory,
            persistenceWriter = PersistenceWriter { it() },
        )

        /** Stands in for the app language; the controller reads it once
         *  per start, so a test can change it afterwards. */
        var vocabulary = FilterReferenceVocabulary.canonicalEnglish

        val controller = CalculatorController(
            films = emptyList(),
            onStart = { duration, identity -> started += duration to identity },
            initialSession = session,
            inventoryModel = model,
            referenceVocabulary = { vocabulary },
        )
    }

    private fun fixture(vararg sets: FilterSet) = Fixture(FilterInventory(sets.toList()))

    private fun source(set: FilterSet) = FilterSource.FilterSet(set.id)

    private fun itemSelection(item: FilterItem, choice: FilterRowChoice = FilterRowChoice.Fixed) =
        FilterWheelSelection.Item(FilterRowSelection(item.id, choice))

    // MARK: - stack helpers

    private fun wheels(c: CalculatorController) = c.state.value.filterWheels

    private fun committed(c: CalculatorController): List<FilterWheelSelection> =
        wheels(c).map { it.rows[it.committedIndex].selection }

    /** [CalculatorUiState.slotStates] is in `availableSlots` order. */
    private fun page(c: CalculatorController, slot: CameraSlotId) =
        c.state.value.slotStates[CameraSlotId.allOrdered.indexOf(slot)]

    private fun committed(c: CalculatorController, slot: CameraSlotId): List<FilterWheelSelection> =
        page(c, slot).filterWheels.map { it.rows[it.committedIndex].selection }

    private fun rowIndex(c: CalculatorController, wheel: Int, selection: FilterWheelSelection): Int =
        wheels(c)[wheel].rows.indexOfFirst { it.selection == selection }.also {
            require(it >= 0) { "row $selection is not offered by wheel $wheel" }
        }

    /** Full touch cycle on one wheel: grab, settle on [selection], release. */
    private fun commit(c: CalculatorController, wheel: Int, selection: FilterWheelSelection) {
        val id = wheels(c)[wheel].id
        c.setNdWheelActive(id, true)
        c.setNdWheelValue(id, rowIndex(c, wheel, selection))
        c.setNdWheelActive(id, false)
    }

    private fun standard(value: Double) = FilterWheelSelection.Standard(value)

    private fun total(c: CalculatorController) = c.state.value.filterStatus.totalStopsText

    private fun indexOfWheel(c: CalculatorController, id: Int) = wheels(c).indexOfFirst { it.id == id }

    /** First wheel whose committed row is Filter Set Empty. */
    private fun emptyWheel(c: CalculatorController) =
        wheels(c).indexOfFirst { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.also {
            require(it >= 0) { "no Empty Filter Set wheel in the stack" }
        }

    // MARK: - item exclusivity (FILTER-STACK-002, FILTER-CPL-005)

    @Test
    fun twoEqualItemsMountTogetherWhileASecondSelectionOfOneIsRejected() {
        val a = stops("A", 3.0)
        val b = stops("B", 3.0)
        val lee = FilterSet("Lee holder", FilterSetColor.indigo, listOf(a, b))
        val f = fixture(lee)
        f.controller.addFilterWheel(source(lee))
        f.controller.addFilterWheel(source(lee))

        val c = f.controller
        commit(c, emptyWheel(c), itemSelection(a))
        val bWheelId = wheels(c)[emptyWheel(c)].id
        commit(c, indexOfWheel(c, bWheelId), itemSelection(b))

        assertEquals("Two separate 3-stop items contribute 6 stops.", "6", total(c))
        assertTrue(committed(c).contains(itemSelection(a)))
        assertTrue(committed(c).contains(itemSelection(b)))

        // A second selection of A on B's wheel is refused with its reason.
        commit(c, indexOfWheel(c, bWheelId), itemSelection(a))
        assertEquals(
            FilterStackRejection.itemAlreadyMounted,
            c.state.value.filterStatus.rejection?.rejection,
        )
        assertEquals("6", total(c))
        assertTrue(committed(c).contains(itemSelection(b)))
    }

    // MARK: - source-group ordering (FILTER-STACK-005)

    @Test
    fun sourceGroupsSortByRegisteredSubtotalAndStayContiguous() {
        val bigStopper = ndFactor("Big Stopper", 1000.0)
        val nisi = FilterSet("NiSi kit", FilterSetColor.red, listOf(bigStopper))
        val nd8 = ndFactor("Lee ND8", 8.0)
        val leeCpl = cpl("Lee CPL", 1.0, 1.5, 2.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(nd8, leeCpl))
        val f = fixture(nisi, lee)
        val c = f.controller

        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(nisi))
        c.addFilterWheel(source(lee))
        c.addFilterWheel(source(lee))
        commit(c, indexOfWheel(c, wheels(c).first { it.source == source(nisi) }.id), itemSelection(bigStopper))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(nd8))
        commit(c, wheels(c).indexOfLast { it.source == source(lee) }, itemSelection(leeCpl, FilterRowChoice.CplLoss(1.0)))

        assertEquals(
            "NiSi (10) before Lee (3 + 1 = 4) before Standard (2), each group contiguous.",
            listOf(source(nisi), source(lee), source(lee), FilterSource.Standard),
            wheels(c).map { it.source },
        )
        assertEquals("16", total(c))
    }

    @Test
    fun addingAStandardWheelReturnsAGroupedAndSortedStack() {
        val threeStop = stops("Lee ND 3", 3.0)
        // A second, unmounted item keeps the source addable (FILTER-PLUS-005).
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(threeStop, stops("Soft", 1.0)))
        val f = fixture(lee)
        val c = f.controller

        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        commit(c, indexOfWheel(c, wheels(c).first { it.source == source(lee) }.id), itemSelection(threeStop))

        // The add is the LAST interaction: nothing scrolls afterwards.
        c.addFilterWheel(FilterSource.Standard)

        assertEquals(
            "Lee (3) first, then the two contiguous Standard wheels.",
            listOf(source(lee), FilterSource.Standard, FilterSource.Standard),
            wheels(c).map { it.source },
        )
        assertEquals(
            listOf(itemSelection(threeStop), standard(2.0), standard(0.0)),
            committed(c),
        )
        assertEquals("5", total(c))
    }

    @Test
    fun anAddedWheelJoinsItsSourceGroupImmediately() {
        val bigStopper = ndFactor("Big Stopper", 1000.0)
        // A second, unmounted item keeps the source addable (FILTER-PLUS-005).
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(bigStopper, stops("Soft", 1.0)))
        val f = fixture(lee)
        val c = f.controller

        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        commit(c, indexOfWheel(c, wheels(c).first { it.source == source(lee) }.id), itemSelection(bigStopper))
        assertEquals(listOf(source(lee), FilterSource.Standard), wheels(c).map { it.source })

        // Lee (10) outranks Standard (2): the added Empty wheel lands
        // inside the Lee group at once, with no further interaction.
        c.addFilterWheel(source(lee))
        assertEquals(
            "The new wheel joins the settled Lee group instead of trailing the stack.",
            listOf(source(lee), source(lee), FilterSource.Standard),
            wheels(c).map { it.source },
        )
        assertEquals(
            "Its own sort value is zero, so it sorts last inside its group.",
            listOf(itemSelection(bigStopper), FilterWheelSelection.Empty, standard(2.0)),
            committed(c),
        )
        assertEquals("12", total(c))
    }

    @Test
    fun anAddedWheelSortsLastInsideItsOwnGroup() {
        val f = fixture()
        val c = f.controller

        commit(c, 0, standard(2.0))
        c.addFilterWheel(FilterSource.Standard)
        commit(c, indexOfWheel(c, wheels(c)[1].id), standard(6.0))
        assertEquals(listOf(standard(6.0), standard(2.0)), committed(c))

        c.addFilterWheel(FilterSource.Standard)
        assertEquals(
            "Standard 0 is Empty-like, so it sorts last within Standard immediately.",
            listOf(standard(6.0), standard(2.0), standard(0.0)),
            committed(c),
        )
    }

    @Test
    fun anAdditionWhileOrderingIsSuspendedDefersToTheSingleReconciliation() {
        val bigStopper = ndFactor("Big Stopper", 1000.0)
        // A second, unmounted item keeps the source addable (FILTER-PLUS-005).
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(bigStopper, stops("Soft", 1.0)))
        val f = fixture(lee)
        val c = f.controller

        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        commit(c, indexOfWheel(c, wheels(c).first { it.source == source(lee) }.id), itemSelection(bigStopper))
        val big = wheels(c)[0].id
        val standardWheel = wheels(c)[1].id

        c.setFilterStackOrderingSuspended(true)
        c.addFilterWheel(source(lee))
        val added = wheels(c).last().id
        assertEquals(
            "FILTER-A11Y-006: membership changes, but no subtotal-based reorder runs.",
            listOf(source(lee), FilterSource.Standard, source(lee)),
            wheels(c).map { it.source },
        )
        assertEquals(listOf(big, standardWheel, added), wheels(c).map { it.id })

        c.setFilterStackOrderingSuspended(false)
        assertEquals(
            "One reconciliation sorts the deferred addition into its group.",
            listOf(big, added, standardWheel),
            wheels(c).map { it.id },
        )
        assertEquals(
            listOf(itemSelection(bigStopper), FilterWheelSelection.Empty, standard(2.0)),
            committed(c),
        )
    }

    @Test
    fun aGndModeSwitchChangesTheContributionButNotTheGroupPosition() {
        val leeGnd = gnd("Lee GND 0.9", 0.9)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(leeGnd))
        val f = fixture(lee)
        val c = f.controller

        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        val gndWheel = wheels(c).first { it.source == source(lee) }.id
        commit(
            c,
            indexOfWheel(c, gndWheel),
            itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
        )
        assertEquals(listOf(source(lee), FilterSource.Standard), wheels(c).map { it.source })
        assertEquals("5", total(c))

        commit(
            c,
            indexOfWheel(c, gndWheel),
            itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
        )
        assertEquals(
            "The registered full density sorts the wheel in BOTH modes, so it does not move.",
            listOf(source(lee), FilterSource.Standard),
            wheels(c).map { it.source },
        )
        assertEquals("2", total(c))
    }

    // MARK: - sighted fallback (FILTER-STACK-004)

    /** A Filter Set with 2-, 3-, and 4-stop items in wheel order. */
    private fun ladderSet(): Triple<FilterSet, List<FilterItem>, FilterSource> {
        val items = listOf(stops("Two", 2.0), stops("Three", 3.0), stops("Four", 4.0))
        val set = FilterSet("Lee holder", FilterSetColor.blue, items)
        return Triple(set, items, source(set))
    }

    @Test
    fun aSettleOnAMountedRowFallsBackToTheNearestTraversedSelectableRow() {
        val (set, items, src) = ladderSet()
        val f = fixture(set)
        val c = f.controller
        c.addFilterWheel(src)
        c.addFilterWheel(src)
        commit(c, 1, itemSelection(items[2]))
        val free = wheels(c).last { it.source == src && it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id

        commit(c, indexOfWheel(c, free), itemSelection(items[2]))

        assertEquals(
            "4 never commits; the wheel settles on the 3-stop row it just traversed.",
            itemSelection(items[1]),
            committed(c)[indexOfWheel(c, free)],
        )
        assertNull("A committed fallback leaves no rejection to show.", c.state.value.filterStatus.rejection)
        assertEquals("7", total(c))
    }

    /**
     * FILTER-STACK-004 / 007 / 008, spec owner's disposition of
     * 2026-09-24: once a sighted fallback commits, the wheel, its
     * persistent label, the status detail and the Total must all
     * describe the same committed row. The rejected candidate must not
     * survive into the settled status.
     *
     * Atomicity is what this asserts, and it is structural: all four
     * come from one immutable state emission, so they cannot disagree.
     * The test pins both sides of that emission — the candidate while
     * the wheel is still active, the committed row the moment it is
     * not — so a future change that let the candidate linger would have
     * to break one of the two.
     */
    @Test
    fun aCommittedFallbackLeavesNoTraceOfTheRejectedCandidate() {
        val (set, items, src) = ladderSet()
        val f = fixture(set)
        val c = f.controller
        c.addFilterWheel(src)
        c.addFilterWheel(src)
        commit(c, 1, itemSelection(items[2]))
        val free = wheels(c).last { it.source == src && it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id
        val freeIndex = indexOfWheel(c, free)

        // Mid-gesture: the status describes the candidate under the
        // touch center, including its contribution in the total.
        c.setNdWheelActive(free, true)
        c.setNdWheelValue(free, rowIndex(c, freeIndex, itemSelection(items[2])))
        assertEquals("Four", c.state.value.filterStatus.movingRow?.itemName)
        assertEquals("8", total(c))

        // Settle: the fallback commits the traversed 3-stop row.
        c.setNdWheelActive(free, false)

        val settled = c.state.value.filterStatus
        assertEquals(
            "The wheel holds the fallback row.",
            itemSelection(items[1]),
            committed(c)[freeIndex],
        )
        assertNotEquals(
            "The rejected candidate must not remain as settled status.",
            "Four",
            settled.movingRow?.itemName,
        )
        assertEquals(
            "The Total is the committed one, not the candidate's.",
            "7",
            settled.totalStopsText,
        )
        assertNull("A committed fallback leaves no rejection to show.", settled.rejection)
    }

    @Test
    fun theFallbackSkipsEveryUnavailableRowItTraverses() {
        val (set, items, src) = ladderSet()
        val f = fixture(set)
        val c = f.controller
        c.addFilterWheel(src)
        c.addFilterWheel(src)
        c.addFilterWheel(src)
        commit(c, 1, itemSelection(items[2]))
        commit(c, wheels(c).indexOfFirst { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }, itemSelection(items[1]))
        val free = wheels(c).first { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id

        commit(c, indexOfWheel(c, free), itemSelection(items[2]))

        assertEquals(
            "4 and 3 are both mounted elsewhere, so the settle lands on 2.",
            itemSelection(items[0]),
            committed(c)[indexOfWheel(c, free)],
        )
        assertEquals("9", total(c))
    }

    @Test
    fun noSelectableTraversedRowKeepsThePreviousSelectionAndShowsTheReason() {
        val (set, items, src) = ladderSet()
        val f = fixture(set)
        val c = f.controller
        c.addFilterWheel(src)
        c.addFilterWheel(src)
        commit(c, 1, itemSelection(items[0]))
        val free = wheels(c).last { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id

        // Empty and the mounted 2-stop row are adjacent: nothing lies
        // strictly between them, so the refusal stands.
        commit(c, indexOfWheel(c, free), itemSelection(items[0]))

        assertEquals(FilterWheelSelection.Empty, committed(c)[indexOfWheel(c, free)])
        assertEquals(
            FilterStackRejection.itemAlreadyMounted,
            c.state.value.filterStatus.rejection?.rejection,
        )
        assertEquals("2", total(c))
    }

    @Test
    fun theFallbackNeverSearchesBeyondTheAttemptedRowOrWraps() {
        val (set, items, src) = ladderSet()
        val f = fixture(set)
        val c = f.controller
        c.addFilterWheel(src)
        c.addFilterWheel(src)
        // Wheel A mounts the 3-stop item; wheel B settles on 2 stops.
        commit(c, 1, itemSelection(items[1]))
        val b = wheels(c).last { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id
        commit(c, indexOfWheel(c, b), itemSelection(items[0]))
        assertEquals("5", total(c))

        // From 2, attempting the mounted 3: the only interval is empty,
        // and the selectable 4-stop row BEYOND the attempt must not be
        // reached.
        commit(c, indexOfWheel(c, b), itemSelection(items[1]))

        assertEquals(itemSelection(items[0]), committed(c)[indexOfWheel(c, b)])
        assertEquals(
            FilterStackRejection.itemAlreadyMounted,
            c.state.value.filterStatus.rejection?.rejection,
        )
        assertEquals("5", total(c))
    }

    @Test
    fun anOverCapSettleFallsBackTheSameWay() {
        val items = listOf(stops("One", 1.0), stops("Two", 2.0), stops("Four", 4.0))
        val set = FilterSet("Lee holder", FilterSetColor.blue, items)
        val f = fixture(set)
        val c = f.controller
        commit(c, 0, standard(27.0))
        c.addFilterWheel(source(set))
        val free = wheels(c).first { it.source == source(set) }.id

        commit(c, indexOfWheel(c, free), itemSelection(items[2]))

        assertEquals(
            "4 would exceed 30; the settle lands on the 2-stop row it traversed.",
            itemSelection(items[1]),
            committed(c)[indexOfWheel(c, free)],
        )
        assertEquals("29", total(c))
    }

    @Test
    fun anAssistiveCommitGetsNoSightedFallback() {
        // Four Lee wheels: A mounts 2, E mounts 3, B holds 1, C is Empty.
        // While B is under a finger, two earlier pendings free the
        // 3-stop row and mount the 4-stop row, so by barrier time B's
        // attempted 4 is refused while the traversed 3 has become
        // selectable. A sighted settle takes that fallback; an assistive
        // adjustment — which traversed nothing — must not.
        fun build(assistive: Boolean): Triple<CalculatorController, List<FilterItem>, Int> {
            val items = listOf(stops("One", 1.0), stops("Two", 2.0), stops("Three", 3.0), stops("Four", 4.0))
            val set = FilterSet("Lee holder", FilterSetColor.blue, items)
            val f = fixture(set)
            val c = f.controller
            repeat(3) { c.addFilterWheel(source(set)) }
            // Drop the Standard wheel so all four wheels are Lee.
            c.removeNdWheelFromOverscroll(wheels(c).first { it.source == FilterSource.Standard }.id)
            c.addFilterWheel(source(set))
            commit(c, 0, itemSelection(items[1]))
            commit(c, wheels(c).indexOfFirst { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }, itemSelection(items[2]))
            commit(c, wheels(c).indexOfFirst { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }, itemSelection(items[0]))
            val b = wheels(c).first { it.rows[it.committedIndex].selection == itemSelection(items[0]) }.id
            val e = wheels(c).first { it.rows[it.committedIndex].selection == itemSelection(items[2]) }.id
            val empty = wheels(c).first { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id

            c.setNdWheelActive(b, true)
            c.setNdWheelValue(e, rowIndex(c, indexOfWheel(c, e), FilterWheelSelection.Empty))
            c.setNdWheelValue(empty, rowIndex(c, indexOfWheel(c, empty), itemSelection(items[3])))
            if (assistive) {
                c.adjustFilterWheel(b, FilterWheelAdjustmentDirection.increment)
            } else {
                c.setNdWheelValue(b, rowIndex(c, indexOfWheel(c, b), itemSelection(items[3])))
            }
            c.setNdWheelActive(b, false)
            return Triple(c, items, b)
        }

        val (sighted, sightedItems, sightedB) = build(assistive = false)
        assertEquals(
            "The sighted settle walks back to the 3-stop row the earlier pending freed.",
            itemSelection(sightedItems[2]),
            committed(sighted)[indexOfWheel(sighted, sightedB)],
        )
        assertNull(sighted.state.value.filterStatus.rejection)

        val (assistive, assistiveItems, assistiveB) = build(assistive = true)
        assertEquals(
            "The assistive commit traversed nothing, so it keeps its 1-stop selection.",
            itemSelection(assistiveItems[0]),
            committed(assistive)[indexOfWheel(assistive, assistiveB)],
        )
        assertEquals(
            FilterStackRejection.itemAlreadyMounted,
            assistive.state.value.filterStatus.rejection?.rejection,
        )
    }

    // MARK: - Plus source memory (FILTER-PLUS-003/004/005)

    @Test
    fun theRememberedSourceIsPerCameraAndAFreshCameraUsesStandard() {
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(stops("Three", 3.0)))
        val f = fixture(lee)
        val c = f.controller

        assertEquals(FilterSource.Standard, c.state.value.plus.sources[c.state.value.plus.selectedIndex].source)
        c.addFilterWheel(source(lee))
        assertEquals(source(lee), c.state.value.plus.sources[c.state.value.plus.selectedIndex].source)

        c.selectSlot(CameraSlotId.camera2)
        assertEquals(
            "A fresh camera remembers nothing and uses Standard.",
            FilterSource.Standard,
            c.state.value.plus.sources[c.state.value.plus.selectedIndex].source,
        )

        c.selectSlot(CameraSlotId.camera1)
        assertEquals(source(lee), c.state.value.plus.sources[c.state.value.plus.selectedIndex].source)
    }

    @Test
    fun aRefusedAddKeepsTheStackTheTotalAndTheRememberedSource() {
        val empty = FilterSet("Empty kit", FilterSetColor.brown)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(stops("Three", 3.0)))
        val f = fixture(lee, empty)
        val c = f.controller
        c.addFilterWheel(source(lee))
        val before = committed(c)

        c.addFilterWheel(source(empty))

        assertEquals(before, committed(c))
        assertEquals("0", total(c))
        assertEquals(
            "The memory only moves on a SUCCESSFUL addition.",
            source(lee),
            c.state.value.plus.sources[c.state.value.plus.selectedIndex].source,
        )
        assertEquals(
            FilterAddUnavailability.filterSetHasNoItems,
            c.state.value.filterStatus.rejection?.addUnavailability,
        )
    }

    @Test
    fun aFullStackRefusesAndReportsStackFull() {
        val f = fixture()
        val c = f.controller
        repeat(3) { c.addFilterWheel(FilterSource.Standard) }
        assertEquals(4, wheels(c).size)
        assertFalse(c.state.value.plus.isVisible)
        assertEquals(FilterAddUnavailability.stackFull, c.state.value.plus.addUnavailability)

        c.addFilterWheel(FilterSource.Standard)
        assertEquals(4, wheels(c).size)
        assertEquals(
            FilterAddUnavailability.stackFull,
            c.state.value.filterStatus.rejection?.addUnavailability,
        )
    }

    @Test
    fun aRecordOnlyItemKeepsItsSourceAddableAtThirtyStops() {
        val leeGnd = gnd("Lee GND 0.9", 0.9)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(leeGnd))
        val f = fixture(lee)
        val c = f.controller
        commit(c, 0, standard(30.0))

        assertNull(
            "A Record-only row fits a 0-stop budget, so the source stays addable.",
            c.filterAddUnavailability(source(lee)),
        )
        assertEquals(
            FilterAddUnavailability.noSelectableValue,
            c.filterAddUnavailability(FilterSource.Standard),
        )

        c.addFilterWheel(source(lee))
        assertEquals(2, wheels(c).size)
        assertEquals("30", total(c))
    }

    // MARK: - cleanup (FILTER-STACK-006)

    @Test
    fun cleanupRemovesEmptyWheelsButKeepsAMountedRecordOnlyGnd() {
        val leeGnd = gnd("Lee GND 0.9", 0.9)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(leeGnd))
        val f = fixture(lee)
        val c = f.controller
        commit(c, 0, standard(5.0))
        c.addFilterWheel(source(lee))
        c.addFilterWheel(source(lee))
        commit(
            c,
            wheels(c).indexOfFirst { it.source == source(lee) },
            itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
        )

        c.cleanupEmptyNdWheels()

        assertEquals(2, wheels(c).size)
        assertTrue(
            "A mounted Record-only item contributes 0 but is never cleaned up.",
            committed(c).contains(itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly))),
        )
        assertEquals("5", total(c))
    }

    @Test
    fun saturationShedsOnlyTheWheelThatCanHoldNoUsableRow() {
        val leeGnd = gnd("Lee GND 0.9", 0.9)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(leeGnd))
        val f = fixture(lee)
        val c = f.controller
        c.addFilterWheel(source(lee))
        c.addFilterWheel(FilterSource.Standard)

        commit(c, wheels(c).indexOfFirst { it.source == FilterSource.Standard }, standard(30.0))

        assertEquals(
            "The Standard 0 wheel can hold nothing at 30 stops and goes; the Empty " +
                "Lee wheel can still mount a Record-only GND and stays.",
            listOf(FilterSource.Standard, source(lee)),
            wheels(c).map { it.source },
        )
        assertEquals("30", total(c))
    }

    @Test
    fun onlyAnActualRemovalPublishesAnEvent() {
        val f = fixture()
        val c = f.controller
        c.addFilterWheel(FilterSource.Standard)
        commit(c, 0, standard(10.0))
        assertNull("Scheduling publishes nothing.", c.state.value.emptyWheelRemoval)

        assertTrue(c.runNdCleanupIfQuiet())
        val event = c.state.value.emptyWheelRemoval
        assertNotNull(event)
        assertEquals(1, event!!.removedCount)
        assertEquals(1, event.sequence)

        // Nothing left to remove: the no-op publishes no new event.
        c.cleanupEmptyNdWheels()
        assertFalse(c.runNdCleanupIfQuiet())
        assertEquals(event, c.state.value.emptyWheelRemoval)
    }

    // MARK: - inventory edits across cameras (FILTER-ITEM-005/006)

    @Test
    fun aGndModeSwitchDoesNotTouchAnotherCamera() {
        val leeGnd = gnd("Lee GND 0.9", 0.9)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(leeGnd))
        val f = fixture(lee)
        val c = f.controller
        val recordOnly = itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly))
        val full = itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue))

        c.selectSlot(CameraSlotId.camera2)
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, recordOnly)

        c.selectSlot(CameraSlotId.camera1)
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, full)

        assertTrue(committed(c).contains(full))
        assertTrue(
            "Camera 2 keeps its own per-shot mode.",
            committed(c, CameraSlotId.camera2).contains(recordOnly),
        )
    }

    @Test
    fun deletingAnItemEmptiesItsWheelsOnEveryCamera() {
        val item = stops("Three", 3.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))
        val f = fixture(lee)
        val c = f.controller
        for (slot in listOf(CameraSlotId.camera2, CameraSlotId.camera1)) {
            c.selectSlot(slot)
            c.addFilterWheel(source(lee))
            commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(item))
        }
        assertEquals(listOf("Camera 1", "Camera 2"), c.cameraNamesAffectedByDeletingItem(item.id).sorted())

        c.deleteFilterItem(item.id)

        assertTrue(committed(c).contains(FilterWheelSelection.Empty))
        assertTrue(committed(c, CameraSlotId.camera2).contains(FilterWheelSelection.Empty))
        assertEquals("0", total(c))
    }

    @Test
    fun deletingAFilterSetRemovesItsWheelsAndFallsBackToStandard() {
        val item = stops("Three", 3.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))
        val f = fixture(lee)
        val c = f.controller
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(item))
        // Leave the camera with ONLY the Filter Set wheel.
        c.removeNdWheelFromOverscroll(wheels(c).first { it.source == FilterSource.Standard }.id)
        assertEquals(listOf(source(lee)), wheels(c).map { it.source })
        assertEquals(listOf("Camera 1"), c.cameraNamesAffectedByDeletingFilterSet(lee.id))

        c.deleteFilterSet(lee.id)

        assertEquals(listOf(FilterSource.Standard), wheels(c).map { it.source })
        assertEquals(listOf(standard(0.0)), committed(c))
        assertEquals(
            "A deleted last-used source falls back to Standard.",
            FilterSource.Standard,
            c.state.value.plus.sources[c.state.value.plus.selectedIndex].source,
        )
    }

    @Test
    fun editingAnItemUpdatesEveryStackAndIsBlockedByTheCap() {
        val item = stops("Three", 3.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))
        val f = fixture(lee)
        val c = f.controller

        c.selectSlot(CameraSlotId.camera2)
        commit(c, 0, standard(27.0))
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(item))
        assertEquals("30", total(c))

        c.selectSlot(CameraSlotId.camera1)
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(item))
        assertEquals("3", total(c))

        val overCap = item.copy(
            behavior = FilterItemBehavior.Fixed(FilterRegisteredValue(5.0, FilterValueUnit.stops)),
        )
        assertEquals(
            FilterItemSaveOutcome.Blocked(listOf("Camera 2"), FilterItemSaveBlockReason.exceedsTotalLimit),
            c.saveFilterItem(overCap, lee.id),
        )
        assertEquals("A blocked save changes nothing.", "3", total(c))

        val withinCap = item.copy(
            behavior = FilterItemBehavior.Fixed(FilterRegisteredValue(2.0, FilterValueUnit.stops)),
        )
        assertEquals(FilterItemSaveOutcome.Saved, c.saveFilterItem(withinCap, lee.id))
        assertEquals("2", total(c))
        c.selectSlot(CameraSlotId.camera2)
        assertEquals("29", total(c))
    }

    @Test
    fun removingASelectedCplChoiceIsBlockedAndNamesEveryAffectedCamera() {
        val item = cpl("Lee CPL", 1.0, 1.5, 2.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))
        val f = fixture(lee)
        val c = f.controller
        val selected = itemSelection(item, FilterRowChoice.CplLoss(1.5))
        for (slot in listOf(CameraSlotId.camera2, CameraSlotId.camera1)) {
            c.selectSlot(slot)
            c.addFilterWheel(source(lee))
            commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, selected)
        }

        val outcome = c.saveFilterItem(
            item.copy(behavior = FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 2.0, null)))),
            lee.id,
        )

        assertEquals(
            FilterItemSaveOutcome.Blocked(
                listOf("Camera 1", "Camera 2"),
                FilterItemSaveBlockReason.removesSelectedChoice,
            ),
            outcome,
        )
        assertTrue("The selection is never silently replaced.", committed(c).contains(selected))
    }

    @Test
    fun changingAMountedItemsKindIsBlockedLikeARemovedRow() {
        val item = stops("Three", 3.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))
        val f = fixture(lee)
        val c = f.controller
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(item))

        val outcome = c.saveFilterItem(
            item.copy(behavior = FilterItemBehavior.Cpl(CplExposureLossChoices.defaults)),
            lee.id,
        )

        assertEquals(
            FilterItemSaveOutcome.Blocked(listOf("Camera 1"), FilterItemSaveBlockReason.removesSelectedChoice),
            outcome,
        )
        assertTrue(committed(c).contains(itemSelection(item)))
    }

    // MARK: - restore (FILTER-PERSIST-001/002)

    @Test
    fun aStalePersistedCplChoiceRestoresAsEmpty() {
        val item = cpl("Lee CPL", 1.0, 1.5, 2.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(item))
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(
                    shutterIndex = 10,
                    ndIndex = 0,
                    selectedFilmId = null,
                    selectedProfileId = null,
                    filterStack = listOf(
                        PersistentFilterWheel(
                            sourceKind = PersistentFilterWheel.FILTER_SET_SOURCE_KIND,
                            filterSetId = lee.id.rawValue,
                            itemId = item.id.rawValue,
                            rowKind = "cpl",
                            cplLossStops = 2.5,
                        ),
                    ),
                ),
            ),
            customNames = emptyMap(),
        )
        val f = Fixture(FilterInventory(listOf(lee)), session)

        assertEquals(
            "A configured choice that no longer exists restores as Empty, never as another choice.",
            listOf(FilterWheelSelection.Empty),
            committed(f.controller),
        )
        assertEquals(listOf(source(lee)), wheels(f.controller).map { it.source })
    }

    @Test
    fun aMixedStackRoundTripsThroughExportSession() {
        val bigStopper = ndFactor("Big Stopper", 1000.0)
        val leeGnd = gnd("Lee GND 0.9", 0.9)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(bigStopper, leeGnd))
        val f = fixture(lee)
        val c = f.controller
        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(bigStopper))
        commit(
            c,
            wheels(c).indexOfLast { it.source == source(lee) },
            itemSelection(leeGnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
        )
        val before = committed(c)
        val sources = wheels(c).map { it.source }

        val restored = Fixture(f.model.inventory.value, c.exportSession()).controller

        assertEquals(sources, wheels(restored).map { it.source })
        assertEquals(before, committed(restored))
        assertEquals(total(c), total(restored))
        assertEquals(
            "The remembered source survives the restart.",
            source(lee),
            restored.state.value.plus.sources[restored.state.value.plus.selectedIndex].source,
        )
    }

    // MARK: - assistive adjustment (FILTER-A11Y-004/005)

    @Test
    fun anAssistiveAdjustmentSkipsAMountedRowAndCommitsTheNextAvailableOne() {
        val nd10 = ndFactor("ND1000", 1000.0)
        val nd6 = ndFactor("ND64", 64.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(nd10, nd6))
        val f = fixture(lee)
        val c = f.controller
        c.addFilterWheel(source(lee))
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(nd10))
        val free = wheels(c).last { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id

        val outcome = c.adjustFilterWheel(free, FilterWheelAdjustmentDirection.increment)

        assertEquals(FilterWheelAdjustmentOutcome.Selection(itemSelection(nd6)), outcome)
        assertTrue(committed(c).contains(itemSelection(nd6)))
        assertEquals("16", total(c))
    }

    @Test
    fun anAssistiveAdjustmentReportsBoundaryAndUnavailableCorrectly() {
        val a = stops("A", 1.0)
        val b = stops("B", 2.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(a, b))
        val f = fixture(lee)
        val c = f.controller
        repeat(3) { c.addFilterWheel(source(lee)) }
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(a))
        commit(c, wheels(c).indexOfFirst { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }, itemSelection(b))
        val free = wheels(c).first { it.rows[it.committedIndex].selection == FilterWheelSelection.Empty }.id

        assertEquals(
            FilterWheelAdjustmentOutcome.Unavailable(FilterStackRejection.itemAlreadyMounted),
            c.adjustFilterWheel(free, FilterWheelAdjustmentDirection.increment),
        )
        assertEquals(
            "Empty is the first row: there is nothing below it.",
            FilterWheelAdjustmentOutcome.Boundary,
            c.adjustFilterWheel(free, FilterWheelAdjustmentDirection.decrement),
        )
        assertEquals(FilterWheelSelection.Empty, committed(c)[indexOfWheel(c, free)])
    }

    // MARK: - screen-reader ordering (FILTER-A11Y-006)

    @Test
    fun suspensionFreezesTheOrderAndResumingReconcilesExactlyOnce() {
        val f = fixture()
        val c = f.controller
        c.addFilterWheel(FilterSource.Standard)
        commit(c, 0, standard(8.0))
        val small = wheels(c)[1].id
        val big = wheels(c)[0].id

        c.setFilterStackOrderingSuspended(true)
        assertTrue(c.state.value.isFilterStackOrderingSuspended)
        commit(c, indexOfWheel(c, small), standard(10.0))
        assertEquals("The frozen order is kept through the commit.", listOf(big, small), wheels(c).map { it.id })
        assertEquals(listOf(standard(8.0), standard(10.0)), committed(c))

        c.setFilterStackOrderingSuspended(false)
        assertEquals("One reconciliation, identities preserved.", listOf(small, big), wheels(c).map { it.id })
        assertEquals(listOf(standard(10.0), standard(8.0)), committed(c))
        assertEquals("18", total(c))
    }

    @Test
    fun resumingWaitsForTouchAndPendingCommitsAndCanBeCancelled() {
        val f = fixture()
        val c = f.controller
        c.addFilterWheel(FilterSource.Standard)
        commit(c, 0, standard(8.0))
        val big = wheels(c)[0].id
        val small = wheels(c)[1].id

        c.setFilterStackOrderingSuspended(true)
        commit(c, indexOfWheel(c, small), standard(10.0))
        // A finger is down when the screen reader turns off: the queued
        // reconciliation waits for the barrier.
        c.setNdWheelActive(big, true)
        c.setFilterStackOrderingSuspended(false)
        assertEquals(listOf(big, small), wheels(c).map { it.id })

        c.setNdWheelActive(big, false)
        assertEquals(listOf(small, big), wheels(c).map { it.id })

        // Re-enabling before the reconciliation runs cancels it.
        c.setFilterStackOrderingSuspended(true)
        commit(c, indexOfWheel(c, big), standard(12.0))
        c.setNdWheelActive(small, true)
        c.setFilterStackOrderingSuspended(false)
        c.setFilterStackOrderingSuspended(true)
        c.setNdWheelActive(small, false)
        assertEquals(
            "The cancelled reconciliation never runs.",
            listOf(small, big),
            wheels(c).map { it.id },
        )
        assertEquals(listOf(standard(10.0), standard(12.0)), committed(c))
    }

    @Test
    fun launchingWithSuspensionActiveRestoresThePersistedOrder() {
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(
                    shutterIndex = 10,
                    ndIndex = 8,
                    selectedFilmId = null,
                    selectedProfileId = null,
                    ndStack = listOf(2.0, 8.0),
                    filterStack = listOf(
                        PersistentFilterWheel(PersistentFilterWheel.STANDARD_SOURCE_KIND, stops = 2.0),
                        PersistentFilterWheel(PersistentFilterWheel.STANDARD_SOURCE_KIND, stops = 8.0),
                    ),
                ),
            ),
            customNames = emptyMap(),
        )
        val c = Fixture(FilterInventory.empty, session).controller
        c.setFilterStackOrderingSuspended(true)

        assertEquals(
            "The persisted order restores without an automatic value-based reorder.",
            listOf(standard(2.0), standard(8.0)),
            committed(c),
        )

        c.setFilterStackOrderingSuspended(false)
        assertEquals(listOf(standard(8.0), standard(2.0)), committed(c))
    }

    // MARK: - timer capture (FILTER-PERSIST-003)

    @Test
    fun theCapturedSummaryAndReferenceSurviveLaterRenames() {
        val bigStopper = ndFactor("Big Stopper", 1000.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(bigStopper))
        val f = fixture(lee)
        val c = f.controller
        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        commit(c, wheels(c).indexOfFirst { it.source == source(lee) }, itemSelection(bigStopper))

        c.startFromAdjusted()
        val identity = f.started.single().second

        assertEquals(12.0, identity.ndStops!!, 1e-9)
        val entry = identity.filterSummary!!.first { it.sourceKind == FilterSummaryEntry.SourceKind.filterSet }
        assertEquals(
            "ND1000 is exactly 10 stops, not log2(1000).",
            10.0,
            entry.canonicalStops!!,
            1e-9,
        )
        assertEquals(1000.0, entry.originalValue!!, 1e-9)
        assertEquals(FilterValueUnit.filterFactor, entry.originalUnit)
        assertEquals(
            listOf("Lee holder" to "Big Stopper", null to null),
            identity.filterSummary!!.map { it.filterSetName to it.itemName },
        )
        assertEquals(
            "Lee holder: Big Stopper ND1000 · Standard 2 stops",
            identity.filterReferenceText,
        )

        c.renameFilterSet(lee.id, "Renamed kit")
        c.saveFilterItem(bigStopper.copy(name = "Renamed filter"), lee.id)
        c.deleteFilterSet(lee.id)

        assertEquals(
            "A captured entry is descriptive only; a later rename, edit or " +
                "deletion never rewrites it.",
            "Lee holder: Big Stopper ND1000 · Standard 2 stops",
            f.started.single().second.filterReferenceText,
        )
        assertEquals(
            listOf("Lee holder" to "Big Stopper", null to null),
            f.started.single().second.filterSummary!!.map { it.filterSetName to it.itemName },
        )
    }

    @Test
    fun aStandardOnlyTimerCapturesAStandardOnlySummary() {
        val f = fixture()
        val c = f.controller
        commit(c, 0, standard(5.0))

        c.startFromAdjusted()
        val identity = f.started.single().second

        assertEquals(
            listOf(FilterSummaryEntry.SourceKind.standard),
            identity.filterSummary!!.map { it.sourceKind },
        )
        assertEquals(5.0, identity.filterSummary!!.single().contributedStops, 1e-9)
        assertEquals("Standard 5 stops", identity.filterReferenceText)
    }

    @Test
    fun aLaterLanguageChangeDoesNotRewriteAnAlreadyCapturedReference() {
        val bigStopper = ndFactor("Big Stopper", 1000.0)
        val lee = FilterSet("Lee holder", FilterSetColor.blue, listOf(bigStopper))
        val f = fixture(lee)
        val c = f.controller
        f.vocabulary = FilterReferenceVocabulary.canonicalEnglish.copy(
            standardSource = "표준",
            oneStop = "1 스톱",
            stopsFormat = "%1\u0024s 스톱",
        )

        commit(c, 0, standard(2.0))
        c.addFilterWheel(source(lee))
        commit(c, indexOfWheel(c, wheels(c).first { it.source == source(lee) }.id), itemSelection(bigStopper))
        c.startFromAdjusted()

        val captured = f.started.single().second
        assertEquals("Lee holder: Big Stopper ND1000 · 표준 2 스톱", captured.filterReferenceText)

        // The app language changes afterwards.
        f.vocabulary = FilterReferenceVocabulary.canonicalEnglish
        assertEquals(
            "The captured entry keeps the language it was started in.",
            "Lee holder: Big Stopper ND1000 · 표준 2 스톱",
            f.started.single().second.filterReferenceText,
        )

        // Only a new timer picks the new language up.
        c.startFromAdjusted()
        assertEquals(
            "Lee holder: Big Stopper ND1000 · Standard 2 stops",
            f.started.last().second.filterReferenceText,
        )
    }

    // MARK: - rejection notice lifetime (FILTER-STACK-004)

    @Test
    fun theRejectionNoticeIsClearedByASlotSwitchAndByAnInventoryChange() {
        val empty = FilterSet("Empty kit", FilterSetColor.brown)
        val f = fixture(empty)
        val c = f.controller

        c.addFilterWheel(source(empty))
        assertNotNull(c.state.value.filterStatus.rejection)
        c.selectSlot(CameraSlotId.camera2)
        assertNull("A refusal belongs to the camera that produced it.", c.state.value.filterStatus.rejection)

        c.addFilterWheel(source(empty))
        assertNotNull(c.state.value.filterStatus.rejection)
        c.createFilterSet("NiSi kit", FilterSetColor.red)
        assertNull("A changed inventory drops the stale reason.", c.state.value.filterStatus.rejection)
    }
}
