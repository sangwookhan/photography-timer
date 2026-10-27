// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.*
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.pow

class TargetNDProposalSessionTest {
    private fun input() = TargetNDProposalInput("camera", 1.0, 1024.0, null, FilterInventory.empty, emptyList(), FilterStack.single(0.0), TargetNDSettings(), TargetNDMedium.digital)
    private fun ready(data: TargetNDProposalInput): TargetNDProposalSession = TargetNDProposalSession().also {
        it.begin(data)
        val token = requireNotNull(it.settle(data, true))
        assertTrue(it.complete(data.evaluate(), data, token, 10.0))
    }
    @Test fun finalCommitAndSameValueInteractionNeedQuietFilters() {
        val data = input()
        val session = TargetNDProposalSession()
        assertNull(session.settle(data, true))
        session.begin(data)
        session.preview(data)
        assertNull(session.settle(data, false))
        assertNotNull(session.settle(data, true))
    }
    @Test fun fiveSecondsStartsAtResultReadyAndOldTimeoutCannotDismissNewResult() {
        val data = input()
        val session = ready(data)
        val old = session.generation
        session.expire(old, 14.999)
        assertEquals(TargetNDProposalSession.Phase.result, session.phase)
        session.expire(old, 15.0)
        assertEquals(TargetNDProposalSession.Phase.idle, session.phase)
        session.begin(data)
        val fresh = requireNotNull(session.settle(data, true))
        assertFalse(session.complete(data.evaluate(), data, old, 20.0))
        assertTrue(session.complete(data.evaluate(), data, fresh, 20.0))
        session.expire(old, 100.0)
        assertEquals(TargetNDProposalSession.Phase.result, session.phase)
    }
    @Test fun noCombinationLastsTwoSecondsAndOldDeadlineCannotDismissNextOffer() {
        val impossible = input().copy(targetSeconds = 2.0.pow(31))
        val session = ready(impossible)
        assertEquals(TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.NoCombination), session.result)
        assertEquals(12.0, session.expiresAt!!, 0.0)
        val old = session.generation
        session.expire(old, 11.999)
        assertEquals(TargetNDProposalSession.Phase.result, session.phase)
        session.begin(input())
        val fresh = requireNotNull(session.settle(input(), true))
        assertTrue(session.complete(input().evaluate(), input(), fresh, 11.999))
        session.expire(old, 12.0)
        assertEquals(TargetNDProposalSession.Phase.result, session.phase)
        assertEquals(16.999, session.expiresAt!!, 1e-9)
    }
    @Test fun focusSuspendsExpiryAndRestoresRemainingLifetime() {
        val session = ready(input())
        session.focusAction(true, 12.0)
        session.expire(session.generation, 100.0)
        assertEquals(TargetNDProposalSession.Phase.result, session.phase)
        session.focusAction(false, 100.0)
        assertEquals(103.0, session.expiresAt!!, 0.0)
        session.expire(session.generation, 103.0)
        assertEquals(TargetNDProposalSession.Phase.idle, session.phase)
    }
    @Test fun changedCameraInputSettingsInventoryAreStale() {
        val data = input()
        for (changed in listOf(data.copy(cameraId = "other"), data.copy(targetSeconds = 512.0), data.copy(settings = data.settings.copy(isEnabled = false)), data.copy(filmId = "other-film"), data.copy(filmColor = com.sangwook.ptimer.core.reciprocity.FilmColor.color), data.copy(inventory = FilterInventory(listOf(FilterSet("New", FilterSetColor.blue)))))) {
            val session = ready(data)
            assertEquals(TargetNDApplyResult.Rejected(TargetNDApplyFailure.stale), session.consume(changed, 11.0))
            assertEquals(TargetNDProposalSession.Phase.idle, session.phase)
        }
    }
    @Test fun consumeIsOneShotAndInvalidationRequiresAnotherManualInteraction() {
        val data = input()
        val session = ready(data)
        val result = session.consume(data, 11.0) as TargetNDApplyResult.Accepted
        assertEquals(10.0, result.stack.effectiveStops, 0.0)
        assertEquals(0.0, data.current.effectiveStops, 0.0)
        assertEquals(TargetNDApplyResult.Rejected(TargetNDApplyFailure.duplicate), session.consume(data, 11.0))
        session.invalidate()
        assertNull(session.settle(data, true))
        assertFalse(session.complete(data.evaluate(), data, session.generation - 1, 20.0))
    }
}
