// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/** PTIMER-73: staged-alert duration buckets and pre2 foreground suppression. */
class StagedAlertPolicyTest {

    @Test
    fun shortDurationHasNoPreAlerts() {
        assertTrue(StagedAlertPolicy.preAlerts(1.0).isEmpty())
        assertTrue(StagedAlertPolicy.preAlerts(30.0).isEmpty())
    }

    @Test
    fun mediumDurationHasPre1AtFiveSeconds() {
        assertEquals(
            listOf(PreAlertSpec(AlertStage.PRE1, 5)),
            StagedAlertPolicy.preAlerts(45.0),
        )
        // Boundary: exactly 60s stays in the medium bucket.
        assertEquals(listOf(PreAlertSpec(AlertStage.PRE1, 5)), StagedAlertPolicy.preAlerts(60.0))
    }

    @Test
    fun longDurationHasPre1AtTenAndPre2AtFive() {
        assertEquals(
            listOf(PreAlertSpec(AlertStage.PRE1, 10), PreAlertSpec(AlertStage.PRE2, 5)),
            StagedAlertPolicy.preAlerts(61.0),
        )
    }

    @Test
    fun pre2IsSuppressedInForegroundOnly() {
        assertFalse(StagedAlertPolicy.shouldDeliver(AlertStage.PRE2, isAppForeground = true))
        assertTrue(StagedAlertPolicy.shouldDeliver(AlertStage.PRE2, isAppForeground = false))
    }

    @Test
    fun pre1AndMainDeliverRegardlessOfForeground() {
        for (foreground in listOf(true, false)) {
            assertTrue(StagedAlertPolicy.shouldDeliver(AlertStage.PRE1, foreground))
            assertTrue(StagedAlertPolicy.shouldDeliver(AlertStage.MAIN, foreground))
        }
    }

    @Test
    fun requestCodesAreDistinctPerStageForSameTimer() {
        val id = UUID.randomUUID()
        val codes = AlertStage.entries.map { AndroidTimerAlertCoordinator.requestCode(id, it) }
        assertEquals(codes.size, codes.toSet().size)
    }
}
