// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.vm.FilterSourcePlusGestureArbiter.ReleaseOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FILTER-PLUS-001/003: tap and source browsing never compete on one
 * touch; a touch that leaves the stationary tolerance without browsing is
 * neither.
 */
class FilterSourcePlusGestureArbiterTest {

    private fun arbiter(settledIndex: Int = 0, sourceCount: Int = 4) =
        FilterSourcePlusGestureArbiter(settledIndex, sourceCount)

    @Test
    fun `a stationary release adds the displayed source`() {
        assertEquals(ReleaseOutcome.Add, arbiter().released())
    }

    @Test
    fun `movement past the stationary tolerance is no tap`() {
        val gesture = arbiter()
        gesture.moved(dx = 0f, dy = -5f)
        assertEquals(FilterSourcePlusGestureArbiter.Phase.unsettled, gesture.phase)
        assertEquals(ReleaseOutcome.None, gesture.released())
    }

    @Test
    fun `browsing wins past the drag threshold`() {
        val gesture = arbiter()
        gesture.moved(dx = 0f, dy = -9f)
        assertEquals(FilterSourcePlusGestureArbiter.Phase.browsing, gesture.phase)
    }

    @Test
    fun `releasing on a different source adds that index once`() {
        val gesture = arbiter()
        // One step up (26 dp) past the browse threshold.
        assertTrue(gesture.moved(dx = 0f, dy = -26f))
        assertEquals(1, gesture.candidateIndex)
        // The same candidate does not report a change again.
        assertFalse(gesture.moved(dx = 0f, dy = -28f))
        assertEquals(ReleaseOutcome.AddBrowsed(1), gesture.released())
    }

    @Test
    fun `returning to the starting source adds nothing`() {
        val gesture = arbiter()
        gesture.moved(dx = 0f, dy = -26f)
        assertTrue(gesture.moved(dx = 0f, dy = 0f))
        assertEquals(0, gesture.candidateIndex)
        assertEquals(ReleaseOutcome.None, gesture.released())
    }

    @Test
    fun `browsing clamps to the ends of the source list`() {
        val gesture = arbiter(settledIndex = 1, sourceCount = 2)
        gesture.moved(dx = 0f, dy = -260f)
        assertEquals(1, gesture.candidateIndex)
        assertEquals(ReleaseOutcome.None, gesture.released())
    }
}
