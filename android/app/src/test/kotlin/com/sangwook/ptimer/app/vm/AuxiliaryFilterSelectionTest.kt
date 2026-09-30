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
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The shooting popup's auxiliary selection on the controller
 * (FILTER-AUX-002/003/004, FILTER-STACK-004): any number of auxiliary
 * filters, one display order whatever the mount order, three rows plus a
 * count on Main, an auxiliary-only subtotal, and the 30-stop cap in both
 * selection orders. (iOS: `AuxiliaryFilterSelectionTests`.)
 */
class AuxiliaryFilterSelectionTest {

    private val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
    private val marumi = FilterItem("MARUMI Red 25A", FilterItemBehavior.Color(FilterExposureLoss(2.0), FilterSetColor.red))
    private val night = FilterItem("Night Clear", FilterItemBehavior.Effect(FilterExposureLoss(1.0)))
    private val heavy = FilterItem("Heavy Effect", FilterItemBehavior.Effect(FilterExposureLoss(9.0)))
    private val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.5, null, null))))
    private val gnd = FilterItem(
        "Soft GND 2",
        FilterItemBehavior.Gnd(FilterRegisteredValue(2.0, FilterValueUnit.stops)),
    )
    // Set order puts the GND and CPL first, so the kind order has to win.
    private val kit = FilterSet("Kit", FilterSetColor.blue, listOf(gnd, cpl, heavy, night, marumi, red))

    private fun controller(): CalculatorController {
        val model = FilterInventoryModel(
            initial = FilterInventory(listOf(kit)),
            persistenceWriter = PersistenceWriter { it() },
        )
        return CalculatorController(films = emptyList(), inventoryModel = model).also {
            it.setCandidateFilterSets(listOf(kit.id))
        }
    }

    private fun mount(item: FilterItem) =
        MountedAuxiliaryFilter(kit.id, item.id, MountedAuxiliaryFilter.initialChoice(item)!!)

    private fun ndWheel(c: CalculatorController, stops: Double) {
        val wheel = c.state.value.filterWheels.first()
        c.setNdWheelActive(wheel.id, true)
        c.setNdWheelValue(wheel.id, wheel.rows.indexOfFirst { it.selection == FilterWheelSelection.Standard(stops) })
        c.setNdWheelActive(wheel.id, false)
    }

    @Test fun moreThanThreeMountInDisplayOrderWhateverTheMountOrder() {
        val c = controller()
        assertNull(c.applyAuxiliaryFilters(listOf(gnd, cpl, night, marumi, red).map(::mount)))

        val expected = listOf(marumi, red, night, cpl, gnd).map { it.id }
        assertEquals(expected, c.state.value.mountedAuxiliaryFilters.map { it.itemId })
        assertNull(c.applyAuxiliaryFilters(listOf(red, gnd, night, cpl, marumi).map(::mount)))
        assertEquals("Mount order never matters.", expected, c.state.value.mountedAuxiliaryFilters.map { it.itemId })
        // Color 2 + 3, Effect 1, CPL 1.5, GND Record only 0.
        assertEquals("7.5", c.state.value.filterStatus.totalStopsText)
    }

    @Test fun mainShowsTheFirstThreeAndCountsTheRest() {
        val c = controller()
        assertNull(c.applyAuxiliaryFilters(listOf(gnd, cpl, night, marumi, red).map(::mount)))
        val summary = c.state.value.auxiliarySummary!!
        assertEquals(listOf("MARUMI Red 25A", "Red 25A", "Night Clear"), summary.visibleItems.map { it.name })
        assertEquals(2, summary.hiddenItemCount)

        assertNull(c.applyAuxiliaryFilters(listOf(marumi, red, night).map(::mount)))
        assertEquals(0, c.state.value.auxiliarySummary!!.hiddenItemCount)
        assertNull(c.applyAuxiliaryFilters(emptyList()))
        assertNull("No mounted item hides the summary space.", c.state.value.auxiliarySummary)
    }

    @Test fun theSubtotalCountsOnlyAuxiliaryFilters() {
        val c = controller()
        ndWheel(c, 10.0)
        val selection = listOf(red, night, cpl).map(::mount)
        assertEquals(5.5, c.auxiliaryFiltersSubtotal(selection), 1e-9)
        assertNull(c.applyAuxiliaryFilters(selection))
        assertEquals("The whole Total includes ND.", "15.5", c.state.value.filterStatus.totalStopsText)
        assertEquals("The subtotal never does.", 5.5, c.auxiliaryFiltersSubtotal(c.state.value.mountedAuxiliaryFilters), 1e-9)
    }

    @Test fun anAuxiliaryFilterAfterNdIsRefusedPastThirtyStops() {
        val c = controller()
        ndWheel(c, 20.0)
        assertNull(c.applyAuxiliaryFilters(listOf(mount(red))))
        val attempt = listOf(mount(red), mount(heavy))

        assertEquals(FilterStackRejection.exceedsTotalLimit, c.auxiliaryFiltersRejection(attempt))
        assertEquals(FilterStackRejection.exceedsTotalLimit, c.applyAuxiliaryFilters(attempt))
        assertEquals("Nothing already mounted changes.", listOf(mount(red)), c.state.value.mountedAuxiliaryFilters)
        assertEquals("23", c.state.value.filterStatus.totalStopsText)
    }

    @Test fun anNdChangeAfterAuxiliaryFiltersIsHeldToTheRemainingBudget() {
        val c = controller()
        ndWheel(c, 15.0)
        assertNull(c.applyAuxiliaryFilters(listOf(mount(heavy), mount(red))))

        val wheel = c.state.value.filterWheels.first()
        val offered = wheel.rows.map { (it.selection as FilterWheelSelection.Standard).stops }
        assertEquals("27 mounted leaves 18 for the wheel's own row.", 18.0, offered.max(), 1e-9)
        assertTrue(offered.none { it > 18.0 })
        assertEquals(listOf(mount(heavy), mount(red)).map { it.itemId }.toSet(), c.state.value.mountedAuxiliaryFilters.map { it.itemId }.toSet())
        assertEquals("27", c.state.value.filterStatus.totalStopsText)
    }

    @Test fun anAuxiliaryFilterCannotJoinFourNdWheels() {
        val c = controller()
        repeat(3) { c.addFilterWheel(FilterSource.Standard) }
        assertEquals(FilterStack.MAX_WHEEL_COUNT, c.state.value.filterWheels.size)
        assertEquals(FilterStackRejection.tooManyNDWheels, c.applyAuxiliaryFilters(listOf(mount(cpl))))
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
    }

    @Test fun excludingACandidateSetThisCameraUsesIsBlocked() {
        val c = controller()
        assertNull(c.applyAuxiliaryFilters(listOf(mount(red))))
        val outcome = c.setCandidateFilterSets(emptyList())
        assertEquals(CandidateFilterSetAssignmentOutcome.Blocked(listOf(kit)), outcome)
        assertEquals(listOf(kit.id), c.state.value.candidateFilterSetIds)
        assertNull(c.applyAuxiliaryFilters(emptyList()))
        assertEquals(CandidateFilterSetAssignmentOutcome.Assigned, c.setCandidateFilterSets(emptyList()))
        assertTrue(c.state.value.candidateFilterSetIds.isEmpty())
        assertEquals(
            "Only Standard is offered without candidates.",
            listOf(FilterSource.Standard),
            c.state.value.plus.sources.map { it.source },
        )
    }

    @Test fun aSingleCplOrGndShowsItsTypeWhileTwoOfAKindShowTheirNames() {
        val hard = FilterItem("Hard GND 3", FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops)))
        val c = CalculatorController(
            films = emptyList(),
            inventoryModel = FilterInventoryModel(
                initial = FilterInventory(listOf(kit.copy(items = kit.items + hard))),
                persistenceWriter = PersistenceWriter { it() },
            ),
        ).also { it.setCandidateFilterSets(listOf(kit.id)) }
        assertNull(c.applyAuxiliaryFilters(listOf(mount(cpl), mount(gnd))))
        assertEquals(
            listOf(listOf("CPL"), listOf("GND")),
            c.state.value.auxiliarySummary!!.items.map { it.compactLabels },
        )
        assertNull(c.applyAuxiliaryFilters(listOf(mount(gnd), MountedAuxiliaryFilter(kit.id, hard.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly)))))
        assertEquals(
            listOf(listOf("Soft GND 2", "Soft GND", "Soft"), listOf("Hard GND 3", "Hard GND", "Hard")),
            c.state.value.auxiliarySummary!!.items.map { it.compactLabels },
        )
    }
}
