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
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val nisi = FilterSet("NiSi", FilterSetColor.red, listOf(nd1000))
        val lee = FilterSet("Lee", FilterSetColor.green, listOf(nd8, cpl))
        val inventory = FilterInventory(listOf(nisi, lee))
        // Deliberately interleaved: Standard, Lee, NiSi, Lee.
        val stack = stackOf(
            listOf(
                FilterWheel.standard(2.0),
                wheel(lee, cpl, FilterRowChoice.CplLoss(1.0)),
                wheel(nisi, nd1000),
                wheel(lee, nd8),
            ),
            inventory,
        )
        assertEquals(16.0, stack.effectiveStops, 1e-9)
        assertEquals(10.0, stack.registeredSubtotal(FilterSource.FilterSet(nisi.id)), 1e-9)
        assertEquals(4.0, stack.registeredSubtotal(FilterSource.FilterSet(lee.id)), 1e-9)
        assertEquals(2.0, stack.registeredSubtotal(FilterSource.Standard), 1e-9)

        // NiSi (10) > Lee (3 + 1 = 4) > Standard (2); Lee's rows descend.
        assertEquals(listOf(2, 3, 1, 0), stack.commitSortPermutation(inventory))
        val sorted = stack.sortedForCommit(inventory)
        assertEquals(
            listOf(
                FilterSource.FilterSet(nisi.id),
                FilterSource.FilterSet(lee.id),
                FilterSource.FilterSet(lee.id),
                FilterSource.Standard,
            ),
            sorted.wheels.map { it.source },
        )
        assertEquals(select(nd8), sorted.wheels[1].selection)
        assertEquals(select(cpl, FilterRowChoice.CplLoss(1.0)), sorted.wheels[2].selection)
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
        var stack = stackOf(listOf(FilterWheel.standard(3.0), FilterWheel.empty(set.id)), inventory)

        stack = accepted(
            stack.replacingWheel(
                1,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
                inventory,
            ),
        )
        assertEquals(3.0, stack.effectiveStops, 1e-9)
        assertNotNull("Record only is a mounted item.", stack.wheels[1].mountedItemId)
        assertFalse(
            "A mounted Record-only item is never cleaned up.",
            stack.wheels[1].isCleanable,
        )
        assertFalse(stack.canRemoveEmptyWheel)

        stack = accepted(
            stack.replacingWheel(
                1,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
                inventory,
            ),
        )
        assertEquals(5.0, stack.effectiveStops, 1e-9)
        // The GND sorts by its registered value even in Record-only mode.
        assertEquals(2.0, stack.rows[1].registeredStops, 0.0)
    }

    @Test fun emptyAndRecordOnlyAreDistinctStates() {
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(2.0)))
        val set = FilterSet("GND", FilterSetColor.purple, listOf(gnd))
        val inventory = FilterInventory(listOf(set))
        val empty = stackOf(listOf(FilterWheel.standard(1.0), FilterWheel.empty(set.id)), inventory)
        assertTrue(empty.wheels[1].isCleanable)
        assertTrue(empty.canRemoveEmptyWheel)
        assertEquals(1, empty.removingRightmostEmptyWheel().wheels.size)

        val recordOnly = accepted(
            empty.replacingWheel(
                1,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
                inventory,
            ),
        )
        assertEquals(empty.effectiveStops, recordOnly.effectiveStops, 0.0)
        assertNotEquals(empty.wheels[1], recordOnly.wheels[1])
        assertEquals(2, recordOnly.removingRightmostEmptyWheel().wheels.size)
    }

    // --- Example 5 — CPL rows and sibling exclusivity ---

    @Test fun cplRowsAreDistinctChoicesAndSiblingsDisableEveryRowOfTheItem() {
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val set = FilterSet("CPL", FilterSetColor.orange, listOf(cpl))
        val inventory = FilterInventory(listOf(set))
        var stack = stackOf(
            listOf(FilterWheel.empty(set.id), FilterWheel.empty(set.id)),
            inventory,
        )

        val ownRows = stack.rowOptions(0, inventory)
        assertEquals(
            listOf(
                FilterWheelSelection.Empty,
                select(cpl, FilterRowChoice.CplLoss(1.0)),
                select(cpl, FilterRowChoice.CplLoss(1.5)),
                select(cpl, FilterRowChoice.CplLoss(2.0)),
            ),
            ownRows.map { it.selection },
        )

        stack = accepted(
            stack.replacingWheel(0, select(cpl, FilterRowChoice.CplLoss(1.5)), inventory),
        )
        assertEquals(1.5, stack.effectiveStops, 1e-9)

        val siblingRows = stack.rowOptions(1, inventory)
        for (option in siblingRows.filter { it.selection != FilterWheelSelection.Empty }) {
            assertEquals(FilterStackRejection.itemAlreadyMounted, option.unavailability)
        }
        // The owning wheel may switch between the item's own rows.
        assertTrue(stack.rowOptions(0, inventory).all { it.isAvailable })
        stack = accepted(
            stack.replacingWheel(0, select(cpl, FilterRowChoice.CplLoss(2.0)), inventory),
        )
        assertEquals(2.0, stack.effectiveStops, 1e-9)
    }

    // --- Example 6 — cap behavior with Record only ---

    @Test fun recordOnlyRemainsAddableAtCapAndEnablingContributionIsRejected() {
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(2.0)))
        val set = FilterSet("GND", FilterSetColor.purple, listOf(gnd))
        val inventory = FilterInventory(listOf(set))
        var stack = stackOf(listOf(FilterWheel.standard(30.0)), inventory)

        assertNull(stack.addUnavailability(FilterSource.FilterSet(set.id), inventory))
        assertEquals(
            FilterAddUnavailability.noSelectableValue,
            stack.addUnavailability(FilterSource.Standard, inventory),
        )

        stack = stack.addingWheel(FilterSource.FilterSet(set.id), inventory)
        stack = accepted(
            stack.replacingWheel(
                1,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
                inventory,
            ),
        )
        assertEquals(30.0, stack.effectiveStops, 1e-9)

        val before = stack
        assertEquals(
            rejected(FilterStackRejection.exceedsTotalLimit),
            stack.replacingWheel(
                1,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
                inventory,
            ),
        )
        assertEquals("A rejected change leaves the previous state intact.", before, stack)
        val options = stack.rowOptions(1, inventory)
        assertEquals(
            FilterStackRejection.exceedsTotalLimit,
            options.first {
                it.selection == select(gnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue))
            }.unavailability,
        )
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
        val full = FilterStack.standardSteps(listOf(1.0, 1.0, 1.0, 1.0))
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

    @Test fun cplSortsByItsSelectedChoiceAndGndByRegisteredDensityInBothModes() {
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val gnd = FilterItem("GND", FilterItemBehavior.Gnd(stops(1.8)))
        val two = fixed("Two", 2.0)
        val set = FilterSet("S", FilterSetColor.red, listOf(cpl, gnd, two))
        val inventory = FilterInventory(listOf(set))
        val base = stackOf(
            listOf(
                wheel(set, cpl, FilterRowChoice.CplLoss(1.0)),
                wheel(set, gnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
                wheel(set, two),
            ),
            inventory,
        )
        // Registered values: CPL 1 < GND 1.8 < Two 2 -> [two, gnd, cpl].
        assertEquals(listOf(2, 1, 0), base.commitSortPermutation(inventory))

        // Raising the CPL choice to 2 ties with Two: the stable sort keeps
        // the CPL (index 0) ahead of Two (index 2).
        val cplTwo = accepted(
            base.replacingWheel(0, select(cpl, FilterRowChoice.CplLoss(2.0)), inventory),
        )
        assertEquals(listOf(0, 2, 1), cplTwo.commitSortPermutation(inventory))

        // Switching the GND to Apply full value must not move it.
        val gndFull = accepted(
            base.replacingWheel(
                1,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
                inventory,
            ),
        )
        assertEquals(
            base.commitSortPermutation(inventory),
            gndFull.commitSortPermutation(inventory),
        )
        assertEquals(1.8, gndFull.rows[1].registeredStops, 0.0)
        assertEquals(1.8, gndFull.rows[1].contributionStops, 0.0)
        assertEquals(0.0, base.rows[1].contributionStops, 0.0)
    }

    @Test fun gndModeSwitchNeverMovesItsGroupWhileACplChoiceMayAfterSettlement() {
        val gnd = FilterItem("GND 0.9", FilterItemBehavior.Gnd(stops(3.0)))
        val cpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))),
        )
        val lee = FilterSet("Lee", FilterSetColor.red, listOf(gnd))
        val nisi = FilterSet("NiSi", FilterSetColor.green, listOf(cpl))
        val inventory = FilterInventory(listOf(lee, nisi))
        var stack = stackOf(
            listOf(
                FilterWheel.standard(2.0),
                wheel(lee, gnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
                wheel(nisi, cpl, FilterRowChoice.CplLoss(2.0)),
            ),
            inventory,
        ).sortedForCommit(inventory)
        // Lee (registered 3) > Standard (2) == NiSi (2) -> Standard first.
        assertEquals(
            listOf(
                FilterSource.FilterSet(lee.id),
                FilterSource.Standard,
                FilterSource.FilterSet(nisi.id),
            ),
            stack.wheels.map { it.source },
        )
        assertEquals("Record only contributes nothing.", 4.0, stack.effectiveStops, 1e-9)

        // Record only -> Apply full value: same sort value, same position.
        stack = accepted(
            stack.replacingWheel(
                0,
                select(gnd, FilterRowChoice.Gnd(GndCalculationMode.applyFullValue)),
                inventory,
            ),
        )
        assertEquals(listOf(0, 1, 2), stack.commitSortPermutation(inventory))
        assertEquals(3.0, stack.registeredSubtotal(FilterSource.FilterSet(lee.id)), 1e-9)
        assertEquals(7.0, stack.effectiveStops, 1e-9)

        // A different CPL choice changes NiSi's subtotal: NiSi (1.5) drops
        // below Standard (2).
        stack = accepted(
            stack.replacingWheel(2, select(cpl, FilterRowChoice.CplLoss(1.5)), inventory),
        )
        assertEquals(listOf(0, 1, 2), stack.commitSortPermutation(inventory))
        stack = accepted(stack.replacingWheel(1, FilterWheelSelection.Standard(1.0), inventory))
        assertEquals(
            "NiSi (1.5) now leads Standard (1).",
            listOf(0, 2, 1),
            stack.commitSortPermutation(inventory),
        )
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
