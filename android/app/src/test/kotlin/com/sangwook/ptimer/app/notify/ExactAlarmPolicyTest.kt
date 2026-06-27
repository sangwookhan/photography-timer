// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExactAlarmPolicyTest {

    private class FakeAvailability(
        override val isPermissionGated: Boolean,
        private val allowed: Boolean,
    ) : ExactAlarmAvailability {
        override fun isAllowed(): Boolean = allowed
        override fun openSettings() { /* no-op in tests */ }
    }

    @Test
    fun allowedSchedulesExactAndDoesNotWarn() {
        val a = FakeAvailability(isPermissionGated = true, allowed = true)
        assertEquals(AlarmScheduling.EXACT, ExactAlarmPolicy.scheduling(a))
        assertFalse(ExactAlarmPolicy.shouldWarn(a))
    }

    @Test
    fun deniedFallsBackToInexactAndWarns() {
        val a = FakeAvailability(isPermissionGated = true, allowed = false)
        assertEquals(AlarmScheduling.INEXACT, ExactAlarmPolicy.scheduling(a))
        assertTrue(ExactAlarmPolicy.shouldWarn(a))
    }

    @Test
    fun ungatedOsSchedulesExactAndNeverWarns() {
        // Pre-API-31: exact alarms need no permission, so always allowed, never warned.
        val a = FakeAvailability(isPermissionGated = false, allowed = true)
        assertEquals(AlarmScheduling.EXACT, ExactAlarmPolicy.scheduling(a))
        assertFalse(ExactAlarmPolicy.shouldWarn(a))
    }
}
