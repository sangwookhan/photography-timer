package com.sangwook.ptimer.timer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure exact-vs-inexact + prompt decision (no Android). */
class ExactAlarmPolicyTest {

    @Test
    fun belowApi31AlwaysUsesExactWithoutPrompt() {
        val d = ExactAlarmPolicy.decide(sdkInt = 30, canScheduleExact = false, promptDismissed = false)
        assertTrue(d.shouldUseExact)
        assertFalse(d.shouldShowPermissionPrompt)
        assertEquals(FallbackMode.NONE, d.fallbackMode)
    }

    @Test
    fun api31PlusPermittedUsesExactWithoutPrompt() {
        val d = ExactAlarmPolicy.decide(sdkInt = 34, canScheduleExact = true, promptDismissed = false)
        assertTrue(d.shouldUseExact)
        assertFalse(d.shouldShowPermissionPrompt)
        assertEquals(FallbackMode.NONE, d.fallbackMode)
    }

    @Test
    fun api31PlusDeniedFallsBackToInexactAndOffersPrompt() {
        val d = ExactAlarmPolicy.decide(sdkInt = 34, canScheduleExact = false, promptDismissed = false)
        assertFalse(d.shouldUseExact)
        assertTrue(d.shouldShowPermissionPrompt)
        assertEquals(FallbackMode.INEXACT, d.fallbackMode)
    }

    @Test
    fun api31PlusDeniedButDismissedStillFallsBackWithoutPrompt() {
        val d = ExactAlarmPolicy.decide(sdkInt = 34, canScheduleExact = false, promptDismissed = true)
        assertFalse(d.shouldUseExact)
        assertFalse(d.shouldShowPermissionPrompt) // no repeated nagging
        assertEquals(FallbackMode.INEXACT, d.fallbackMode)
    }
}
