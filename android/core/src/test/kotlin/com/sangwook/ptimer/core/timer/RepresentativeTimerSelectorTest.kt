package com.sangwook.ptimer.core.timer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class RepresentativeTimerSelectorTest {

    private val base: Instant = Instant.parse("2026-06-17T00:00:00Z")

    @Test
    fun picksEarliestEndingRunningTimer() {
        val timers = listOf(
            TimerState.running("a", 100.0, base),
            TimerState.running("b", 10.0, base), // ends first
        )
        assertEquals("b", RepresentativeTimerSelector.select(timers, base)!!.id)
    }

    @Test
    fun excludesPausedAndCompletedAndIsNullWhenNoneRunning() {
        val timers = listOf(
            TimerState.Paused("p", 100.0, base, 50.0, base),
            TimerState.Completed("c", 10.0, base, base.plusSeconds(10)),
        )
        assertNull(RepresentativeTimerSelector.select(timers, base.plusSeconds(1)))
    }

    @Test
    fun stableTiebreakById() {
        val timers = listOf(
            TimerState.running("z", 10.0, base),
            TimerState.running("a", 10.0, base), // same end, lower id wins
        )
        assertEquals("a", RepresentativeTimerSelector.select(timers, base)!!.id)
    }
}
