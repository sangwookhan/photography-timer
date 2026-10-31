// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.ui.component

import org.junit.Assert.*
import org.junit.Test

class SnapWheelSettlementGateTest {
    private fun frame(row: Int = 12, offset: Int = 0, distance: Float = 0f,
        touch: Boolean = false, scroll: Boolean = false, fling: Boolean = false) =
        SnapWheelSettlementFrame(touch, scroll, fling, row, row, offset, distance)

    @Test fun idleSignalBetweenDragAndFlingIsNotFinalSettlement() {
        val gate = SnapWheelSettlementGate()
        assertNull(gate.observe(frame(touch = true, scroll = true)))
        assertNull(gate.observe(frame())) // The old flag-only signal restored here.
        assertNull(gate.observe(frame(scroll = true, fling = true)))
        assertNull(gate.observe(frame(row = 15, fling = true)))
        assertNull(gate.observe(frame(row = 15)))
        assertEquals(15, gate.observe(frame(row = 15)))
        assertNull(gate.observe(frame(row = 15)))
    }

    @Test fun fractionalMotionAndFinalSnapMustFinishEvenWithoutScrollingFlag() {
        val gate = SnapWheelSettlementGate()
        for (offset in listOf(20, 12, 4, 0)) assertNull(gate.observe(frame(offset = offset, distance = offset.toFloat())))
        assertNull(gate.observe(frame(offset = 1, distance = 1f)))
        assertNull(gate.observe(frame()))
        assertEquals(12, gate.observe(frame()))
    }

    @Test fun retouchAndNoChangeTouchCannotReuseEarlierRestConfirmation() {
        val gate = SnapWheelSettlementGate()
        assertNull(gate.observe(frame()))
        assertNull(gate.observe(frame(touch = true)))
        assertNull(gate.observe(frame(touch = true)))
        assertNull(gate.observe(frame()))
        assertEquals(12, gate.observe(frame()))
    }
}
