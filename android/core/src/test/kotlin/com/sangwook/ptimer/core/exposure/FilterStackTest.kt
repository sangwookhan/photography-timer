// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Filter Set contract — mixed stack rules (FILTER-STACK-001…006,
 * FILTER-GND-001/002, FILTER-CPL-005, FILTER-PLUS-005,
 * FILTER-PERSIST-002) driven by the spec's verification examples. Port
 * of iOS FilterStackTests.
 */
class FilterStackTest {

    private fun stops(value: Double) = FilterRegisteredValue(value, FilterValueUnit.stops)

    private fun fixed(name: String, value: Double) =
        FilterItem(name, FilterItemBehavior.Fixed(stops(value)))

    private fun select(
        item: FilterItem,
        choice: FilterRowChoice = FilterRowChoice.Fixed,
    ): FilterWheelSelection = FilterWheelSelection.Item(FilterRowSelection(item.id, choice))

    private fun wheel(
        set: FilterSet,
        item: FilterItem,
        choice: FilterRowChoice = FilterRowChoice.Fixed,
    ) = FilterWheel(FilterSource.FilterSet(set.id), select(item, choice))

    private fun stackOf(wheels: List<FilterWheel>, inventory: FilterInventory): FilterStack =
        FilterStack.validated(wheels, inventory)!!

    private fun accepted(change: FilterStackChange): FilterStack =
        (change as FilterStackChange.Accepted).stack

    private fun rejected(reason: FilterStackRejection) = FilterStackChange.Rejected(reason)

    // --- Example 1 — two separate 3-stop items, exclusivity by id ---

    @Test fun twoEqualItemsSumWhileASecondSelectionOfEitherIsUnavailable() {
        val a = fixed("ND8", 3.0)
        val b = fixed("ND8", 3.0)
        val set = FilterSet("Holder", FilterSetColor.blue, listOf(a, b))
        val inventory = FilterInventory(listOf(set))
        var stack = FilterStack.single(0.0)
            .addingWheel(FilterSource.FilterSet(set.id), inventory)
            .addingWheel(FilterSource.FilterSet(set.id), inventory)

        stack = accepted(stack.replacingWheel(1, select(a), inventory))
        stack = accepted(stack.replacingWheel(2, select(b), inventory))
        assertEquals(6.0, stack.effectiveStops, 1e-9)

        val options = stack.rowOptions(2, inventory)
        assertEquals(
            FilterStackRejection.itemAlreadyMounted,
            options.first { it.selection == select(a) }.unavailability,
        )
        assertNull(
            "The wheel's own item stays available.",
            options.first { it.selection == select(b) }.unavailability,
        )
        assertEquals(
            rejected(FilterStackRejection.itemAlreadyMounted),
            stack.replacingWheel(2, select(a), inventory),
        )
    }

    // --- Example 2 — FILTER-STACK-005 source groups by registered subtotal ---

