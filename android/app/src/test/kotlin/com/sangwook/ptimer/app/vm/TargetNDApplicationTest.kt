// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.*
import org.junit.Assert.*
import org.junit.Test

class TargetNDApplicationTest {
    private fun controller() = CalculatorController(films = emptyList()).also {
        it.setShutterIndex(ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { step -> step.seconds == 1.0 })
        it.setTargetShutter(1024.0)
    }
    @Test fun atomicApplyKeepsBaseTargetAndRejectsRepeatAndChangedTarget() {
        val settings = TargetNDSettings()
        val controller = controller()
        val input = requireNotNull(controller.targetNDInput(settings))
        assertNull(controller.applyTargetNDProposal(input, input.evaluate(), settings))
        val after = requireNotNull(controller.targetNDInput(settings))
        assertEquals(input.baseSeconds, after.baseSeconds, 0.0)
        assertEquals(input.targetSeconds, after.targetSeconds, 0.0)
        assertEquals(10.0, after.current.effectiveStops, 0.0)
        assertEquals(TargetNDApplyFailure.stale, controller.applyTargetNDProposal(input, input.evaluate(), settings))
        val old = after
        controller.setTargetShutter(512.0)
        assertEquals(TargetNDApplyFailure.stale, controller.applyTargetNDProposal(old, old.evaluate(), settings))
        assertEquals(10.0, requireNotNull(controller.targetNDInput(settings)).current.effectiveStops, 0.0)
    }
    @Test fun standardSelectionChangeKeepsWheelIdentityForVisibleValueMotion() {
        val settings = TargetNDSettings()
        val controller = controller()
        val initialId = controller.state.value.filterWheels.single().id
        val first = requireNotNull(controller.targetNDInput(settings))
        assertNull(controller.applyTargetNDProposal(first, first.evaluate(), settings))
        assertEquals(initialId, controller.state.value.filterWheels.single().id)
        controller.setTargetShutter(4096.0)
        val second = requireNotNull(controller.targetNDInput(settings))
        assertNull(controller.applyTargetNDProposal(second, second.evaluate(), settings))
        assertEquals(initialId, controller.state.value.filterWheels.single().id)
        assertEquals(12.0, requireNotNull(controller.targetNDInput(settings)).current.effectiveStops, 0.0)
    }
    @Test fun physicalApplyRetainsAuxiliaryChoiceSetsAndPlusSource() {
        val nd = FilterItem("ND6", FilterItemBehavior.Fixed(FilterRegisteredValue(6.0, FilterValueUnit.stops)))
        val aux = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 2.0))))
        val set = FilterSet("Kit", FilterSetColor.blue, listOf(nd, aux))
        val controller = CalculatorController(films = emptyList(), inventoryModel = FilterInventoryModel(initial = FilterInventory(listOf(set)), persistenceWriter = PersistenceWriter { it() }))
        val mounts = listOf(MountedAuxiliaryFilter(set.id, aux.id, AuxiliaryFilterChoice.CplLoss(2.0)))
        assertNull(controller.applyShootingFilters(listOf(set.id), mounts))
        controller.setShutterIndex(ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 })
        controller.setTargetShutter(256.0)
        val settings = TargetNDSettings()
        val input = requireNotNull(controller.targetNDInput(settings))
        val source = controller.state.value.plus.let { it.sources.getOrNull(it.selectedIndex)?.source }
        assertNull(controller.applyTargetNDProposal(input, input.evaluate(), settings))
        val after = requireNotNull(controller.targetNDInput(settings))
        assertEquals(mounts, after.current.auxiliaryFilters)
        assertEquals(input.selectedSets, after.selectedSets)
        assertEquals(source, controller.state.value.plus.let { it.sources.getOrNull(it.selectedIndex)?.source })
        assertEquals(8.0, after.current.effectiveStops, 0.0)
    }
}
