// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterExposureLoss
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.RequiredNDResult
import org.junit.Assert.*
import org.junit.Test

class RequiredNDGuidanceTest {
    @Test fun tracksInertiaFinalValueAndRejectsDuplicateSettlement() {
        val model = RequiredNDGuidanceModel()
        model.begin(1.0, 1024.0, null)
        model.update(2.0)
        model.update(4.0)
        assertEquals(RequiredNDResult.Value(8.0, false), model.state.result)
        model.settle(8.0)
        val outgoing = model.state
        model.update(16.0)
        model.settle(32.0)
        assertEquals(outgoing, model.state)
        assertEquals(RequiredNDResult.Value(7.0, false), outgoing.result)
        model.complete(outgoing.generation)
        assertNull(model.state.result)
    }

    @Test fun retouchAndContextInvalidationRejectOldCompletion() {
        val model = RequiredNDGuidanceModel()
        model.begin(1.0, 1024.0, null)
        model.settle(1.0)
        val old = model.state.generation
        model.begin(4.0, 1024.0, null)
        model.complete(old)
        assertEquals(RequiredNDResult.Value(8.0, false), model.state.result)
        model.settle(4.0)
        val next = model.state.generation
        model.invalidate()
        model.complete(next)
        assertNull(model.state.result)
        assertEquals(RequiredNDGuidanceState.Phase.Ordinary, model.state.phase)
    }

    @Test fun editingSelectedProfileWithoutChangingItsIdCancelsGuidance() {
        val film = LaunchPresetFilmCatalogV2.films.first { it.id == "ilford-hp5-plus-400" }
        val controller = CalculatorController(listOf(film))
        controller.selectFilm(film.id)
        controller.setTargetShutter(1024.0)
        controller.beginBaseInteraction()
        assertNotNull(controller.state.value.requiredND.result)
        val original = film.profiles.first()
        val changed = original.copy(rules = original.rules.map { rule ->
            val f = rule.formula
            if (f != null) rule.copy(formula = f.copy(formula = f.formula.copy(exponent = 2.0))) else rule
        })
        controller.setFilms(listOf(film.copy(profiles = listOf(changed))))
        assertNull(controller.state.value.requiredND.result)
    }

    @Test fun cameraSwitchCancelsCrossfadeAndItsOldCompletion() {
        val controller = CalculatorController(LaunchPresetFilmCatalogV2.films)
        controller.setTargetShutter(1024.0)
        controller.beginBaseInteraction()
        controller.finishBaseInteraction(controller.state.value.shutterIndex)
        val old = controller.state.value.requiredND.generation
        controller.selectSlot(controller.state.value.slots.first { !it.isActive }.id)
        controller.completeRequiredNDCrossfade(old)
        assertNull(controller.state.value.requiredND.result)
        assertEquals(RequiredNDGuidanceState.Phase.Ordinary, controller.state.value.requiredND.phase)
    }

    @Test fun auxiliaryTwoStopsDoesNotSubtractFromRequiredTotal() {
        val item = FilterItem("Two stops", FilterItemBehavior.Effect(FilterExposureLoss(2.0)))
        val kit = FilterSet("Test kit", FilterSetColor.blue, listOf(item))
        val inventory = FilterInventoryModel(initial = FilterInventory(listOf(kit)), persistenceWriter = PersistenceWriter { it() })
        val controller = CalculatorController(emptyList(), inventoryModel = inventory)
        controller.arrangeCandidateFilterSets(listOf(kit.id))
        val mount = MountedAuxiliaryFilter(kit.id, item.id, MountedAuxiliaryFilter.initialChoice(item)!!)
        assertNull(controller.applyMounts(listOf(mount)))
        controller.setShutterIndex(ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 })
        controller.setTargetShutter(1024.0)
        controller.beginBaseInteraction()
        assertEquals(RequiredNDResult.Value(10.0, false), controller.state.value.requiredND.result)
        assertEquals(listOf(mount), controller.state.value.mountedAuxiliaryFilters)
        assertEquals("2", controller.state.value.filterStatus.totalStopsText)
    }

    @Test fun runningTimerKeepsItsCapturedShotAndCompletesDuringGuidance() {
        val start = java.time.Instant.ofEpochSecond(100)
        var workspace = com.sangwook.ptimer.app.timer.TimerWorkspace()
        val controller = CalculatorController(emptyList(), onStart = { duration, identity ->
            workspace = workspace.start(java.util.UUID.randomUUID(), duration, identity, start)
        })
        controller.setTargetShutter(1024.0)
        controller.startFromTarget()
        val captured = workspace.timers.single()
        controller.beginBaseInteraction()
        controller.setShutterIndex(controller.state.value.shutterIndex + 1)
        controller.finishBaseInteraction(controller.state.value.shutterIndex)
        controller.completeRequiredNDCrossfade(controller.state.value.requiredND.generation)
        assertEquals(listOf(captured), workspace.timers)
        workspace = workspace.reconciled(start.plusSeconds(1024))
        assertTrue(workspace.timers.single().state is com.sangwook.ptimer.core.timer.TimerState.Completed)
        assertEquals(captured.id, workspace.timers.single().id)
        assertEquals(captured.identity, workspace.timers.single().identity)
    }

    @Test fun controllerPreservesInputsAndCancelsForTargetNdCameraAndPreference() {
        val controller = CalculatorController(LaunchPresetFilmCatalogV2.films)
        val index = ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 }
        controller.setShutterIndex(index)
        controller.setTargetShutter(1024.0)
        assertNull(controller.state.value.requiredND.result)
        val before = controller.exportCameraList()
        controller.beginBaseInteraction()
        assertEquals(RequiredNDResult.Value(10.0, false), controller.state.value.requiredND.result)
        assertEquals(before, controller.exportCameraList())
        controller.finishBaseInteraction(index)
        assertEquals(RequiredNDGuidanceState.Phase.Crossfading, controller.state.value.requiredND.phase)
        controller.setTargetShutter(2048.0)
        assertNull(controller.state.value.requiredND.result)
        controller.beginBaseInteraction()
        controller.setNdWheelActive(controller.state.value.filterWheels.first().id, true)
        assertNull(controller.state.value.requiredND.result)
        controller.beginBaseInteraction()
        controller.setShowRequiredND(false)
        assertFalse(controller.state.value.showRequiredND)
        assertNull(controller.state.value.requiredND.result)
        controller.beginBaseInteraction()
        assertNull(controller.state.value.requiredND.result)
    }
}
