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
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.slots.CameraSlotId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Camera Reset with Filter Sets (RESET-004/011/012, FILTER-PLUS-004): both
 * choices return the Filter Stack to one Standard 0 wheel and clear every
 * auxiliary selection, a zero-contribution Record-only GND included, while
 * the camera's selected Filter Sets and its remembered Plus source stay;
 * the inventory and other cameras are untouched. (iOS: `FilterResetTests`.)
 */
class FilterResetTest {

    private val gnd = FilterItem("Soft GND 2", FilterItemBehavior.Gnd(FilterRegisteredValue(2.0, FilterValueUnit.stops)))
    private val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
    private val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
    private val night = FilterItem("Night", FilterItemBehavior.Effect(FilterExposureLoss(1.0)))
    private val nd8 = FilterItem("ND8", FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops)))
    private val kit = FilterSet("Kit", FilterSetColor.teal, listOf(gnd, cpl, red, night, nd8))

    private fun mount(item: FilterItem, choice: AuxiliaryFilterChoice = MountedAuxiliaryFilter.initialChoice(item)!!) =
        MountedAuxiliaryFilter(kit.id, item.id, choice)

    private fun plusSource(c: CalculatorController): FilterSource = c.state.value.plus.let { it.sources[it.selectedIndex].source }

    /** The camera selects Kit, with Plus on Kit after the Apply. */
    private fun camera(): Pair<CalculatorController, FilterInventoryModel> {
        val model = FilterInventoryModel(initial = FilterInventory(listOf(kit)), persistenceWriter = PersistenceWriter { it() })
        val c = CalculatorController(films = emptyList(), inventoryModel = model)
        assertNull(c.applyShootingFilters(listOf(kit.id), emptyList()))
        assertEquals("Plus moved to Kit on Apply.", FilterSource.FilterSet(kit.id), plusSource(c))
        assertEquals(listOf(FilterWheelSelection.Empty), c.state.value.filterWheels.map { it.rows[it.committedIndex].selection })
        assertFalse("Selecting a Filter Set alone, with the Empty wheel its Apply leaves, does not show Reset.", c.state.value.canReset)
        return c to model
    }

    @Test fun aZeroTotalRecordOnlyGndAndAnEmptySetWheelAreResetAndSelectedSetsStay() {
        val (c, model) = camera()
        assertNull(c.applyShootingFilters(listOf(kit.id), listOf(mount(gnd))))
        assertEquals(listOf(FilterWheelSelection.Empty), c.state.value.filterWheels.map { it.rows[it.committedIndex].selection })
        assertEquals((mount(gnd).choice as AuxiliaryFilterChoice.Gnd).mode, GndCalculationMode.recordOnly)
        assertTrue("A zero-contribution auxiliary filter shows Reset.", c.state.value.canReset)
        val inventoryBefore = model.inventory.value

        c.resetActiveSlotSettings()

        assertEquals(listOf(FilterWheelSelection.Standard(0.0)), c.state.value.filterWheels.map { it.rows[it.committedIndex].selection })
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
        assertEquals("Selected Filter Sets stay.", listOf(kit.id), c.state.value.candidateFilterSetIds)
        assertEquals("The remembered Plus source stays.", FilterSource.FilterSet(kit.id), plusSource(c))
        assertEquals("The inventory is unchanged.", inventoryBefore, model.inventory.value)
        assertFalse("Selected Filter Sets alone do not show Reset.", c.state.value.canReset)

        val restored = CalculatorController(films = emptyList(), initialSession = c.exportSession(), inventoryModel = model)
        assertTrue("The reset is saved.", restored.state.value.mountedAuxiliaryFilters.isEmpty())
        assertEquals(listOf(kit.id), restored.state.value.candidateFilterSetIds)
        assertEquals(FilterSource.FilterSet(kit.id), plusSource(restored))
    }

    @Test fun resetSettingsAndNameClearsEveryAuxiliaryKindAndLeavesOtherCamerasAlone() {
        val (c, _) = camera()
        c.selectSlot(CameraSlotId.camera2)
        assertNull(c.applyShootingFilters(listOf(kit.id), listOf(mount(red))))
        c.selectSlot(CameraSlotId.camera1)
        c.renameActiveSlot("Field")
        assertNull(c.applyShootingFilters(listOf(kit.id), listOf(mount(cpl, AuxiliaryFilterChoice.CplLoss(1.5)), mount(red), mount(night), mount(gnd))))
        val wheel = c.state.value.filterWheels.first()
        c.setNdWheelActive(wheel.id, true)
        c.setNdWheelValue(wheel.id, wheel.rows.indexOfFirst { it.selection == FilterWheelSelection.Item(FilterRowSelection(nd8.id, FilterRowChoice.Fixed)) })
        c.setNdWheelActive(wheel.id, false)
        assertEquals("8.5", c.state.value.filterStatus.totalStopsText)

        c.resetActiveSlotSettingsAndName()

        assertEquals(listOf(FilterWheelSelection.Standard(0.0)), c.state.value.filterWheels.map { it.rows[it.committedIndex].selection })
        assertTrue(c.state.value.mountedAuxiliaryFilters.isEmpty())
        assertEquals(listOf(kit.id), c.state.value.candidateFilterSetIds)
        assertEquals("Camera 1", c.state.value.activeSlotName)
        c.selectSlot(CameraSlotId.camera2)
        assertEquals("Another camera is unchanged.", listOf(mount(red)), c.state.value.mountedAuxiliaryFilters)
    }
}