    @Test fun sourceGroupsSortByRegisteredSubtotalAndStayContiguous() {
        val nd1000 = FilterItem(
            "Big Stopper",
            FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor)),
        )
        val nd8 = fixed("ND8", 3.0)
        val nd2 = fixed("ND2", 1.0)
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val nisi = FilterSet("NiSi", FilterSetColor.red, listOf(nd1000))
        val lee = FilterSet("Lee", FilterSetColor.green, listOf(nd8, nd2, cpl))
        val inventory = FilterInventory(listOf(nisi, lee))
        // Deliberately interleaved: Lee, NiSi, Lee — three ND wheels
        // beside a mounted CPL that never takes part in ND ordering.
        val stack = FilterStack.validated(
            listOf(wheel(lee, nd2), wheel(nisi, nd1000), wheel(lee, nd8)),
            listOf(MountedAuxiliaryFilter(lee.id, cpl.id, AuxiliaryFilterChoice.CplLoss(2.0))),
            inventory,
        )!!
        assertEquals(16.0, stack.effectiveStops, 1e-9)
        assertEquals(10.0, stack.registeredSubtotal(FilterSource.FilterSet(nisi.id)), 1e-9)
        assertEquals("Auxiliary contributions are not an ND subtotal.", 4.0, stack.registeredSubtotal(FilterSource.FilterSet(lee.id)), 1e-9)

        // NiSi (10) > Lee (3 + 1 = 4); Lee's rows descend.
        assertEquals(listOf(1, 2, 0), stack.commitSortPermutation(inventory))
        val sorted = stack.sortedForCommit(inventory)
        assertEquals(
            listOf(
                FilterSource.FilterSet(nisi.id),
                FilterSource.FilterSet(lee.id),
                FilterSource.FilterSet(lee.id),
            ),
            sorted.wheels.map { it.source },
        )
        assertEquals(select(nd8), sorted.wheels[1].selection)
        assertEquals(select(nd2), sorted.wheels[2].selection)
        assertEquals("The auxiliary filters stay as they are.", stack.auxiliaryFilters, sorted.auxiliaryFilters)
        assertEquals(16.0, sorted.effectiveStops, 1e-9)
    }

    @Test fun equalSubtotalsPutStandardFirstThenFilterSetUserOrder() {
        val three = fixed("Three", 3.0)
        val alsoThree = fixed("Three", 3.0)
        val setA = FilterSet("A", FilterSetColor.red, listOf(three))
        val setB = FilterSet("B", FilterSetColor.green, listOf(alsoThree))
        val inventory = FilterInventory(listOf(setA, setB))
        val stack = stackOf(
            listOf(wheel(setB, alsoThree), wheel(setA, three), FilterWheel.standard(3.0)),
            inventory,
        )
        assertEquals(listOf(2, 1, 0), stack.commitSortPermutation(inventory))

        // Reversing the user-defined set order reverses the tie only.
        val reversed = FilterInventory(listOf(setB, setA))
        assertEquals(listOf(2, 0, 1), stack.commitSortPermutation(reversed))
    }

    @Test fun standardSelectionCanReorderGroupsOnlyThroughItsSubtotal() {
        val four = fixed("Four", 4.0)
        val set = FilterSet("S", FilterSetColor.teal, listOf(four))
        val inventory = FilterInventory(listOf(set))
        var stack = stackOf(listOf(FilterWheel.standard(2.0), wheel(set, four)), inventory)
        assertEquals(
            "Set (4) ahead of Standard (2).",
            listOf(1, 0),
            stack.commitSortPermutation(inventory),
        )
        stack = accepted(stack.replacingWheel(0, FilterWheelSelection.Standard(5.0), inventory))
        assertEquals(
            "Standard (5) now ahead of the set (4).",
            listOf(0, 1),
            stack.commitSortPermutation(inventory),
        )
    }

    @Test fun withinSourceSortIsDescendingWithEmptyLast() {
        val one = fixed("One", 1.0)
        val five = fixed("Five", 5.0)
        val set = FilterSet("S", FilterSetColor.teal, listOf(one, five))
        val inventory = FilterInventory(listOf(set))
        val stack = stackOf(
            listOf(
                FilterWheel.empty(set.id),
                wheel(set, one),
                FilterWheel.standard(0.0),
                wheel(set, five),
            ),
            inventory,
        )
        // The set's subtotal (5 + 1 + 0) leads Standard 0; within the set
        // Five, One, then Empty.
        val sorted = stack.sortedForCommit(inventory)
        assertEquals(select(five), sorted.wheels[0].selection)
        assertEquals(select(one), sorted.wheels[1].selection)
        assertEquals(FilterWheelSelection.Empty, sorted.wheels[2].selection)
        assertEquals(FilterWheelSelection.Standard(0.0), sorted.wheels[3].selection)
        assertEquals(0.0, stack.sortValue(0), 0.0)
        assertEquals(0.0, stack.sortValue(2), 0.0)
    }

    // --- Example 4 — GND Record only vs Apply full value ---

    @Test fun gndRecordOnlyContributesZeroAndApplyFullContributesRegisteredValue() {
        val gnd = FilterItem("GND 0.6", FilterItemBehavior.Gnd(stops(2.0)))
        val set = FilterSet("GND", FilterSetColor.purple, listOf(gnd))
        val inventory = FilterInventory(listOf(set))
        var stack = stackOf(listOf(FilterWheel.standard(3.0)), inventory)

        stack = accepted(
            stack.replacingAuxiliaryFilters(
                listOf(MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly))),
                inventory,
            ),
        )
        assertEquals(3.0, stack.effectiveStops, 1e-9)
        assertTrue("Record only is a mounted item and keeps the summary.", stack.hasAuxiliaryFilters)
        assertEquals(0.0, stack.auxiliaryRows.single().contributionStops, 0.0)

        stack = accepted(
            stack.replacingAuxiliaryFilters(
                listOf(MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.applyFullValue))),
                inventory,
            ),
        )
        assertEquals(5.0, stack.effectiveStops, 1e-9)
        assertEquals(2.0, stack.auxiliaryRows.single().registeredStops, 0.0)
    }

    @Test fun emptyAndRecordOnlyAreDistinctStates() {
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(2.0)))
        val nd = fixed("ND8", 3.0)
        val set = FilterSet("GND", FilterSetColor.purple, listOf(gnd, nd))
        val inventory = FilterInventory(listOf(set))
        val empty = stackOf(listOf(FilterWheel.standard(1.0), FilterWheel.empty(set.id)), inventory)
        assertTrue(empty.wheels[1].isCleanable)
        assertTrue(empty.canRemoveEmptyWheel)

        val recordOnly = accepted(
            empty.replacingAuxiliaryFilters(
                listOf(MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly))),
                inventory,
            ),
        )
        assertEquals(empty.effectiveStops, recordOnly.effectiveStops, 0.0)
        assertTrue("The Empty wheel stays an Empty wheel.", recordOnly.wheels[1].isCleanable)
        assertTrue("The Record-only GND is mounted in the summary.", recordOnly.hasAuxiliaryFilters)
        // Wheel cleanup never removes a mounted auxiliary filter.
        assertEquals(recordOnly.auxiliaryFilters, recordOnly.removingEmptyWheel(at = 1).auxiliaryFilters)
    }

    // --- Example 5 — CPL rows and sibling exclusivity ---

    @Test fun auxiliaryItemsNeverAppearOnAnNdWheelAndMountOnce() {
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val nd = fixed("ND8", 3.0)
        val set = FilterSet("CPL", FilterSetColor.orange, listOf(cpl, nd))
        val inventory = FilterInventory(listOf(set))
        var stack = stackOf(listOf(FilterWheel.empty(set.id)), inventory)

        // FILTER-STACK-003: Empty plus the set's ND items only.
        assertEquals(
            listOf(FilterWheelSelection.Empty, select(nd)),
            stack.rowOptions(0, inventory).map { it.selection },
        )
        assertEquals(
            rejected(FilterStackRejection.unresolvedSelection),
            stack.replacingWheel(0, select(cpl, FilterRowChoice.CplLoss(1.5)), inventory),
        )

        val mount = MountedAuxiliaryFilter(set.id, cpl.id, AuxiliaryFilterChoice.CplLoss(1.5))
        stack = accepted(stack.replacingAuxiliaryFilters(listOf(mount), inventory))
        assertEquals(1.5, stack.effectiveStops, 1e-9)
        // Changing the choice updates the same mounted item.
        stack = accepted(stack.replacingAuxiliaryFilters(listOf(mount.copy(choice = AuxiliaryFilterChoice.CplLoss(2.0))), inventory))
        assertEquals(2.0, stack.effectiveStops, 1e-9)
        // The same physical item cannot be mounted twice.
        assertEquals(
            rejected(FilterStackRejection.itemAlreadyMounted),
            stack.replacingAuxiliaryFilters(listOf(mount, mount), inventory),
        )
    }

    // --- Example 6 — cap behavior with Record only ---

    @Test fun recordOnlyRemainsMountableAtCapAndEnablingContributionIsRejected() {
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(2.0)))
        val set = FilterSet("GND", FilterSetColor.purple, listOf(gnd))
        val inventory = FilterInventory(listOf(set))
        var stack = stackOf(listOf(FilterWheel.standard(30.0)), inventory)

        // A GND-only set holds no ND item, so it never makes a wheel.
        assertEquals(
            FilterAddUnavailability.filterSetHasNoItems,
            stack.addUnavailability(FilterSource.FilterSet(set.id), inventory),
        )
        assertEquals(
            FilterAddUnavailability.noSelectableValue,
            stack.addUnavailability(FilterSource.Standard, inventory),
        )

        val recordOnly = MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly))
        stack = accepted(stack.replacingAuxiliaryFilters(listOf(recordOnly), inventory))
        assertEquals(30.0, stack.effectiveStops, 1e-9)

        val before = stack
        assertEquals(
            rejected(FilterStackRejection.exceedsTotalLimit),
            stack.replacingAuxiliaryFilters(
                listOf(recordOnly.copy(choice = AuxiliaryFilterChoice.Gnd(GndCalculationMode.applyFullValue))),
                inventory,
            ),
        )
        assertEquals("A rejected change leaves the previous state intact.", before, stack)
    }

    @Test fun addUnavailabilityReasons() {
        val mounted = fixed("Only", 3.0)
        val set = FilterSet("One item", FilterSetColor.pink, listOf(mounted))
        val emptySet = FilterSet("Empty", FilterSetColor.pink)
        val inventory = FilterInventory(listOf(set, emptySet))
        val stack = stackOf(listOf(wheel(set, mounted)), inventory)
        assertEquals(
            FilterAddUnavailability.allItemsMounted,
            stack.addUnavailability(FilterSource.FilterSet(set.id), inventory),
        )
        assertEquals(
            FilterAddUnavailability.filterSetHasNoItems,
            stack.addUnavailability(FilterSource.FilterSet(emptySet.id), inventory),
        )
        assertEquals(
            FilterAddUnavailability.unknownFilterSet,
            stack.addUnavailability(FilterSource.FilterSet(FilterSetId.generate()), inventory),
        )
        assertNull(stack.addUnavailability(FilterSource.Standard, inventory))
        val full = requireNotNull(FilterStack.validated(List(4) { FilterWheel.standard(1.0) }, inventory))
        assertEquals(
            FilterAddUnavailability.stackFull,
            full.addUnavailability(FilterSource.Standard, inventory),
        )
    }

    @Test fun addingAWheelNeverChangesTheEffectiveValue() {
        val set = FilterSet("S", FilterSetColor.red, listOf(fixed("X", 4.0)))
        val inventory = FilterInventory(listOf(set))
        val stack = FilterStack.single(6.6)
        val added = stack.addingWheel(FilterSource.FilterSet(set.id), inventory)
        assertEquals(2, added.wheels.size)
        assertEquals(FilterWheel.empty(set.id), added.wheels[1])
        assertEquals(stack.effectiveStops, added.effectiveStops, 0.0)
        assertEquals(stack, stack.addingWheel(FilterSource.FilterSet(FilterSetId.generate()), inventory))
    }

    // --- ND wheel row order ---

    /** FILTER-STACK-003: an ND wheel offers Empty, then only its Set's ND
     *  items, weakest to strongest by canonical stops (never by name or the
     *  registered number), equal stops by name and then id. It is not the
     *  Filter Set list order reversed: equal stops still read by name. */
    @Test fun ndWheelRowsReadWeakestFirstByCanonicalStops() {
        fun factor(name: String, value: Double) =
            FilterItem(name, FilterItemBehavior.Fixed(FilterRegisteredValue(value, FilterValueUnit.filterFactor)))
        val nd100k = factor("ND100k", 100_000.0)
        val bigStopper = fixed("Big Stopper", 10.0)
        val nd400 = factor("ND400", 400.0)
        val alpha = fixed("Alpha 3", 3.0)
        val nd8 = fixed("ND8", 3.0)
        val twin = fixed("ND8", 3.0)
        val gnd = FilterItem("A soft GND", FilterItemBehavior.Gnd(stops(2.0)))
        val red = FilterItem("Red", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
        val set = FilterSet("Bag", FilterSetColor.blue, listOf(nd100k, gnd, nd8, bigStopper, red, nd400, twin, alpha))
        val inventory = FilterInventory(listOf(set))
        val stack = stackOf(listOf(FilterWheel.empty(set.id)), inventory)

        val twins = listOf(nd8, twin).sortedBy { it.id.rawValue }
        val rows = stack.rowOptions(0, inventory)
        assertEquals(
            listOf(FilterWheelSelection.Empty) + (listOf(alpha) + twins + listOf(nd400, bigStopper, nd100k)).map { select(it) },
            rows.map { it.selection },
        )
        assertEquals(listOf(3.0, 3.0, 3.0, 8.64, 10.0, 16.6), rows.drop(1).map { Math.round(it.row.contributionStops * 100) / 100.0 })
    }

    // --- Standard wheels keep the budget-truncated ladder ---

    @Test fun standardRowsAreTruncatedToTheRemainingBudget() {
        val item = fixed("Big", 25.0)
        val set = FilterSet("S", FilterSetColor.red, listOf(item))
        val inventory = FilterInventory(listOf(set))
        val stack = stackOf(listOf(FilterWheel.standard(0.0), wheel(set, item)), inventory)
        val rows = stack.rowOptions(0, inventory)
        assertEquals(5.0, rows.last().row.contributionStops, 0.0)
        assertTrue(rows.all { it.isAvailable })
        assertEquals(
            rejected(FilterStackRejection.exceedsTotalLimit),
            stack.replacingWheel(0, FilterWheelSelection.Standard(6.0), inventory),
        )
    }

    // --- FILTER-ITEM-004 — ND1000 is exactly 10 stops through the stack ---

    @Test fun nd1000ContributesExactlyTenStopsThroughSumSortAndCap() {
        val nd1000 = FilterItem(
            "Big Stopper",
            FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor)),
        )
        val nd8 = fixed("ND8", 3.0)
        val set = FilterSet("Lee", FilterSetColor.red, listOf(nd8, nd1000))
        val inventory = FilterInventory(listOf(set))

        var stack = stackOf(
            listOf(
                FilterWheel.standard(17.0),
                FilterWheel.empty(set.id),
                FilterWheel.empty(set.id),
            ),
            inventory,
        )
        stack = accepted(stack.replacingWheel(1, select(nd8), inventory))
        stack = accepted(stack.replacingWheel(2, select(nd1000), inventory))
        assertEquals("Exact, not log2(1000).", 10.0, stack.rows[2].contributionStops, 0.0)
        assertEquals(
            "17 + 3 + 10 lands exactly on the cap.",
            30.0,
            stack.effectiveStops,
            0.0,
        )
        assertTrue(FilterStack.isWithinTotalLimit(stack.contributions))

        // Standard (17) leads the set (10 + 3); within the set ND1000 (10)
        // before ND8 (3).
        val sorted = stack.sortedForCommit(inventory)
        assertEquals(FilterWheelSelection.Standard(17.0), sorted.wheels[0].selection)
        assertEquals(select(nd1000), sorted.wheels[1].selection)
        assertEquals(select(nd8), sorted.wheels[2].selection)

        // Cap: one more Standard stop with ND1000 mounted is refused.
        assertEquals(
            rejected(FilterStackRejection.exceedsTotalLimit),
            stack.replacingWheel(0, FilterWheelSelection.Standard(18.0), inventory),
        )
        // A 9.97-stop reading would have left room; the exact 10 does not.
        assertNull(
            FilterStack.validated(
                listOf(FilterWheel.standard(21.0), wheel(set, nd1000)),
                inventory,
            ),
        )
    }

    // --- FILTER-PERSIST-002 — safe normalization ---

    @Test fun normalizationDropsUnknownSetsEmptiesUnknownItemsAndFallsBackToStandardZero() {
        val item = fixed("X", 4.0)
        val set = FilterSet("S", FilterSetColor.red, listOf(item))
        val inventory = FilterInventory(listOf(set))
        val unknownSet = FilterSetId.generate()
        val wheels = listOf(
            FilterWheel(FilterSource.FilterSet(unknownSet), FilterWheelSelection.Empty),
            FilterWheel(
                FilterSource.FilterSet(set.id),
                FilterWheelSelection.Item(
                    FilterRowSelection(FilterItemId.generate(), FilterRowChoice.Fixed),
                ),
            ),
            wheel(set, item),
            wheel(set, item),
        )
        assertEquals(
            listOf(FilterWheel.empty(set.id), wheel(set, item), FilterWheel.empty(set.id)),
            FilterStack.normalizedWheels(wheels, inventory),
        )
        assertEquals(
            listOf(FilterWheel.standard(0.0)),
            FilterStack.normalizedWheels(
                listOf(FilterWheel(FilterSource.FilterSet(unknownSet), FilterWheelSelection.Empty)),
                inventory,
            ),
        )
        assertNull(
            FilterStack.normalizedWheels(List(5) { FilterWheel.standard(0.0) }, inventory),
        )
    }

    @Test fun normalizationRestoresAVanishedCplChoiceAsEmptyNeverAnotherChoice() {
        // FILTER-PERSIST-002: a persisted CPL selection whose configured
        // choice no longer exists restores as Empty.
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 2.0, null))),
        )
        val set = FilterSet("CPL", FilterSetColor.orange, listOf(cpl))
        val inventory = FilterInventory(listOf(set))
        val stale = wheel(set, cpl, FilterRowChoice.CplLoss(1.5))
        assertEquals(
            listOf(FilterWheel.empty(set.id)),
            FilterStack.normalizedWheels(listOf(stale), inventory),
        )
        // A kind change that removes the mounted row restores as Empty too.
        val nowGnd = FilterItem("CPL", FilterItemBehavior.Gnd(stops(2.0)), cpl.id)
        val changed = FilterInventory(
            listOf(FilterSet("CPL", FilterSetColor.orange, listOf(nowGnd), set.id)),
        )
        assertEquals(
            listOf(FilterWheel.empty(set.id)),
            FilterStack.normalizedWheels(listOf(stale), changed),
        )
    }

    // --- FILTER-STACK-005 — CPL and GND sort keys ---

    @Test fun auxiliaryChangesNeverMoveTheNdWheels() {
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(1.8)))
        val two = fixed("Two", 2.0)
        val set = FilterSet("S", FilterSetColor.red, listOf(cpl, gnd, two))
        val inventory = FilterInventory(listOf(set))
        val base = stackOf(listOf(FilterWheel.standard(3.0), wheel(set, two)), inventory)
        val permutation = base.commitSortPermutation(inventory)
        val mounted = accepted(
            base.replacingAuxiliaryFilters(
                listOf(
                    MountedAuxiliaryFilter(set.id, cpl.id, AuxiliaryFilterChoice.CplLoss(2.0)),
                    MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.applyFullValue)),
                ),
                inventory,
            ),
        )
        assertEquals(permutation, mounted.commitSortPermutation(inventory))
        assertEquals(3.0, mounted.registeredSubtotal(FilterSource.Standard), 1e-9)
        assertEquals(2.0, mounted.registeredSubtotal(FilterSource.FilterSet(set.id)), 1e-9)
        assertEquals(8.8, mounted.effectiveStops, 1e-9)
    }

    // --- FILTER-STACK-001 / FILTER-AUX-002/004 — the auxiliary summary ---

    private fun auxiliaryInventory(): Pair<FilterInventory, List<FilterItem>> {
        val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
        val night = FilterItem("Night", FilterItemBehavior.Effect(FilterExposureLoss(1.0)))
        val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.5, null, null))))
        val soft = FilterItem("Soft GND 2", FilterItemBehavior.Gnd(stops(2.0)))
        val hard = FilterItem("Hard GND 3", FilterItemBehavior.Gnd(stops(3.0)))
        // Set order puts the GNDs first, so kind order has to win.
        val set = FilterSet("Kit", FilterSetColor.blue, listOf(soft, hard, cpl, night, red))
        return FilterInventory(listOf(set)) to listOf(red, night, cpl, soft, hard)
    }

    private fun mountAll(inventory: FilterInventory, items: List<FilterItem>): List<MountedAuxiliaryFilter> {
        val setId = inventory.filterSets.single().id
        return items.map { MountedAuxiliaryFilter(setId, it.id, MountedAuxiliaryFilter.initialChoice(it)!!) }
    }

    @Test fun anyNumberOfAuxiliaryFiltersMountWithinTheCap() {
        val (inventory, items) = auxiliaryInventory()
        val stack = accepted(
            stackOf(listOf(FilterWheel.standard(2.0)), inventory)
                .replacingAuxiliaryFilters(mountAll(inventory, items), inventory),
        )
        assertEquals(5, stack.auxiliaryFilters.size)
        // Red 3 + Night 1 + CPL 1.5 + two Record-only GNDs + Standard 2.
        assertEquals(7.5, stack.effectiveStops, 1e-9)
        assertEquals("Three ND wheels beside the summary.", 3, stack.wheelLimit)
    }

    @Test fun auxiliaryFiltersKeepTheirDisplayOrderWhateverTheMountOrder() {
        val (inventory, items) = auxiliaryInventory()
        val (red, night, cpl, soft, hard) = items
        val expected = listOf(red.id, night.id, cpl.id, soft.id, hard.id)
        for (order in listOf(items, items.reversed(), listOf(hard, cpl, red, soft, night))) {
            val stack = accepted(
                stackOf(listOf(FilterWheel.standard(0.0)), inventory)
                    .replacingAuxiliaryFilters(mountAll(inventory, order), inventory),
            )
            assertEquals(expected, stack.auxiliaryFilters.map { it.itemId })
            assertEquals(expected, FilterStack.normalizedAuxiliaryFilters(mountAll(inventory, order), inventory).map { it.itemId })
        }
    }

    @Test fun theCapRefusesAuxiliaryAfterNdAndNdAfterAuxiliary() {
        val heavy = FilterItem("Heavy Effect", FilterItemBehavior.Effect(FilterExposureLoss(9.0)))
        val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
        val set = FilterSet("Kit", FilterSetColor.blue, listOf(heavy, red))
        val inventory = FilterInventory(listOf(set))
        val redMount = MountedAuxiliaryFilter(set.id, red.id, AuxiliaryFilterChoice.RegisteredLoss)
        val heavyMount = MountedAuxiliaryFilter(set.id, heavy.id, AuxiliaryFilterChoice.RegisteredLoss)

        // ND first: ND 20 + Red 3 = 23; adding a 9-stop Effect is refused
        // and nothing already mounted changes.
        val ndFirst = accepted(stackOf(listOf(FilterWheel.standard(20.0)), inventory).replacingAuxiliaryFilters(listOf(redMount), inventory))
        assertEquals(
            rejected(FilterStackRejection.exceedsTotalLimit),
            ndFirst.replacingAuxiliaryFilters(listOf(redMount, heavyMount), inventory),
        )
        assertEquals(23.0, ndFirst.effectiveStops, 1e-9)

        // Auxiliary first: 9 + 3 = 12 mounted; the ND wheel's budget is 18
        // and a value past it is refused.
        val auxFirst = accepted(
            stackOf(listOf(FilterWheel.standard(15.0)), inventory)
                .replacingAuxiliaryFilters(listOf(heavyMount, redMount), inventory),
        )
        assertEquals(18.0, auxFirst.remainingBudget(excludingWheelAt = 0), 1e-9)
        assertEquals(
            rejected(FilterStackRejection.exceedsTotalLimit),
            auxFirst.replacingWheel(0, FilterWheelSelection.Standard(19.0), inventory),
        )
        assertTrue(auxFirst.rowOptions(0, inventory).all { (it.selection as FilterWheelSelection.Standard).stops <= 18.0 })
        assertEquals(27.0, auxFirst.effectiveStops, 1e-9)
    }

    @Test fun fourNdWheelsRefuseAnAuxiliaryMountAndThreeKeepPlusAway() {
        val (inventory, items) = auxiliaryInventory()
        val four = stackOf(List(4) { FilterWheel.standard(0.0) }, inventory)
        assertEquals(
            rejected(FilterStackRejection.tooManyNDWheels),
            four.replacingAuxiliaryFilters(mountAll(inventory, items.take(1)), inventory),
        )
        val three = accepted(
            stackOf(List(3) { FilterWheel.standard(0.0) }, inventory)
                .replacingAuxiliaryFilters(mountAll(inventory, items.take(1)), inventory),
        )
        assertFalse(three.canAddWheel)
        assertEquals(FilterAddUnavailability.stackFull, three.addUnavailability(FilterSource.Standard, inventory))
        // Clearing the auxiliary filters gives the fourth space back.
        assertTrue(accepted(three.replacingAuxiliaryFilters(emptyList(), inventory)).canAddWheel)
    }

    @Test fun legacyCplAndGndWheelsMigrateIntoAuxiliaryFilters() {
        val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(3.0)))
        val set = FilterSet("Lee", FilterSetColor.red, listOf(cpl, gnd))
        val (wheels, auxiliary) = FilterStack.migratingLegacyWheels(
            listOf(
                wheel(set, cpl, FilterRowChoice.CplLoss(1.5)),
                wheel(set, gnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
            ),
        )
        assertEquals("A stack of only auxiliary rows gets one Standard 0 wheel.", listOf(FilterWheel.standard(0.0)), wheels)
        assertEquals(
            listOf(
                MountedAuxiliaryFilter(set.id, cpl.id, AuxiliaryFilterChoice.CplLoss(1.5)),
                MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.applyFullValue)),
            ),
            auxiliary,
        )
        val stack = FilterStack.validated(wheels, auxiliary, FilterInventory(listOf(set)))!!
        assertEquals("The effective total is preserved.", 4.5, stack.effectiveStops, 1e-9)
    }

    @Test fun aKindChangeMovesTheSelectionIntoTheNewRole() {
        val item = fixed("Red 25A", 3.0)
        val set = FilterSet("S", FilterSetColor.red, listOf(item))
        val asColor = FilterInventory(
            listOf(set.copy(items = listOf(item.copy(behavior = FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))))),
        )
        val moved = FilterStack.reassigningRoles(listOf(FilterWheel.standard(1.0), wheel(set, item)), emptyList(), listOf(set.id), asColor)
        assertEquals(listOf(FilterWheel.standard(1.0)), moved.wheels)
        assertEquals(listOf(0), moved.wheelOrigins)
        assertEquals(listOf(MountedAuxiliaryFilter(set.id, item.id, AuxiliaryFilterChoice.RegisteredLoss)), moved.auxiliaryFilters)

        // Back to ND: the mount becomes a Filter Set ND wheel at the end.
        val back = FilterStack.reassigningRoles(moved.wheels, moved.auxiliaryFilters, listOf(set.id), FilterInventory(listOf(set)))
        assertEquals(listOf(FilterWheel.standard(1.0), wheel(set, item)), back.wheels)
        assertEquals(listOf(0, null), back.wheelOrigins)
        assertTrue(back.auxiliaryFilters.isEmpty())
    }

    /** FILTER-ITEM-005/009: a moved item is judged against the camera's
     *  selected Filter Sets before the move. Into a Set the camera does not
     *  select, an ND wheel becomes Empty under its original source at the
     *  same position and an auxiliary item is unmounted; nothing selects the
     *  destination. (iOS: `testAMovedAuxiliaryItemFollowsOnlyIntoASelectedSet`.) */
    @Test fun aMovedAuxiliaryItemFollowsOnlyIntoASelectedSet() {
        val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
        val red = FilterItem("Red", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
        val nd8 = fixed("ND8", 3.0)
        val kit = FilterSet("Kit", FilterSetColor.blue, emptyList())
        val pouch = FilterSet("Pouch", FilterSetColor.orange, listOf(cpl, nd8))
        val bag = FilterSet("Bag", FilterSetColor.green, listOf(red))
        val inventory = FilterInventory(listOf(kit, pouch, bag))
        val mounts = listOf(
            MountedAuxiliaryFilter(kit.id, cpl.id, AuxiliaryFilterChoice.CplLoss(1.5)),
            MountedAuxiliaryFilter(kit.id, red.id, AuxiliaryFilterChoice.RegisteredLoss),
        )

        val onlyKit = FilterStack.reassigningRoles(listOf(wheel(kit, nd8)), mounts, listOf(kit.id), inventory)
        assertEquals("Pouch is not selected: the ND wheel stays Kit's, now Empty.", listOf(FilterWheel.empty(kit.id)), onlyKit.wheels)
        assertEquals("The same wheel, so it keeps its identity.", listOf<Int?>(0), onlyKit.wheelOrigins)
        assertTrue("Neither Pouch nor Bag is selected: the CPL and the Red are unmounted.", onlyKit.auxiliaryFilters.isEmpty())

        val withBag = FilterStack.reassigningRoles(listOf(FilterWheel.standard(0.0)), mounts, listOf(kit.id, bag.id), inventory)
        val wheelMadeCpl = FilterStack.reassigningRoles(
            listOf(wheel(kit, nd8)),
            emptyList(),
            listOf(kit.id),
            FilterInventory(listOf(kit, pouch.copy(items = listOf(nd8.copy(behavior = cpl.behavior))), bag)),
        )
        assertEquals(
            "A wheel item made auxiliary and moved to an unselected Set is unchecked, not mounted there.",
            Pair(listOf(FilterWheel.standard(0.0)), emptyList<MountedAuxiliaryFilter>()),
            wheelMadeCpl.wheels to wheelMadeCpl.auxiliaryFilters,
        )
        assertEquals(
            "Bag is selected, so the Red follows; Pouch is not, so the CPL is unmounted.",
            listOf(MountedAuxiliaryFilter(bag.id, red.id, AuxiliaryFilterChoice.RegisteredLoss)),
            withBag.auxiliaryFilters,
        )
    }

    /** FILTER-ITEM-005: an ND item moved into a selected Filter Set stays on
     *  the same wheel under its new Set; moved into a Set the camera does not
     *  select, the wheel becomes Empty under its original source in the same
     *  position. An auxiliary item that becomes ND while it moves to an
     *  unselected Set gets no wheel there.
     *  (iOS: `testAMovedNDItemStaysOnlyUnderASelectedSetAndOtherwiseLeavesItsWheelEmpty`.) */
    @Test fun aMovedNdItemStaysOnlyUnderASelectedSetAndOtherwiseLeavesItsWheelEmpty() {
        val nd8 = fixed("ND8", 3.0)
        val red = fixed("Red", 2.0)
        val kit = FilterSet("Kit", FilterSetColor.blue, emptyList())
        val bag = FilterSet("Bag", FilterSetColor.green, listOf(nd8, red))
        val inventory = FilterInventory(listOf(kit, bag))
        val wheels = listOf(FilterWheel.standard(2.0), wheel(kit, nd8))
        val redMount = MountedAuxiliaryFilter(kit.id, red.id, AuxiliaryFilterChoice.RegisteredLoss)

        val unselected = FilterStack.reassigningRoles(wheels, listOf(redMount), listOf(kit.id), inventory)
        assertEquals(listOf(FilterWheel.standard(2.0), FilterWheel.empty(kit.id)), unselected.wheels)
        assertEquals(listOf<Int?>(0, 1), unselected.wheelOrigins)
        assertTrue("The Red, now ND and in Bag, gets no wheel in a Set the camera does not select.", unselected.auxiliaryFilters.isEmpty())

        val selected = FilterStack.reassigningRoles(wheels, emptyList(), listOf(kit.id, bag.id), inventory)
        assertEquals(listOf(FilterWheel.standard(2.0), wheel(bag, nd8)), selected.wheels)
        assertEquals(listOf<Int?>(0, 1), selected.wheelOrigins)
    }

    @Test fun validatedRejectsOverCapDuplicateAndUnresolvedWheels() {
        val big = fixed("Big", 20.0)
        val set = FilterSet("S", FilterSetColor.red, listOf(big))
        val inventory = FilterInventory(listOf(set))
        assertNull(
            FilterStack.validated(
                listOf(FilterWheel.standard(11.0), wheel(set, big)),
                inventory,
            ),
        )
        assertNull(
            FilterStack.validated(listOf(wheel(set, big), wheel(set, big)), inventory),
        )
        assertNull(
            FilterStack.validated(listOf(FilterWheel.empty(FilterSetId.generate())), inventory),
        )
        assertNull(FilterStack.validated(emptyList(), inventory))
        assertNotNull(
            FilterStack.validated(
                listOf(FilterWheel.standard(10.0), wheel(set, big)),
                inventory,
            ),
        )
    }
}
