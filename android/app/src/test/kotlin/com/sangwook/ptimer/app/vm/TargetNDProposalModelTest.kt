// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.*
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.pow

class TargetNDProposalModelTest {
    private fun input(target: Double = 1024.0) = TargetNDProposalInput("a", 1.0, target, null,
        FilterInventory.empty, emptyList(), FilterStack.single(0.0), TargetNDSettings(), TargetNDMedium.digital)

    @Test fun noCombinationSchedulesTwoSecondsAndPriorCallbackCannotExpireNextCandidate() {
        var time = 4.0
        val actions = mutableListOf<() -> Unit>()
        val delays = mutableListOf<Double>()
        val model = TargetNDProposalModel({ time }, schedule = { delay, action -> delays += delay; actions += action; {} })
        val impossible = input(2.0.pow(31))
        model.begin(impossible); model.settle(impossible, true)
        assertEquals(listOf(2.0), delays)
        model.begin(input()); time = 5.0; model.settle(input(), true)
        assertEquals(listOf(2.0, 5.0), delays)
        time = 6.0; actions[0]()
        assertEquals(TargetNDProposalSession.Phase.result, model.state.value.phase)
        time = 10.0; actions[1]()
        assertEquals(TargetNDProposalSession.Phase.idle, model.state.value.phase)
    }

    @Test fun readinessSchedulesExpiryAndOldCallbacksCannotDismissNewOrFocusedOffers() {
        var time = 10.0
        val actions = mutableListOf<() -> Unit>()
        val delays = mutableListOf<Double>()
        val model = TargetNDProposalModel({ time }, schedule = { delay, action -> delays += delay; actions += action; {} })
        model.begin(input())
        model.preview(input().copy(baseSeconds = 2.0))
        assertTrue(actions.isEmpty())
        model.settle(input(), true)
        assertEquals(listOf(5.0), delays)
        model.begin(input()); time = 12.0; model.settle(input(), true)
        time = 15.0; actions[0]()
        assertEquals(TargetNDProposalSession.Phase.result, model.state.value.phase)
        model.focusAction(true); time = 100.0; actions[1]()
        assertEquals(TargetNDProposalSession.Phase.result, model.state.value.phase)
        model.focusAction(false)
        assertEquals(2.0, delays.last(), 0.0)
        time = 102.0; actions.last()()
        assertEquals(TargetNDProposalSession.Phase.idle, model.state.value.phase)
    }
    @Test fun lateWorkersCannotRecreateAnInvalidatedOrNewerOffer() {
        val completions = mutableListOf<(TargetNDSelectionResult) -> Unit>()
        val model = TargetNDProposalModel(evaluate = { _, complete -> completions += complete; {} })
        model.begin(input()); model.settle(input(), true)
        model.begin(input(512.0)); model.settle(input(512.0), true)
        completions[0](input().evaluate())
        assertEquals(TargetNDProposalSession.Phase.evaluating, model.state.value.phase)
        completions[1](input(512.0).evaluate())
        assertEquals(TargetNDProposalSession.Phase.result, model.state.value.phase)
        model.invalidate(); completions[1](input(512.0).evaluate())
        assertEquals(TargetNDProposalSession.Phase.idle, model.state.value.phase)
    }
    @Test fun targetChangeDuringMotionAndNoisyFiltersCannotOffer() {
        val model = TargetNDProposalModel()
        model.begin(input()); model.reconcile(input(512.0)); model.settle(input(512.0), true)
        assertEquals(TargetNDProposalSession.Phase.idle, model.state.value.phase)
        model.begin(input()); model.settle(input(), false)
        assertEquals(TargetNDProposalSession.Phase.idle, model.state.value.phase)
    }
    @Test fun realControllerSameValueGestureCommitsOnlyNdOnce() {
        val controller = CalculatorController(films = emptyList())
        val index = ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 }
        controller.setShutterIndex(index); controller.setTargetShutter(1024.0)
        controller.beginManualBase(); controller.previewManualBase(index + 1)
        assertEquals(TargetNDProposalSession.Phase.interacting, controller.targetNDProposal.state.value.phase)
        controller.commitManualBase(index)
        assertEquals(TargetNDProposalSession.Phase.result, controller.targetNDProposal.state.value.phase)
        assertNull(controller.applyPendingTargetNDProposal())
        val after = requireNotNull(controller.targetNDInput(TargetNDSettings()))
        assertEquals(1.0, after.baseSeconds, 0.0)
        assertEquals(1024.0, after.targetSeconds, 0.0)
        assertEquals(10.0, after.current.effectiveStops, 0.0)
        assertNotNull(controller.applyPendingTargetNDProposal())
    }
    @Test fun settingsAndExternalBaseChangesInvalidateRealControllerImmediately() {
        repeat(2) { change ->
            val controller = CalculatorController(films = emptyList())
            val index = ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 }
            controller.setShutterIndex(index); controller.setTargetShutter(1024.0)
            controller.beginManualBase(); controller.commitManualBase(index)
            if (change == 0) controller.updateTargetNDSettings(TargetNDSettings(isEnabled = false))
            else controller.setShutterIndex(index + 1)
            assertEquals(TargetNDProposalSession.Phase.idle, controller.targetNDProposal.state.value.phase)
            assertNotNull(controller.applyPendingTargetNDProposal())
        }
    }
    @Test fun earlyTimeoutIsRearmedForTheRemainingFractionInsteadOfStrandingOffer() {
        var time = 0.0
        val actions = mutableListOf<() -> Unit>()
        val delays = mutableListOf<Double>()
        val model = TargetNDProposalModel({ time }, schedule = { delay, action -> delays += delay; actions += action; {} })
        model.begin(input()); model.settle(input(), true)
        time = 4.9996
        actions[0]()
        assertEquals(TargetNDProposalSession.Phase.result, model.state.value.phase)
        assertEquals(2, actions.size)
        assertEquals(0.0004, delays.last(), 1e-9)
        time = 5.0
        actions.last()()
        assertEquals(TargetNDProposalSession.Phase.idle, model.state.value.phase)
    }

}
